#!/usr/bin/env python3
"""Run headless Swift tests and require complete machine-readable results."""
import argparse
from datetime import datetime, timezone
import json
import os
import stat
import time
from collections import Counter
from pathlib import Path
import subprocess
import shutil
import re
import tempfile
import xml.etree.ElementTree as ET


def test_inventory(output):
    tests = [line.strip() for line in output.splitlines()
             if re.fullmatch(r"[\w.]+/[^\s/]+\(.*\)", line.strip())]
    if not tests or len(tests) != len(set(tests)):
        raise ValueError("The Swift test inventory is empty or contains duplicates.")
    return set(tests)


def verify_results(expected, reports):
    actual = []
    found = False
    for path in reports:
        if not path.exists():
            continue
        found = True
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as error:
            raise ValueError("The Swift test report is incomplete or invalid: " + str(path)
                             + ". Check the test log for failures or an interrupted process.") from error
        if root.tag not in {"testsuites", "testsuite"}:
            raise ValueError("The test report has an invalid root element.")
        for suite in (node for node in root.iter() if node.tag in {"testsuite", "testsuites"}):
            cases = list(suite.iter("testcase"))
            if (suite.tag == "testsuite" or suite.get("tests") is not None) and int(suite.get("tests", "-1")) != len(cases):
                raise ValueError("The test report count does not match its cases.")
            for field in ("failures", "errors", "skipped"):
                if int(suite.get(field, "0")) != 0:
                    raise ValueError("The test report contains " + field + ".")
        for case in root.iter("testcase"):
            if any(case.find(field) is not None for field in ("failure", "error", "skipped")):
                raise ValueError("A test did not pass: " + case.get("name", "unknown"))
            if not case.get("classname") or not case.get("name"):
                raise ValueError("A test result has no identity.")
            actual.append(case.get("classname") + "/" + case.get("name"))
    if not found:
        raise ValueError("The Swift test command produced no test report.")
    duplicates = [name for name, count in Counter(actual).items() if count != 1]
    if duplicates:
        raise ValueError("Duplicate test results: " + ", ".join(sorted(duplicates)))
    missing, unexpected = expected - set(actual), set(actual) - expected
    if missing or unexpected:
        details = []
        if missing:
            details.append("Missing results: " + ", ".join(sorted(missing)))
        if unexpected:
            details.append("Unexpected results: " + ", ".join(sorted(unexpected)))
        raise ValueError("\n".join(details))
    return Counter(name.split(".", 1)[0] for name in actual)


