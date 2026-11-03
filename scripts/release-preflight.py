#!/usr/bin/env python3
"""Check the source identity for a release rehearsal. This does not publish."""

import argparse
from pathlib import Path
import plistlib
import re
import subprocess



import importlib.util
_channels_spec = importlib.util.spec_from_file_location("release_channels", Path(__file__).with_name("release-channels.py"))
channels = importlib.util.module_from_spec(_channels_spec)
_channels_spec.loader.exec_module(channels)

TAG_PATTERN = channels.TAG_PATTERN
BUILD_PATTERN = re.compile(r"[1-9][0-9]*\Z")


def validate(tag, head, main, tag_commit, version, build):
    match = TAG_PATTERN.fullmatch(tag)
    if not match:
        raise ValueError("Use vMAJOR.MINOR.PATCH, optionally followed by -alpha.N or -beta.N.")
    if version != channels.parse(tag)[0]:
        raise ValueError("The tag must match CFBundleShortVersionString.")
    if not isinstance(build, str) or not BUILD_PATTERN.fullmatch(build):
        raise ValueError("CFBundleVersion must be a positive integer.")
    if not head or not main or not tag_commit or head != main or head != tag_commit:
        raise ValueError("The checked-out commit and tag must match origin/main.")


def validate_notes(tag, directory=Path("docs/releases"), *, changelog=None):
    notes = (Path(directory) / (tag + ".txt")).read_text(encoding="utf-8")
    if not notes.strip():
        raise ValueError("Release notes must not be empty: " + tag + ".txt")
    if changelog is not None:
        contents = Path(changelog).read_text(encoding="utf-8")
        heading = "## [" + tag[1:] + "]"
        sections = contents.splitlines()
        matches = [i for i, line in enumerate(sections) if line == heading]
        if len(matches) != 1:
            raise ValueError("The changelog must contain one entry for the release tag.")
        start = matches[0] + 1
        end = next((i for i in range(start, len(sections)) if sections[i].startswith("## [")), len(sections))
        if "\n".join(sections[start:end]).strip() != notes.strip():
            raise ValueError("The changelog entry must match the release notes.")


def git_commit(ref):
    result = subprocess.run(["git", "rev-parse", "--verify", ref + "^{commit}"],
                            check=True, capture_output=True, text=True)
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="Existing release tag to rehearse")
    args = parser.parse_args()
    if not TAG_PATTERN.fullmatch(args.tag):
        parser.error("Use vMAJOR.MINOR.PATCH, optionally followed by -alpha.N or -beta.N.")
    try:
        with Path("Configuration/Info.plist").open("rb") as source:
            info = plistlib.load(source)
        validate(args.tag, git_commit("HEAD"), git_commit("refs/remotes/origin/main"),
                 git_commit("refs/tags/" + args.tag), info.get("CFBundleShortVersionString"),
                 info.get("CFBundleVersion"))
        validate_notes(args.tag, changelog=Path("CHANGELOG.md"))
    except (ValueError, OSError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        parser.exit(1, "Release preflight failed: " + str(error) + "\n")
    print("Release source preflight passed. Nothing was published.")


if __name__ == "__main__":
    main()
