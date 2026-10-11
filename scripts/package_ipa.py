"""Package the built device app using its own version metadata; preserve modes."""
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def package(application, destination):
    application = Path(application).resolve()
    destination = Path(destination).resolve()
    metadata = plistlib.loads((application / "Info.plist").read_bytes())
    assert metadata["CFBundleIdentifier"] == "com.ghb997.location"
    version = metadata["CFBundleShortVersionString"]
    assert version and all(c.isdigit() or c == "." for c in version)
    destination.mkdir(parents=True, exist_ok=True)
    payload = destination / "Payload"
    payload.mkdir(exist_ok=True)
    copied = payload / application.name
    # Each CI checkout is fresh. Never silently package an old app directory.
    assert not copied.exists(), f"Output app already exists: {copied}"
    shutil.copytree(application, copied, symlinks=True)
    shutil.copy2(ROOT / "LICENSE", copied / "LICENSE-Locus.txt")
    shutil.copy2(ROOT / "Vendor/idevice/LICENSE", copied / "LICENSE-idevice.txt")
    shutil.copy2(ROOT / "Vendor/coordtransform/LICENSE", copied / "LICENSE-coordtransform.txt")
    shutil.copy2(ROOT / "Vendor/NaturalEarth/LICENSE.md", copied / "NOTICE-NaturalEarth.txt")
    filename = f"Locus-{version}-zh-Hans-unsigned.ipa"
    subprocess.run(["zip", "-qry", filename, "Payload"], cwd=destination, check=True)
    digest = hashlib.sha256((destination / filename).read_bytes()).hexdigest()
    (destination / "SHA256SUMS.txt").write_text(f"{digest}  {filename}\n", encoding="utf-8")
    print(destination / filename)


if __name__ == "__main__":
    package(sys.argv[1], sys.argv[2])
