"""Read-only IPA structure, device executable, metadata and localization checks."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import struct
import zipfile
import re
import stat


def sdk_version(value):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
        raise argparse.ArgumentTypeError("Expected an SDK version such as 27.2")
    components = [int(part) for part in value.split(".")]
    return tuple((components + [0, 0])[:3])


def verify_executable(archive, bundle, metadata, min_sdk):
    filename = metadata["CFBundleExecutable"]
    assert filename and "/" not in filename, f"Invalid executable name in {bundle}"
    member = archive.getinfo(bundle + filename)
    mode = member.external_attr >> 16
    assert stat.S_ISREG(mode) and mode & 0o111, f"Missing executable permissions: {member.filename}"
    executable = archive.read(member)
    magic, cpu, _, filetype, commands, command_bytes, _, _ = struct.unpack_from("<8I", executable)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C and filetype == 2, f"Expected an arm64 Mach-O executable: {filename}"
    offset = 32
    end = offset + command_bytes
    assert end <= len(executable), f"Truncated Mach-O header: {filename}"
    linked_sdk = None
    for _ in range(commands):
        assert offset + 8 <= end, f"Truncated load command: {filename}"
        command, size = struct.unpack_from("<2I", executable, offset)
        assert size >= 8 and offset + size <= end, f"Invalid load command size: {filename}"
        assert command != 0x1D, f"Unexpected Mach-O code signature: {filename}"
        if command == 0x32:
            assert size >= 24, "Truncated LC_BUILD_VERSION"
            platform, _, sdk = struct.unpack_from("<3I", executable, offset + 8)
            assert platform == 2, f"Mach-O is not built for an iOS device: {filename}"
            linked_sdk = (sdk >> 16, (sdk >> 8) & 0xFF, sdk & 0xFF)
        offset += size
    assert offset == end and linked_sdk is not None, f"Missing or invalid iOS build-version command: {filename}"
    linked_version = ".".join(map(str, linked_sdk))
    if min_sdk is not None and linked_sdk < min_sdk:
        required = ".".join(map(str, min_sdk))
        raise ValueError(f"{filename} links iOS SDK {linked_version}, requires at least {required}")
    return linked_version


def verify(path, min_sdk=None):
    root = Path(__file__).resolve().parents[1]
    project = (root / "project.yml").read_text(encoding="utf-8")
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
        linked_version = verify_executable(archive, app, info, min_sdk)
        extensions = [name for name in names if re.fullmatch(re.escape(app) + r"PlugIns/[^/]+\.appex/Info\.plist", name)]
        assert len(extensions) == 1, "Expected one embedded packet tunnel extension in PlugIns/"
        extension = plistlib.loads(archive.read(extensions[0]))
        extension_id = info["CFBundleIdentifier"] + ".TunnelProvider"
        assert extension["CFBundleIdentifier"] == extension_id, "Unexpected VPN extension identifier"
        assert extension["CFBundlePackageType"] == "XPC!", "Expected an app extension bundle"
        for key in ("MinimumOSVersion", "CFBundleVersion", "CFBundleShortVersionString", "CFBundleSupportedPlatforms"):
            assert extension[key] == info[key], f"VPN extension {key} differs from host"
        provider = extension["NSExtension"]
        assert provider["NSExtensionPointIdentifier"] == "com.apple.networkextension.packet-tunnel", "Unexpected extension point"
        assert provider["NSExtensionPrincipalClass"].endswith(".PacketTunnelProvider"), "Unexpected VPN provider class"
        extension_bundle = extensions[0].removesuffix("Info.plist")
        verify_executable(archive, extension_bundle, extension, min_sdk)
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
        for notice in ("LocalDevVPN-LICENSE.txt", "LocalDevVPN-Attribution.txt"):
            source_text = (root / "Vendor" / "LocalDevVPN" / notice).read_text(encoding="utf-8")
            assert source_text.strip(), f"Empty source notice: {notice}"
            bundled_text = archive.read(app + notice).decode("utf-8")
            assert bundled_text.splitlines() == source_text.splitlines(), f"VPN notice mismatch: {notice}"
        assert not any(name.endswith("/embedded.mobileprovision") or "/_CodeSignature/" in name for name in names), "Expected unsigned host and extension"
        coverage = [name for name in names if name in [app + "mainland-coverage.json", app + "CoordinateData/mainland-coverage.json"]]
        assert len(coverage) == 1, "Missing or ambiguous offline coordinate coverage"
        assert hashlib.sha256(archive.read(coverage[0])).hexdigest() == "ec3fa27963f5e4481b6d68bdb9a132f48188dc5619df0a237dbdeac70009d2ec", "Offline coordinate coverage checksum mismatch"
        print(f"PASS: arm64 iPhoneOS SDK {linked_version}, {info['CFBundleIdentifier']}, v{info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), iOS {info['MinimumOSVersion']}+, bilingual resources and licenses.")
        print(f"Embedded VPN: {extension_id}. Signing: unsigned host and extension.")
    with Path(path).open("rb") as handle:
        print("SHA-256: " + hashlib.file_digest(handle, "sha256").hexdigest())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="IPA to verify")
    parser.add_argument("--min-sdk", type=sdk_version, help="Minimum linked iOS SDK, e.g. 27.2")
    args = parser.parse_args()
    verify(args.path, args.min_sdk)
