#!/usr/bin/env python3
"""Publish a verified GitHub draft after checking a staged Firebase version."""

import argparse
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import zipfile


ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("github_stage", ROOT / "scripts/stage-github-release.py")
github_stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(github_stage)
firebase = github_stage.firebase


class PublishingGitHub(github_stage.GitHub):
    def publish(self, release_id):
        if isinstance(release_id, bool) or not isinstance(release_id, int) or release_id <= 0:
            raise ValueError("The GitHub release ID is invalid.")
        try:
            response = json.loads(self.command(["api", "--method", "PATCH", "--input", "-",
                github_stage.REPOSITORY + "/releases/" + str(release_id)],
                body=json.dumps({"draft": False, "prerelease": False, "make_latest": "true"})))
        except ValueError as error:
            raise ValueError("GitHub publication did not return valid data. Reinspect the release.") from error
        if not isinstance(response, dict) or response.get("id") != release_id or response.get("draft") is not False:
            raise ValueError("GitHub did not confirm publication. Reinspect the release.")


def validate_site(client, receipt, feed, compressed):
    if not isinstance(receipt, dict):
        raise ValueError("The Firebase staging receipt is invalid.")
    base, staged, digest = receipt.get("baseVersion"), receipt.get("stagedVersion"), receipt.get("appcastHash")
    if (not isinstance(base, str) or not firebase.VERSION_PATTERN.fullmatch(base)
            or not isinstance(staged, str) or not firebase.VERSION_PATTERN.fullmatch(staged) or staged == base
            or not isinstance(digest, str) or not firebase.HASH_PATTERN.fullmatch(digest)):
        raise ValueError("The Firebase staging receipt is invalid.")
    actual_digest = hashlib.sha256(compressed).hexdigest()
    if actual_digest != digest:
        raise ValueError("The staged appcast differs from the Firebase receipt.")
    live = firebase.snapshot(client)
    if live["version"] not in (base, staged):
        raise ValueError("The live Firebase version changed after staging.")
    if live["version"] == base:
        base_files, base_config = live["files"], live["config"]
    else:
        base_details = client.request("GET", base)
        if base_details.get("name") != base or base_details.get("status") != "FINALIZED":
            raise ValueError("The original Firebase version is unavailable for recovery.")
        base_files, base_config = firebase.list_files(client, base), base_details.get("config", {})
    if receipt.get("preservedFiles") != len(base_files):
        raise ValueError("The Firebase receipt has an incorrect file count.")
    staged_files = firebase.list_files(client, staged)
    expected = dict(base_files)
    expected["/appcast.xml"] = digest
    website = receipt.get("websiteHashes", {})
    if not isinstance(website, dict) or len(website) > 100:
        raise ValueError("The Firebase website receipt is invalid.")
    for path, value in website.items():
        if not firebase.site_overlay.valid_path(path) or (value is not None and
                (not isinstance(value, str) or not firebase.HASH_PATTERN.fullmatch(value))):
            raise ValueError("The Firebase website receipt is invalid.")
        if value is None:
            expected.pop(path, None)
        else:
            expected[path] = value
    if "/index.html" not in expected:
        raise ValueError("The staged website has no index page.")
    if staged_files != expected:
        raise ValueError("The staged Firebase version does not preserve the live files.")
    details = client.request("GET", staged)
    if (details.get("name") != staged or details.get("status") != "FINALIZED"
            or details.get("config", {}) != base_config):
        raise ValueError("The staged Firebase configuration is invalid.")
    source = receipt.get("websiteSource")
    if source is not None:
        labels = details.get("labels", {})
        if not isinstance(source, dict) or not isinstance(labels, dict) or labels.get("draftly-site-source") != source.get("target"):
            raise ValueError("The staged website source differs from its receipt.")
    if live["version"] == staged and (live["files"] != expected or live["config"] != base_config):
        raise ValueError("The promoted Firebase version does not match the receipt.")
    if firebase.snapshot(client)["version"] != live["version"]:
        raise ValueError("The live Firebase version changed during verification.")
    return "promoted" if live["version"] == staged else "staged"


