"""Test Firebase appcast staging without changing a real site."""
import base64
import gzip
import hashlib
import io
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import urlsplit

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

spec = importlib.util.spec_from_file_location("firebase_stage", Path(__file__).with_name("firebase-stage-appcast.py"))
firebase = importlib.util.module_from_spec(spec)
spec.loader.exec_module(firebase)
TOOL = Path(__file__).resolve().parent.parent / ".build/artifacts/sparkle/Sparkle/bin/sign_update"
OLD = firebase.SITE + "/versions/old123"
NEW = firebase.SITE + "/versions/new456"
CHANGED = firebase.SITE + "/versions/changed789"


class FakeHosting:
    def __init__(self, *, change_after_upload=False, missing_old=False, unsafe_upload=False, has_feed=False):
        self.live = OLD
        self.live_files = {"/index.html": "a" * 64, "/actions.html": "b" * 64, "/actions/a.json": "c" * 64}
        if has_feed:
            self.live_files["/appcast.xml"] = "d" * 64
        self.config = {"headers": [{"glob": "**", "headers": {"Cache-Control": "max-age=60"}}]}
        self.staged_files = {}
        self.staged_config = None
        self.staged_labels = {}
        self.staged_status = "CREATED"
        self.change_after_upload = change_after_upload
        self.missing_old = missing_old
        self.unsafe_upload = unsafe_upload
        self.calls = []
        self.uploaded = None

    def request(self, method, path, body=None, *, upload=False):
        self.calls.append((method, path, body, upload))
        route = urlsplit(path).path if upload else path.split("?", 1)[0]
        if method == "GET" and route == firebase.SITE + "/channels/live":
            return {"release": {"version": {"name": self.live}}}
        if method == "GET" and route in (OLD, CHANGED):
            return {"name": route, "status": "FINALIZED", "config": self.config, "fileCount": str(len(self.live_files))}
        if method == "GET" and route == NEW:
            return {"name": NEW, "status": self.staged_status, "config": self.staged_config, "labels": self.staged_labels}
        if method == "GET" and route in (OLD + "/files", CHANGED + "/files", NEW + "/files"):
            files = self.staged_files if route == NEW + "/files" else self.live_files
            return {"files": [{"path": path, "hash": digest, "status": "ACTIVE"} for path, digest in files.items()]}
        if method == "POST" and route == firebase.SITE + "/versions":
            self.staged_config = body["config"]
            self.staged_labels = body["labels"]
            return {"name": NEW}
        if method == "POST" and route == NEW + ":populateFiles":
            self.staged_files.update(body["files"])
            digest = body["files"].get("/appcast.xml")
            required = ["a" * 64] if self.missing_old else ([digest] if digest else [])
            host = "evil.example" if self.unsafe_upload else "upload-firebasehosting.googleapis.com"
            return {"uploadRequiredHashes": required, "uploadUrl": "https://" + host + "/upload/" + NEW + "/files"}
        if method == "POST" and upload:
            self.uploaded = body
            if self.change_after_upload:
                self.live = CHANGED
            return {}
        if method == "PATCH" and route == NEW:
            self.staged_status = "FINALIZED"
            return {"name": NEW, "status": "FINALIZED"}
        raise AssertionError("Unexpected request: " + method + " " + path)


class FirebaseStageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="draftly-firebase-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.key = Ed25519PrivateKey.generate()
        self.secret = base64.b64encode(self.key.private_bytes(serialization.Encoding.Raw,
            serialization.PrivateFormat.Raw, serialization.NoEncryption())).decode()
        self.public = base64.b64encode(self.key.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
        self.assertTrue(TOOL.is_file(), "Resolve the pinned Sparkle package before running tests.")

    def feed(self, *versions, first_title=""):
        entries = "".join("<item>%s<s:shortVersionString>%s</s:shortVersionString><s:version>%s</s:version></item>"
                          % (("<title>" + first_title + "</title>") if i == 0 and first_title else "", *item)
                          for i, item in enumerate(versions))
        path = self.root / "appcast.xml"
        path.write_text('<rss xmlns:s="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>' + entries + '</channel></rss>')
        result = subprocess.run([str(TOOL), "--ed-key-file", "-", str(path)], input=self.secret + "\n",
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, "Sparkle could not sign the disposable fixture.")
        return path.read_bytes()

    def test_cli_requires_a_journal_before_staging(self):
        args = ["firebase-stage-appcast.py", "--appcast", "feed.xml", "--public-key", self.public,
                "--expected-version", OLD]
        with patch("sys.argv", args), patch.dict("os.environ", {"DRAFTLY_FIREBASE_ACCESS_TOKEN": "fixture"}), \
                patch.object(firebase, "HostingClient") as client:
            with self.assertRaisesRegex(SystemExit, "journal"):
                firebase.main()
            client.return_value.request.assert_not_called()

    def test_read_only_snapshot_captures_all_files_and_config(self):
        client = FakeHosting()
        result = firebase.snapshot(client)
        self.assertEqual(result, {"version": OLD, "config": client.config, "files": client.live_files})
        self.assertTrue(all(method == "GET" for method, _, _, _ in client.calls))

    def test_file_listing_uses_all_pages_and_rejects_repeated_paths(self):
        class Pages:
            def __init__(self, duplicate=False):
                self.duplicate = duplicate
            def request(self, method, path):
                first = {"path": "/index.html", "hash": "a" * 64, "status": "ACTIVE"}
                second = first if self.duplicate else {"path": "/actions.html", "hash": "b" * 64, "status": "ACTIVE"}
                return {"files": [second]} if "pageToken=" in path else {"files": [first], "nextPageToken": "next"}
        self.assertEqual(firebase.list_files(Pages(), OLD), {"/index.html": "a" * 64, "/actions.html": "b" * 64})
        with self.assertRaisesRegex(ValueError, "invalid or inactive"):
            firebase.list_files(Pages(duplicate=True), OLD)

    def test_api_client_rejects_unsafe_uploads_without_exposing_token(self):
        client = firebase.HostingClient("private-token")
        with self.assertRaises(ValueError) as failure:
            client.request("POST", "https://evil.example/upload", b"data", upload=True)
        self.assertNotIn("private-token", str(failure.exception))
        self.assertIsNone(firebase.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.example"))

    def test_gzip_feed_has_a_stable_header_across_python_versions(self):
        result = firebase.compress_feed(b"draftly")
        self.assertEqual(result, bytes.fromhex("1f8b08000000000002ff4b294a4c2bc9a90400dfc009ad07000000"))
        self.assertEqual(gzip.decompress(result), b"draftly")

    def test_stages_signed_appcast_and_preserves_live_site_without_publishing(self):
        client = FakeHosting()
        data = self.feed(("0.1.0", "1"))
        result = firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None)
        self.assertEqual(result["baseVersion"], OLD)
        self.assertEqual(result["stagedVersion"], NEW)
        self.assertEqual(result["preservedFiles"], 3)
        self.assertEqual(gzip.decompress(client.uploaded), data)
        self.assertEqual(hashlib.sha256(client.uploaded).hexdigest(), result["appcastHash"])
        self.assertEqual({k: v for k, v in client.staged_files.items() if k != "/appcast.xml"}, client.live_files)
        self.assertEqual(client.staged_config, client.config)
        self.assertFalse(any("/releases" in path for _, path, _, _ in client.calls))

    def test_staged_feed_passes_publication_site_verification(self):
        spec = importlib.util.spec_from_file_location("publish_release_for_stage", Path(__file__).with_name("publish-github-release.py"))
        publisher = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(publisher)
        client = FakeHosting()
        data = self.feed(("0.1.0", "1"))
        receipt = firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None)
        self.assertEqual(publisher.validate_site(client, receipt, data, firebase.compress_feed(data)), "staged")
        self.assertFalse(any("/releases" in path for _, path, _, _ in client.calls))

    def test_recovery_reuses_the_finalized_version_when_a_draft_exists(self):
        client = FakeHosting()
        data = self.feed(("0.1.0", "1"))
        journal = self.root / "journal.json"
        first = firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None, journal=journal)
        releases = [{"tag_name": "v0.1.0", "draft": True, "prerelease": False}]
        second = firebase.stage(client, OLD, data, self.public, releases=releases, current_feed=None,
                                journal=journal, resume=True)
        self.assertEqual(first, second)
        self.assertEqual(sum(method == "POST" and path == firebase.SITE + "/versions" for method, path, _, _ in client.calls), 1)
        self.assertEqual(sum(method == "PATCH" for method, _, _, _ in client.calls), 1)

    def test_existing_payload_is_preserved_before_any_firebase_write(self):
        client = FakeHosting()
        data = self.feed(("0.1.0", "1"))
        journal = self.root / "journal.json"
        payload = firebase.payload_path(journal)
        payload.write_bytes(b"keep existing bytes")
        with self.assertRaises(FileExistsError):
            firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None, journal=journal)
        self.assertEqual(payload.read_bytes(), b"keep existing bytes")
        self.assertFalse(journal.exists())
        self.assertFalse(any(method in ("POST", "PATCH") for method, _, _, _ in client.calls))

    def test_recovery_uses_original_compressed_bytes_without_recompressing(self):
        client = FakeHosting()
        data = self.feed(("0.1.0", "1"))
        journal = self.root / "journal.json"
        first = firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None, journal=journal)
        with patch.object(firebase, "compress_feed", side_effect=AssertionError("must use saved bytes")):
            second = firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None,
                                    journal=journal, resume=True)
        self.assertEqual(first, second)

    def test_recovery_rejects_changed_or_missing_compressed_payload(self):
        client = FakeHosting()
        data = self.feed(("0.1.0", "1"))
        journal = self.root / "journal.json"
        firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None, journal=journal)
        payload = firebase.payload_path(journal)
        original = payload.read_bytes()
        for value in (b"invalid", gzip.compress(b"other", mtime=0)):
            payload.write_bytes(value)
            with self.subTest(value=value), self.assertRaises(ValueError):
                firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None,
                               journal=journal, resume=True)
        payload.unlink()
        with self.assertRaises((ValueError, OSError)):
            firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None,
                           journal=journal, resume=True)
        self.assertTrue(original)

    def test_saved_payload_must_decode_to_exact_feed_even_with_matching_hash(self):
        payload = self.root / "payload.gz"
        for value in (b"not gzip", gzip.compress(b"different", mtime=0)):
            payload.write_bytes(value)
            digest = hashlib.sha256(value).hexdigest()
            with self.subTest(value=value), self.assertRaises(ValueError):
                firebase.read_payload(payload, b"expected", digest)

    def test_recovery_continues_the_same_incomplete_version(self):
        client = FakeHosting(unsafe_upload=True)
        data = self.feed(("0.1.0", "1"))
        journal = self.root / "journal.json"
        with self.assertRaisesRegex(ValueError, "invalid upload URL"):
            firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None, journal=journal)
        client.unsafe_upload = False
        result = firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None,
                                journal=journal, resume=True)
        self.assertEqual(result["stagedVersion"], NEW)
        self.assertEqual(sum(method == "POST" and path == firebase.SITE + "/versions" for method, path, _, _ in client.calls), 1)

    def test_unknown_creation_outcome_requires_inspection_without_creating_again(self):
        class UnknownCreation(FakeHosting):
            def request(self, method, path, body=None, *, upload=False):
                if method == "POST" and path == firebase.SITE + "/versions":
                    self.calls.append((method, path, body, upload))
                    raise ValueError("Connection lost after request")
                return super().request(method, path, body, upload=upload)
        client = UnknownCreation()
        data = self.feed(("0.1.0", "1"))
        journal = self.root / "journal.json"
        with self.assertRaisesRegex(ValueError, "Connection lost"):
            firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None, journal=journal)
        with self.assertRaisesRegex(ValueError, "outcome is unknown"):
            firebase.stage(client, OLD, data, self.public, releases=[], current_feed=None, journal=journal, resume=True)
        self.assertEqual(sum(method == "POST" and path == firebase.SITE + "/versions" for method, path, _, _ in client.calls), 1)

    def test_tampered_feed_or_wrong_key_is_rejected(self):
        signed = self.feed(("0.1.0", "1"))
        for value, key in ((signed.replace(b"0.1.0", b"0.1.1"), self.public),
                           (signed, base64.b64encode(bytes(32)).decode()), (b"<rss/>", self.public)):
            with self.subTest(value=value[:20]), self.assertRaises(ValueError):
                firebase.verify_feed(value, key)

    def test_expected_version_and_concurrent_live_change_abort(self):
        feed = self.feed(("0.1.0", "1"))
        stale = FakeHosting()
        with self.assertRaisesRegex(ValueError, "changed before"):
            firebase.stage(stale, CHANGED, feed, self.public, releases=[], current_feed=None)
        self.assertFalse(any(method == "POST" for method, _, _, _ in stale.calls))
        concurrent = FakeHosting(change_after_upload=True)
        with self.assertRaisesRegex(ValueError, "changed while"):
            firebase.stage(concurrent, OLD, feed, self.public, releases=[], current_feed=None)
        self.assertFalse(any(method == "PATCH" for method, _, _, _ in concurrent.calls))

    def test_missing_existing_content_or_unsafe_upload_url_aborts(self):
        feed = self.feed(("0.1.0", "1"))
        for client in (FakeHosting(missing_old=True), FakeHosting(unsafe_upload=True)):
            with self.subTest(client=client), self.assertRaises(ValueError):
                firebase.stage(client, OLD, feed, self.public, releases=[], current_feed=None)
            self.assertIsNone(client.uploaded)
            self.assertFalse(any(method == "PATCH" for method, _, _, _ in client.calls))

    def test_rejects_missing_live_feed_and_nonmonotonic_history(self):
        feed = self.feed(("0.1.0", "1"))
        with self.assertRaisesRegex(ValueError, "file list do not agree"):
            firebase.stage(FakeHosting(has_feed=True), OLD, feed, self.public, releases=[], current_feed=None)
        old_feed = self.feed(("0.2.0", "2"))
        new_feed = self.feed(("0.2.0", "2"), ("0.1.0", "3"))
        releases = [{"tag_name": "v0.2.0", "draft": False, "prerelease": False}]
        with self.assertRaisesRegex(ValueError, "version must be greater"):
            firebase.stage(FakeHosting(has_feed=True), OLD, new_feed, self.public, releases=releases, current_feed=old_feed)

    def test_preserves_the_contents_of_published_release_items(self):
        old_feed = self.feed(("0.1.0", "1"), first_title="Original")
        next_feed = self.feed(("0.1.0", "1"), ("0.2.0", "2"), first_title="Original")
        changed_feed = self.feed(("0.1.0", "1"), ("0.2.0", "2"), first_title="Changed")
        releases = [{"tag_name": "v0.1.0", "draft": False, "prerelease": False}]
        result = firebase.stage(FakeHosting(has_feed=True), OLD, next_feed, self.public,
                                releases=releases, current_feed=old_feed)
        self.assertEqual(result["stagedVersion"], NEW)
        with self.assertRaisesRegex(ValueError, "changes a published release item"):
            firebase.stage(FakeHosting(has_feed=True), OLD, changed_feed, self.public,
                           releases=releases, current_feed=old_feed)

    def test_public_feed_must_match_the_live_file_hash(self):
        signed = self.feed(("0.1.0", "1"))
        digest = "d" * 64

        class Response(io.BytesIO):
            def __init__(self, body, etag):
                super().__init__(body)
                self.headers = {"ETag": '"' + etag + '"'}

        class Opener:
            def __init__(self, response):
                self.response = response
            def open(self, request, timeout):
                if isinstance(self.response, Exception):
                    raise self.response
                return self.response

        live = {"files": {"/appcast.xml": digest}}
        with patch.object(firebase.urllib.request, "build_opener", return_value=Opener(Response(signed, digest))):
            self.assertEqual(firebase.fetch_live_feed(live), signed)
        with patch.object(firebase.urllib.request, "build_opener", return_value=Opener(Response(signed, "a" * 64))):
            with self.assertRaisesRegex(ValueError, "does not match"):
                firebase.fetch_live_feed(live)
        missing = HTTPError(firebase.history.FEED_URL, 404, "fixture", {}, None)
        with patch.object(firebase.urllib.request, "build_opener", return_value=Opener(missing)):
            self.assertIsNone(firebase.fetch_live_feed({"files": {}}))
            with self.assertRaisesRegex(ValueError, "cannot be read"):
                firebase.fetch_live_feed(live)


if __name__ == "__main__":
    unittest.main()
