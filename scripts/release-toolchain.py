#!/usr/bin/env python3
"""Reject release toolchains that omit supported macOS 27 features."""
import re
import subprocess


def validate(sdk, swift):
    match = re.fullmatch(r"(\d+)(?:\.\d+)*", sdk.strip())
    if not match or int(match.group(1)) < 27:
        raise ValueError("Release signing requires the macOS 27 SDK to preserve all supported features.")
    match = re.search(r"Apple Swift version (\d+)\.(\d+)", swift)
    if not match or (int(match.group(1)), int(match.group(2))) < (6, 4):
        raise ValueError("Release signing requires Swift 6.4 or later to preserve all supported features.")


def check(runner=subprocess.run):
    def output(command):
        return runner(command, check=True, text=True, capture_output=True).stdout
    validate(output(["xcrun", "--sdk", "macosx", "--show-sdk-version"]), output(["swiftc", "--version"]))


if __name__ == "__main__":
    try:
        check()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit("Release toolchain check failed: " + str(error))
