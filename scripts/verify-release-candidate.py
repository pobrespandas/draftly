#!/usr/bin/env python3
"""Verify a restored release candidate without signing or publishing it."""

import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("github_stage_verify", ROOT / "scripts/stage-github-release.py")
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


def verify(directory, tag, public_key, *, verify_signature=stage.verify_candidate,
           source_commit=None, source_info=None):
    directory = Path(directory)
    stage.prepare.release.validate_key(public_key)
    if not (directory / "READY").is_file():
        raise ValueError("The candidate has no READY marker.")
    metadata = json.loads((directory / "candidate.json").read_text())
    if not isinstance(metadata, dict) or metadata.get("updatesEnabled") is not True:
        raise ValueError("The candidate must enable updates.")
    version, build = metadata.get("version"), metadata.get("build")
    stage.prepare.history.version_tuple(version)
    stage.prepare.history.build_number(build)
    if tag != "v" + version or metadata.get("tag") != tag:
        raise ValueError("The candidate tag does not match.")
    commit = metadata.get("sourceCommit")
    if not isinstance(commit, str) or not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("The candidate source identity is invalid.")
    actual_commit = source_commit if source_commit is not None else stage.prepare.release.source_commit(tag, stage.secret_free_run)
    if commit != actual_commit:
        raise ValueError("The candidate source commit does not match the tag.")
    package = directory / "Draftly.zip"
    before = stage.file_digest(package)
    digest = before.removeprefix("sha256:")
    if metadata.get("sha256") != digest or (directory / "Draftly.zip.sha256").read_text() != digest + "  Draftly.zip\n":
        raise ValueError("The candidate checksum does not match its ZIP.")
    stage.safe_archive(package)
    with zipfile.ZipFile(package) as archive:
        matches = [item for item in archive.infolist() if item.filename == "Draftly.app/Contents/Info.plist"]
        if len(matches) != 1 or matches[0].file_size > 1024 * 1024:
            raise ValueError("The candidate must contain one app Info.plist.")
        info = plistlib.loads(archive.read(matches[0]))
    if source_info is None:
        source_info = plistlib.loads((ROOT / "Configuration/Info.plist").read_bytes())
    stage.prepare.release.validate_metadata(source_info, info, public_key=public_key)
    if source_info.get("CFBundleShortVersionString") != version or source_info.get("CFBundleVersion") != build:
        raise ValueError("The candidate version does not match the source.")
    verify_signature(directory)
    if stage.file_digest(package) != before:
        raise ValueError("The candidate ZIP changed during verification.")
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--public-key", required=True)
    args = parser.parse_args()
    try:
        verify(args.candidate, args.tag, args.public_key)
    except (ValueError, OSError, subprocess.SubprocessError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        raise SystemExit("Candidate verification failed: " + str(error))
    print("Candidate verified. Nothing was published.")


if __name__ == "__main__":
    main()
