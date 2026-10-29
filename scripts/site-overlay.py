#!/usr/bin/env python3
"""Plan website file changes against the exact live contents. Never publish."""


def valid_path(path):
    if not isinstance(path, str) or not path.startswith("/") or path.startswith("/__/"):
        return False
    parts = path[1:].split("/")
    if (not parts or any(part in ("", ".", "..") for part in parts)
            or any(ord(char) < 32 or char in "\\?#%" for char in path)
            or path == "/appcast.xml"):
        return False
    return True


def validate_sources(base, target):
    if not isinstance(base, dict) or not isinstance(target, dict):
        raise ValueError("The website file inventories are invalid.")
    for mapping in (base, target):
        if any(not valid_path(path) or not isinstance(data, bytes) for path, data in mapping.items()):
            raise ValueError("A website file or path is invalid.")


def plan(base, target, live):
    validate_sources(base, target)
    if not isinstance(live, dict):
        raise ValueError("The live website file inventory is invalid.")
    if any(not valid_path(path) or (data is not None and not isinstance(data, bytes)) for path, data in live.items()):
        raise ValueError("A live website file or path is invalid.")
    changes = {}
    for path in sorted(base.keys() | target.keys()):
        before, after = base.get(path), target.get(path)
        if before == after:
            continue
        if path not in live:
            raise ValueError("The live website file was not observed: " + path)
        actual = live[path]
        if actual == after:
            continue
        if actual != before:
            raise ValueError("The live website file changed independently: " + path)
        changes[path] = after
    return changes


def inspect(client, base, target, *, snapshot, fetch):
    validate_sources(base, target)
    before = snapshot(client)
    changed = {path for path in base.keys() | target.keys() if base.get(path) != target.get(path)}
    observed = {path: fetch(path, before["files"][path]) if path in before["files"] else None
                for path in sorted(changed)}
    changes = plan(base, target, observed)
    if snapshot(client) != before:
        raise ValueError("The live site changed during inspection.")
    return {"baseVersion": before["version"],
            "changedPaths": [path for path, data in changes.items() if data is not None],
            "deletedPaths": [path for path, data in changes.items() if data is None]}


def read_git_tree(root, commit):
    import os
    import re
    import subprocess

    if not isinstance(commit, str) or not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("The website source commit must be a full SHA-1.")
    env = {name: os.environ[name] for name in ("PATH", "HOME", "TMPDIR", "LANG", "LC_ALL") if name in os.environ}
    def git(*args):
        return subprocess.run(["git", *args], cwd=root, env=env, capture_output=True, check=True, timeout=30).stdout
    entries = git("ls-tree", "-r", "-z", commit, "--", "website/public/")
    files = {}
    for entry in entries.split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, blob = metadata.decode("ascii").split()
        if mode not in ("100644", "100755") or kind != "blob":
            raise ValueError("The website source contains a non-file entry.")
        relative = name.decode("utf-8").removeprefix("website/public/")
        path = "/" + relative
        if not valid_path(path) or path in files:
            raise ValueError("The website source contains an invalid path.")
        data = git("cat-file", "blob", blob)
        if len(data) > 2 * 1024 * 1024:
            raise ValueError("A website source file is too large.")
        files[path] = data
    if "/index.html" not in files:
        raise ValueError("The website source has no index page.")
    return files


def fetch_public(no_redirect, path, digest):
    import urllib.error
    import urllib.parse
    import urllib.request

    if not valid_path(path):
        raise ValueError("The public website path is invalid.")
    request = urllib.request.Request("https://draftly.pobrespandas.com" + urllib.parse.quote(path, safe="/"),
        headers={"Accept-Encoding": "identity", "Cache-Control": "no-cache"})
    try:
        with urllib.request.build_opener(no_redirect()).open(request, timeout=20) as response:
            if response.headers.get("Content-Encoding", "identity") != "identity":
                raise ValueError("A public website file has an unexpected content encoding.")
            if response.headers.get("ETag", "").strip('"') != digest:
                raise ValueError("A public website file does not match the live Firebase snapshot.")
            data = response.read(2 * 1024 * 1024 + 1)
    except (urllib.error.HTTPError, urllib.error.URLError) as error:
        raise ValueError("A public website file could not be read.") from error
    if len(data) > 2 * 1024 * 1024:
        raise ValueError("A public website file is too large.")
    return data


def main():
    import argparse
    import importlib.util
    import json
    import os
    from pathlib import Path
    import subprocess

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, help="Full commit of the site source deployed before these changes.")
    parser.add_argument("--target", required=True, help="Full commit containing the new site source.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    spec = importlib.util.spec_from_file_location("firebase_site_inspection", root / "scripts/firebase-stage-appcast.py")
    firebase = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(firebase)
    try:
        base, target = read_git_tree(root, args.base), read_git_tree(root, args.target)
        client = firebase.HostingClient(os.environ.get("DRAFTLY_FIREBASE_ACCESS_TOKEN"))
        def fetch(path, digest):
            return fetch_public(firebase.NoRedirect, path, digest)
        result = inspect(client, base, target, snapshot=firebase.snapshot, fetch=fetch)
        result.update({"baseCommit": args.base, "targetCommit": args.target})
        print(json.dumps(result, indent=2))
    except (ValueError, OSError, UnicodeError, subprocess.SubprocessError) as error:
        raise SystemExit("Site inspection failed: " + str(error))


if __name__ == "__main__":
    main()
