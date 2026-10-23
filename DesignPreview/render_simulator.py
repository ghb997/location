#!/usr/bin/env python3
"""Render real production SwiftUI components in an isolated simulator fixture."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import time
from pathlib import Path

BUNDLE_ID = "com.ghb997.location.designpreview"
SCENARIOS = ("idle", "active-route", "large-type", "reduced-transparency")
ROOT = Path(__file__).resolve().parents[1]


def run(*arguments: str, check: bool = True, timeout: int = 180) -> str:
    print("+ " + " ".join(arguments), flush=True)
    result = subprocess.run(arguments, check=False, text=True, capture_output=True, timeout=timeout)
    if result.stdout:
        print(result.stdout.rstrip(), flush=True)
    if result.stderr:
        print(result.stderr.rstrip(), flush=True)
    if check and result.returncode:
        raise RuntimeError(f"Command exited {result.returncode}: {arguments[0]}")
    return result.stdout


def available_targets() -> tuple[dict, list[tuple[str, dict]]]:
    runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
    candidates = [runtime for runtime in runtimes
                  if runtime.get("isAvailable") and runtime.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
                  and runtime.get("version", "").split(".")[0] == "26"]
    if not candidates:
        raise RuntimeError("An installed, available iOS 26 simulator runtime is required; no fallback to older material APIs.")
    candidates.sort(key=lambda runtime: tuple(int(part) for part in runtime["version"].split(".")), reverse=True)
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
    for runtime in candidates:
        available = devices.get(runtime["identifier"], [])
        phones = [device for device in available if device["name"].startswith("iPhone")]
        tablets = [device for device in available if device["name"].startswith("iPad")]
        if not phones or not tablets:
            continue
        phones.sort(key=lambda device: ("Pro Max" in device["name"], "Pro" not in device["name"], device["name"]))
        tablets.sort(key=lambda device: ("11-inch" not in device["name"], "Pro" not in device["name"], device["name"]))
        return runtime, [("iphone", phones[0]), ("ipad", tablets[0])]
    raise RuntimeError("No available iOS 26 runtime contains both an iPhone and iPad simulator.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    if not app.is_dir():
        raise RuntimeError(f"Built simulator app is missing: {app}")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    runtime, targets = available_targets()
    manifest = {
        "scope": "Production SwiftUI component rendering on a synthetic map with fake session state. Not the full app, real map tiles, native connection, real-device positioning, or hardware validation.",
        "commit": run("git", "rev-parse", "HEAD").strip(),
        "runtime": runtime,
        "device_appearance": "dark",
        "app_appearance": "light (Info.plist and preferredColorScheme)",
        "language": "zh-Hans",
        "accessibility": "Fixture injects accessibility2 for large-type. Simulator Accessibility preferences set reduceTransparency for reduced-transparency and reduceMotion for all scenarios; actual SwiftUI environment values are checked before screenshots.",
        "screenshots": [],
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for family, device in targets:
        udid = device["udid"]
        try:
            if device["state"] != "Booted":
                run("xcrun", "simctl", "boot", udid)
            run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=240)
            run("xcrun", "simctl", "ui", udid, "appearance", "dark")
            appearance = run("xcrun", "simctl", "ui", udid, "appearance").strip()
            if "dark" not in appearance.lower():
                raise RuntimeError("Simulator did not accept dark system appearance.")
            run("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged", "--batteryLevel", "100", check=False)
            run("xcrun", "simctl", "spawn", udid, "defaults", "write", "com.apple.Accessibility", "ReduceMotionEnabled", "-bool", "true")
            run("xcrun", "simctl", "install", udid, str(app))
            container = Path(run("xcrun", "simctl", "get_app_container", udid, BUNDLE_ID, "data").strip())
            for scenario in SCENARIOS:
                reduced = scenario == "reduced-transparency"
                run("xcrun", "simctl", "spawn", udid, "defaults", "write", "com.apple.Accessibility", "ReduceTransparencyEnabled", "-bool", str(reduced).lower())
                run("xcrun", "simctl", "launch", "--terminate-running-process", udid, BUNDLE_ID,
                    "--scenario", scenario, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN")
                time.sleep(3)
                observed = json.loads((container / "Documents" / f"preview-environment-{scenario}.json").read_text())
                (output / f"{family}-{scenario}-environment.json").write_text(json.dumps(observed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                if observed.get("scenario") != scenario or observed.get("colorScheme") != "light":
                    raise RuntimeError(f"Wrong app scenario/appearance: {observed}")
                if observed.get("reduceTransparency") != reduced or observed.get("reduceMotion") is not True:
                    raise RuntimeError(f"Simulator accessibility preferences did not reach the app: {observed}")
                if observed.get("language") != "zh-Hans":
                    raise RuntimeError(f"Chinese localization was not selected: {observed}")
                if observed.get("isAccessibilitySize") != (scenario == "large-type"):
                    raise RuntimeError(f"Wrong Dynamic Type size: {observed}")
                filename = f"{family}-{scenario}.png"
                screenshot = output / filename
                run("xcrun", "simctl", "io", udid, "screenshot", str(screenshot))
                dimensions = run("sips", "-g", "pixelWidth", "-g", "pixelHeight", str(screenshot))
                manifest["screenshots"].append({
                    "file": filename,
                    "scenario": scenario,
                    "device": device["name"],
                    "udid": udid,
                    "observed_environment": observed,
                    "sha256": hashlib.sha256(screenshot.read_bytes()).hexdigest(),
                    "pixel_size": [int(value) for value in re.findall(r"pixel(?:Width|Height): (\d+)", dimensions)],
                })
                (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                run("xcrun", "simctl", "terminate", udid, BUNDLE_ID)
        finally:
            run("xcrun", "simctl", "shutdown", udid, check=False)
    print(f"Rendered {len(manifest['screenshots'])} simulator screenshots.", flush=True)


if __name__ == "__main__":
    main()
