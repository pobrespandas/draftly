#!/usr/bin/env python3
"""Check the source identity for a release rehearsal. This does not publish."""

import argparse
from pathlib import Path
import plistlib
import re
import subprocess


TAG_PATTERN = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
BUILD_PATTERN = re.compile(r"[1-9][0-9]*\Z")


def validate(tag, head, main, tag_commit, version, build):
    match = TAG_PATTERN.fullmatch(tag)
    if not match:
        raise ValueError("The tag must use the form vMAJOR.MINOR.PATCH.")
    if version != tag[1:]:
        raise ValueError("The tag must match CFBundleShortVersionString.")
    if not isinstance(build, str) or not BUILD_PATTERN.fullmatch(build):
        raise ValueError("CFBundleVersion must be a positive integer.")
    if not head or not main or not tag_commit or head != main or head != tag_commit:
        raise ValueError("The checked-out commit and tag must match origin/main.")


def validate_notes(tag, directory=Path("docs/releases")):
    notes = (Path(directory) / (tag + ".txt")).read_text(encoding="utf-8")
    if not notes.strip():
        raise ValueError("Release notes must not be empty: " + tag + ".txt")


def git_commit(ref):
    result = subprocess.run(["git", "rev-parse", "--verify", ref + "^{commit}"],
                            check=True, capture_output=True, text=True)
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="Existing release tag to rehearse")
    args = parser.parse_args()
    if not TAG_PATTERN.fullmatch(args.tag):
        parser.error("The tag must use the form vMAJOR.MINOR.PATCH.")
    try:
        with Path("Configuration/Info.plist").open("rb") as source:
            info = plistlib.load(source)
        validate(args.tag, git_commit("HEAD"), git_commit("refs/remotes/origin/main"),
                 git_commit("refs/tags/" + args.tag), info.get("CFBundleShortVersionString"),
                 info.get("CFBundleVersion"))
        validate_notes(args.tag)
    except (ValueError, OSError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        parser.exit(1, "Release preflight failed: " + str(error) + "\n")
    print("Release source preflight passed. Nothing was published.")


if __name__ == "__main__":
    main()
