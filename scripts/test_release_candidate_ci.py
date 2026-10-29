"""Test ephemeral CI signing setup without touching the user's Keychain."""
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS base64 and bash")
class ReleaseCandidateCITests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="draftly-ci-signing-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.tools = self.root / "tools"
        self.tools.mkdir()
        (self.root / "scripts").mkdir()
        self.runner = self.root / "runner"
        self.runner.mkdir()
        self.profiles = self.root / "profiles"
        self.profiles.mkdir()
        self.log = self.root / "calls.jsonl"
        self.uuid = "12345678-1234-1234-1234-123456789abc"
        self.profile_plist = self.root / "fixture.plist"
        self.profile_plist.write_bytes(plistlib.dumps({"UUID": self.uuid}))
        security = (f"#!{sys.executable}\n"
                    "import json, os, pathlib, sys\n"
                    "with open(os.environ['TEST_CALL_LOG'], 'a') as out: out.write(json.dumps(['security', sys.argv[1]]) + '\\n')\n"
                    "if sys.argv[1] == 'cms': sys.stdout.buffer.write(pathlib.Path(os.environ['TEST_PROFILE_PLIST']).read_bytes())\n")
        xcrun = (f"#!{sys.executable}\n"
                 "import json, os, sys\n"
                 "with open(os.environ['TEST_CALL_LOG'], 'a') as out: out.write(json.dumps(['xcrun', *sys.argv[1:3]]) + '\\n')\n"
                 "if sys.argv[1:] == ['--sdk', 'macosx', '--show-sdk-version']: print(os.environ.get('TEST_CI_SDK_VERSION', '27.0'))\n")
        swiftc = (f"#!{sys.executable}\n"
                  "import os\n"
                  "print('Apple Swift version ' + os.environ.get('TEST_CI_SWIFT_VERSION', '6.4'))\n")
        for name, body in (("security", security), ("xcrun", xcrun), ("swiftc", swiftc)):
            path = self.tools / name
            path.write_text(body)
            path.chmod(0o755)
        package = ("import json, os, sys\n"
                   "names = ['APPLE_DEVELOPER_ID_P12_B64', 'APPLE_DEVELOPER_ID_P12_PASSWORD', "
                   "'APPLE_DEVELOPER_ID_PROFILE_B64', 'APPLE_NOTARY_API_KEY_B64', 'APPLE_NOTARY_KEY_ID', "
                   "'APPLE_NOTARY_ISSUER_ID', 'DRAFTLY_SPARKLE_PRIVATE_KEY', 'DRAFTLY_FIREBASE_ACCESS_TOKEN', 'GH_TOKEN']\n"
                   "with open(os.environ['TEST_CALL_LOG'], 'a') as out: out.write(json.dumps(['package', "
                   "any(name in os.environ for name in names), *sys.argv[1:]]) + '\\n')\n"
                   "sys.exit(1 if os.environ.get('TEST_PACKAGE_FAIL') else 0)\n")
        (self.root / "scripts/package-release.py").write_text(package)
        fake = base64.b64encode(b"neutral fixture").decode()
        self.env = {key: value for key, value in os.environ.items() if key not in (
            "GH_TOKEN", "GITHUB_TOKEN", "DRAFTLY_SPARKLE_PRIVATE_KEY", "DRAFTLY_FIREBASE_ACCESS_TOKEN")}
        self.env.update({"PATH": str(self.tools) + ":/usr/bin:/bin:/usr/sbin:/sbin", "GITHUB_ACTIONS": "true",
            "RUNNER_ENVIRONMENT": "github-hosted", "RUNNER_TEMP": str(self.runner), "RELEASE_TAG": "v1.2.3",
            "DRAFTLY_DEVELOPER_ID_PROFILE": "Fixture profile",
            "DRAFTLY_SPARKLE_PUBLIC_KEY": base64.b64encode(bytes(range(32))).decode(),
            "APPLE_DEVELOPER_ID_P12_B64": fake, "APPLE_DEVELOPER_ID_P12_PASSWORD": "fixture-password",
            "APPLE_DEVELOPER_ID_PROFILE_B64": fake, "APPLE_NOTARY_API_KEY_B64": fake,
            "APPLE_NOTARY_KEY_ID": "fixture-key", "APPLE_NOTARY_ISSUER_ID": "fixture-issuer",
            "DRAFTLY_SPARKLE_PRIVATE_KEY": "fixture-private", "DRAFTLY_FIREBASE_ACCESS_TOKEN": "fixture-token",
            "GH_TOKEN": "fixture-gh", "DRAFTLY_CI_PROFILE_DIRECTORY": str(self.profiles),
            "TEST_CALL_LOG": str(self.log), "TEST_PROFILE_PLIST": str(self.profile_plist)})
        self.script = Path(__file__).with_name("release-candidate-ci.sh").resolve()

    def run_script(self, **overrides):
        return subprocess.run(["/bin/bash", str(self.script)], cwd=self.root,
                              env={**self.env, **overrides}, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_hosted_setup_cleans_up_and_removes_secrets_before_build(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        package = next(call for call in calls if call[0] == "package")
        self.assertFalse(package[1], "The package process inherited service credentials.")
        self.assertIn("v1.2.3", package)
        self.assertIn("Fixture profile", package)
        self.assertIn(["xcrun", "notarytool", "store-credentials"], calls)
        self.assertIn(["security", "delete-keychain"], calls)
        self.assertFalse((self.profiles / (self.uuid + ".provisionprofile")).exists())
        self.assertEqual(list(self.runner.iterdir()), [])
        for secret in ("fixture-password", "fixture-private", "fixture-token", "fixture-gh"):
            self.assertNotIn(secret, result.stdout + result.stderr)

    def test_refuses_non_hosted_runner_before_touching_keychain(self):
        result = self.run_script(RUNNER_ENVIRONMENT="self-hosted")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_invalid_public_key_is_rejected_before_keychain_setup(self):
        result = self.run_script(DRAFTLY_SPARKLE_PUBLIC_KEY="invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("public key", result.stderr)
        self.assertFalse(any(call[0] == 'security' for call in self.calls()))

    def test_old_sdk_is_rejected_before_keychain_setup(self):
        result = self.run_script(TEST_CI_SDK_VERSION="26.6")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("macOS 27 SDK", result.stderr)
        self.assertFalse(any(call[0] == "security" for call in self.calls()))

    def test_old_compiler_is_rejected_before_keychain_setup(self):
        result = self.run_script(TEST_CI_SWIFT_VERSION="6.3")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Swift 6.4", result.stderr)
        self.assertFalse(any(call[0] == "security" for call in self.calls()))

    def test_existing_profile_is_preserved(self):
        existing = self.profiles / (self.uuid + ".provisionprofile")
        existing.write_bytes(b"keep")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(existing.read_bytes(), b"keep")
        self.assertFalse(any(call[0] == "package" for call in self.calls()))
        self.assertIn(["security", "delete-keychain"], self.calls())

    def test_failed_build_still_removes_only_temporary_signing_material(self):
        result = self.run_script(TEST_PACKAGE_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.profiles / (self.uuid + ".provisionprofile")).exists())
        self.assertEqual(list(self.runner.iterdir()), [])
        self.assertIn(["security", "delete-keychain"], self.calls())


if __name__ == "__main__":
    unittest.main()
