#!/usr/bin/env python3
"""Verify a candidate and upload missing assets to a GitHub draft release."""

import argparse
import base64
import hashlib
import html
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import stat
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "repos/pobrespandas/draftly"
UNSET = object()


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare = load_module("prepare_appcast", "prepare-appcast.py")
firebase = load_module("firebase_stage", "firebase-stage-appcast.py")
preflight = load_module("release_preflight", "release-preflight.py")


def safe_archive(path):
    seen = set()
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = entry.filename
            normalized = posixpath.normpath(name)
            if (not name or "\\" in name or name.startswith("/") or "\x00" in name
                    or ".." in PurePosixPath(name).parts
                    or normalized in seen or normalized == "." or normalized.startswith("../")
                    or not (normalized == "Draftly.app" or normalized.startswith("Draftly.app/")
                            or normalized in ("__MACOSX", "__MACOSX/Draftly.app")
                            or normalized.startswith("__MACOSX/Draftly.app/"))):
                raise ValueError("The candidate ZIP contains an unsafe or duplicate path.")
            seen.add(normalized)
            mode = (entry.external_attr >> 16) & 0o170000
            if mode not in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK):
                raise ValueError("The candidate ZIP contains an unsupported file type.")
            if mode == stat.S_IFLNK:
                if not normalized.startswith("Draftly.app/") or entry.file_size > 4096:
                    raise ValueError("The candidate ZIP contains an unsafe link.")
                target = archive.read(entry).decode("utf-8")
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(normalized), target))
                if (not target or target.startswith("/") or "\\" in target or "\x00" in target
                        or not (resolved == "Draftly.app" or resolved.startswith("Draftly.app/"))):
                    raise ValueError("The candidate ZIP contains an unsafe link target.")


def inspect_inputs(candidate, staged, secret, notes):
    candidate, staged = Path(candidate), Path(staged)
    if not isinstance(notes, str) or not notes.strip() or len(notes.encode("utf-8")) > 65536:
        raise ValueError("Release notes must contain between 1 and 65536 bytes of text.")
    if not (staged / "READY").is_file():
        raise ValueError("The staged appcast has no READY marker.")
    key = prepare.private_key(secret)
    metadata, length, signature, minimum = prepare.candidate_details(candidate, key)
    archive = candidate / "Draftly.zip"
    safe_archive(archive)
    public = base64.b64encode(key.public_key().public_bytes(
        prepare.serialization.Encoding.Raw, prepare.serialization.PublicFormat.Raw)).decode("ascii")
    feed = (staged / "appcast.xml").read_bytes()
    versions = firebase.verify_feed(feed, public)
    expected = prepare.history.version_tuple(metadata["version"])
    if versions.get(expected) != int(metadata["build"]):
        raise ValueError("The signed appcast does not contain the candidate build.")
    root = ET.fromstring(feed)
    items = [item for item in root.find("channel").findall("item")
             if item.findtext(prepare.history.SPARKLE + "shortVersionString") == metadata["version"]]
    if len(items) != 1:
        raise ValueError("The signed appcast does not contain exactly one candidate.")
    item = items[0]
    enclosure = item.find("enclosure")
    expected_url = "https://github.com/pobrespandas/draftly/releases/download/" + metadata["tag"] + "/Draftly.zip"
    if (enclosure is None or enclosure.get("url") != expected_url or enclosure.get("length") != str(length)
            or enclosure.get("type") != "application/octet-stream"
            or enclosure.get(prepare.history.SPARKLE + "edSignature") != signature
            or item.findtext(prepare.history.SPARKLE + "minimumSystemVersion") != minimum
            or item.findtext("description") != "<pre>" + html.escape(notes) + "</pre>"):
        raise ValueError("The signed appcast does not match the candidate and release notes.")
    expected_checksum = metadata["sha256"] + "  Draftly.zip\n"
    if (candidate / "Draftly.zip.sha256").read_text() != expected_checksum:
        raise ValueError("The candidate checksum file does not match the ZIP.")
    return metadata


def secret_free_run(command, **options):
    env = dict(options.pop("env", os.environ))
    for name in ("DRAFTLY_SPARKLE_PRIVATE_KEY", "DRAFTLY_FIREBASE_ACCESS_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"):
        env.pop(name, None)
    return subprocess.run(command, env=env, **options)


