#!/usr/bin/env python3
"""Promote a verified public release while holding the site writer lock."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent

def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

publisher = load("release_publisher", "publish-github-release.py")
locks = load("site_writer_lock", "release-lock.py")
firebase = publisher.firebase


def public_feed(expected):
    request = urllib.request.Request("https://draftly.pobrespandas.com/appcast.xml",
        headers={"Accept-Encoding": "identity", "Cache-Control": "no-cache"})
    with urllib.request.build_opener(firebase.NoRedirect()).open(request, timeout=30) as response:
        actual = response.read(len(expected) + 1)
    if actual != expected:
        raise ValueError("The public appcast does not match the release.")


def promote(client, receipt, feed, compressed, journal, *, enabled, check_lock,
            verify_public, check_feed=public_feed):
    if enabled != "YES":
        raise ValueError("Firebase promotion is disabled.")
    journal = Path(journal)
    if journal.is_symlink():
        raise ValueError("The promotion journal must not be a symlink.")
    check_lock()
    verified = verify_public()
    expected = {"baseVersion": receipt["baseVersion"], "stagedVersion": receipt["stagedVersion"],
                "appcastHash": receipt["appcastHash"], "publicRelease": verified}
    state = None
    if journal.exists():
        if journal.stat().st_size > 65536:
            raise ValueError("The promotion journal is too large.")
        state = json.loads(journal.read_text())
        if (not isinstance(state, dict) or state.get("release") != expected
                or state.get("state") not in ("pending", "complete")):
            raise ValueError("The promotion journal does not match this release.")
    status = publisher.validate_site(client, receipt, feed, compressed)
    if status == "staged":
        if state is not None:
            raise ValueError("The promotion outcome is uncertain. Inspect Firebase before recovery.")
        check_lock()
        # The journal must reach disk before the request. Never retry an unknown POST.
        state = {"state": "pending", "release": expected}
        locks.write_journal(journal, state, new=True)
        if publisher.validate_site(client, receipt, feed, compressed) != "staged":
            raise ValueError("The site changed before promotion.")
        check_lock()
        path = firebase.SITE + "/releases?" + urllib.parse.urlencode({"versionName": receipt["stagedVersion"]})
        result = client.request("POST", path, {"message": "Draftly " + verified["tag"]})
        if result.get("version", {}).get("name") != receipt["stagedVersion"]:
            raise ValueError("Firebase did not confirm promotion. Inspect the pending journal.")
    check_lock()
    if publisher.validate_site(client, receipt, feed, compressed) != "promoted":
        raise ValueError("Firebase has not confirmed the live release.")
    check_feed(feed)
    check_lock()
    # Detect a site change during the public download.
    if publisher.validate_site(client, receipt, feed, compressed) != "promoted":
        raise ValueError("The site changed during public verification.")
    if state is None:
        state = {"state": "pending", "release": expected}
        locks.write_journal(journal, state, new=True)
    state["state"] = "complete"
    locks.write_journal(journal, state)
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("candidate", "appcast", "notes", "firebase-receipt", "journal", "lock-bucket", "lock-journal"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    try:
        candidate, appcast = Path(args.candidate), Path(args.appcast)
        receipt = json.loads(Path(args.firebase_receipt).read_text())
        marker = json.loads((candidate / "PUBLIC_VERIFIED.json").read_text())
        github = publisher.PublishingGitHub()
        release = publisher.github_stage.find_release(github.releases(), marker["tag"])
        if release is None or release.get("draft") is not False or release.get("id") != marker["releaseId"]:
            raise ValueError("The verified public GitHub release is required before promotion.")
        token = os.environ.get("DRAFTLY_FIREBASE_ACCESS_TOKEN")
        client = firebase.HostingClient(token)
        store = locks.StorageLock(args.lock_bucket, token)
        def verify():
            result = publisher.publish(candidate, appcast, Path(args.notes).read_text(),
                os.environ.get("DRAFTLY_SPARKLE_PRIVATE_KEY", "").strip(), receipt, client,
                enabled=os.environ.get("DRAFTLY_RELEASE_PUBLISH_ENABLED"), github=github)
            if result != marker:
                raise ValueError("The public release receipt changed.")
            return result
        feed = (appcast / "appcast.xml").read_bytes()
        compressed = firebase.read_payload(firebase.payload_path(appcast / "firebase-journal.json"), feed, receipt["appcastHash"])
        result = promote(client, receipt, feed, compressed, args.journal,
            enabled=os.environ.get("DRAFTLY_RELEASE_PROMOTION_ENABLED"),
            check_lock=lambda: locks.check(store, args.lock_journal), verify_public=verify)
        print(json.dumps(result, indent=2))
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit("Firebase promotion failed: " + str(error))

if __name__ == "__main__":
    main()
