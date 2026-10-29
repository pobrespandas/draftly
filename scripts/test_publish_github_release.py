"""Test release publication control without changing GitHub or Firebase."""
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

import test_firebase_stage_appcast as hosting_fixture

spec = importlib.util.spec_from_file_location("publish_release", Path(__file__).with_name("publish-github-release.py"))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
OLD, NEW = hosting_fixture.OLD, hosting_fixture.NEW
COMMIT = "a" * 40
TAG = "v0.1.0"
NOTES = "Neutral release"


class FinalizedHosting(hosting_fixture.FakeHosting):
    def request(self, method, path, body=None, *, upload=False):
        if method == "GET" and path == NEW:
            self.calls.append((method, path, body, upload))
            return {"name": NEW, "status": "FINALIZED", "config": self.staged_config}
        return super().request(method, path, body, upload=upload)


class FakeGitHub:
    def __init__(self, paths):
        self.calls = []
        self.item = {"id": 42, "tag_name": TAG, "name": "Draftly 0.1.0", "body": NOTES,
                     "draft": True, "prerelease": False,
                     "assets": [{"name": name, "state": "uploaded", "size": path.stat().st_size,
                                 "digest": publisher.github_stage.file_digest(path)} for name, path in paths.items()]}

    def releases(self):
        self.calls.append("releases")
        return [self.item]

    def refs(self, tag):
        self.calls.append("refs")
        return COMMIT, COMMIT

    def publish(self, release_id):
        self.calls.append("publish")
        if release_id != 42:
            raise ValueError("Wrong release")
        self.item["draft"] = False


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="draftly-publish-test-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.candidate, self.staged = root / "candidate", root / "staged"
        self.candidate.mkdir()
        self.staged.mkdir()
        (self.candidate / "Draftly.zip").write_bytes(b"candidate zip")
        self.digest = hashlib.sha256(b"candidate zip").hexdigest()
        (self.candidate / "Draftly.zip.sha256").write_text(self.digest + "  Draftly.zip\n")
        (self.candidate / "candidate.json").write_text(json.dumps({"sourceCommit": COMMIT}))
        (self.staged / "appcast.xml").write_bytes(b"signed feed")
        self.paths = {"Draftly.zip": self.candidate / "Draftly.zip",
                      "Draftly.zip.sha256": self.candidate / "Draftly.zip.sha256",
                      "candidate.json": self.candidate / "candidate.json", "appcast.xml": self.staged / "appcast.xml"}
        self.client = FinalizedHosting()
        self.client.staged_config = self.client.config
        digest = hashlib.sha256(gzip.compress(b"signed feed", mtime=0)).hexdigest()
        self.client.staged_files = dict(self.client.live_files, **{"/appcast.xml": digest})
        self.receipt = {"baseVersion": OLD, "stagedVersion": NEW,
                        "preservedFiles": len(self.client.live_files), "appcastHash": digest}
        self.github = FakeGitHub(self.paths)
        self.downloads = []
        inspect = patch.object(publisher.github_stage, "inspect_inputs", return_value={})
        source = patch.object(publisher.github_stage.prepare.release, "source_commit", return_value=COMMIT)
        inspect.start(); source.start()
        self.addCleanup(inspect.stop); self.addCleanup(source.stop)

    def stage_draft(self, candidate, staged, notes, secret, *, github):
        return {"tag": TAG, "sha256": self.digest, "draft": github.item["draft"]}

    def download(self, url, size, digest):
        self.downloads.append((url, size, digest))

    def run_publish(self, *, enabled="YES", download=None):
        return publisher.publish(self.candidate, self.staged, NOTES, "not-a-real-key", self.receipt, self.client,
                                 enabled=enabled, github=self.github, stage_draft=self.stage_draft,
                                 download=download or self.download)

    def test_requires_explicit_enablement_before_any_external_work(self):
        with self.assertRaisesRegex(ValueError, "disabled"):
            self.run_publish(enabled=None)
        self.assertEqual(self.github.calls, [])
        self.assertEqual(self.client.calls, [])

    def test_publishes_only_after_site_check_and_verifies_all_public_assets(self):
        result = self.run_publish()
        self.assertEqual(result["releaseId"], 42)
        self.assertEqual(self.github.calls.count("publish"), 1)
        self.assertEqual(len(self.downloads), 4)
        self.assertTrue(all(url.startswith("https://github.com/pobrespandas/draftly/releases/download/" + TAG + "/")
                            for url, _, _ in self.downloads))
        self.assertEqual(json.loads((self.candidate / "PUBLIC_VERIFIED.json").read_text()), result)
        self.assertFalse(any("/releases" in path for _, path, _, _ in self.client.calls))

    def test_interrupted_public_download_can_resume_without_republishing(self):
        def fail(url, size, digest):
            raise ValueError("Download interrupted")
        with self.assertRaisesRegex(ValueError, "interrupted"):
            self.run_publish(download=fail)
        self.assertFalse((self.candidate / "PUBLIC_VERIFIED.json").exists())
        self.assertFalse(self.github.item["draft"])
        result = self.run_publish()
        self.assertEqual(result["releaseId"], 42)
        self.assertEqual(self.github.calls.count("publish"), 1)

    def test_existing_promoted_site_and_public_release_can_be_rechecked(self):
        self.github.item["draft"] = False
        self.client.live = NEW
        result = self.run_publish()
        self.assertEqual(result["releaseId"], 42)
        self.assertNotIn("publish", self.github.calls)

    def test_draft_cannot_be_published_if_the_appcast_is_already_live(self):
        self.client.live = NEW
        with self.assertRaisesRegex(ValueError, "already live"):
            self.run_publish()
        self.assertNotIn("publish", self.github.calls)

    def test_site_drift_or_changed_assets_stop_publication(self):
        self.client.staged_files["/actions.html"] = "d" * 64
        with self.assertRaisesRegex(ValueError, "does not preserve"):
            self.run_publish()
        self.assertNotIn("publish", self.github.calls)
        self.client.staged_files["/actions.html"] = self.client.live_files["/actions.html"]
        self.github.item["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.run_publish()
        self.assertNotIn("publish", self.github.calls)

    def test_feed_change_during_draft_staging_stops_publication(self):
        def changed(candidate, staged, notes, secret, *, github):
            (self.staged / "appcast.xml").write_bytes(b"changed")
            return {"tag": TAG, "sha256": self.digest, "draft": True}
        with self.assertRaisesRegex(ValueError, "changed during"):
            publisher.publish(self.candidate, self.staged, NOTES, "fixture", self.receipt, self.client,
                              enabled="YES", github=self.github, stage_draft=changed, download=self.download)
        self.assertNotIn("publish", self.github.calls)

    def test_live_site_change_after_publication_blocks_receipt(self):
        original = self.github.publish
        def publish_and_change(release_id):
            original(release_id)
            self.client.live = hosting_fixture.CHANGED
        self.github.publish = publish_and_change
        with self.assertRaisesRegex(ValueError, "live Firebase version changed"):
            self.run_publish()
        self.assertFalse((self.candidate / "PUBLIC_VERIFIED.json").exists())
        self.assertFalse(self.github.item["draft"])

    def test_local_asset_change_during_public_verification_blocks_receipt(self):
        def change_after_download(url, size, digest):
            if url.endswith("/Draftly.zip"):
                (self.candidate / "Draftly.zip").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "changed during public verification"):
            self.run_publish(download=change_after_download)
        self.assertFalse((self.candidate / "PUBLIC_VERIFIED.json").exists())
        self.assertFalse(self.github.item["draft"])