def verify_candidate(candidate, *, runner=secret_free_run):
    archive = Path(candidate) / "Draftly.zip"
    with tempfile.TemporaryDirectory(prefix="draftly-verify-release-") as temporary:
        runner(["ditto", "-x", "-k", str(archive), temporary], check=True, capture_output=True)
        app = Path(temporary) / "Draftly.app"
        runner([sys.executable, str(ROOT / "scripts/verify-cloud-signing.py"), str(app),
                "--expected-bundle-identifier", prepare.release.BUNDLE, "--expected-team", prepare.release.TEAM,
                "--expected-container", prepare.release.CONTAINER, "--expected-cloud-environment", "Production",
                "--expected-push-environment", "production", "--require-developer-id"], check=True, capture_output=True)
        runner(["xcrun", "stapler", "validate", str(app)], check=True, capture_output=True)
        runner(["spctl", "--assess", "--type", "execute", str(app)], check=True, capture_output=True)
        metadata = json.loads((Path(candidate) / "candidate.json").read_text())
        dmg = load_module("release_disk_image_verify", "release-dmg.py")
        disk_assets = (dmg.assets(candidate, metadata["version"], metadata["sha256"])
                       if (Path(candidate) / "disk-image.json").exists() else {})
        for name, path in disk_assets.items():
            if name.endswith(".dmg"):
                dmg.verify(path, lambda command: runner(command, check=True, capture_output=True))


