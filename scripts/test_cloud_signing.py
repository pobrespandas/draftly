import copy
import contextlib
import datetime
import importlib.util
import io
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("cloud_signing", Path(__file__).with_name("verify-cloud-signing.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "Draftly.app"
        (self.app / "Contents").mkdir(parents=True)
        self.info = {"CFBundleIdentifier": "com.example.draftly", "CFBundleShortVersionString": "1", "CFBundleVersion": "1",
                     "DraftlyCloudKitContainer": "iCloud.com.example.draftly"}
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))
        self.rights = {"com.apple.developer.team-identifier": "TEAM", "com.apple.application-identifier": "TEAM.com.example.draftly",
                       "com.apple.developer.icloud-container-identifiers": ["iCloud.com.example.draftly"],
                       "com.apple.developer.icloud-container-environment": "Development",
                       "com.apple.developer.icloud-services": ["CloudKit"], "com.apple.developer.aps-environment": "development"}
        allowed = copy.deepcopy(self.rights)
        allowed["com.apple.developer.icloud-container-environment"] = ["Development", "Production"]
        self.profile = {"Entitlements": allowed, "TeamIdentifier": ["TEAM"], "TeamName": "Test Team",
                        "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=30), "ProvisionedDevices": ["private-device"]}
        self.addCleanup(patch.stopall)
        patch.object(module.subprocess, "run").start()
        patch.object(module, "read_plist", side_effect=lambda args: self.rights if args[0] == "codesign" else self.profile).start()

    def test_valid_profile_reports_no_device_identifiers_or_notarization_claim(self):
        result = module.verify(self.app)
        self.assertEqual(result["registeredDeviceCount"], 1)
        self.assertFalse(result["notarizationVerified"])
        self.assertNotIn("private-device", str(result))

    def test_matching_expected_identity_is_accepted(self):
        result = module.verify(self.app, expected_bundle_identifier="com.example.draftly",
                               expected_team="TEAM", expected_container="iCloud.com.example.draftly")
        self.assertEqual(result["bundleIdentifier"], "com.example.draftly")

    def test_self_consistent_identity_must_match_each_expectation(self):
        cases = [("expected_bundle_identifier", "com.example.other", "expected bundle identifier"),
                 ("expected_team", "OTHER", "expected team"),
                 ("expected_container", "iCloud.com.example.other", "expected container")]
        for name, value, message in cases:
            with self.subTest(expectation=name), self.assertRaisesRegex(ValueError, message):
                module.verify(self.app, **{name: value})

    def test_command_line_passes_optional_expectations(self):
        with patch.object(module, "verify", return_value={}) as verify, contextlib.redirect_stdout(io.StringIO()):
            module.main([str(self.app), "--expected-bundle-identifier", "com.example.draftly",
                         "--expected-team", "TEAM", "--expected-container", "iCloud.com.example.draftly"])
        verify.assert_called_once_with(str(self.app), expected_bundle_identifier="com.example.draftly",
                                       expected_team="TEAM", expected_container="iCloud.com.example.draftly",
                                       expected_cloud_environment=None, expected_push_environment=None,
                                       require_developer_id=False)

    def test_command_line_preserves_generic_mode(self):
        with patch.object(module, "verify", return_value={}) as verify, contextlib.redirect_stdout(io.StringIO()):
            module.main([str(self.app)])
        verify.assert_called_once_with(str(self.app), expected_bundle_identifier=None,
                                       expected_team=None, expected_container=None,
                                       expected_cloud_environment=None, expected_push_environment=None,
                                       require_developer_id=False)

    def test_expected_production_environments_reject_development_even_if_profile_allows_it(self):
        with self.assertRaisesRegex(ValueError, "CloudKit environment.*expected"):
            module.verify(self.app, expected_cloud_environment="Production")
        with self.assertRaisesRegex(ValueError, "push environment.*expected"):
            module.verify(self.app, expected_push_environment="production")
        self.rights["com.apple.developer.icloud-container-environment"] = "Production"
        self.rights["com.apple.developer.aps-environment"] = "production"
        self.profile["Entitlements"]["com.apple.developer.aps-environment"] = "production"
        result = module.verify(self.app, expected_cloud_environment="Production", expected_push_environment="production")
        self.assertEqual(result["cloudEnvironment"], "Production")
        self.assertEqual(result["pushEnvironment"], "production")

    def test_command_line_passes_expected_environments(self):
        with patch.object(module, "verify", return_value={}) as verify, contextlib.redirect_stdout(io.StringIO()):
            module.main([str(self.app), "--expected-cloud-environment", "Production",
                         "--expected-push-environment", "production"])
        self.assertEqual(verify.call_args.kwargs["expected_cloud_environment"], "Production")
        self.assertEqual(verify.call_args.kwargs["expected_push_environment"], "production")

    def test_developer_id_requires_the_correct_team_and_hardened_runtime(self):
        signature = "Authority=Developer ID Application: Example (TEAM)\nCodeDirectory flags=0x10000(runtime)\n"
        module.verify_developer_id(signature, "TEAM")
        for invalid in (signature.replace("TEAM", "OTHER"), signature.replace("Developer ID Application", "Apple Development"),
                        signature.replace("(runtime)", "(adhoc)")):
            with self.subTest(signature=invalid), self.assertRaises(ValueError):
                module.verify_developer_id(invalid, "TEAM")

    def test_developer_id_rejects_debug_entitlement_before_checking_metadata(self):
        self.rights["com.apple.security.get-task-allow"] = True
        with self.assertRaisesRegex(ValueError, "get-task-allow"):
            module.verify(self.app, require_developer_id=True)

    def test_developer_id_mode_checks_signature_metadata(self):
        metadata = subprocess.CompletedProcess([], 0, stdout="", stderr=(
            "Authority=Developer ID Application: Example (TEAM)\nCodeDirectory flags=0x10000(runtime)\n"))
        with patch.object(module.subprocess, "run", side_effect=[None, metadata]) as run:
            module.verify(self.app, require_developer_id=True)
        self.assertEqual(run.call_count, 2)
        self.assertIn("--verbose=4", run.call_args.args[0])

    def test_command_line_passes_developer_id_requirement(self):
        with patch.object(module, "verify", return_value={}) as verify, contextlib.redirect_stdout(io.StringIO()):
            module.main([str(self.app), "--require-developer-id"])
        self.assertTrue(verify.call_args.kwargs["require_developer_id"])

    def test_missing_or_wrong_container_is_rejected(self):
        self.rights["com.apple.developer.icloud-container-identifiers"] = []
        with self.assertRaisesRegex(ValueError, "signature.*container"):
            module.verify(self.app)

    def test_expired_profile_is_rejected(self):
        self.profile["ExpirationDate"] = datetime.datetime(2000, 1, 1)
        with self.assertRaisesRegex(ValueError, "expired"):
            module.verify(self.app)

    def test_wrong_team_or_application_is_rejected(self):
        self.rights["com.apple.developer.team-identifier"] = "OTHER"
        with self.assertRaisesRegex(ValueError, "team"):
            module.verify(self.app)
        self.rights["com.apple.developer.team-identifier"] = "TEAM"
        self.rights["com.apple.application-identifier"] = "TEAM.other"
        with self.assertRaisesRegex(ValueError, "identity"):
            module.verify(self.app)

    def test_missing_environment_or_push_permission_is_rejected(self):
        self.rights["com.apple.developer.icloud-container-environment"] = None
        with self.assertRaisesRegex(ValueError, "CloudKit environment"):
            module.verify(self.app)
        self.rights["com.apple.developer.icloud-container-environment"] = "Development"
        self.rights["com.apple.developer.aps-environment"] = "production"
        with self.assertRaisesRegex(ValueError, "push environment"):
            module.verify(self.app)


if __name__ == "__main__":
    unittest.main()