class PublicDownloadTests(unittest.TestCase):
    class Response(io.BytesIO):
        headers = {}

    class Opener:
        def __init__(self, responses):
            self.responses = iter(responses)
            self.requests = []
        def open(self, request, timeout):
            self.requests.append(request)
            response = next(self.responses)
            if isinstance(response, Exception):
                raise response
            return response

    def test_follows_only_trusted_https_redirects_and_checks_bytes(self):
        url = "https://github.com/pobrespandas/draftly/releases/download/v0.1.0/Draftly.zip"
        redirect = HTTPError(url, 302, "fixture", {"Location": "https://release-assets.githubusercontent.com/item?sig=fixture"}, None)
        opener = self.Opener([redirect, self.Response(b"archive")])
        publisher.verify_public_asset(url, 7, "sha256:" + hashlib.sha256(b"archive").hexdigest(), opener=opener)
        self.assertEqual(len(opener.requests), 2)
        self.assertTrue(all(request.get_header("Authorization") is None for request in opener.requests))

    def test_rejects_unsafe_redirect_and_changed_content(self):
        url = "https://github.com/pobrespandas/draftly/releases/download/v0.1.0/Draftly.zip"
        redirect = HTTPError(url, 302, "fixture", {"Location": "https://evil.example/item"}, None)
        opener = self.Opener([redirect])
        with self.assertRaisesRegex(ValueError, "unsafe host"):
            publisher.verify_public_asset(url, 7, "sha256:" + "0" * 64, opener=opener)
        self.assertEqual(len(opener.requests), 1)
        with self.assertRaisesRegex(ValueError, "does not match"):
            publisher.verify_public_asset(url, 7, "sha256:" + "0" * 64, opener=self.Opener([self.Response(b"archive")]))


if __name__ == "__main__":
    unittest.main()
