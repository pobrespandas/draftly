#!/usr/bin/env python3
"""Stage a signed appcast with the current Firebase site. Never deploy it."""

import argparse
import base64
import copy
import gzip
import hashlib
import io
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import uuid
import zlib

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey


ROOT = Path(__file__).resolve().parent.parent
SITE = "sites/draftly-pobrespandas-prod"
API = "https://firebasehosting.googleapis.com/v1beta1/"
PROJECT = "gen-lang-client-0607406471"
VERSION_PATTERN = re.compile(re.escape(SITE) + r"/versions/[A-Za-z0-9]+\Z")
HASH_PATTERN = re.compile(r"[a-f0-9]{64}\Z")
SIGNATURE_PREFIX = b"<!-- sparkle-signatures:\n"

spec = importlib.util.spec_from_file_location("release_history", ROOT / "scripts/release-history.py")
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)
site_spec = importlib.util.spec_from_file_location("site_overlay", ROOT / "scripts/site-overlay.py")
site_overlay = importlib.util.module_from_spec(site_spec)
site_spec.loader.exec_module(site_overlay)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


def verify_feed(data, public_key):
    if len(data) > history.MAX_FEED_BYTES:
        raise ValueError("The appcast is too large.")
    try:
        key = base64.b64decode(public_key, validate=True)
        if len(key) != 32:
            raise ValueError("The update public key must contain 32 bytes.")
        offset = data.rfind(SIGNATURE_PREFIX)
        if offset < 0:
            raise ValueError("The appcast is not signed.")
        end = data.find(b"-->", offset + len(SIGNATURE_PREFIX))
        if end < 0 or data[end + 3:].strip():
            raise ValueError("The appcast signature block is invalid.")
        lines = data[offset + len(SIGNATURE_PREFIX):end].decode("ascii").splitlines()
        values = {}
        for line in lines:
            key_name, separator, value = line.partition(":")
            if not separator or key_name in values:
                raise ValueError("The appcast signature block is invalid.")
            values[key_name] = value.strip()
        if set(values) != {"edSignature", "length"} or values["length"] != str(offset):
            raise ValueError("The appcast signed length is invalid.")
        signature = base64.b64decode(values["edSignature"], validate=True)
        Ed25519PublicKey.from_public_bytes(key).verify(signature, data[:offset])
    except (UnicodeError, InvalidSignature, TypeError) as error:
        raise ValueError("The appcast signature is invalid.") from error
    return history.feed_versions(data)


def feed_items(data):
    root = ET.fromstring(data)
    items = {}
    for item in root.find("channel").findall("item"):
        enclosure = item.find("enclosure")
        value = item.findtext(history.SPARKLE + "shortVersionString")
        if not value and enclosure is not None:
            value = enclosure.get(history.SPARKLE + "shortVersionString")
        version = history.version_tuple(value)
        item = copy.deepcopy(item)
        item.tail = None
        items[version] = ET.canonicalize(ET.tostring(item, encoding="unicode"))
    return items


def fetch_live_feed(live):
    request = urllib.request.Request(history.FEED_URL, headers={"Cache-Control": "no-cache", "Accept-Encoding": "identity"})
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=20) as response:
            if response.headers.get("Content-Encoding", "identity") != "identity":
                raise ValueError("The public appcast has an unexpected content encoding.")
            etag = response.headers.get("ETag", "").strip('"')
            data = response.read(history.MAX_FEED_BYTES + 1)
    except urllib.error.HTTPError as error:
        if error.code == 404 and "/appcast.xml" not in live["files"]:
            return None
        raise ValueError("The public appcast cannot be read.") from error
    except urllib.error.URLError as error:
        raise ValueError("The public appcast cannot be read.") from error
    if etag != live["files"].get("/appcast.xml"):
        raise ValueError("The public appcast does not match the live Firebase version.")
    return data


