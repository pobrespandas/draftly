"""Exercise GitHub draft staging without publishing or using real credentials."""
import base64
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

spec = importlib.util.spec_from_file_location("github_stage", Path(__file__).with_name("stage-github-release.py"))
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)
COMMIT = "a" * 40
NOTES = "Neutral release 🐼\n"


class FakeGitHub:
    def __init__(self, *, interrupt=False):
        self.items = []
        self.calls = []
        self.interrupt = interrupt
        self.main = COMMIT
        self.tag = COMMIT

    def refs(self, tag):
        self.calls.append("refs")
        return self.main, self.tag

    def releases(self):
        self.calls.append("releases")
        return self.items

    def create_draft(self, tag, notes):
        self.calls.append("create")
        result = {"tag_name": tag, "name": "Draftly " + tag[1:], "draft": True,
                  "prerelease": False, "body": notes, "assets": []}
        self.items.append(result)
        return result

    def upload(self, tag, paths):
        self.calls.append("upload")
        release = next(item for item in self.items if item["tag_name"] == tag)
        for path in paths:
            release["assets"].append({"name": path.name, "state": "uploaded", "size": path.stat().st_size,
                                      "digest": stage.file_digest(path)})
            if self.interrupt:
                self.interrupt = False
                raise ValueError("Simulated interruption")


class GitHubReleaseStageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="draftly-github-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        key = Ed25519PrivateKey.generate()
        self.secret = base64.b64encode(key.private_bytes(serialization.Encoding.Raw,
            serialization.PrivateFormat.Raw, serialization.NoEncryption())).decode()
        public = base64.b64encode(key.public_key().public_bytes(serialization.Encoding.Raw,
            serialization.PublicFormat.Raw)).decode()
        self.candidate = self.root / "candidate"
        self.candidate.mkdir()
        info = {"CFBundleIdentifier": stage.prepare.release.BUNDLE, "CFBundleName": "Draftly",
                "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                "CFBundleURLTypes": [{"CFBundleURLSchemes": ["draftly"]}], "LSMinimumSystemVersion": "26.0",
                "DraftlyUpdatesEnabled": "YES", "SUPublicEDKey": public, "SUFeedURL": stage.prepare.release.FEED,
                "SUAutomaticallyUpdate": False, "SUAllowsAutomaticUpdates": False, "SUEnableAutomaticChecks": True,
                "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True}
        package = self.candidate / "Draftly.zip"
        with zipfile.ZipFile(package, "w") as archive:
            archive.writestr("Draftly.app/Contents/Info.plist", plistlib.dumps(info))
        digest = hashlib.sha256(package.read_bytes()).hexdigest()
        (self.candidate / "candidate.json").write_text(json.dumps({"version": "0.1.0", "build": "1",
            "tag": "v0.1.0", "sourceCommit": COMMIT, "updatesEnabled": True, "sha256": digest}))
        (self.candidate / "Draftly.zip.sha256").write_text(digest + "  Draftly.zip\n")
        (self.candidate / "READY").write_text("fixture")
        self.appcast = self.root / "feed"
        stage.prepare.prepare(self.candidate, self.appcast, NOTES, self.secret, releases=[],
                              now=datetime.datetime(2026, 10, 29, tzinfo=datetime.timezone.utc))
        self.github = FakeGitHub()
        self.verifications = []
        patcher = patch.object(stage.prepare.release, "source_commit", return_value=COMMIT)
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_stage(self, *, current_feed=None):
        return stage.stage(self.candidate, self.appcast, NOTES, self.secret, github=self.github,
                           verify=lambda path: self.verifications.append(path), current_feed=current_feed)

    def test_creates_draft_with_exact_assets_and_never_publishes(self):
        result = self.run_stage()
        self.assertTrue(result["draft"])
        self.assertEqual(result["assets"], ["Draftly.zip", "Draftly.zip.sha256", "appcast.xml", "candidate.json"])
        self.assertEqual(self.verifications, [self.candidate])
        self.assertEqual(self.github.calls.count("create"), 1)
        self.assertEqual(self.github.calls.count("upload"), 1)
        self.assertNotIn("publish", self.github.calls)

    def test_interrupted_upload_resumes_without_replacing_an_asset(self):
        self.github.interrupt = True
        with self.assertRaisesRegex(ValueError, "interruption"):
            self.run_stage()
        existing = dict(self.github.items[0]["assets"][0])
        result = self.run_stage()
        self.assertTrue(result["draft"])
        self.assertEqual(self.github.calls.count("create"), 1)
        self.assertEqual(self.github.items[0]["assets"][0], existing)
        self.assertEqual(len(self.github.items[0]["assets"]), 4)

    def test_existing_asset_mismatch_is_never_overwritten(self):
        self.run_stage()
        self.github.items[0]["assets"][0]["digest"] = "sha256:" + "0" * 64
        before = self.github.calls.count("upload")
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.run_stage()
        self.assertEqual(self.github.calls.count("upload"), before)

    def test_unknown_asset_and_release_notes_mismatch_are_never_overwritten(self):
        self.run_stage()
        self.github.items[0]["assets"].append({"name": "unknown.txt", "state": "uploaded", "size": 1, "digest": "sha256:" + "0" * 64})
        with self.assertRaisesRegex(ValueError, "unexpected"):
            self.run_stage()
        self.github.items[0]["assets"].pop()
        self.github.items[0]["body"] = "Other notes"
        with self.assertRaisesRegex(ValueError, "metadata"):
            self.run_stage()
        self.assertEqual(self.github.calls.count("upload"), 1)

    def test_already_published_candidate_can_be_checked_without_mutation(self):
        self.run_stage()
        self.github.items[0]["draft"] = False
        before = list(self.github.calls)
        result = self.run_stage(current_feed=(self.appcast / "appcast.xml").read_bytes())
        self.assertFalse(result["draft"])
        self.assertNotIn("create", self.github.calls[len(before):])
        self.assertNotIn("upload", self.github.calls[len(before):])

    def test_rejects_changed_source_notes_or_feed_before_writing(self):
        self.github.main = "b" * 40
        with self.assertRaises(ValueError):
            self.run_stage()
        self.assertNotIn("create", self.github.calls)
        self.github.main = COMMIT
        with self.assertRaisesRegex(ValueError, "release notes"):
            stage.inspect_inputs(self.candidate, self.appcast, self.secret, "Different")
        feed = self.appcast / "appcast.xml"
        feed.write_bytes(feed.read_bytes().replace(b"Draftly 0.1.0", b"Changed 0.1.0"))
        with self.assertRaises(ValueError):
            self.run_stage()
        self.assertNotIn("create", self.github.calls)

    def test_candidate_verification_failure_precedes_github_access(self):
        def reject(_):
            raise subprocess.CalledProcessError(1, ["spctl"])
        with self.assertRaises(subprocess.CalledProcessError):
            stage.stage(self.candidate, self.appcast, NOTES, self.secret, github=self.github,
                        verify=reject, current_feed=None)
        self.assertEqual(self.github.calls, [])

    def test_never_extracts_unsafe_zip_paths_or_links(self):
        for name, target in (("../escape", None), ("Draftly.app/a/../../escape", None),
                             ("Draftly.app/link", "../../escape"), ("Draftly.app/link", "/tmp/escape")):
            with self.subTest(name=name, target=target):
                path = self.root / "unsafe.zip"
                with zipfile.ZipFile(path, "w") as archive:
                    entry = zipfile.ZipInfo(name)
                    if target is not None:
                        entry.create_system = 3
                        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(entry, target or "fixture")
                with self.assertRaises(ValueError):
                    stage.safe_archive(path)

    def test_accepts_internal_framework_links(self):
        path = self.root / "safe.zip"
        with zipfile.ZipFile(path, "w") as archive:
            entry = zipfile.ZipInfo("Draftly.app/Contents/Frameworks/Sparkle.framework/Versions/Current")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(entry, "B")
        stage.safe_archive(path)

    def test_remote_ref_change_after_draft_creation_stops_upload(self):
        original = self.github.create_draft
        def create(tag, notes):
            result = original(tag, notes)
            self.github.main = "b" * 40
            return result
        self.github.create_draft = create
        with self.assertRaisesRegex(ValueError, "refs changed"):
            self.run_stage()
        self.assertEqual(self.github.calls.count("create"), 1)
        self.assertNotIn("upload", self.github.calls)

    def test_annotated_remote_tags_are_peeled_to_the_commit(self):
        github = stage.GitHub()
        objects = {stage.REPOSITORY + "/git/ref/heads/main": {"object": {"type": "commit", "sha": COMMIT}},
                   stage.REPOSITORY + "/git/ref/tags/v0.1.0": {"object": {"type": "tag", "sha": "b" * 40}},
                   stage.REPOSITORY + "/git/tags/" + "b" * 40: {"object": {"type": "commit", "sha": COMMIT}}}
        with patch.object(github, "api", side_effect=lambda path: objects[path]):
            self.assertEqual(github.refs("v0.1.0"), (COMMIT, COMMIT))

    def test_verification_runs_signing_stapler_and_gatekeeper_checks(self):
        calls = []
        def runner(command, **kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0)
        stage.verify_candidate(self.candidate, runner=runner)
        self.assertEqual([command[0] for command in calls], ["ditto", stage.sys.executable, "xcrun", "spctl"])
        self.assertIn("--require-developer-id", calls[1])
        self.assertEqual(calls[2][1:3], ["stapler", "validate"])

    def test_github_child_does_not_inherit_update_or_firebase_secrets(self):
        result = subprocess.CompletedProcess([], 0, stdout="{}", stderr="")
        with patch.dict(os.environ, {"DRAFTLY_SPARKLE_PRIVATE_KEY": self.secret,
                                    "DRAFTLY_FIREBASE_ACCESS_TOKEN": "private-token"}), \
             patch.object(stage.subprocess, "run", return_value=result) as run:
            stage.GitHub().command(["api", "fixture"])
        self.assertNotIn("DRAFTLY_SPARKLE_PRIVATE_KEY", run.call_args.kwargs["env"])
        self.assertNotIn("DRAFTLY_FIREBASE_ACCESS_TOKEN", run.call_args.kwargs["env"])

    def test_local_verification_does_not_inherit_service_credentials(self):
        result = subprocess.CompletedProcess([], 0, stdout="", stderr="")
        with patch.dict(os.environ, {"DRAFTLY_SPARKLE_PRIVATE_KEY": self.secret,
                                    "DRAFTLY_FIREBASE_ACCESS_TOKEN": "firebase", "GH_TOKEN": "github"}), \
             patch.object(stage.subprocess, "run", return_value=result) as run:
            stage.secret_free_run(["fixture"], check=True)
        for name in ("DRAFTLY_SPARKLE_PRIVATE_KEY", "DRAFTLY_FIREBASE_ACCESS_TOKEN", "GH_TOKEN"):
            self.assertNotIn(name, run.call_args.kwargs["env"])

    def test_local_verification_accepts_an_explicit_sanitized_environment(self):
        result = subprocess.CompletedProcess([], 0, stdout="", stderr="")
        with patch.object(stage.subprocess, "run", return_value=result) as run:
            stage.secret_free_run(["fixture"], env={"PATH": "/bin", "GH_TOKEN": "fixture"}, check=True)
        self.assertEqual(run.call_args.kwargs["env"], {"PATH": "/bin"})


if __name__ == "__main__":
    unittest.main()
