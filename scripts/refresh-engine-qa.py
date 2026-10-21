#!/usr/bin/env python3
"""Refresh an existing isolated QA bundle. Keep its identity and library."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid


def refresh(source, target, identity, run=subprocess.run):
    source, target = Path(source).expanduser().resolve(), Path(target).expanduser().resolve()
    if source == target or source in target.parents or target in source.parents:
        raise ValueError("The build and QA bundles must be separate.")
    info = plistlib.loads((target / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.andrestobelem.draftly.engine-qa" or info.get("DraftlyUITesting") is not True:
        raise ValueError("The destination must be the isolated engine QA app.")
    uuid.UUID(info.get("DraftlyUITestingLibraryID", ""))
    schemes = [scheme for item in info.get("CFBundleURLTypes", []) for scheme in item.get("CFBundleURLSchemes", [])]
    if schemes != ["draftly-engine-qa"] or info.get("DraftlyCallbackScheme") != "draftly-engine-qa":
        raise ValueError("The QA app must use only its isolated callback scheme.")
    executable = info.get("CFBundleExecutable", "")
    if not executable or "/" in executable or not (source / "Contents/MacOS" / executable).is_file():
        raise ValueError("The build executable is unavailable.")
    processes = run(["ps", "-axo", "pid=,comm="], capture_output=True, text=True)
    if processes.returncode != 0 or not processes.stdout.strip():
        raise ValueError("Quit QA before refreshing. Its process must be absent.")
    destination_executable = target / "Contents/MacOS" / executable
    for line in processes.stdout.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) != 2 or not fields[0].isdigit():
            continue
        path = Path(fields[1])
        if path.resolve() == destination_executable or (not path.is_absolute() and path.name == executable):
            raise ValueError("Quit QA before refreshing. Its process must be absent.")
    hashes = {}
    for name in ["MacOS", "Resources", "Frameworks"]:
        current, replacement = target / "Contents" / name, source / "Contents" / name
        if current.exists():
            shutil.rmtree(current)
        if replacement.exists():
            shutil.copytree(replacement, current, symlinks=True)
            for file in replacement.rglob("*"):
                if file.is_file():
                    relative = file.relative_to(source / "Contents")
                    digest = hashlib.sha256(file.read_bytes()).hexdigest()
                    if hashlib.sha256((target / "Contents" / relative).read_bytes()).hexdigest() != digest:
                        raise ValueError("The copied QA file differs: " + str(relative))
                    hashes[str(relative)] = digest
    # QA must not publish duplicate capture entries in the user's Services menu.
    if "NSServices" in info:
        del info["NSServices"]
        (target / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    run(["codesign", "--force", "--deep", "--sign", identity, str(target)], check=True)
    run(["codesign", "--verify", "--deep", "--strict", str(target)], check=True)
    return hashes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    parser.add_argument("--identity", required=True)
    args = parser.parse_args()
    for name, digest in refresh(args.source, args.target, args.identity).items():
        print(digest + "  " + name + " (before signing)")


if __name__ == "__main__":
    main()