class HostingClient:
    def __init__(self, token):
        if not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9._~+/=-]{1,8192}", token):
            raise ValueError("A Firebase access token is required.")
        self._token = token

    def request(self, method, path, body=None, *, upload=False):
        url = path if upload else API + path
        parsed = urllib.parse.urlsplit(url)
        host = "upload-firebasehosting.googleapis.com" if upload else "firebasehosting.googleapis.com"
        if parsed.scheme != "https" or parsed.netloc != host:
            raise ValueError("The Firebase API returned an unsafe URL.")
        headers = {"Authorization": "Bearer " + self._token, "x-goog-user-project": PROJECT}
        if body is not None:
            if upload:
                headers["Content-Type"] = "application/octet-stream"
            else:
                headers["Content-Type"] = "application/json"
                body = json.dumps(body).encode("utf-8")
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
                payload = response.read(8 * 1024 * 1024 + 1)
        except urllib.error.HTTPError as error:
            raise ValueError("Firebase Hosting request failed (HTTP " + str(error.code) + ").") from error
        except urllib.error.URLError as error:
            raise ValueError("Firebase Hosting request failed.") from error
        if len(payload) > 8 * 1024 * 1024:
            raise ValueError("Firebase Hosting response is too large.")
        try:
            value = json.loads(payload or b"{}")
        except (ValueError, UnicodeError) as error:
            raise ValueError("Firebase Hosting returned invalid JSON.") from error
        if not isinstance(value, dict):
            raise ValueError("Firebase Hosting returned invalid data.")
        return value


def list_files(client, version):
    if not VERSION_PATTERN.fullmatch(version):
        raise ValueError("The Firebase version name is invalid.")
    files, seen_pages, token = {}, set(), None
    while True:
        query = {"pageSize": 1000}
        if token:
            query["pageToken"] = token
        page = client.request("GET", version + "/files?" + urllib.parse.urlencode(query))
        entries = page.get("files", [])
        if not isinstance(entries, list):
            raise ValueError("Firebase returned an invalid file list.")
        for entry in entries:
            if not isinstance(entry, dict):
                raise ValueError("Firebase returned an invalid file entry.")
            path, digest = entry.get("path"), entry.get("hash")
            if (not isinstance(path, str) or not path.startswith("/") or path in files
                    or not isinstance(digest, str) or not HASH_PATTERN.fullmatch(digest)
                    or entry.get("status") != "ACTIVE"):
                raise ValueError("Firebase returned an invalid or inactive file.")
            files[path] = digest
        token = page.get("nextPageToken")
        if token is None or token == "":
            return files
        if not isinstance(token, str) or token in seen_pages:
            raise ValueError("Firebase returned an invalid page token.")
        seen_pages.add(token)


def snapshot(client):
    channel = client.request("GET", SITE + "/channels/live")
    version = channel.get("release", {}).get("version", {}).get("name")
    if not isinstance(version, str) or not VERSION_PATTERN.fullmatch(version):
        raise ValueError("Firebase has no valid live version.")
    details = client.request("GET", version)
    if details.get("name") != version or details.get("status") != "FINALIZED":
        raise ValueError("The live Firebase version is not finalized.")
    config = details.get("config", {})
    if not isinstance(config, dict):
        raise ValueError("The live Firebase configuration is invalid.")
    files = list_files(client, version)
    if "/index.html" not in files:
        raise ValueError("The live Firebase version has no index page.")
    count = details.get("fileCount")
    if count is not None and (not str(count).isdigit() or int(count) != len(files)):
        raise ValueError("The live Firebase file count is inconsistent.")
    labels = details.get("labels", {})
    if not isinstance(labels, dict):
        raise ValueError("The live website source label is invalid.")
    source = labels.get("draftly-site-source")
    if source is not None and (not isinstance(source, str) or not re.fullmatch(r"[a-f0-9]{40}", source)):
        raise ValueError("The live website source label is invalid.")
    return {"version": version, "config": config, "files": files, "siteSourceCommit": source}


