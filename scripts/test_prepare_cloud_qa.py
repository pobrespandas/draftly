import contextlib
import copy
import importlib.util
import os
from pathlib import Path
import plistlib
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import uuid


SCRIPT = Path(__file__).resolve().with_name("prepare-cloud-qa.py")
CONTAINER = "iCloud.com.andrestobelem.draftly.cloudqa"


def load_preparation():
    spec = importlib.util.spec_from_file_location("prepare_cloud_qa", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@contextlib.contextmanager
def working_directory(path):
    previous = Path.cwd()
    try:
        os.chdir(path)
        yield
    finally:
        os.chdir(previous)


class CloudQAPreparationCLITests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.source = self.root / "Configuration/Info.plist"
        self.target = self.root / "output/Info.plist"
        self.backup = self.target.with_name("Info.previous.plist")
        self.source.parent.mkdir()
        self.target.parent.mkdir()
        self.template = {
            "CFBundleName": "Draftly", "CFBundleDisplayName": "Draftly",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "DraftlyCloudKitContainer": "$(DRAFTLY_CLOUDKIT_CONTAINER)",
            "FutureTemplateField": {"values": ["café", "🐼"], "data": b"neutral"},
        }
        self.source.write_bytes(plistlib.dumps(self.template))
        self.generated_id = uuid.UUID("D0AE8200-0000-4000-8000-000000000001")
        self.uuid_factory = Mock(return_value=self.generated_id)

    def run_cli(self, *extra):
        self.uuid_factory.reset_mock()
        with working_directory(self.root), patch.object(sys, "argv", [str(SCRIPT), str(self.target), *extra]), \
                patch("uuid.uuid4", self.uuid_factory):
            runpy.run_path(str(SCRIPT), run_name="__main__")

    def expected(self, library_id):
        return dict(self.template, CFBundleName="Draftly iCloud QA", CFBundleDisplayName="Draftly iCloud QA",
                    DraftlyCloudTesting=True, DraftlyQATestContainer=CONTAINER, DraftlyUITestingLibraryID=library_id)

    def test_new_destination_uses_working_directory_template_and_keeps_its_fields(self):
        self.run_cli()
        self.assertEqual(self.target.read_bytes(), plistlib.dumps(self.expected(str(self.generated_id))))
        self.assertFalse(self.backup.exists())
        self.assertEqual(plistlib.loads(self.source.read_bytes()), self.template)
        self.uuid_factory.assert_called_once_with()

    def test_matching_container_keeps_existing_id_and_does_not_replace_backup(self):
        for library_id in ["existing-neutral-id", "", 0]:
            with self.subTest(library_id=library_id):
                previous = {"DraftlyQATestContainer": CONTAINER, "DraftlyUITestingLibraryID": library_id,
                            "OldOnlyField": "Not a template field"}
                self.target.write_bytes(plistlib.dumps(previous))
                self.backup.write_bytes(b"Keep existing backup")
                self.run_cli()
                self.assertEqual(plistlib.loads(self.target.read_bytes()), self.expected(library_id))
                self.assertEqual(self.backup.read_bytes(), b"Keep existing backup")
                self.uuid_factory.assert_called_once_with()

    def test_matching_container_without_id_uses_generated_id_without_backup(self):
        self.target.write_bytes(plistlib.dumps({"DraftlyQATestContainer": CONTAINER}))
        self.run_cli()
        self.assertEqual(plistlib.loads(self.target.read_bytes()), self.expected(str(self.generated_id)))
        self.assertFalse(self.backup.exists())
        self.uuid_factory.assert_called_once_with()

    def test_changed_container_preserves_parsed_previous_fields_before_replacing_target(self):
        previous = {"DraftlyQATestContainer": "iCloud.example.previous", "DraftlyUITestingLibraryID": "old-id",
                    "UnknownPreviousField": {"data": b"neutral", "label": "café 🐼"}}
        self.target.write_bytes(plistlib.dumps(previous, fmt=plistlib.FMT_BINARY))
        self.backup.write_bytes(b"Older backup")
        self.run_cli()
        self.assertEqual(self.backup.read_bytes(), plistlib.dumps(previous))
        self.assertEqual(plistlib.loads(self.target.read_bytes()), self.expected(str(self.generated_id)))
        self.uuid_factory.assert_called_once_with()

    def test_empty_previous_dictionary_does_not_replace_existing_backup(self):
        self.target.write_bytes(plistlib.dumps({}))
        self.backup.write_bytes(b"Keep existing backup")
        self.run_cli()
        self.assertEqual(plistlib.loads(self.target.read_bytes()), self.expected(str(self.generated_id)))
        self.assertEqual(self.backup.read_bytes(), b"Keep existing backup")

    def test_invalid_input_fails_before_any_write_or_uuid_generation(self):
        for malformed in ["destination", "template"]:
            with self.subTest(malformed=malformed):
                self.source.write_bytes(plistlib.dumps(self.template))
                self.target.write_bytes(plistlib.dumps({"previous": "Keep"}))
                (self.target if malformed == "destination" else self.source).write_bytes(b"not a plist")
                self.backup.write_bytes(b"Keep backup")
                before = self.target.read_bytes()
                with self.assertRaises(plistlib.InvalidFileException):
                    self.run_cli()
                self.assertEqual(self.target.read_bytes(), before)
                self.assertEqual(self.backup.read_bytes(), b"Keep backup")
                self.uuid_factory.assert_not_called()

    def test_write_failures_keep_the_existing_order_and_completed_effects(self):
        previous = {"DraftlyQATestContainer": "iCloud.example.previous", "unknown": "Keep café 🐼"}
        original_write = Path.write_bytes
        for failed_path in [self.backup, self.target]:
            with self.subTest(failed_path=failed_path.name):
                self.target.write_bytes(plistlib.dumps(previous))
                self.backup.write_bytes(b"Old backup")
                writes = []

                def write(path, data):
                    writes.append(path)
                    if path == failed_path:
                        raise OSError("Injected write failure")
                    return original_write(path, data)

                with patch.object(Path, "write_bytes", write), self.assertRaisesRegex(OSError, "Injected write failure"):
                    self.run_cli()
                self.assertEqual(writes, [self.backup] if failed_path == self.backup else [self.backup, self.target])
                self.assertEqual(self.target.read_bytes(), plistlib.dumps(previous))
                self.assertEqual(self.backup.read_bytes(), b"Old backup" if failed_path == self.backup else plistlib.dumps(previous))

    def test_real_command_line_keeps_relative_paths_and_ignores_extra_arguments(self):
        previous = {"DraftlyQATestContainer": CONTAINER, "DraftlyUITestingLibraryID": "existing-neutral-id"}
        self.target.write_bytes(plistlib.dumps(previous))
        result = subprocess.run([sys.executable, str(SCRIPT), "output/Info.plist", "ignored-extra"],
                                cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(plistlib.loads(self.target.read_bytes()), self.expected("existing-neutral-id"))


class CloudQAPreparationBoundaryTests(unittest.TestCase):
    def test_import_does_not_read_arguments_plists_or_generate_an_id(self):
        with patch.object(sys, "argv", [str(SCRIPT)]), \
                patch.object(Path, "read_bytes", side_effect=AssertionError("Import read a plist")), \
                patch.object(Path, "write_bytes", side_effect=AssertionError("Import wrote a plist")), \
                patch("uuid.uuid4", side_effect=AssertionError("Import generated an ID")):
            module = load_preparation()
        self.assertTrue(callable(module.prepare))
        self.assertTrue(callable(module.main))

    def test_metadata_transformation_is_pure_and_retains_container_rules(self):
        module = load_preparation()
        template = {"CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "Unknown": {"values": ["café", "🐼"]}}
        cases = [({}, "new-id", False),
                 ({"DraftlyQATestContainer": CONTAINER}, "new-id", False),
                 ({"DraftlyQATestContainer": CONTAINER, "DraftlyUITestingLibraryID": ""}, "", False),
                 ({"DraftlyQATestContainer": "iCloud.example.old", "unknown": b"neutral"}, "new-id", True)]
        for previous, expected_id, expected_backup in cases:
            with self.subTest(previous=previous):
                before = copy.deepcopy((template, previous))
                with patch.object(Path, "read_bytes", side_effect=AssertionError("Metadata read a file")), \
                        patch.object(Path, "write_bytes", side_effect=AssertionError("Metadata wrote a file")), \
                        patch("uuid.uuid4", side_effect=AssertionError("Metadata generated an ID")):
                    info, backup = module.cloud_qa_metadata(template, previous, "new-id")
                self.assertEqual(info, dict(template, CFBundleName="Draftly iCloud QA", CFBundleDisplayName="Draftly iCloud QA",
                                            DraftlyCloudTesting=True, DraftlyQATestContainer=CONTAINER,
                                            DraftlyUITestingLibraryID=expected_id))
                self.assertEqual(backup, expected_backup)
                self.assertEqual((template, previous), before)

    def test_callable_preparation_uses_explicit_source_and_uuid_factory(self):
        module = load_preparation()
        generated = uuid.UUID("D0AE8200-0000-4000-8000-000000000002")
        factory = Mock(return_value=generated)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root / "Source.plist", root / "Prepared.plist"
            template = {"CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "Unknown": "Neutral café 🐼"}
            source.write_bytes(plistlib.dumps(template))
            self.assertIsNone(module.prepare(target, source_path=source, uuid_factory=factory))
            first = plistlib.loads(target.read_bytes())
            self.assertEqual(first["DraftlyUITestingLibraryID"], str(generated))
            self.assertEqual(first["DraftlyQATestContainer"], CONTAINER)
            self.assertEqual(first["Unknown"], template["Unknown"])
            self.assertEqual(first["CFBundleIdentifier"], template["CFBundleIdentifier"])
            factory.assert_called_once_with()
            factory.reset_mock()
            template["Unknown"] = "Updated source"
            source.write_bytes(plistlib.dumps(template))
            module.prepare(target, source_path=source, uuid_factory=factory)
            second = plistlib.loads(target.read_bytes())
            self.assertEqual(second["Unknown"], "Updated source")
            self.assertEqual(second["DraftlyUITestingLibraryID"], first["DraftlyUITestingLibraryID"])
            self.assertFalse(target.with_name("Info.previous.plist").exists())
            factory.assert_called_once_with()

    def test_main_uses_first_argument_and_keeps_missing_argument_error(self):
        module = load_preparation()
        with patch.object(module, "prepare") as prepare:
            module.main(["output/Info.plist", "ignored-extra"])
            prepare.assert_called_once_with(Path("output/Info.plist"))
            prepare.reset_mock()
            with patch.object(sys, "argv", [str(SCRIPT), "another/Info.plist"]):
                module.main()
            prepare.assert_called_once_with(Path("another/Info.plist"))
            prepare.reset_mock()
            with self.assertRaises(IndexError):
                module.main([])
            prepare.assert_not_called()


if __name__ == "__main__":
    unittest.main()
