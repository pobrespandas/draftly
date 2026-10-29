"""Verify restored release candidates without native signing or network access."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("candidate_verify", Path(__file__).with_name("verify-release-candidate.py"))
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class CandidateRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.public = base64.b64encode(bytes(range(32))).decode()
        self.commit = "a" * 40
        self.source = {"CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"}
        info = {"CFBundleIdentifier": verify.stage.prepare.release.BUNDLE, "CFBundleName": "Draftly",
                "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                "CFBundleURLTypes": [{"CFBundleURLSchemes": ["draftly"]}],
                "DraftlyUpdatesEnabled": "YES", "SUPublicEDKey": self.public,
                "SUFeedURL": verify.stage.prepare.release.FEED, "SUAutomaticallyUpdate": False,
                "SUAllowsAutomaticUpdates": False, "SUEnableAutomaticChecks": True,
                "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True}
        self.package = self.directory / "Draftly.zip"
        with zipfile.ZipFile(self.package, "w") as archive:
            archive.writestr("Draftly.app/Contents/Info.plist", plistlib.dumps(info))
        digest = hashlib.sha256(self.package.read_bytes()).hexdigest()
        self.metadata = {"version": "0.1.0", "build": "1", "tag": "v0.1.0",
                         "sourceCommit": self.commit, "updatesEnabled": True, "sha256": digest}
        self.write_metadata()
        (self.directory / "Draftly.zip.sha256").write_text(digest + "  Draftly.zip\n")
        (self.directory / "READY").write_text("fixture")
        self.checked = []

    def write_metadata(self):
        (self.directory / "candidate.json").write_text(json.dumps(self.metadata))

    def check(self, **kwargs):
        return verify.verify(self.directory, "v0.1.0", self.public, source_commit=self.commit,
                             source_info=self.source, verify_signature=lambda path: self.checked.append(path), **kwargs)

    def test_valid_candidate_checks_native_signature(self):
        self.assertEqual(self.check(), self.metadata)
        self.assertEqual(self.checked, [self.directory])

    def test_source_and_checksum_mismatch_stop_before_native_check(self):
        self.metadata["sourceCommit"] = "b" * 40
        self.write_metadata()
        with self.assertRaisesRegex(ValueError, "source commit"):
            self.check()
        self.metadata["sourceCommit"] = self.commit
        self.metadata["sha256"] = "0" * 64
        self.write_metadata()
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.check()
        self.assertEqual(self.checked, [])

    def test_different_public_key_is_rejected(self):
        other = base64.b64encode(bytes(reversed(range(32)))).decode()
        with self.assertRaisesRegex(ValueError, "update configuration"):
            verify.verify(self.directory, "v0.1.0", other, source_commit=self.commit,
                          source_info=self.source, verify_signature=lambda _: self.fail("must not verify"))

    def test_archive_changed_during_native_verification_is_rejected(self):
        def change(_):
            with self.package.open("ab") as output:
                output.write(b"changed")
        with self.assertRaisesRegex(ValueError, "changed"):
            verify.verify(self.directory, "v0.1.0", self.public, source_commit=self.commit,
                          source_info=self.source, verify_signature=change)

    def test_native_verification_failure_propagates(self):
        def fail(_):
            raise ValueError("invalid signature")
        with self.assertRaisesRegex(ValueError, "invalid signature"):
            verify.verify(self.directory, "v0.1.0", self.public, source_commit=self.commit,
                          source_info=self.source, verify_signature=fail)

    def test_source_build_mismatch_is_rejected(self):
        self.source["CFBundleVersion"] = "2"
        with self.assertRaisesRegex(ValueError, "CFBundleVersion"):
            self.check()
        self.assertEqual(self.checked, [])


if __name__ == "__main__":
    unittest.main()