def site_base_commit(live, bootstrap):
    source = live.get("siteSourceCommit")
    if source is None:
        if "/appcast.xml" in live["files"]:
            raise ValueError("The published site has no source checkpoint. Inspect it before continuing.")
        source = bootstrap
    if not isinstance(source, str) or not re.fullmatch(r"[a-f0-9]{40}", source):
        raise ValueError("A valid website source commit is required.")
    return source


def write_journal(path, data, *, new=False):
    path = Path(path)
    payload = json.dumps(data, indent=2, sort_keys=True) + "\n"
    if new:
        with path.open("x") as output:
            output.write(payload)
        return
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".firebase-journal-", delete=False) as output:
            name = output.name
            output.write(payload)
        os.replace(name, path)
        name = None
    finally:
        if name is not None:
            Path(name).unlink(missing_ok=True)


def compress_feed(feed):
    output = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as stream:
        stream.write(feed)
    return output.getvalue()


def payload_path(journal):
    journal = Path(journal)
    return journal.with_name(journal.name + ".feed.gz")


def read_payload(path, feed, expected_digest):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > history.MAX_FEED_BYTES + 65536:
        raise ValueError("The saved compressed appcast is missing or invalid.")
    data = path.read_bytes()
    if not isinstance(expected_digest, str) or hashlib.sha256(data).hexdigest() != expected_digest:
        raise ValueError("The saved compressed appcast does not match the staging receipt.")
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(data), mode="rb") as stream:
            decoded = stream.read(len(feed) + 1)
    except (OSError, EOFError, zlib.error) as error:
        raise ValueError("The saved compressed appcast is invalid.") from error
    if decoded != feed:
        raise ValueError("The saved compressed appcast does not match the feed.")
    return data


def decode_website_payload(entry, content):
    if not isinstance(entry, dict) or set(entry) != {"hash", "data"} or not isinstance(content, bytes):
        raise ValueError("The saved website payload is invalid.")
    encoded_text = entry["data"]
    if not isinstance(encoded_text, str) or len(encoded_text) > 3 * 1024 * 1024:
        raise ValueError("The saved website payload is invalid.")
    try:
        encoded = base64.b64decode(encoded_text, validate=True)
        with gzip.GzipFile(fileobj=io.BytesIO(encoded), mode="rb") as stream:
            decoded = stream.read(len(content) + 1)
    except (ValueError, TypeError, OSError, EOFError, zlib.error) as error:
        raise ValueError("The saved website payload is invalid.") from error
    if decoded != content or hashlib.sha256(encoded).hexdigest() != entry["hash"]:
        raise ValueError("The saved website payload does not match the source.")
    return encoded


