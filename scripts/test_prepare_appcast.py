"""Test Sparkle feed generation with disposable keys and archives."""
import base64
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

spec = importlib.util.spec_from_file_location("prepare_appcast", Path(__file__).with_name("prepare-appcast.py"))
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


class PrepareAppcastTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="draftly-appcast-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.key = Ed25519PrivateKey.generate()
        seed = self.key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
                                      serialization.NoEncryption())
        self.secret = base64.b64encode(seed).decode()
        self.public = base64.b64encode(self.key.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
        self.assertTrue(appcast.TOOL.is_file(), "Resolve the pinned Sparkle package before running tests.")

    def candidate(self, version="0.1.0", build="1"):
        directory = self.root / ("candidate-" + version)
        directory.mkdir()
        info = {"CFBundleIdentifier": appcast.release.BUNDLE, "CFBundleName": "Draftly",
                "CFBundleShortVersionString": version, "CFBundleVersion": build,
                "CFBundleURLTypes": [{"CFBundleURLSchemes": ["draftly"]}],
                "LSMinimumSystemVersion": "26.0", "DraftlyUpdatesEnabled": "YES",
                "SUPublicEDKey": self.public, "SUFeedURL": appcast.release.FEED,
                "SUAutomaticallyUpdate": False, "SUAllowsAutomaticUpdates": False, "SUEnableAutomaticChecks": True,
                "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True}
        package = directory / "Draftly.zip"
        with zipfile.ZipFile(package, "w") as archive:
            archive.writestr("Draftly.app/Contents/Info.plist", plistlib.dumps(info))
        metadata = {"version": version, "build": build, "tag": "v" + version,
                    "sourceCommit": "a" * 40, "updatesEnabled": True,
                    "sha256": hashlib.sha256(package.read_bytes()).hexdigest()}
        (directory / "candidate.json").write_text(json.dumps(metadata))
        (directory / "READY").write_text("fixture")
        return directory

    def prepare(self, candidate, output, *, releases=None, old_feed=None, notes="Neutral <note> 🐼"):
        appcast.prepare(candidate, output, notes, self.secret, releases=releases or [], appcast=old_feed,
                        now=datetime.datetime(2026, 10, 29, tzinfo=datetime.timezone.utc))

    def test_signed_first_feed_contains_a_verifiable_package_and_safe_notes(self):
        candidate = self.candidate()
        output = self.root / "stage"
        self.prepare(candidate, output)
        self.assertTrue((output / "READY").exists())
        feed = (output / "appcast.xml").read_bytes()
        appcast.sparkle_feed(appcast.TOOL, output / "appcast.xml", self.secret, verify=True)
        item = ET.fromstring(feed).find("channel/item")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), "https://github.com/pobrespandas/draftly/releases/download/v0.1.0/Draftly.zip")
        package = (candidate / "Draftly.zip").read_bytes()
        self.assertEqual(int(enclosure.get("length")), len(package))
        signature = base64.b64decode(enclosure.get("{" + appcast.SPARKLE_NS + "}edSignature"))
        self.key.public_key().verify(signature, package)
        verified = subprocess.run([str(appcast.TOOL), "--verify", "--ed-key-file", "-",
                                   str(candidate / "Draftly.zip"), base64.b64encode(signature).decode()],
                                  input=self.secret + "\n", text=True, capture_output=True)
        self.assertEqual(verified.returncode, 0, "Sparkle rejected the archive signature.")
        self.assertIn("&lt;note&gt;", item.findtext("description"))

    def test_later_feed_verifies_and_keeps_prior_items(self):
        first = self.candidate()
        first_output = self.root / "first"
        self.prepare(first, first_output)
        second = self.candidate("0.2.0", "2")
        second_output = self.root / "second"
        old_feed = (first_output / "appcast.xml").read_bytes()
        releases = [{"tag_name": "v0.1.0", "draft": False, "prerelease": False}]
        self.prepare(second, second_output, releases=releases, old_feed=old_feed)
        values = appcast.history.feed_versions((second_output / "appcast.xml").read_bytes())
        self.assertEqual(values, {(0, 1, 0): 1, (0, 2, 0): 2})
        appcast.sparkle_feed(appcast.TOOL, second_output / "appcast.xml", self.secret, verify=True)

    def test_rejects_a_tampered_prior_feed_without_marking_ready(self):
        first_output = self.root / "first"
        self.prepare(self.candidate(), first_output)
        old_feed = (first_output / "appcast.xml").read_bytes().replace(b"Draftly 0.1.0", b"Changed 0.1.0")
        output = self.root / "second"
        releases = [{"tag_name": "v0.1.0", "draft": False, "prerelease": False}]
        with self.assertRaisesRegex(ValueError, "verify the appcast"):
            self.prepare(self.candidate("0.2.0", "2"), output, releases=releases, old_feed=old_feed)
        self.assertFalse((output / "READY").exists())

    def test_rejects_wrong_key_or_changed_candidate(self):
        candidate = self.candidate()
        with self.assertRaisesRegex(ValueError, "update configuration"):
            appcast.prepare(candidate, self.root / "wrong", "notes", base64.b64encode(bytes(32)).decode(), releases=[])
        with (candidate / "Draftly.zip").open("ab") as package:
            package.write(b"changed")
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.prepare(candidate, self.root / "changed")
        self.assertFalse((self.root / "changed").exists())

    def test_refuses_existing_output_and_invalid_notes(self):
        candidate = self.candidate()
        output = self.root / "existing"
        output.mkdir()
        (output / "keep").write_text("unchanged")
        with self.assertRaises(FileExistsError):
            self.prepare(candidate, output)
        self.assertEqual((output / "keep").read_text(), "unchanged")
        with self.assertRaisesRegex(ValueError, "Release notes"):
            self.prepare(candidate, self.root / "empty", notes="  ")

    def test_sparkle_failure_does_not_expose_its_output_or_private_key(self):
        fake = subprocess.CompletedProcess([], 1, stdout=self.secret, stderr=self.secret)
        with patch.dict(appcast.os.environ, {"DRAFTLY_SPARKLE_PRIVATE_KEY": self.secret, "GH_TOKEN": "token"}), \
                patch.object(appcast.subprocess, "run", return_value=fake) as run:
            with self.assertRaises(ValueError) as failure:
                appcast.sparkle_feed(appcast.TOOL, self.root / "feed.xml", self.secret)
        self.assertNotIn("DRAFTLY_SPARKLE_PRIVATE_KEY", run.call_args.kwargs["env"])
        self.assertNotIn("GH_TOKEN", run.call_args.kwargs["env"])
        self.assertNotIn(self.secret, str(failure.exception))


if __name__ == "__main__":
    unittest.main()