def file_digest(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


class GitHub:
    def command(self, arguments, *, body=None):
        env = dict(os.environ)
        for name in ("DRAFTLY_SPARKLE_PRIVATE_KEY", "DRAFTLY_FIREBASE_ACCESS_TOKEN"):
            env.pop(name, None)
        try:
            result = subprocess.run(["gh", *arguments], cwd=ROOT, input=body, text=True,
                                    capture_output=True, timeout=120, env=env)
        except (OSError, subprocess.SubprocessError) as error:
            raise ValueError("GitHub command could not complete.") from error
        if result.returncode:
            # A command can fail after GitHub accepted it. Reinspect before retrying.
            raise ValueError("GitHub command failed or its result is unknown. Reinspect the draft before retrying.")
        return result.stdout

    def api(self, path, *, body=None):
        arguments = ["api"] + (["--method", "POST", "--input", "-"] if body is not None else []) + [path]
        try:
            result = json.loads(self.command(arguments, body=json.dumps(body) if body is not None else None))
        except ValueError as error:
            raise ValueError("GitHub returned invalid data or did not complete the request.") from error
        if not isinstance(result, dict):
            raise ValueError("GitHub returned invalid data.")
        return result

    def refs(self, tag):
        main = self.api(REPOSITORY + "/git/ref/heads/main").get("object", {})
        ref = self.api(REPOSITORY + "/git/ref/tags/" + tag).get("object", {})
        if not isinstance(main, dict) or not isinstance(ref, dict):
            raise ValueError("The remote main or release tag is invalid.")
        for _ in range(5):
            if ref.get("type") != "tag":
                break
            sha = ref.get("sha", "")
            if not isinstance(sha, str) or not re.fullmatch(r"[a-f0-9]{40}", sha):
                raise ValueError("The remote tag object is invalid.")
            ref = self.api(REPOSITORY + "/git/tags/" + sha).get("object", {})
            if not isinstance(ref, dict):
                raise ValueError("The remote tag object is invalid.")
        if main.get("type") != "commit" or ref.get("type") != "commit":
            raise ValueError("The remote main or release tag is invalid.")
        return main.get("sha"), ref.get("sha")

    def releases(self):
        try:
            pages = json.loads(self.command(["api", "--paginate", "--slurp", REPOSITORY + "/releases?per_page=100"]))
        except ValueError as error:
            raise ValueError("GitHub release history is unavailable.") from error
        if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
            raise ValueError("GitHub release history is invalid.")
        return [item for page in pages for item in page]

    def create_draft(self, tag, notes):
        return self.api(REPOSITORY + "/releases", body={"tag_name": tag, "name": "Draftly " + tag[1:],
                                                       "body": notes, "draft": True, "prerelease": False})

    def upload(self, tag, paths):
        self.command(["release", "upload", tag, *[str(path) for path in paths], "--repo", "pobrespandas/draftly"])


def find_release(releases, tag):
    matches = [item for item in releases if isinstance(item, dict) and item.get("tag_name") == tag]
    if len(matches) > 1:
        raise ValueError("GitHub returned duplicate releases for the candidate.")
    return matches[0] if matches else None


def validate_assets(release, expected, notes, tag, *, allow_missing):
    if (not isinstance(release, dict) or not isinstance(release.get("draft"), bool)
            or release.get("tag_name") != tag or release.get("name") != "Draftly " + tag[1:]
            or release.get("prerelease") is not False or release.get("body") != notes
            or not isinstance(release.get("assets"), list)):
        raise ValueError("The GitHub release metadata does not match the candidate.")
    seen = set()
    for asset in release["assets"]:
        if not isinstance(asset, dict):
            raise ValueError("GitHub returned an invalid release asset.")
        name = asset.get("name")
        if name not in expected or name in seen:
            raise ValueError("The GitHub release has an unexpected or duplicate asset.")
        seen.add(name)
        path = expected[name]
        if (asset.get("state") != "uploaded" or asset.get("size") != path.stat().st_size
                or asset.get("digest") != file_digest(path)):
            raise ValueError("A GitHub asset does not match the candidate.")
    missing = set(expected) - seen
    if missing and not allow_missing:
        raise ValueError("The published GitHub release is missing candidate assets.")
    return [expected[name] for name in sorted(missing)]


def release_assets(candidate, staged):
    candidate, staged = Path(candidate), Path(staged)
    metadata = json.loads((candidate / "candidate.json").read_text())
    dmg = load_module("release_disk_image", "release-dmg.py")
    result = {"Draftly.zip": candidate / "Draftly.zip", "Draftly.zip.sha256": candidate / "Draftly.zip.sha256",
              "candidate.json": candidate / "candidate.json", "appcast.xml": staged / "appcast.xml"}
    if (candidate / "disk-image.json").exists():
        result.update(dmg.assets(candidate, metadata["version"], metadata["sha256"]))
    return result


def stage(candidate, staged, notes, secret, *, github=None, verify=verify_candidate, current_feed=UNSET):
    expected = release_assets(candidate, staged)
    hashes = {name: (path.stat().st_size, file_digest(path)) for name, path in expected.items()}
    metadata = inspect_inputs(candidate, staged, secret, notes)
    verify(candidate)
    if any((path.stat().st_size, file_digest(path)) != hashes[name] for name, path in expected.items()):
        raise ValueError("A candidate file changed during verification.")
    tag, version, build, commit = metadata["tag"], metadata["version"], metadata["build"], metadata["sourceCommit"]
    local = prepare.release.source_commit(tag, secret_free_run)
    github = github or GitHub()
    main, remote_tag = github.refs(tag)
    preflight.validate(tag, local, main, remote_tag, version, build)
    if local != commit:
        raise ValueError("The candidate was built from a different source commit.")
    releases = github.releases()
    existing = find_release(releases, tag)
    if current_feed is UNSET:
        current_feed = prepare.history.fetch_appcast()
    key = prepare.private_key(secret)
    public = base64.b64encode(key.public_key().public_bytes(
        prepare.serialization.Encoding.Raw, prepare.serialization.PublicFormat.Raw)).decode("ascii")
    current_versions = firebase.verify_feed(current_feed, public) if current_feed is not None else {}
    if current_feed is not None:
        old_items = firebase.feed_items(current_feed)
        staged_items = firebase.feed_items((Path(staged) / "appcast.xml").read_bytes())
        if any(staged_items.get(version) != item for version, item in old_items.items()):
            raise ValueError("The staged appcast changes a published release item.")
    version_key = prepare.history.version_tuple(version)
    if version_key in current_versions:
        if existing is None or existing.get("draft") is not False or current_feed != (Path(staged) / "appcast.xml").read_bytes():
            raise ValueError("The live appcast already contains a different candidate.")
    else:
        prepare.history.validate_history(version, build, [item for item in releases if item is not existing], current_feed)
    if hashes["Draftly.zip"][1] != "sha256:" + metadata["sha256"]:
        raise ValueError("The candidate ZIP changed after verification.")

    def check_inputs():
        if any((path.stat().st_size, file_digest(path)) != hashes[name] for name, path in expected.items()):
            raise ValueError("A verified candidate file changed during staging.")
        latest_main, latest_tag = github.refs(tag)
        if latest_main != commit or latest_tag != commit or prepare.release.source_commit(tag, secret_free_run) != commit:
            raise ValueError("The source commit or remote refs changed during staging.")

    if existing is None:
        check_inputs()
        existing = github.create_draft(tag, notes)
        if existing.get("tag_name") != tag or existing.get("draft") is not True:
            raise ValueError("GitHub did not create the expected draft.")
    missing = validate_assets(existing, expected, notes, tag, allow_missing=existing.get("draft") is True)
    if missing:
        check_inputs()
        github.upload(tag, missing)
        existing = find_release(github.releases(), tag)
        if existing is None or existing.get("draft") is not True:
            raise ValueError("The GitHub draft changed during asset upload.")
        check_inputs()
        validate_assets(existing, expected, notes, tag, allow_missing=False)
    check_inputs()
    return {"tag": tag, "draft": existing["draft"], "assets": sorted(expected), "sha256": metadata["sha256"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--appcast", required=True, help="Directory with staged appcast and READY marker.")
    parser.add_argument("--notes", required=True, help="Same UTF-8 release notes used for the appcast.")
    args = parser.parse_args()
    try:
        secret = os.environ.get("DRAFTLY_SPARKLE_PRIVATE_KEY")
        if not secret:
            raise ValueError("DRAFTLY_SPARKLE_PRIVATE_KEY is required.")
        print(json.dumps(stage(args.candidate, args.appcast, Path(args.notes).read_text(encoding="utf-8"), secret.strip()), indent=2))
    except (ValueError, OSError, UnicodeError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        raise SystemExit("GitHub release staging failed: " + str(error))


if __name__ == "__main__":
    main()