def stage(client, expected_version, feed, public_key, *, releases=None, current_feed=None, journal=None, resume=False, website=None, website_source=None, website_only=False):
    if resume and journal is None:
        raise ValueError("Recovery needs a Firebase staging journal.")
    checkpoint = None
    if journal is not None:
        journal = Path(journal)
        if resume:
            if journal.is_symlink() or journal.stat().st_size > 24 * 1024 * 1024:
                raise ValueError("The Firebase staging journal is invalid.")
            checkpoint = json.loads(journal.read_text())
            if not isinstance(checkpoint, dict) or checkpoint.get("state") not in ("created", "finalized"):
                raise ValueError("The Firebase staging outcome is unknown. Inspect Firebase before retrying.")
        elif journal.exists() or journal.is_symlink():
            raise ValueError("The Firebase staging journal already exists. Use recovery.")
    if website_source is not None and (website is None or not isinstance(website_source, dict)
            or set(website_source) != {"base", "target"}
            or any(not isinstance(v, str) or not re.fullmatch(r"[a-f0-9]{40}", v) for v in website_source.values())):
        raise ValueError("The website source commits are invalid.")
    if resume and checkpoint.get("websiteSource") != website_source:
        raise ValueError("The website source commits do not match the staging journal.")
    new_versions = verify_feed(feed, public_key)
    live = snapshot(client)
    if live["version"] != expected_version:
        raise ValueError("The live site changed before staging.")
    changes = {}
    if website is not None:
        if journal is None or not isinstance(website, tuple) or len(website) != 3:
            raise ValueError("Website staging needs source trees, a fetcher, and a journal.")
        base, target, fetch = website
        site_overlay.validate_sources(base, target)
        if "/index.html" not in base or "/index.html" not in target or not callable(fetch):
            raise ValueError("The website source or fetcher is invalid.")
        changed = {path for path in base.keys() | target.keys() if base.get(path) != target.get(path)}
        observed = {path: fetch(path, live["files"][path]) if path in live["files"] else None
                    for path in sorted(changed)}
        changes = site_overlay.plan(base, target, observed)
        if len(changes) > 100 or any(data is not None and len(data) > history.MAX_FEED_BYTES for data in changes.values()):
            raise ValueError("The website changes exceed staging limits.")
    if releases is None:
        releases = history.fetch_releases()
        current_feed = fetch_live_feed(live)
    old_versions = verify_feed(current_feed, public_key) if current_feed is not None else {}
    if any(new_versions.get(version) != build for version, build in old_versions.items()):
        raise ValueError("The new appcast does not preserve published versions.")
    if current_feed is not None:
        old_items, new_items = feed_items(current_feed), feed_items(feed)
        if any(new_items.get(version) != item for version, item in old_items.items()):
            raise ValueError("The new appcast changes a published release item.")
    added = set(new_versions) - set(old_versions)
    if website_only:
        if website is None or current_feed is None or feed != current_feed:
            raise ValueError("A website-only deployment must preserve the exact published feed.")
        stable = []
        for release in releases:
            if (not isinstance(release, dict) or not isinstance(release.get("draft"), bool)
                    or not isinstance(release.get("prerelease"), bool)):
                raise ValueError("A GitHub release has invalid metadata.")
            if not release["draft"] and not release["prerelease"]:
                tag = release.get("tag_name")
                if not isinstance(tag, str) or not tag.startswith("v"):
                    raise ValueError("A stable release tag is invalid.")
                stable.append(history.version_tuple(tag[1:]))
        if len(stable) != len(set(stable)) or set(stable) != set(new_versions):
            raise ValueError("The published releases do not match the unchanged feed.")
        builds = [new_versions[version] for version in sorted(new_versions)]
        if any(first >= second for first, second in zip(builds, builds[1:])):
            raise ValueError("Published builds do not increase with their versions.")
    else:
        if len(added) != 1:
            raise ValueError("The new appcast must add exactly one version.")
        version = next(iter(added))
        history.validate_history(".".join(str(part) for part in version), str(new_versions[version]), releases, current_feed,
                                 resume_candidate=resume)
    if (current_feed is None) != ("/appcast.xml" not in live["files"]):
        raise ValueError("The live appcast and Firebase file list do not agree.")
    if resume:
        compressed = read_payload(payload_path(journal), feed, checkpoint.get("appcastHash"))
    else:
        compressed = compress_feed(feed)
    digest = hashlib.sha256(compressed).hexdigest()
    files = dict(live["files"])
    files["/appcast.xml"] = digest
    uploads = {digest: compressed}
    website_payloads = {}
    if website is not None:
        saved = checkpoint.get("websitePayloads") if resume else None
        if resume and (not isinstance(saved, dict) or set(saved) != set(changes)):
            raise ValueError("The website changes do not match the staging journal.")
        for path, content in changes.items():
            if content is None:
                if resume and saved[path] is not None:
                    raise ValueError("The website deletion does not match the staging journal.")
                files.pop(path, None)
                website_payloads[path] = None
                continue
            if resume:
                entry = saved[path]
                encoded = decode_website_payload(entry, content)
            else:
                encoded = compress_feed(content)
                entry = {"hash": hashlib.sha256(encoded).hexdigest(), "data": base64.b64encode(encoded).decode("ascii")}
            files[path] = entry["hash"]
            uploads[entry["hash"]] = encoded
            website_payloads[path] = entry
        if sum(len(data) for data in uploads.values()) > 16 * 1024 * 1024:
            raise ValueError("The compressed website changes exceed staging limits.")
    elif resume and checkpoint.get("websitePayloads") is not None:
        raise ValueError("Recovery requires the original website sources.")
    if resume:
        if (checkpoint.get("baseVersion") != live["version"] or checkpoint.get("appcastHash") != digest
                or checkpoint.get("preservedFiles") != len(live["files"])
                or not isinstance(checkpoint.get("operation"), str)
                or not re.fullmatch(r"[a-f0-9]{32}", checkpoint["operation"])):
            raise ValueError("The Firebase staging journal does not match the candidate.")
        staged = checkpoint.get("stagedVersion")
    else:
        operation = uuid.uuid4().hex
        checkpoint = {"state": "creating", "operation": operation, "baseVersion": live["version"],
                      "preservedFiles": len(live["files"]), "appcastHash": digest}
        if website is not None:
            checkpoint["websitePayloads"] = website_payloads
        if website_source is not None:
            checkpoint["websiteSource"] = website_source
        if journal is not None:
            payload = payload_path(journal)
            saved = payload.open("xb")
            try:
                with saved:
                    saved.write(compressed)
            except BaseException:
                payload.unlink(missing_ok=True)
                raise
            try:
                write_journal(journal, checkpoint, new=True)
            except BaseException:
                payload.unlink(missing_ok=True)
                raise
        labels = {"draftly-operation": operation}
        if website_source is not None:
            labels["draftly-site-source"] = website_source["target"]
        created = client.request("POST", SITE + "/versions", {"config": live["config"], "labels": labels})
        staged = created.get("name")
    if not isinstance(staged, str) or not VERSION_PATTERN.fullmatch(staged) or staged == live["version"]:
        raise ValueError("Firebase returned an invalid staged version.")
    if not resume:
        checkpoint.update({"state": "created", "stagedVersion": staged})
        if journal is not None:
            write_journal(journal, checkpoint)
    details = client.request("GET", staged)
    labels = details.get("labels", {})
    if (details.get("name") != staged or details.get("config", {}) != live["config"]
            or not isinstance(labels, dict) or labels.get("draftly-operation") != checkpoint["operation"]
            or details.get("status") not in ("CREATED", "FINALIZED")):
        raise ValueError("The Firebase staged version does not match its journal.")
    if website_source is not None and labels.get("draftly-site-source") != website_source["target"]:
        raise ValueError("The staged website source does not match its journal.")
    if details["status"] == "CREATED":
        entries = list(files.items())
        for start in range(0, len(entries), 1000):
            response = client.request("POST", staged + ":populateFiles", {"files": dict(entries[start:start + 1000])})
            required = response.get("uploadRequiredHashes", [])
            if not isinstance(required, list) or any(value not in uploads for value in required):
                raise ValueError("Firebase cannot reuse one or more live site files.")
            if required:
                upload_url = response.get("uploadUrl")
                expected_path = "/upload/" + staged + "/files"
                parsed = urllib.parse.urlsplit(upload_url) if isinstance(upload_url, str) else None
                if (parsed is None or parsed.scheme != "https" or parsed.netloc != "upload-firebasehosting.googleapis.com"
                        or parsed.path != expected_path or parsed.query or parsed.fragment):
                    raise ValueError("Firebase returned an invalid upload URL.")
                for required_digest in set(required):
                    client.request("POST", upload_url + "/" + required_digest, uploads[required_digest], upload=True)
    if list_files(client, staged) != files:
        raise ValueError("The staged site does not preserve the live files.")
    staged_details = client.request("GET", staged)
    if staged_details.get("name") != staged or staged_details.get("config", {}) != live["config"]:
        raise ValueError("The staged site configuration differs from the live site.")
    if snapshot(client)["version"] != live["version"]:
        raise ValueError("The live site changed while staging.")
    if details["status"] == "CREATED":
        final = client.request("PATCH", staged + "?updateMask=status", {"status": "FINALIZED"})
        if final.get("name") != staged or final.get("status") != "FINALIZED":
            raise ValueError("Firebase did not finalize the staged version.")
    if journal is not None:
        checkpoint["state"] = "finalized"
        write_journal(journal, checkpoint)
    result = {"baseVersion": live["version"], "stagedVersion": staged,
              "preservedFiles": len(live["files"]), "appcastHash": digest}
    if website is not None:
        result["websiteHashes"] = {path: entry["hash"] if entry is not None else None
                                   for path, entry in website_payloads.items()}
    if website_source is not None:
        result["websiteSource"] = website_source
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bootstrap-site-base", help="Initial website source when no published appcast exists.")
    parser.add_argument("--inspect", action="store_true", help="Inspect the live version without changing Firebase.")
    parser.add_argument("--appcast", help="Signed appcast to stage.")
    parser.add_argument("--public-key", help="Base64 Ed25519 public key from the app.")
    parser.add_argument("--expected-version", help="Live Firebase version used to prepare the appcast.")
    parser.add_argument("--journal", help="New staging journal, or the journal to recover.")
    parser.add_argument("--website-only", action="store_true", help="Preserve the exact existing feed for website changes.")
    parser.add_argument("--resume", action="store_true", help="Resume the version recorded in the staging journal.")
    parser.add_argument("--site-base", help="Full commit of the previously deployed site source.")
    parser.add_argument("--site-target", help="Full commit of the new site source.")
    args = parser.parse_args()
    try:
        client = HostingClient(os.environ.get("DRAFTLY_FIREBASE_ACCESS_TOKEN"))
        if args.inspect:
            if args.appcast or args.public_key or args.expected_version or args.journal or args.resume or args.site_base or args.site_target or args.website_only:
                raise ValueError("Inspect does not accept staging options.")
            live = snapshot(client)
            result = {"liveVersion": live["version"], "fileCount": len(live["files"]), "hasAppcast": "/appcast.xml" in live["files"],
                      "siteSourceCommit": live["siteSourceCommit"]}
            if args.bootstrap_site_base is not None:
                result["siteBaseCommit"] = site_base_commit(live, args.bootstrap_site_base)
        else:
            if args.bootstrap_site_base is not None:
                raise ValueError("The bootstrap source is only valid for inspection.")
            if not args.appcast or not args.public_key or not args.expected_version or not args.journal:
                raise ValueError("Staging needs an appcast, public key, expected live version, and journal.")
            if bool(args.site_base) != bool(args.site_target):
                raise ValueError("Website staging needs both base and target commits.")
            website = None
            if args.site_base:
                actual = subprocess.run(["git", "rev-parse", "HEAD^{commit}"], cwd=ROOT, check=True,
                                        capture_output=True, text=True, timeout=30, env={"PATH": os.environ.get("PATH", "")}).stdout.strip()
                if args.site_target != actual:
                    raise ValueError("The website target commit must match the checked-out source.")
                base = site_overlay.read_git_tree(ROOT, args.site_base)
                target = site_overlay.read_git_tree(ROOT, args.site_target)
                website = (base, target, lambda path, digest: site_overlay.fetch_public(NoRedirect, path, digest))
            result = stage(client, args.expected_version, Path(args.appcast).read_bytes(), args.public_key,
                           journal=args.journal, resume=args.resume, website=website,
                           website_source={"base": args.site_base, "target": args.site_target} if website is not None else None,
                           website_only=args.website_only)
        print(json.dumps(result, indent=2))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit("Firebase appcast staging failed: " + str(error))


if __name__ == "__main__":
    main()
