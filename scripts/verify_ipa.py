"""Read-only IPA structure, device executable, metadata and localization checks."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import struct
import zipfile
import re


def sdk_version(value):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
        raise argparse.ArgumentTypeError("Expected an SDK version such as 27.2")
    components = [int(part) for part in value.split(".")]
    return tuple((components + [0, 0])[:3])


def verify(path, min_sdk=None):
    project = (Path(__file__).resolve().parents[1] / "project.yml").read_text(encoding="utf-8")
    expected_version = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', project).group(1)
    expected_build = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', project).group(1)
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, "Corrupt ZIP member"
        names = archive.namelist()
        assert len(names) == len(set(names)), "Duplicate ZIP members"
        assert not any(".." in name.split("/") or name.startswith("/") for name in names), "Unexpected archive path"
        candidates = [name for name in names if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")]
        assert len(candidates) == 1, "Expected one Payload application"
        info_path = candidates[0]
        app = info_path.removesuffix("Info.plist")
        info = plistlib.loads(archive.read(info_path))
        assert info["UIUserInterfaceStyle"] == "Light"
        assert info["CFBundleDisplayName"] == "location"
        assert info["CFBundleName"] == "location"
        assert info["CFBundleIdentifier"] == "com.ghb997.location"
        assert info["CFBundleShortVersionString"] == expected_version
        assert info["CFBundleVersion"] == expected_build
        assert info["MinimumOSVersion"] == "18.0"
        assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
        assert set(info["UIDeviceFamily"]) == {1, 2}, "Expected iPhone and iPad support"
        executable = archive.read(app + info["CFBundleExecutable"])
        magic, cpu, _, filetype, commands, _, _, _ = struct.unpack_from("<8I", executable)
        assert magic == 0xFEEDFACF and cpu == 0x0100000C and filetype == 2, "Expected an arm64 Mach-O executable"
        offset = 32
        linked_sdk = None
        for _ in range(commands):
            command, size = struct.unpack_from("<2I", executable, offset)
            assert size >= 8
            assert command != 0x1D, "Unexpected Mach-O code signature"
            if command == 0x32:
                assert size >= 24, "Truncated LC_BUILD_VERSION"
                platform, _, sdk = struct.unpack_from("<3I", executable, offset + 8)
                assert platform == 2, "Mach-O is not built for an iOS device"
                linked_sdk = (sdk >> 16, (sdk >> 8) & 0xFF, sdk & 0xFF)
            offset += size
        assert linked_sdk is not None, "No iOS build-version command"
        linked_version = ".".join(map(str, linked_sdk))
        if min_sdk is not None and linked_sdk < min_sdk:
            required = ".".join(map(str, min_sdk))
            raise ValueError(f"Mach-O links iOS SDK {linked_version}, requires at least {required}")
        for language in ["en", "zh-Hans"]:
            for filename in ["Localizable.strings", "InfoPlist.strings"]:
                content = plistlib.loads(archive.read(app + language + ".lproj/" + filename))
                if filename == "InfoPlist.strings":
                    assert content["CFBundleDisplayName"] == "location"
                assert content, f"Empty {language}/{filename}"
                if language == "zh-Hans" and filename == "Localizable.strings":
                    assert content["Teleport"] == "修改定位"
                    assert len(content) >= 170
        assert app + "LICENSE-Locus.txt" in names
        assert app + "LICENSE-idevice.txt" in names
        assert app + "LICENSE-coordtransform.txt" in names
        assert app + "NOTICE-NaturalEarth.txt" in names
        assert app + "embedded.mobileprovision" not in names, "Expected unsigned artifact"
        assert not any(name.startswith(app + "_CodeSignature/") for name in names), "Unexpected app signature"
        coverage = [name for name in names if name in [app + "mainland-coverage.json", app + "CoordinateData/mainland-coverage.json"]]
        assert len(coverage) == 1, "Missing or ambiguous offline coordinate coverage"
        assert hashlib.sha256(archive.read(coverage[0])).hexdigest() == "ec3fa27963f5e4481b6d68bdb9a132f48188dc5619df0a237dbdeac70009d2ec", "Offline coordinate coverage checksum mismatch"
        print(f"PASS: arm64 iPhoneOS SDK {linked_version}, {info['CFBundleIdentifier']}, v{info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), iOS {info['MinimumOSVersion']}+, bilingual resources and licenses.")
        print("Signing: " + ("provisioning profile present" if app + "embedded.mobileprovision" in names else "unsigned/re-sign with your installation tool"))
    with Path(path).open("rb") as handle:
        print("SHA-256: " + hashlib.file_digest(handle, "sha256").hexdigest())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="IPA to verify")
    parser.add_argument("--min-sdk", type=sdk_version, help="Minimum linked iOS SDK, e.g. 27.2")
    args = parser.parse_args()
    verify(args.path, args.min_sdk)
