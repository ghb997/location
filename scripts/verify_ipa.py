"""Read-only IPA structure, device executable, metadata and localization checks."""
import hashlib
from pathlib import Path
import plistlib
import struct
import sys
import zipfile


def verify(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, "Corrupt ZIP member"
        names = archive.namelist()
        candidates = [name for name in names if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")]
        assert len(candidates) == 1, "Expected one Payload application"
        info_path = candidates[0]
        app = info_path.removesuffix("Info.plist")
        info = plistlib.loads(archive.read(info_path))
        assert info["CFBundleIdentifier"] == "com.ghb997.location"
        assert info["CFBundleShortVersionString"] == "1.0.3"
        assert info["MinimumOSVersion"] == "18.0"
        assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
        executable = archive.read(app + info["CFBundleExecutable"])
        magic, cpu, _, filetype, commands, _, _, _ = struct.unpack_from("<8I", executable)
        assert magic == 0xFEEDFACF and cpu == 0x0100000C and filetype == 2, "Expected an arm64 Mach-O executable"
        offset = 32
        device_platform = False
        for _ in range(commands):
            command, size = struct.unpack_from("<2I", executable, offset)
            assert size >= 8
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
        print(f"PASS: arm64 iPhoneOS, {info['CFBundleIdentifier']}, v{info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), iOS {info['MinimumOSVersion']}+, bilingual resources and licenses.")
        print("Signing: " + ("provisioning profile present" if app + "embedded.mobileprovision" in names else "unsigned/re-sign with your installation tool"))
    with Path(path).open("rb") as handle:
        print("SHA-256: " + hashlib.file_digest(handle, "sha256").hexdigest())


if __name__ == "__main__":
    verify(sys.argv[1])
