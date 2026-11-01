import copy
import datetime
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("agent_packaging", Path(__file__).with_name("package-agent-helper.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AgentHelperPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.executable = self.root / "executable"
        self.executable.write_bytes(b"neutral executable fixture")
        self.profile_file = self.root / "profile"
        self.profile_file.write_bytes(b"neutral profile fixture")
        self.output = self.root / "candidate"
        self.rights = {"com.apple.application-identifier": module.TEAM + "." + module.IDENTIFIER,
                       "com.apple.developer.team-identifier": module.TEAM,
                       "keychain-access-groups": [module.GROUP]}
        self.profile = {"TeamIdentifier": [module.TEAM], "Entitlements": copy.deepcopy(self.rights),
                        "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=1),
                        "DeveloperCertificates": [b"neutral public certificate"]}
        self.calls = []
        self.certificate = b"neutral public certificate"

    def runner(self, command, capture=False):
        self.calls.append(command)
        if command[0] == "security":
            return plistlib.dumps(self.profile)
        if "--entitlements" in command and "-d" in command:
            return plistlib.dumps(self.rights)
        if "--extract-certificates" in command:
            Path(command[command.index("--extract-certificates") + 1] + "0").write_bytes(self.certificate)
        return b""

    def package(self):
        return module.package(self.executable, self.profile_file, self.output,
                              "Neutral signing identity", "1.0.0", "1", runner=self.runner)

    def test_wrapper_preserves_payload_and_requires_signed_exact_identity(self):
        result = self.package()
        contents = self.output / "DraftlyAgent.app/Contents"
        self.assertEqual((contents / "MacOS/draftly-agent").read_bytes(), self.executable.read_bytes())
        self.assertEqual((contents / "embedded.provisionprofile").read_bytes(), self.profile_file.read_bytes())
        info = plistlib.loads((contents / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], module.IDENTIFIER)
        self.assertEqual(info["CFBundleExecutable"], "draftly-agent")
        self.assertEqual(info["CFBundlePackageType"], "APPL")
        signing = next(c for c in self.calls if "--sign" in c)
        verification = next(c for c in self.calls if "--verify" in c)
        self.assertIn("runtime", signing)
        self.assertIn("-R", verification)
        self.assertIn(module.IDENTIFIER, verification[verification.index("-R") + 1])
        self.assertFalse(result["keychainSharingVerified"])
        self.assertFalse(result["notarizationVerified"])

    def test_wrong_identity_expiry_and_group_fail_before_output_or_signing(self):
        cases = [lambda p: p.update(TeamIdentifier=["OTHER"]),
                 lambda p: p.update(ExpirationDate=datetime.datetime(2000, 1, 1)),
                 lambda p: p["Entitlements"].update({"com.apple.application-identifier": module.TEAM + ".com.pobrespandas.draftly"}),
                 lambda p: p["Entitlements"].update({"keychain-access-groups": ["OTHER.*"]}),
                 lambda p: p.update(DeveloperCertificates=[])]
        original = copy.deepcopy(self.profile)
        for mutate in cases:
            self.profile = copy.deepcopy(original)
            mutate(self.profile)
            with self.subTest(profile=self.profile), self.assertRaises(ValueError):
                self.package()
            self.assertFalse(self.output.exists())
        self.assertFalse(any(c[0] == "codesign" for c in self.calls))

    def test_team_wildcard_group_is_permitted_but_signature_uses_exact_group(self):
        self.profile["Entitlements"]["keychain-access-groups"] = [module.TEAM + ".*"]
        self.package()
        self.assertEqual(self.rights["keychain-access-groups"], [module.GROUP])

    def test_existing_output_and_symlink_inputs_are_preserved(self):
        self.output.mkdir()
        sentinel = self.output / "retained"
        sentinel.write_text("neutral")
        with self.assertRaises(FileExistsError):
            self.package()
        self.assertEqual(sentinel.read_text(), "neutral")
        alias = self.root / "alias"
        alias.symlink_to(self.executable)
        self.executable = alias
        with self.assertRaises(ValueError):
            self.package()
        self.assertFalse(any(c[0] == "codesign" for c in self.calls))

    def test_unexpected_rights_or_certificate_never_report_success(self):
        self.rights["com.apple.security.get-task-allow"] = True
        with self.assertRaisesRegex(ValueError, "entitlements"):
            self.package()
        self.assertFalse(any("--extract-certificates" in c for c in self.calls))
        self.output = self.root / "other-candidate"
        self.rights.pop("com.apple.security.get-task-allow")
        self.certificate = b"different public certificate"
        with self.assertRaisesRegex(ValueError, "certificate"):
            self.package()

    def test_profile_replacement_during_validation_fails_before_output(self):
        def replaced(command, capture=False):
            result = self.runner(command, capture)
            if command[0] == "security":
                self.profile_file.write_bytes(b"changed profile")
            return result
        with self.assertRaisesRegex(ValueError, "changed"):
            module.package(self.executable, self.profile_file, self.output,
                           "Neutral signing identity", "1", "1", runner=replaced)
        self.assertFalse(self.output.exists())

    def test_malformed_profile_has_explicit_validation_error(self):
        for profile in [[], {}, {"Entitlements": []}, {"Entitlements": {}}]:
            with self.subTest(profile=profile), self.assertRaises(ValueError):
                module.validate_profile(profile)

    def test_signing_failure_preserves_only_isolated_candidate_and_propagates(self):
        import subprocess
        def failed(command, capture=False):
            if "--sign" in command:
                raise subprocess.CalledProcessError(1, command)
            return self.runner(command, capture)
        with self.assertRaises(subprocess.CalledProcessError):
            module.package(self.executable, self.profile_file, self.output,
                           "Neutral signing identity", "1", "1", runner=failed)
        self.assertTrue((self.output / "DraftlyAgent.app/Contents/Info.plist").is_file())
        self.assertFalse(any("--verify" in c for c in self.calls))
