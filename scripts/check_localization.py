"""Check translation coverage and printf argument compatibility; no dependencies."""
from pathlib import Path
import collections
import json
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
ENTRY = re.compile(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;')
CALL = re.compile(r'L10n\.(?:tr|format)\(("(?:[^"\\]|\\.)*")')
FORMAT = re.compile(r'%(?:\d+\$)?(?:@|d|ld|lld|u|f|s)')


def strings(path):
    source = path.read_text(encoding="utf-8")
    result = {}
    for match in ENTRY.finditer(source):
        key, value = (json.loads(item) for item in match.groups())
        assert key not in result, f"Duplicate key in {path}: {key}"
        result[key] = value
    assert result, f"No strings in {path}"
    return result


def main():
    resources = ROOT / "Locus/Resources"
    english = strings(resources / "en.lproj/Localizable.strings")
    chinese = strings(resources / "zh-Hans.lproj/Localizable.strings")
    assert english.keys() == chinese.keys(), "English/Chinese keys differ"
    for key, value in chinese.items():
        assert value.strip(), f"Empty translation: {key}"
        assert collections.Counter(FORMAT.findall(english[key])) == collections.Counter(FORMAT.findall(value)), f"Format arguments differ: {key}"
    used = set()
    for source in (ROOT / "Locus").rglob("*.swift"):
        for match in CALL.finditer(source.read_text(encoding="utf-8")):
            used.add(json.loads(match.group(1)))
    assert used <= chinese.keys(), f"Missing keys: {used - chinese.keys()}"
    for language in ["en", "zh-Hans"]:
        info = strings(resources / f"{language}.lproj/InfoPlist.strings")
        for key in ["CFBundleDisplayName", "NSLocalNetworkUsageDescription", "NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"]:
            assert info.get(key), f"Missing {language} permission: {key}"
    with (resources / "Info.plist").open("rb") as handle:
        plistlib.load(handle)
    print(f"PASS: {len(english)} translation pairs; {len(used)} referenced keys; localized permissions; Info.plist.")


if __name__ == "__main__":
    main()
