"""Read-only IPA structure, device executable, metadata and localization checks."""
import hashlib
from pathlib import Path
import plistlib
import struct
import sys
import zipfile
import re


def verify(path):
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
        device_platform = False
        for _ in range(commands):
            command, size = struct.unpack_from("<2I", executable, offset)
            assert size >= 8
            assert command != 0x1D, "Unexpected Mach-O code signature"
            if command == 0x32:
                platform = struct.unpack_from("<I", executable, offset + 8)[0]
                assert platform == 2, "Mach-O is not built for an iOS device"
                device_platform = True
            offset += size
        assert device_platform, "No iOS build-version command"
        for language in ["en", "zh-Hans"]:
            for filename in ["Localizable.strings", "InfoPlist.strings"]:
                content = plistlib.loads(archive.read(app + language + ".lproj/" + filename))
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
        assert hashlib.sha256(archive.read(coverage[0])).hexdigest() == "12d48be1a20de89ad2ed0bb2068acbbf24d4f8967d305a68e5acdc7c73d99283", "Offline coordinate coverage checksum mismatch"
        print(f"PASS: arm64 iPhoneOS, {info['CFBundleIdentifier']}, v{info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), iOS {info['MinimumOSVersion']}+, bilingual resources and licenses.")
        print("Signing: " + ("provisioning profile present" if app + "embedded.mobileprovision" in names else "unsigned/re-sign with your installation tool"))
    with Path(path).open("rb") as handle:
        print("SHA-256: " + hashlib.file_digest(handle, "sha256").hexdigest())


if __name__ == "__main__":
    verify(sys.argv[1])