def capture_native_crashes(source, destination, started_at):
    """Copy bounded, fresh test-process reports from an isolated CI runner."""
    copied, skipped = [], 0
    try:
        if source.is_symlink():
            return {"state": "unavailable", "files": []}
        candidates = sorted(source.iterdir())
    except OSError:
        return {"state": "unavailable", "files": []}
    for path in candidates:
        if not re.fullmatch(r"(?:DraftlyTests|swiftpm-testing-helper|swift-test|xctest)[_-].+\.(?:ips|crash)", path.name):
            continue
        descriptor = None
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_mtime < started_at:
                continue
            if info.st_size > 2 * 1024 * 1024 or len(copied) >= 4:
                skipped += 1
                continue
            data = bytearray()
            while len(data) <= 2 * 1024 * 1024:
                chunk = os.read(descriptor, min(65536, 2 * 1024 * 1024 + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
            if len(data) > 2 * 1024 * 1024:
                skipped += 1
                continue
            destination.mkdir(parents=True, exist_ok=True)
            (destination / path.name).write_bytes(data)
            copied.append(path.name)
        except OSError:
            skipped += 1
        finally:
            if descriptor is not None:
                os.close(descriptor)
    return {"state": "scanned", "files": copied, "skipped": skipped}


def collect_ci_crashes(output):
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise ValueError("Native crash collection is restricted to the isolated CI runner.")
    for path in sorted(output.glob("*/process.json")):
        if path.is_symlink() or path.parent.is_symlink():
            continue
        record = json.loads(path.read_text())
        started = datetime.fromisoformat(record["startedAt"])
        if started.tzinfo is None or record.get("scope") != "swift_cli":
            raise ValueError("The test process record has no valid start time or scope.")
        record["nativeCrashReports"] = capture_native_crashes(
            Path.home() / "Library/Logs/DiagnosticReports", path.parent / "native-crashes", started.timestamp())
        path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")


def run_target(module, expected, output, *, concurrent_app=False, test_filter=None):
    output.mkdir(parents=True, exist_ok=True)
    reports = [output / "results.xml", output / "results-swift-testing.xml"]
    for report in reports:
        report.unlink(missing_ok=True)
    # Discovery already built the products. Run that same inventory without rebuilding.
    command = ["swift", "test", "--skip-build", "--filter", test_filter or module, "--xunit-output", str(reports[0])]
    if module != "DraftlyTests" or not concurrent_app:
        command.append("--no-parallel")
    started = time.monotonic()
    started_at = time.time()
    record = {"scope": "swift_cli", "command": command,
              "startedAt": datetime.now(timezone.utc).isoformat(), "state": "invocation_started",
              "returnCode": None, "signal": None, "elapsedSeconds": None, "verification": "not_run"}

    def save_record():
        (output / "process.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")

    save_record()
    try:
        with (output / "tests.log").open("w") as log:
            process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    except OSError:
        record.update(state="launch_failed", elapsedSeconds=time.monotonic() - started)
        save_record()
        raise
    record.update(state="exited", returnCode=process.returncode,
                  signal=-process.returncode if process.returncode < 0 else None,
                  elapsedSeconds=time.monotonic() - started,
                  finishedAt=datetime.now(timezone.utc).isoformat())
    save_record()
    if os.environ.get("GITHUB_ACTIONS") == "true":
        record["nativeCrashReports"] = capture_native_crashes(
            Path.home() / "Library/Logs/DiagnosticReports", output / "native-crashes", started_at)
        save_record()
    if process.returncode:
        raise ValueError("Swift tests failed. See " + str(output / "tests.log"))
    try:
        counts = verify_results(expected, reports)
    except ValueError:
        record["verification"] = "rejected"
        save_record()
        raise
    record["verification"] = "passed"
    save_record()
    return counts



def run(output, *, concurrent_app=False, diagnostic_suite=None):
    output.mkdir(parents=True, exist_ok=True)
    inventory = subprocess.run(["swift", "test", "list"], capture_output=True, text=True)
    (output / "inventory.log").write_text(inventory.stdout + inventory.stderr)
    if inventory.returncode:
        raise ValueError("Swift test discovery failed. See inventory.log.")
    expected = test_inventory(inventory.stdout)
    if diagnostic_suite:
        prefix = "DraftlyTests." + diagnostic_suite + "/"
        expected = {name for name in expected if name.startswith(prefix)}
        if not expected:
            raise ValueError("The diagnostic suite has no discovered cases.")
    counts = Counter()
    # Keep target reports separate. Core tests also share limited runner resources.
    for module in sorted({name.split(".", 1)[0] for name in expected}):
        selected = {name for name in expected if name.startswith(module + ".")}
        if not selected:
            raise ValueError("The test inventory has no cases for " + module)
        test_filter = "DraftlyTests." + diagnostic_suite if diagnostic_suite else None
        counts.update(run_target(module, selected, output / module, concurrent_app=concurrent_app,
                                 test_filter=test_filter))
    print("Verified complete Swift results: " + ", ".join(
        name + " " + str(count) for name, count in sorted(counts.items())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path,
                        help="Keep logs and XML in this directory. Default: temporary files.")
    parser.add_argument("--collect-native-crashes", action="store_true",
                        help="Collect delayed crash reports in CI without running tests.")
    parser.add_argument("--concurrent-app", action="store_true",
                        help="Diagnose concurrent AppKit tests. Default: serial app tests.")
    parser.add_argument("--diagnostic-suite", choices=["LibrarySplitViewTests", "TypewriterScrollingTests", "ThemeRenderingTests"],
                        help="Run one suite for diagnosis, not release acceptance.")
    args = parser.parse_args()
    if args.collect_native_crashes:
        if args.output_dir is None:
            parser.error("--collect-native-crashes requires --output-dir")
        try:
            collect_ci_crashes(args.output_dir.resolve())
        except (ValueError, OSError, KeyError) as error:
            print("Native crash collection failed: " + str(error))
            return 1
        return 0
    temporary = args.output_dir is None
    folder = Path(tempfile.mkdtemp(prefix="Draftly-Tests-")) if temporary else args.output_dir
    try:
        run(folder.resolve(), concurrent_app=args.concurrent_app, diagnostic_suite=args.diagnostic_suite)
    except (ValueError, OSError, ET.ParseError) as error:
        print("Swift verification failed: " + str(error))
        print("Diagnostic files retained in " + str(folder.resolve()))
        return 1
    if temporary:
        shutil.rmtree(folder)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