def verify_website_checkpoint(staged, receipt, commit):
    website = receipt.get("websiteHashes")
    if not isinstance(website, dict) or len(website) > 100:
        raise ValueError("The Firebase website receipt is invalid.")
    journal = staged / "firebase-journal.json"
    if journal.is_symlink() or not journal.is_file() or journal.stat().st_size > 24 * 1024 * 1024:
        raise ValueError("The website staging journal is invalid.")
    checkpoint = json.loads(journal.read_text())
    if (not isinstance(checkpoint, dict) or checkpoint.get("state") != "finalized"
            or checkpoint.get("baseVersion") != receipt.get("baseVersion")
            or checkpoint.get("stagedVersion") != receipt.get("stagedVersion")):
        raise ValueError("The website staging journal does not match the receipt.")
    source_commits = receipt.get("websiteSource")
    if checkpoint.get("websiteSource") != source_commits:
        raise ValueError("The website source commits differ from the staging journal.")
    if source_commits is not None and (not isinstance(source_commits, dict)
            or set(source_commits) != {"base", "target"} or source_commits.get("target") != commit
            or any(not isinstance(v, str) or not re.fullmatch(r"[a-f0-9]{40}", v) for v in source_commits.values())):
        raise ValueError("The website source commits do not match the candidate.")
    saved = checkpoint.get("websitePayloads")
    if not isinstance(saved, dict) or set(saved) != set(website):
        raise ValueError("The saved website payloads do not match the receipt.")
    source = firebase.site_overlay.read_git_tree(ROOT, commit)
    for path, digest in website.items():
        if not firebase.site_overlay.valid_path(path):
            raise ValueError("The Firebase website receipt is invalid.")
        entry = saved[path]
        if digest is None:
            if entry is not None or path in source:
                raise ValueError("The website deletion does not match the source.")
        else:
            if not isinstance(digest, str) or not firebase.HASH_PATTERN.fullmatch(digest) or path not in source:
                raise ValueError("The saved website payload does not match the source.")
            firebase.decode_website_payload(entry, source[path])
            if entry["hash"] != digest:
                raise ValueError("The saved website payload does not match the receipt.")


DOWNLOAD_HOSTS = {"github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com",
                  "github-releases.githubusercontent.com"}


def verify_public_asset(url, expected_size, expected_digest, *, opener=None):
    opener = opener or urllib.request.build_opener(firebase.NoRedirect())
    for _ in range(6):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc not in DOWNLOAD_HOSTS or parsed.username or parsed.password:
            raise ValueError("A public download redirected to an unsafe host.")
        request = urllib.request.Request(url, headers={"Accept-Encoding": "identity", "User-Agent": "Draftly-release-verifier"})
        try:
            with opener.open(request, timeout=30) as response:
                if response.headers.get("Content-Encoding", "identity") != "identity":
                    raise ValueError("The public download uses an unexpected content encoding.")
                digest = hashlib.sha256()
                count = 0
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    count += len(chunk)
                    if count > expected_size:
                        raise ValueError("The public download is larger than the verified asset.")
                    digest.update(chunk)
                if count != expected_size or "sha256:" + digest.hexdigest() != expected_digest:
                    raise ValueError("The public download does not match the verified asset.")
                return
        except urllib.error.HTTPError as error:
            if error.code not in (301, 302, 303, 307, 308):
                raise ValueError("The public download is unavailable (HTTP " + str(error.code) + ").") from error
            location = error.headers.get("Location")
            if not location:
                raise ValueError("The public download redirect has no destination.") from error
            url = urllib.parse.urljoin(url, location)
        except urllib.error.URLError as error:
            raise ValueError("The public download is unavailable.") from error
    raise ValueError("The public download redirected too many times.")


