import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
from subprocess import CompletedProcess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("refresh_engine_qa", Path(__file__).with_name("refresh-engine-qa.py"))
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)


class RefreshEngineQATests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source, self.target = [Path(self.temp.name) / name for name in ["Build.app", "QA.app"]]
        for app in [self.source, self.target]:
            (app / "Contents/MacOS").mkdir(parents=True)
        self.info = {"CFBundleIdentifier": "com.andrestobelem.draftly.engine-qa", "CFBundleExecutable": "Draftly", "DraftlyUITesting": True,
                     "DraftlyUITestingLibraryID": "1CBCA092-DAB6-4BFC-9FEC-E4216CDE78AD", "DraftlyCallbackScheme": "draftly-engine-qa",
                     "CFBundleURLTypes": [{"CFBundleURLSchemes": ["draftly-engine-qa"]}]}
        self.write_info()
        for name in ["Draftly", "Draftly.debug.dylib", "__preview.dylib"]:
            (self.source / "Contents/MacOS" / name).write_text("fresh " + name)
        (self.target / "Contents/MacOS/stale.dylib").write_text("old")

    def write_info(self):
        (self.target / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))

    def runner(self, args, **kwargs):
        return CompletedProcess(args, 0, stdout="1 /sbin/launchd\n")

    def test_refreshes_all_code_and_resources_but_keeps_identity(self):
        resource = self.source / "Contents/Resources/Core.bundle/data"
        resource.parent.mkdir(parents=True)
        resource.write_text("fresh resource")
        hashes = qa.refresh(self.source, self.target, "Test identity", run=self.runner)
        self.assertEqual(len(hashes), 4)
        self.assertFalse((self.target / "Contents/MacOS/stale.dylib").exists())
        self.assertEqual((self.target / "Contents/MacOS/Draftly.debug.dylib").read_text(), "fresh Draftly.debug.dylib")
        self.assertEqual(plistlib.loads((self.target / "Contents/Info.plist").read_bytes()), self.info)

    def test_rejects_habitual_identity_and_normal_scheme_before_writing(self):
        for key, value in [("CFBundleIdentifier", "com.andrestobelem.draftly"), ("CFBundleURLTypes", [{"CFBundleURLSchemes": ["draftly"]}])]:
            original = dict(self.info)
            self.info[key] = value
            self.write_info()
            with self.assertRaises(ValueError):
                qa.refresh(self.source, self.target, "Test", run=self.runner)
            self.assertTrue((self.target / "Contents/MacOS/stale.dylib").exists())
            self.info = original

    @unittest.skipUnless(shutil.which("ps") and Path("/bin/sleep").exists(), "Requires ps and sleep")
    def test_actual_process_match_handles_spaces_in_the_bundle_path(self):
        target = self.target.with_name("Engine QA.app")
        self.target.rename(target)
        self.target = target
        executable = target / "Contents/MacOS/Draftly"
        shutil.copyfile("/bin/sleep", executable)
        executable.chmod(0o755)
        process = subprocess.Popen([str(executable), "30"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            with self.assertRaisesRegex(ValueError, "Quit QA"):
                qa.refresh(self.source, self.target, "Test")
            self.assertTrue((self.target / "Contents/MacOS/stale.dylib").exists())
        finally:
            process.terminate()
            process.wait(timeout=5)

    def test_live_or_unverifiable_process_prevents_refresh(self):
        outputs = [(0, "1 " + str(self.target / "Contents/MacOS/Draftly") + "\n"), (0, ""), (1, ""), (2, "")]
        for status, output in outputs:
            with self.assertRaises(ValueError):
                qa.refresh(self.source, self.target, "Test", run=lambda args, **kwargs: CompletedProcess(args, status, stdout=output))
            self.assertTrue((self.target / "Contents/MacOS/stale.dylib").exists())


if __name__ == "__main__":
    unittest.main()
