#!/usr/bin/env python3
"""Prepare a signed Sparkle appcast without publishing it."""

import argparse
import base64
import datetime
from email.utils import format_datetime
import hashlib
import hmac
import html
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / ".build/artifacts/sparkle/Sparkle/bin/sign_update"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


history = load_module("release_history", "release-history.py")
release = load_module("package_release", "package-release.py")


def private_key(secret):
    try:
        seed = base64.b64decode(secret, validate=True)
    except (ValueError, TypeError) as error:
        raise ValueError("The update signing key is invalid.") from error
    if len(seed) != 32:
        raise ValueError("The update signing key must be a 32-byte seed.")
    return Ed25519PrivateKey.from_private_bytes(seed)


def candidate_details(directory, key):
    directory = Path(directory)
    if not (directory / "READY").is_file():
        raise ValueError("The candidate has no READY marker.")
    metadata = json.loads((directory / "candidate.json").read_text())
    if not isinstance(metadata, dict) or metadata.get("updatesEnabled") is not True:
        raise ValueError("The candidate must enable update checks.")
    version, build = metadata.get("version"), metadata.get("build")
    history.version_tuple(version)
    history.build_number(build)
    commit = metadata.get("sourceCommit")
    if metadata.get("tag") != "v" + version or not isinstance(commit, str) or not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("The candidate source identity is invalid.")
    package = directory / "Draftly.zip"
    contents = package.read_bytes()
    digest = hashlib.sha256(contents).hexdigest()
    if (not isinstance(metadata.get("sha256"), str) or not re.fullmatch(r"[a-f0-9]{64}", metadata["sha256"])
            or not hmac.compare_digest(metadata["sha256"], digest)):
        raise ValueError("The candidate checksum does not match its ZIP.")
    with zipfile.ZipFile(package) as archive:
        matches = [entry for entry in archive.infolist() if entry.filename == "Draftly.app/Contents/Info.plist"]
        if len(matches) != 1 or matches[0].file_size > 1024 * 1024:
            raise ValueError("The candidate must contain one app Info.plist.")
        info = plistlib.loads(archive.read(matches[0]))
    public_bytes = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    public_key = base64.b64encode(public_bytes).decode("ascii")
    release.validate_metadata({"CFBundleShortVersionString": version, "CFBundleVersion": build},
                              info, public_key=public_key)
    minimum_os = info.get("LSMinimumSystemVersion")
    if not isinstance(minimum_os, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", minimum_os):
        raise ValueError("The app has no valid minimum macOS version.")
    signature = key.sign(contents)
    key.public_key().verify(signature, contents)
    return metadata, len(contents), base64.b64encode(signature).decode("ascii"), minimum_os


def sparkle_feed(tool, path, secret, *, verify=False):
    command = [str(tool)] + (["--verify"] if verify else []) + ["--ed-key-file", "-", str(path)]
    child_env = {name: os.environ[name] for name in ("PATH", "HOME", "TMPDIR", "LANG", "LC_ALL") if name in os.environ}
    try:
        result = subprocess.run(command, input=secret + "\n", text=True, capture_output=True,
                                timeout=30, env=child_env)
    except (OSError, subprocess.SubprocessError) as error:
        raise ValueError("Sparkle could not process the appcast.") from error
    # Sparkle can echo malformed private input. Never expose its output on failure.
    if result.returncode:
        raise ValueError("Sparkle could not verify the appcast." if verify else "Sparkle could not sign the appcast.")


def prepare(candidate, output, notes, secret, *, releases=None, appcast=None, now=None, tool=TOOL):
    key = private_key(secret)
    metadata, length, signature, minimum_os = candidate_details(candidate, key)
    if not isinstance(notes, str) or not notes.strip() or len(notes.encode("utf-8")) > 65536:
        raise ValueError("Release notes must contain between 1 and 65536 bytes of text.")
    if releases is None:
        releases = history.fetch_releases()
        appcast = history.fetch_appcast()
    history.validate_history(metadata["version"], metadata["build"], releases, appcast)
    output = Path(output).absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir()  # Refuse existing output, including a symlink.
    if appcast is None:
        root = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = "Draftly updates"
        ET.SubElement(channel, "link").text = "https://draftly.pobrespandas.com/"
        ET.SubElement(channel, "description").text = "Draftly for Mac releases"
        ET.SubElement(channel, "language").text = "en"
    else:
        with tempfile.TemporaryDirectory(prefix="draftly-feed-") as temporary:
            old_feed = Path(temporary) / "appcast.xml"
            old_feed.write_bytes(appcast)
            sparkle_feed(tool, old_feed, secret, verify=True)
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
        root = ET.fromstring(appcast, parser=parser)
        channel = root.find("channel")
    item = ET.Element("item")
    ET.SubElement(item, "title").text = "Draftly " + metadata["version"]
    ET.SubElement(item, "description").text = "<pre>" + html.escape(notes) + "</pre>"
    ET.SubElement(item, "pubDate").text = format_datetime(now or datetime.datetime.now(datetime.timezone.utc), usegmt=True)
    ET.SubElement(item, "{" + SPARKLE_NS + "}version").text = metadata["build"]
    ET.SubElement(item, "{" + SPARKLE_NS + "}shortVersionString").text = metadata["version"]
    ET.SubElement(item, "{" + SPARKLE_NS + "}minimumSystemVersion").text = minimum_os
    ET.SubElement(item, "enclosure", {"url": "https://github.com/pobrespandas/draftly/releases/download/"
                  + metadata["tag"] + "/Draftly.zip", "length": str(length), "type": "application/octet-stream",
                  "{" + SPARKLE_NS + "}edSignature": signature})
    channel.insert(0, item)
    path = output / "appcast.xml"
    path.write_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))
    sparkle_feed(tool, path, secret)
    sparkle_feed(tool, path, secret, verify=True)
    staged = history.feed_versions(path.read_bytes())
    expected = dict(history.feed_versions(appcast) or {})
    expected[history.version_tuple(metadata["version"])] = int(metadata["build"])
    if staged != expected:
        raise ValueError("The signed appcast does not preserve the complete release history.")
    (output / "READY").write_text("Signed appcast. Not published.\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--notes", required=True, help="UTF-8 text file with release notes.")
    parser.add_argument("--sparkle-tool", default=str(TOOL), help="Sparkle sign_update executable.")
    args = parser.parse_args()
    try:
        secret = os.environ.get("DRAFTLY_SPARKLE_PRIVATE_KEY")
        if not secret:
            raise ValueError("DRAFTLY_SPARKLE_PRIVATE_KEY is required.")
        prepare(args.candidate, args.output, Path(args.notes).read_text(encoding="utf-8"), secret.strip(),
                tool=Path(args.sparkle_tool))
    except (ValueError, OSError, subprocess.SubprocessError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        raise SystemExit("Appcast preparation failed: " + str(error))
    print("Signed appcast is ready. Nothing was published: " + args.output)


if __name__ == "__main__":
    main()
