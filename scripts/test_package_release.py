"""Exercise the release candidate gates without signing or network access."""
import base64
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("package_release", Path(__file__).with_name("package-release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
SUBMISSION = "12345678-1234-1234-1234-123456789abc"
KEY = base64.b64encode(bytes(range(32))).decode()
COMMIT = "a" * 40
TAG = "v0.1.0"


class FakeRunner:
    def __init__(self, *, notary_status="Accepted", signing_fails=False, fail_command=None, dirty=False,
                 tag_commit=COMMIT, dirty_after_build=False):
        self.commands = []
        self.notary_status = notary_status
        self.signing_fails = signing_fails
        self.fail_command = fail_command
        self.dirty = dirty
        self.tag_commit = tag_commit
        self.dirty_after_build = dirty_after_build
        self.built = False

    def __call__(self, command, **kwargs):
        self.commands.append(command)
        if self.fail_command and command[:len(self.fail_command)] == self.fail_command:
            raise subprocess.CalledProcessError(1, command)
        output = ""
        if command[:2] == ["git", "status"]:
            output = " M example\n" if self.dirty or (self.built and self.dirty_after_build) else ""
        elif command[:2] == ["git", "rev-parse"]:
            output = (self.tag_commit if command[-1].startswith("refs/tags/") else COMMIT) + "\n"
        elif command == ["xcrun", "--sdk", "macosx", "--show-sdk-version"]:
            output = "27.0\n"
        elif command == ["swiftc", "--version"]:
            output = "Apple Swift version 6.4\n"
        elif command[0] == "xcodebuild":
            self.built = True
            archive = Path(command[command.index("-archivePath") + 1])
            contents = archive / "Products/Applications/Draftly.app/Contents"
            contents.mkdir(parents=True)
            info = {"CFBundleIdentifier": release.BUNDLE, "CFBundleName": "Draftly",
                    "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                    "CFBundleURLTypes": [{"CFBundleURLSchemes": ["draftly"]}],
                    "DraftlyUpdatesEnabled": "YES" if "DRAFTLY_UPDATES_ENABLED=YES" in command else "NO",
                    "SUPublicEDKey": KEY, "SUFeedURL": release.FEED, "SUAutomaticallyUpdate": False, "SUAllowsAutomaticUpdates": False,
                    "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
                    "SUEnableAutomaticChecks": True}
            (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        elif command[0] == "ditto":
            Path(command[-1]).write_bytes(b"neutral candidate")
        elif "verify-cloud-signing.py" in command[1]:
            if self.signing_fails:
                raise subprocess.CalledProcessError(1, command)
            output = json.dumps({"teamIdentifier": release.TEAM, "notarizationVerified": False})
        elif command[:3] == ["xcrun", "notarytool", "submit"]:
            output = json.dumps({"id": SUBMISSION})
        elif command[:3] == ["xcrun", "notarytool", "wait"]:
            output = json.dumps({"id": SUBMISSION, "status": self.notary_status})
        return subprocess.CompletedProcess(command, 0, stdout=output, stderr="")


class PackageReleaseTests(unittest.TestCase):
    def test_toolchain_checks_do_not_inherit_release_secrets(self):
        seen = []
        def runner(command, **options):
            seen.append(options["env"])
            value = "27.0" if command[0] == "xcrun" else "Apple Swift version 6.4"
            return subprocess.CompletedProcess(command, 0, stdout=value)
        with patch.dict(os.environ, {"APPLE_DEVELOPER_ID_P12_PASSWORD": "fixture",
                                     "DRAFTLY_SPARKLE_PRIVATE_KEY": "fixture", "GH_TOKEN": "fixture"}):
            release.toolchain.check(runner)
        self.assertEqual(len(seen), 2)
        for environment in seen:
            self.assertNotIn("APPLE_DEVELOPER_ID_P12_PASSWORD", environment)
            self.assertNotIn("DRAFTLY_SPARKLE_PRIVATE_KEY", environment)
            self.assertNotIn("GH_TOKEN", environment)
    def test_toolchain_gate_rejects_older_or_unknown_toolchains(self):
        for sdk, swift in (("26.6", "Apple Swift version 6.4"), ("27.0", "Apple Swift version 6.3"),
                           ("invalid", "Apple Swift version 6.4"), ("27.0", "unknown")):
            with self.subTest(sdk=sdk, swift=swift), self.assertRaises(ValueError):
                release.toolchain.validate(sdk, swift)
        release.toolchain.validate("27.1", "Apple Swift version 6.4 (swiftlang-6.4)")
    def test_candidate_gates_archive_signing_notary_stapling_and_gatekeeper(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate"
            runner = FakeRunner()
            release.package(output, "QA profile", "QA notary", TAG, public_key=KEY, runner=runner)
            self.assertTrue((output / "READY").exists())
            metadata = json.loads((output / "candidate.json").read_text())
            self.assertEqual((metadata["version"], metadata["build"], metadata["updatesEnabled"]), ("0.1.0", "1", True))
            self.assertEqual(metadata["notarySubmission"], SUBMISSION)
            self.assertEqual((metadata["tag"], metadata["sourceCommit"]), (TAG, COMMIT))
            self.assertEqual(metadata["sha256"], hashlib.sha256((output / "Draftly.zip").read_bytes()).hexdigest())
            commands = runner.commands
            build = next(command for command in commands if command[0] == "xcodebuild")
            for setting in ("DRAFTLY_CLOUDKIT_ENVIRONMENT=Production", "DRAFTLY_APS_ENVIRONMENT=production",
                            "DRAFTLY_CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=" + release.TEAM,
                            "DRAFTLY_UPDATES_ENABLED=YES"):
                self.assertIn(setting, build)
            self.assertNotIn("-allowProvisioningUpdates", build)
            verify = next(command for command in commands if "verify-cloud-signing.py" in command[1])
            self.assertIn("--require-developer-id", verify)
            self.assertLess(next(i for i, command in enumerate(commands) if command[:3] == ["xcrun", "notarytool", "wait"]),
                            next(i for i, command in enumerate(commands) if command[:3] == ["xcrun", "stapler", "staple"]))
            self.assertLess(next(i for i, command in enumerate(commands) if command[0] == "spctl"),
                            max(i for i, command in enumerate(commands) if command[0] == "ditto"))

    def test_notary_failure_preserves_receipt_but_never_marks_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate"
            runner = FakeRunner(notary_status="Invalid")
            with self.assertRaisesRegex(ValueError, "did not accept"):
                release.package(output, "QA profile", "QA notary", TAG, runner=runner)
            self.assertEqual(json.loads((output / "notary-submission.json").read_text())["id"], SUBMISSION)
            self.assertTrue((output / "notary-submission.zip").exists())
            self.assertFalse((output / "READY").exists())
            self.assertFalse(any(command[:3] == ["xcrun", "stapler", "staple"] for command in runner.commands))

    def test_interrupted_notary_wait_keeps_submission_for_manual_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate"
            runner = FakeRunner(fail_command=["xcrun", "notarytool", "wait"])
            with self.assertRaises(subprocess.CalledProcessError):
                release.package(output, "QA profile", "QA notary", TAG, runner=runner)
            self.assertEqual(json.loads((output / "notary-submission.json").read_text())["id"], SUBMISSION)
            self.assertTrue((output / "notary-submission.zip").exists())
            self.assertFalse((output / "READY").exists())

    def test_signing_failure_cannot_submit_or_mark_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate"
            runner = FakeRunner(signing_fails=True)
            with self.assertRaises(subprocess.CalledProcessError):
                release.package(output, "QA profile", "QA notary", TAG, runner=runner)
            self.assertFalse((output / "READY").exists())
            self.assertFalse(any(command[:3] == ["xcrun", "notarytool", "submit"] for command in runner.commands))

    def test_stapling_or_gatekeeper_failure_never_creates_a_ready_package(self):
        for command in (["xcrun", "stapler", "validate"], ["spctl"]):
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "candidate"
                runner = FakeRunner(fail_command=command)
                with self.assertRaises(subprocess.CalledProcessError):
                    release.package(output, "QA profile", "QA notary", TAG, runner=runner)
                self.assertTrue((output / "notary-submission.json").exists())
                self.assertFalse((output / "Draftly.zip").exists())
                self.assertFalse((output / "READY").exists())

    def test_candidate_can_be_built_without_enabling_updates(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate"
            runner = FakeRunner()
            release.package(output, "QA profile", "QA notary", TAG, runner=runner)
            self.assertFalse(json.loads((output / "candidate.json").read_text())["updatesEnabled"])
            self.assertIn("DRAFTLY_UPDATES_ENABLED=NO", next(command for command in runner.commands if command[0] == "xcodebuild"))

    def test_never_overwrites_an_existing_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate"
            output.mkdir()
            sentinel = output / "keep"
            sentinel.write_text("unchanged")
            runner = FakeRunner()
            with self.assertRaises(FileExistsError):
                release.package(output, "QA profile", "QA notary", TAG, runner=runner)
            self.assertEqual(sentinel.read_text(), "unchanged")
            self.assertEqual(runner.commands, [])

    def test_invalid_key_or_notary_profile_fails_before_output_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate"
            with self.assertRaises(ValueError):
                release.package(output, "QA profile", "QA notary", TAG, public_key="invalid", runner=FakeRunner())
            with self.assertRaises(ValueError):
                release.package(output, "QA profile", "-bad", TAG, runner=FakeRunner())
            self.assertFalse(output.exists())

    def test_candidate_requires_clean_source_and_matching_tag(self):
        for runner, tag in ((FakeRunner(dirty=True), TAG), (FakeRunner(tag_commit="b" * 40), TAG),
                            (FakeRunner(), "v0.1.1")):
            with self.subTest(tag=tag, dirty=runner.dirty), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "candidate"
                with self.assertRaises(ValueError):
                    release.package(output, "QA profile", "QA notary", tag, runner=runner)
                self.assertFalse(output.exists())
                self.assertFalse(any(command[0] == "xcodebuild" for command in runner.commands))

    def test_changed_source_after_build_cannot_be_submitted(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate"
            runner = FakeRunner(dirty_after_build=True)
            with self.assertRaisesRegex(ValueError, "source tree must be clean"):
                release.package(output, "QA profile", "QA notary", TAG, runner=runner)
            self.assertFalse(any(command[:3] == ["xcrun", "notarytool", "submit"] for command in runner.commands))
            self.assertFalse((output / "READY").exists())

    def test_metadata_rejects_wrong_version_identity_scheme_and_update_settings(self):
        source = {"CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"}
        valid = {"CFBundleIdentifier": release.BUNDLE, "CFBundleName": "Draftly",
                 "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                 "CFBundleURLTypes": [{"CFBundleURLSchemes": ["draftly"]}],
                 "DraftlyUpdatesEnabled": "YES", "SUPublicEDKey": KEY,
                 "SUFeedURL": release.FEED, "SUAutomaticallyUpdate": False, "SUAllowsAutomaticUpdates": False,
                 "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
                 "SUEnableAutomaticChecks": True}
        self.assertEqual(release.validate_metadata(source, valid, public_key=KEY), ("0.1.0", "1"))
        for field, value in (("CFBundleVersion", "2"), ("CFBundleIdentifier", "other"),
                             ("CFBundleURLTypes", [{"CFBundleURLSchemes": "draftly"}]),
                             ("SUAutomaticallyUpdate", True), ("SUAllowsAutomaticUpdates", True), ("SUPublicEDKey", "other"),
                             ("SURequireSignedFeed", False), ("SUVerifyUpdateBeforeExtraction", False),
                             ("SUEnableAutomaticChecks", False)):
            with self.subTest(field=field):
                invalid = dict(valid, **{field: value})
                with self.assertRaises(ValueError):
                    release.validate_metadata(source, invalid, public_key=KEY)


if __name__ == "__main__":
    unittest.main()
