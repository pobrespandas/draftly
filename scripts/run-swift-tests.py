#!/usr/bin/env python3
"""Run headless Swift tests and require complete machine-readable results."""
import argparse
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
        root = ET.parse(path).getroot()
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


def run_target(module, expected, output, *, concurrent_app=False):
    output.mkdir(parents=True, exist_ok=True)
    reports = [output / "results.xml", output / "results-swift-testing.xml"]
    for report in reports:
        report.unlink(missing_ok=True)
    with (output / "tests.log").open("w") as log:
        command = ["swift", "test", "--filter", module, "--xunit-output", str(reports[0])]
        if module != "DraftlyTests" or not concurrent_app:
            command.append("--no-parallel")
        process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if process.returncode:
        raise ValueError("Swift tests failed. See " + str(output / "tests.log"))
    return verify_results(expected, reports)


def run(output, *, concurrent_app=False):
    output.mkdir(parents=True, exist_ok=True)
    inventory = subprocess.run(["swift", "test", "list"], capture_output=True, text=True)
    (output / "inventory.log").write_text(inventory.stdout + inventory.stderr)
    if inventory.returncode:
        raise ValueError("Swift test discovery failed. See inventory.log.")
    expected = test_inventory(inventory.stdout)
    counts = Counter()
    # Keep target reports separate. Core tests also share limited runner resources.
    for module in sorted({name.split(".", 1)[0] for name in expected}):
        selected = {name for name in expected if name.startswith(module + ".")}
        if not selected:
            raise ValueError("The test inventory has no cases for " + module)
        counts.update(run_target(module, selected, output / module, concurrent_app=concurrent_app))
    print("Verified complete Swift results: " + ", ".join(
        name + " " + str(count) for name, count in sorted(counts.items())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path,
                        help="Keep logs and XML in this directory. Default: temporary files.")
    parser.add_argument("--concurrent-app", action="store_true",
                        help="Diagnose concurrent AppKit tests. Default: serial app tests.")
    args = parser.parse_args()
    temporary = args.output_dir is None
    folder = Path(tempfile.mkdtemp(prefix="Draftly-Tests-")) if temporary else args.output_dir
    try:
        run(folder.resolve(), concurrent_app=args.concurrent_app)
    except (ValueError, OSError, ET.ParseError) as error:
        print("Swift verification failed: " + str(error))
        print("Diagnostic files retained in " + str(folder.resolve()))
        return 1
    if temporary:
        shutil.rmtree(folder)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
