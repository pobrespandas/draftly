#!/usr/bin/env python3
"""Check published release history before a release. Never publish."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET


VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
BUILD = re.compile(r"[1-9][0-9]*\Z")
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
FEED_URL = "https://draftly.pobrespandas.com/appcast.xml"
MAX_FEED_BYTES = 2 * 1024 * 1024


def version_tuple(value):
    if not isinstance(value, str) or not VERSION.fullmatch(value):
        raise ValueError("A release version must use MAJOR.MINOR.PATCH.")
    return tuple(int(part) for part in value.split("."))


def build_number(value):
    if not isinstance(value, str) or not BUILD.fullmatch(value):
        raise ValueError("A release build must be a positive integer.")
    return int(value)


def feed_versions(data):
    if data is None:
        return None
    if len(data) > MAX_FEED_BYTES or b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
        raise ValueError("The appcast is too large or contains a document type.")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        raise ValueError("The appcast is not valid XML.") from error
    channel = root.find("channel") if root.tag == "rss" else None
    if channel is None:
        raise ValueError("The appcast must contain an RSS channel.")
    versions = {}
    builds = set()
    for item in channel.findall("item"):
        enclosure = item.find("enclosure")
        version = item.findtext(SPARKLE + "shortVersionString")
        build = item.findtext(SPARKLE + "version")
        if enclosure is not None:
            version = version or enclosure.get(SPARKLE + "shortVersionString")
            build = build or enclosure.get(SPARKLE + "version")
        parsed_version, parsed_build = version_tuple(version), build_number(build)
        if parsed_version in versions or parsed_build in builds:
            raise ValueError("The appcast contains a duplicate version or build.")
        versions[parsed_version] = parsed_build
        builds.add(parsed_build)
    return versions


def validate_history(version, build, releases, appcast, *, resume_candidate=False):
    candidate = version_tuple(version)
    candidate_build = build_number(build)
    if not isinstance(releases, list):
        raise ValueError("GitHub release history is invalid.")
    published = set()
    candidate_seen = False
    for release in releases:
        if (not isinstance(release, dict) or not isinstance(release.get("tag_name"), str)
                or not isinstance(release.get("draft"), bool)
                or not isinstance(release.get("prerelease"), bool)):
            raise ValueError("A GitHub release has invalid metadata.")
        tag = release["tag_name"]
        if tag == "v" + version:
            if not resume_candidate or candidate_seen or release["prerelease"]:
                raise ValueError("The candidate already has a GitHub release.")
            candidate_seen = True
            continue
        if release.get("draft") is not False or release.get("prerelease") is not False:
            continue
        if not tag.startswith("v"):
            raise ValueError("A published stable release has an invalid tag.")
        parsed = version_tuple(tag[1:])
        if parsed in published:
            raise ValueError("GitHub contains a duplicate stable version.")
        published.add(parsed)

    history = feed_versions(appcast)
    if history is None:
        if published:
            raise ValueError("The appcast is missing but published releases exist.")
        return
    if set(history) != published:
        raise ValueError("The appcast and published stable releases do not match.")
    ordered_builds = [history[key] for key in sorted(history)]
    if any(first >= second for first, second in zip(ordered_builds, ordered_builds[1:])):
        raise ValueError("Published builds do not increase with their versions.")
    if any(old >= candidate for old in history):
        raise ValueError("The candidate version must be greater than every published version.")
    if any(old >= candidate_build for old in history.values()):
        raise ValueError("The candidate build must be greater than every published build.")


def fetch_releases():
    command = ["gh", "api", "--paginate", "--slurp", "repos/pobrespandas/draftly/releases?per_page=100"]
    environment = dict(os.environ)
    environment.pop("DRAFTLY_SPARKLE_PRIVATE_KEY", None)
    environment.pop("DRAFTLY_FIREBASE_ACCESS_TOKEN", None)
    result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=60, env=environment)
    pages = json.loads(result.stdout)
    if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
        raise ValueError("GitHub returned invalid release pages.")
    return [release for page in pages for release in page]


def fetch_appcast():
    request = urllib.request.Request(FEED_URL, headers={"Cache-Control": "no-cache"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.geturl() != FEED_URL:
                raise ValueError("The appcast URL redirected.")
            data = response.read(MAX_FEED_BYTES + 1)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resume-candidate", action="store_true",
                        help="Allow one existing candidate release for verified recovery.")
    args = parser.parse_args()
    try:
        with Path("Configuration/Info.plist").open("rb") as source:
            info = plistlib.load(source)
        validate_history(info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"),
                         fetch_releases(), fetch_appcast(), resume_candidate=args.resume_candidate)
    except (ValueError, OSError, plistlib.InvalidFileException, subprocess.SubprocessError) as error:
        raise SystemExit("Release history check failed: " + str(error))
    print("Release history check passed. Nothing was published.")


if __name__ == "__main__":
    main()