def publish(candidate, staged, notes, secret, receipt, client, *, enabled, github=None,
            stage_draft=github_stage.stage, download=verify_public_asset):
    if enabled != "YES":
        raise ValueError("Public release is disabled until distribution acceptance is complete.")
    candidate, staged = Path(candidate), Path(staged)
    feed = (staged / "appcast.xml").read_bytes()
    payload = firebase.payload_path(staged / "firebase-journal.json")
    compressed = firebase.read_payload(payload, feed, receipt.get("appcastHash") if isinstance(receipt, dict) else None)
    metadata = json.loads((candidate / "candidate.json").read_text())
    commit = metadata.get("sourceCommit") if isinstance(metadata, dict) else None
    if not isinstance(commit, str) or not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("The candidate source commit is invalid.")
    verify_website_checkpoint(staged, receipt, commit)
    github_stage.inspect_inputs(candidate, staged, secret, notes)
    site_status = validate_site(client, receipt, feed, compressed)
    github = github or PublishingGitHub()
    result = stage_draft(candidate, staged, notes, secret, github=github)
    tag, digest = result["tag"], result["sha256"]
    if (staged / "appcast.xml").read_bytes() != feed:
        raise ValueError("The staged appcast changed during verification.")
    site_status = validate_site(client, receipt, feed, compressed)
    release = github_stage.find_release(github.releases(), tag)
    if release is None:
        raise ValueError("The verified GitHub release no longer exists.")
    paths = {"Draftly.zip": candidate / "Draftly.zip", "Draftly.zip.sha256": candidate / "Draftly.zip.sha256",
             "candidate.json": candidate / "candidate.json", "appcast.xml": staged / "appcast.xml"}
    github_stage.validate_assets(release, paths, notes, tag, allow_missing=False)
    release_id = release.get("id")
    if isinstance(release_id, bool) or not isinstance(release_id, int) or release_id <= 0:
        raise ValueError("The GitHub release ID is invalid.")
    hashes = {name: (path.stat().st_size, github_stage.file_digest(path)) for name, path in paths.items()}
    if hashes["Draftly.zip"][1] != "sha256:" + digest:
        raise ValueError("The candidate ZIP changed before publication.")
    if release["draft"]:
        if site_status == "promoted":
            raise ValueError("The appcast is already live but the GitHub release is still a draft.")
        if github.refs(tag) != (commit, commit) or github_stage.prepare.release.source_commit(tag, github_stage.secret_free_run) != commit:
            raise ValueError("The source commit or remote refs changed before publication.")
        github.publish(release_id)
    published = github_stage.find_release(github.releases(), tag)
    if published is None or published.get("draft") is not False or published.get("id") != release_id:
        raise ValueError("GitHub has not confirmed the public release. Reinspect it before retrying.")
    github_stage.validate_assets(published, paths, notes, tag, allow_missing=False)
    for name, (size, sha256) in hashes.items():
        if (paths[name].stat().st_size, github_stage.file_digest(paths[name])) != (size, sha256):
            raise ValueError("A candidate asset changed after publication.")
        url = "https://github.com/pobrespandas/draftly/releases/download/" + tag + "/" + urllib.parse.quote(name)
        download(url, size, sha256)
    if (staged / "appcast.xml").read_bytes() != feed:
        raise ValueError("The staged appcast changed after publication.")
    if any((paths[name].stat().st_size, github_stage.file_digest(paths[name])) != expected
           for name, expected in hashes.items()):
        raise ValueError("A candidate asset changed during public verification.")
    if github.refs(tag) != (commit, commit) or github_stage.prepare.release.source_commit(tag, github_stage.secret_free_run) != commit:
        raise ValueError("The source commit or remote refs changed after publication.")
    if firebase.read_payload(payload, feed, receipt["appcastHash"]) != compressed:
        raise ValueError("The saved compressed appcast changed during publication.")
    verify_website_checkpoint(staged, receipt, commit)
    validate_site(client, receipt, feed, compressed)
    result = {"tag": tag, "sha256": digest, "releaseId": published.get("id"),
              "firebaseBaseVersion": receipt["baseVersion"], "firebaseStagedVersion": receipt["stagedVersion"]}
    marker = candidate / "PUBLIC_VERIFIED.json"
    if marker.is_symlink():
        raise ValueError("The public verification receipt must not be a symlink.")
    contents = json.dumps(result, indent=2, sort_keys=True) + "\n"
    try:
        with marker.open("x") as output:
            output.write(contents)
    except FileExistsError:
        if marker.read_text() != contents:
            raise ValueError("An existing public verification receipt does not match.")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--notes", required=True)
    parser.add_argument("--firebase-receipt", required=True)
    args = parser.parse_args()
    try:
        secret = os.environ.get("DRAFTLY_SPARKLE_PRIVATE_KEY")
        if not secret:
            raise ValueError("DRAFTLY_SPARKLE_PRIVATE_KEY is required.")
        client = firebase.HostingClient(os.environ.get("DRAFTLY_FIREBASE_ACCESS_TOKEN"))
        result = publish(args.candidate, args.appcast, Path(args.notes).read_text(encoding="utf-8"), secret.strip(),
                         json.loads(Path(args.firebase_receipt).read_text()), client,
                         enabled=os.environ.get("DRAFTLY_RELEASE_PUBLISH_ENABLED"))
        print(json.dumps(result, indent=2))
    except (ValueError, OSError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        raise SystemExit("GitHub publication failed: " + str(error))


if __name__ == "__main__":
    main()
