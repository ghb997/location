#!/usr/bin/env python3
"""Render real production SwiftUI components in an isolated simulator fixture."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
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


def wait_for_environment(path: Path, timeout: float = 90) -> dict:
    """First Simulator launch can take much longer than simctl launch returning."""
    deadline = time.monotonic() + timeout
    print(f"Waiting up to {timeout:g}s for app-rendered environment evidence: {path.name}", flush=True)
    while True:
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                return value
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"App did not produce valid environment evidence within {timeout:g}s: {path}")
        time.sleep(min(2, remaining))


def collect_failure_evidence(udid: str, prefix: str, output: Path, error: Exception) -> None:
    """Best-effort diagnostics must never mask the original rendering failure."""
    (output / f"{prefix}-failure.txt").write_text(repr(error) + "\n", encoding="utf-8")
    commands = [
        ("screenshot", ["xcrun", "simctl", "io", udid, "screenshot", str(output / f"{prefix}-failure.png")]),
        ("app-log", ["xcrun", "simctl", "spawn", udid, "log", "show", "--style", "compact", "--last", "3m",
                     "--predicate", 'process == "LocationDesignPreview"']),
    ]
    for name, command in commands:
        try:
            result = subprocess.run(command, check=False, text=True, capture_output=True, timeout=30)
            (output / f"{prefix}-{name}.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        except Exception as diagnostic_error:
            (output / f"{prefix}-{name}.log").write_text(repr(diagnostic_error) + "\n", encoding="utf-8")
    crash_roots = [
        Path.home() / "Library/Logs/DiagnosticReports",
        Path.home() / "Library/Developer/CoreSimulator/Devices" / udid / "data/Library/Logs/CrashReporter",
    ]
    copied = []
    for root in crash_roots:
        try:
            reports = sorted((path for path in root.rglob("LocationDesignPreview*") if path.is_file()),
                             key=lambda path: path.stat().st_mtime, reverse=True)[:5]
            for report in reports:
                destination = output / f"{prefix}-crash-{len(copied)}-{report.name}"
                shutil.copy2(report, destination)
                copied.append(destination.name)
        except OSError as diagnostic_error:
            print(f"Crash report collection: {diagnostic_error}", flush=True)
    print(f"Saved failure screenshot/log attempts and {len(copied)} crash reports for {prefix}.", flush=True)


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
        active_scenario = "setup"
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
            if not container.is_dir():
                raise RuntimeError(f"Simulator data container does not exist: {container}")
            for scenario in SCENARIOS:
                active_scenario = scenario
                reduced = scenario == "reduced-transparency"
                environment_path = container / "Documents" / f"preview-environment-{scenario}.json"
                environment_path.unlink(missing_ok=True)
                # Matches appium-ios-simulator's setReduceTransparency preference.
                run("xcrun", "simctl", "spawn", udid, "defaults", "write", "com.apple.Accessibility", "EnhancedBackgroundContrastEnabled", "-int", str(int(reduced)))
                run("xcrun", "simctl", "launch", "--terminate-running-process", udid, BUNDLE_ID,
                    "--scenario", scenario, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN")
                observed = wait_for_environment(environment_path)
                (output / f"{family}-{scenario}-environment.json").write_text(json.dumps(observed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                if observed.get("scenario") != scenario or observed.get("colorScheme") != "light":
                    raise RuntimeError(f"Wrong app scenario/appearance: {observed}")
                if observed.get("reduceTransparency") != reduced or observed.get("reduceMotion") is not True:
                    raise RuntimeError(f"Simulator accessibility preferences did not reach the app: {observed}")
                if observed.get("language") != "zh-Hans":
                    raise RuntimeError(f"Chinese localization was not selected: {observed}")
                if observed.get("isAccessibilitySize") != (scenario == "large-type"):
                    raise RuntimeError(f"Wrong Dynamic Type size: {observed}")
                time.sleep(3)
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
        except Exception as error:
            collect_failure_evidence(udid, f"{family}-{active_scenario}", output, error)
            raise
        finally:
            run("xcrun", "simctl", "shutdown", udid, check=False)
    print(f"Rendered {len(manifest['screenshots'])} simulator screenshots.", flush=True)


if __name__ == "__main__":
    main()
