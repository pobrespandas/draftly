import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(Path("/bin/zsh").exists(), "Requires zsh")
class BuildAppTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="draftly-build-script-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        scripts = self.root / "scripts"
        scripts.mkdir()
        self.script = scripts / "build-app.sh"
        shutil.copyfile(Path(__file__).with_name("build-app.sh"), self.script)
        tools = self.root / "tools"
        tools.mkdir()
        self.log = self.root / "calls.jsonl"
        stub = (f"#!{sys.executable}\n"
                "import json, os, pathlib, sys\n"
                "with open(os.environ['BUILD_TEST_CALL_LOG'], 'a') as output:\n"
                "    output.write(json.dumps([pathlib.Path(sys.argv[0]).name, *sys.argv[1:]]) + '\\n')\n")
        for name in ["xcodebuild", "codesign", "python3"]:
            tool = tools / name
            tool.write_text(stub)
            tool.chmod(0o755)
        self.environment = {key: value for key, value in os.environ.items()
                            if key not in ["DRAFTLY_BUILD_OUTPUT", "DRAFTLY_PROVISIONING_PROFILE", "ZDOTDIR"]}
        self.environment.update(PATH=f"{tools}:/usr/bin:/bin", BUILD_TEST_CALL_LOG=str(self.log))

    def run_build(self, mode=None, **overrides):
        result = subprocess.run(["/bin/zsh", str(self.script), *([mode] if mode else [])],
                                env={**self.environment, **overrides}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result, calls

    def assert_output(self, calls, output, configuration):
        build = next(call for call in calls if call[0] == "xcodebuild")
        self.assertEqual(build[build.index("-derivedDataPath") + 1], str(output))
        self.assertEqual(build[build.index("-configuration") + 1], configuration)
        app = str((self.root / output / "Build/Products" / configuration / "Draftly.app").resolve())
        self.assertIn(["codesign", "--verify", "--deep", "--strict", app], calls)
        return build, app

    def test_default_local_build_uses_ad_hoc_signature_without_provisioning(self):
        _, calls = self.run_build()
        build, app = self.assert_output(calls, ".build/xcode", "Debug")
        for value in ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGN_ENTITLEMENTS=", "DRAFTLY_CLOUDKIT_CONTAINER="]:
            self.assertIn(value, build)
        self.assertIn(["codesign", "--force", "--sign", "-", app], calls)
        self.assertFalse(any(call[0] == "python3" for call in calls))
        self.assertNotIn("-allowProvisioningUpdates", build)

    def test_local_output_override_is_isolated_and_ignores_manual_profile(self):
        output = self.root / "isolated output"
        result, calls = self.run_build("--local", DRAFTLY_BUILD_OUTPUT=str(output),
                                       DRAFTLY_PROVISIONING_PROFILE="Test Manual Profile")
        build, app = self.assert_output(calls, output, "Debug")
        self.assertFalse(any("Test Manual Profile" in arg for arg in build))
        self.assertIn(f"App: {app}", result.stdout)

    def test_signed_defaults_retain_automatic_provisioning(self):
        for mode, output, configuration in [("--icloud", ".build/icloud", "Debug"),
                                             ("--personal", ".build/personal", "Release")]:
            with self.subTest(mode=mode):
                self.log.unlink(missing_ok=True)
                _, calls = self.run_build(mode)
                build, app = self.assert_output(calls, output, configuration)
                self.assertIn("-allowProvisioningUpdates", build)
                self.assertIn("-allowProvisioningDeviceRegistration", build)
                self.assertIn(["python3", "scripts/verify-cloud-signing.py", app], calls)

    def test_manual_main_profile_uses_target_scoped_build_variables(self):
        output = self.root / "signed output"
        _, calls = self.run_build("--personal", DRAFTLY_BUILD_OUTPUT=str(output),
                                  DRAFTLY_PROVISIONING_PROFILE="Test Manual Profile")
        build, app = self.assert_output(calls, output, "Release")
        self.assertIn("DRAFTLY_CODE_SIGN_STYLE=Manual", build)
        self.assertIn("DRAFTLY_PROVISIONING_PROFILE=Test Manual Profile", build)
        self.assertFalse(any(arg.startswith(("CODE_SIGN_STYLE=", "PROVISIONING_PROFILE_SPECIFIER=")) for arg in build))
        self.assertNotIn("-allowProvisioningUpdates", build)
        self.assertNotIn("-allowProvisioningDeviceRegistration", build)
        self.assertIn(["python3", "scripts/verify-cloud-signing.py", app], calls)

    def test_packager_uses_the_same_output_as_the_signed_build(self):
        self.script.chmod(0o755)
        package = self.root / "scripts/package-personal.sh"
        shutil.copyfile(Path(__file__).with_name("package-personal.sh"), package)
        for name in ["ditto", "shasum"]:
            shutil.copyfile(self.root / "tools/codesign", self.root / "tools" / name)
            (self.root / "tools" / name).chmod(0o755)
        for output in [None, self.root / "isolated signed output"]:
            with self.subTest(output=output):
                self.log.unlink(missing_ok=True)
                environment = dict(self.environment)
                if output is not None:
                    environment["DRAFTLY_BUILD_OUTPUT"] = str(output)
                result = subprocess.run(["/bin/zsh", str(package)], env=environment,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = [json.loads(line) for line in self.log.read_text().splitlines()]
                _, app = self.assert_output(calls, output or ".build/personal", "Release")
                archive = next(call for call in calls if call[0] == "ditto")
                self.assertEqual((self.root / archive[-2]).resolve(), Path(app))
                checks = [call for call in calls if call[:2] == ["python3", "scripts/verify-cloud-signing.py"]]
                self.assertEqual(len(checks), 2)
                self.assertTrue(all((self.root / call[2]).resolve() == Path(app) for call in checks))

    def test_cloud_qa_keeps_its_identity_with_automatic_or_manual_signing(self):
        for manual in [False, True]:
            with self.subTest(manual=manual):
                self.log.unlink(missing_ok=True)
                overrides = {"DRAFTLY_PROVISIONING_PROFILE": "Test QA Profile"} if manual else {}
                _, calls = self.run_build("--cloud-qa", **overrides)
                build, app = self.assert_output(calls, ".build/cloud-qa", "Debug")
                self.assertIn("PRODUCT_BUNDLE_IDENTIFIER=com.andrestobelem.draftly.cloud-qa", build)
                self.assertIn("DRAFTLY_CLOUDKIT_CONTAINER=iCloud.com.andrestobelem.draftly.cloudqa", build)
                self.assertIn(f"INFOPLIST_FILE={self.root}/.build/cloud-qa-config/Info.plist", build)
                self.assertIn(["python3", "scripts/prepare-cloud-qa.py", ".build/cloud-qa-config/Info.plist"], calls)
                self.assertIn(["python3", "scripts/verify-cloud-signing.py", app], calls)
                self.assertEqual("-allowProvisioningUpdates" in build, not manual)


if __name__ == "__main__":
    unittest.main()
