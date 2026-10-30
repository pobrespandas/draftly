"""Verify promotion ordering and recovery without external services."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("promote_release", Path(__file__).with_name("promote-firebase-release.py"))
promoter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(promoter)


class PromotionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.journal = Path(self.tmp.name) / "promotion.json"
        self.receipt = {"baseVersion": "sites/test/versions/base", "stagedVersion": "sites/test/versions/new", "appcastHash": "a" * 64}
        self.verified = {"tag": "v0.1.0", "releaseId": 3}
        self.events = []
        self.live = "staged"
        self.fail_post = False
        self.fail_feed = False
        self.bad_reply = False

    def check_lock(self):
        self.events.append("lock")

    def verify_public(self):
        self.events.append("public")
        return self.verified

    def check_feed(self, data):
        self.assertEqual(data, b"feed")
        self.events.append("feed")
        if self.fail_feed:
            raise ValueError("Public feed differs")

    def request(self, method, path, body):
        self.assertEqual(method, "POST")
        self.assertEqual(path, promoter.firebase.SITE + "/releases?versionName=sites%2Ftest%2Fversions%2Fnew")
        self.assertEqual(json.loads(self.journal.read_text())["state"], "pending")
        self.assertEqual(self.events[-1], "lock")
        self.events.append("post")
        self.live = "promoted"
        if self.fail_post:
            raise OSError("Response lost")
        return {"version": {"name": "other" if self.bad_reply else self.receipt["stagedVersion"]}}

    def run_promotion(self, **overrides):
        options = dict(enabled="YES", check_lock=self.check_lock, verify_public=self.verify_public, check_feed=self.check_feed)
        options.update(overrides)
        with patch.object(promoter.publisher, "validate_site", side_effect=lambda *args: self.live):
            return promoter.promote(self, self.receipt, b"feed", b"compressed", self.journal, **options)

    def test_public_verification_and_durable_journal_precede_promotion(self):
        self.run_promotion()
        self.assertLess(self.events.index("public"), self.events.index("post"))
        self.assertEqual(json.loads(self.journal.read_text())["state"], "complete")
        self.run_promotion()
        self.assertEqual(self.events.count("post"), 1)

    def test_failed_public_verification_or_lock_never_promotes(self):
        def fail():
            raise ValueError("Rejected")
        for option in ("verify_public", "check_lock"):
            with self.subTest(option=option), self.assertRaisesRegex(ValueError, "Rejected"):
                self.run_promotion(**{option: fail})
            self.assertNotIn("post", self.events)
            self.assertFalse(self.journal.exists())

    def test_lost_response_recovers_by_observation_without_another_post(self):
        self.fail_post = True
        with self.assertRaises(OSError):
            self.run_promotion()
        self.assertEqual(json.loads(self.journal.read_text())["state"], "pending")
        self.fail_post = False
        self.run_promotion()
        self.assertEqual(self.events.count("post"), 1)

    def test_pending_request_on_old_live_version_never_retries(self):
        self.fail_post = True
        with self.assertRaises(OSError):
            self.run_promotion()
        self.live = "staged"
        with self.assertRaisesRegex(ValueError, "uncertain"):
            self.run_promotion()
        self.assertEqual(self.events.count("post"), 1)

    def test_public_feed_failure_keeps_pending_journal(self):
        self.fail_feed = True
        with self.assertRaisesRegex(ValueError, "differs"):
            self.run_promotion()
        self.assertEqual(json.loads(self.journal.read_text())["state"], "pending")
        self.fail_feed = False
        self.run_promotion()
        self.assertEqual(self.events.count("post"), 1)

    def test_disabled_promotion_does_not_check_or_mutate(self):
        with self.assertRaisesRegex(ValueError, "disabled"):
            self.run_promotion(enabled=None)
        self.assertEqual(self.events, [])

    def test_wrong_reply_or_changed_release_cannot_complete(self):
        self.bad_reply = True
        with self.assertRaisesRegex(ValueError, "confirm"):
            self.run_promotion()
        self.verified = {"tag": "v0.2.0", "releaseId": 4}
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.run_promotion()

    def test_lock_loss_after_promotion_prevents_acceptance(self):
        def check():
            if "post" in self.events:
                raise ValueError("Lock lost")
            self.check_lock()
        with self.assertRaisesRegex(ValueError, "Lock lost"):
            self.run_promotion(check_lock=check)
        self.assertEqual(json.loads(self.journal.read_text())["state"], "pending")

    def test_symlink_journal_is_rejected_before_checks(self):
        self.journal.symlink_to(Path(self.tmp.name) / "other")
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.run_promotion()
        self.assertEqual(self.events, [])

if __name__ == "__main__":
    unittest.main()
