"""Package the built device app using its own version metadata; preserve modes."""
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def package(application, destination):
    application = Path(application).resolve()
    destination = Path(destination).resolve()
    metadata = plistlib.loads((application / "Info.plist").read_bytes())
    assert metadata["CFBundleIdentifier"] == "com.ghb997.location"
    providers = list(application.glob("PlugIns/*.appex/Info.plist"))
    assert len(providers) == 1, "Expected a built app with an embedded VPN extension"
    provider = plistlib.loads(providers[0].read_bytes())
    assert provider["CFBundleIdentifier"] == metadata["CFBundleIdentifier"] + ".TunnelProvider"
    version = metadata["CFBundleShortVersionString"]
    assert version and all(c.isdigit() or c == "." for c in version)
    destination.mkdir(parents=True, exist_ok=True)
    filename = f"location-{version}-zh-Hans-embedded-vpn-unsigned.ipa"
    # A fresh staging area prevents zip from retaining obsolete app or extension files on rebuild.
    with tempfile.TemporaryDirectory(dir=destination) as staging:
        copied = Path(staging) / "Payload" / application.name
        shutil.copytree(application, copied, symlinks=True)
        shutil.copy2(ROOT / "LICENSE", copied / "LICENSE-Locus.txt")
        shutil.copy2(ROOT / "Vendor/idevice/LICENSE", copied / "LICENSE-idevice.txt")
        shutil.copy2(ROOT / "Vendor/coordtransform/LICENSE", copied / "LICENSE-coordtransform.txt")
        shutil.copy2(ROOT / "Vendor/NaturalEarth/LICENSE.md", copied / "NOTICE-NaturalEarth.txt")
        subprocess.run(["zip", "-qry", filename, "Payload"], cwd=staging, check=True)
        (Path(staging) / filename).replace(destination / filename)
    digest = hashlib.sha256((destination / filename).read_bytes()).hexdigest()
    (destination / "SHA256SUMS.txt").write_text(f"{digest}  {filename}\n", encoding="utf-8")
    print(destination / filename)


if __name__ == "__main__":
    package(sys.argv[1], sys.argv[2])
