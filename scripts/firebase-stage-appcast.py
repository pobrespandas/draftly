#!/usr/bin/env python3
"""Stage a signed appcast with the current Firebase site. Never deploy it."""

import argparse
import base64
import copy
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey


ROOT = Path(__file__).resolve().parent.parent
SITE = "sites/draftly-pobrespandas"
API = "https://firebasehosting.googleapis.com/v1beta1/"
PROJECT = "pobrespandas-home"
VERSION_PATTERN = re.compile(re.escape(SITE) + r"/versions/[A-Za-z0-9]+\Z")
HASH_PATTERN = re.compile(r"[a-f0-9]{64}\Z")
SIGNATURE_PREFIX = b"<!-- sparkle-signatures:\n"

spec = importlib.util.spec_from_file_location("release_history", ROOT / "scripts/release-history.py")
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)


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
    return {"version": version, "config": config, "files": files}


def stage(client, expected_version, feed, public_key, *, releases=None, current_feed=None):
    new_versions = verify_feed(feed, public_key)
    live = snapshot(client)
    if live["version"] != expected_version:
        raise ValueError("The live site changed before staging.")
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
    if len(added) != 1:
        raise ValueError("The new appcast must add exactly one version.")
    version = next(iter(added))
    history.validate_history(".".join(str(part) for part in version), str(new_versions[version]), releases, current_feed)
    if (current_feed is None) != ("/appcast.xml" not in live["files"]):
        raise ValueError("The live appcast and Firebase file list do not agree.")
    compressed = gzip.compress(feed, mtime=0)
    digest = hashlib.sha256(compressed).hexdigest()
    files = dict(live["files"])
    files["/appcast.xml"] = digest
    created = client.request("POST", SITE + "/versions", {"config": live["config"]})
    staged = created.get("name")
    if not isinstance(staged, str) or not VERSION_PATTERN.fullmatch(staged) or staged == live["version"]:
        raise ValueError("Firebase returned an invalid staged version.")
    entries = list(files.items())
    for start in range(0, len(entries), 1000):
        response = client.request("POST", staged + ":populateFiles", {"files": dict(entries[start:start + 1000])})
        required = response.get("uploadRequiredHashes", [])
        if not isinstance(required, list) or any(value != digest for value in required):
            raise ValueError("Firebase cannot reuse one or more live site files.")
        if required:
            upload_url = response.get("uploadUrl")
            expected_path = "/upload/" + staged + "/files"
            parsed = urllib.parse.urlsplit(upload_url) if isinstance(upload_url, str) else None
            if (parsed is None or parsed.scheme != "https" or parsed.netloc != "upload-firebasehosting.googleapis.com"
                    or parsed.path != expected_path or parsed.query or parsed.fragment):
                raise ValueError("Firebase returned an invalid upload URL.")
            client.request("POST", upload_url + "/" + digest, compressed, upload=True)
    if list_files(client, staged) != files:
        raise ValueError("The staged site does not preserve the live files.")
    staged_details = client.request("GET", staged)
    if staged_details.get("name") != staged or staged_details.get("config", {}) != live["config"]:
        raise ValueError("The staged site configuration differs from the live site.")
    if snapshot(client)["version"] != live["version"]:
        raise ValueError("The live site changed while staging.")
    final = client.request("PATCH", staged + "?updateMask=status", {"status": "FINALIZED"})
    if final.get("name") != staged or final.get("status") != "FINALIZED":
        raise ValueError("Firebase did not finalize the staged version.")
    return {"baseVersion": live["version"], "stagedVersion": staged,
            "preservedFiles": len(live["files"]), "appcastHash": digest}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspect", action="store_true", help="Inspect the live version without changing Firebase.")
    parser.add_argument("--appcast", help="Signed appcast to stage.")
    parser.add_argument("--public-key", help="Base64 Ed25519 public key from the app.")
    parser.add_argument("--expected-version", help="Live Firebase version used to prepare the appcast.")
    args = parser.parse_args()
    try:
        client = HostingClient(os.environ.get("DRAFTLY_FIREBASE_ACCESS_TOKEN"))
        if args.inspect:
            if args.appcast or args.public_key or args.expected_version:
                raise ValueError("Inspect does not accept staging options.")
            live = snapshot(client)
            result = {"liveVersion": live["version"], "fileCount": len(live["files"]), "hasAppcast": "/appcast.xml" in live["files"]}
        else:
            if not args.appcast or not args.public_key or not args.expected_version:
                raise ValueError("Staging needs an appcast, public key, and expected live version.")
            result = stage(client, args.expected_version, Path(args.appcast).read_bytes(), args.public_key)
        print(json.dumps(result, indent=2))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit("Firebase appcast staging failed: " + str(error))


if __name__ == "__main__":
    main()
