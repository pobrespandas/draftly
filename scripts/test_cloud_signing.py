import copy
import datetime
import importlib.util
from pathlib import Path
import plistlib
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
