"""Test disk image release gates without native tools or credentials."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release_dmg', Path(__file__).with_name('release-dmg.py'))
dmg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmg)
SUBMISSION = '4d5a9a69-b1d9-402b-9d18-18a84a531a42'

class DiskImageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.output = Path(self.tmp.name)
        (self.output / 'Draftly.zip').write_bytes(b'zip candidate')
        self.calls = []
        self.status = 'Accepted'

    def run_tool(self, command, capture=False):
        self.calls.append(command)
        if command[:2] == ['hdiutil', 'create']:
            payload = Path(command[command.index('-srcfolder') + 1])
            self.assertEqual((payload / 'Applications').readlink(), Path('/Applications'))
            Path(command[-1]).write_bytes(b'signed image')
        if command[:3] == ['xcrun', 'notarytool', 'submit']:
            return json.dumps({'id': SUBMISSION})
        if command[:3] == ['xcrun', 'notarytool', 'wait']:
            return json.dumps({'id': SUBMISSION, 'status': self.status})
        return ''

    def create(self):
        return dmg.create(Path('/neutral/Draftly.app'), self.output, '1.2.3', 'test profile', self.run_tool)

    def test_image_must_pass_notary_and_native_checks_before_manifest(self):
        result = self.create()
        paths = dmg.assets(self.output, '1.2.3', dmg.digest(self.output / 'Draftly.zip'))
        self.assertEqual(set(paths), {'Draftly-1.2.3.dmg', 'Draftly-1.2.3.dmg.sha256', 'disk-image.json'})
        self.assertEqual(result['notarySubmission'], SUBMISSION)
        commands = [command[:3] for command in self.calls]
        self.assertLess(commands.index(['xcrun', 'notarytool', 'wait']), commands.index(['xcrun', 'stapler', 'staple']))
        self.assertTrue(any(command[:3] == ['spctl', '--assess', '--type'] for command in self.calls))
        with self.assertRaises(ValueError): self.create()

    def test_rejected_notary_keeps_receipt_without_publishable_manifest(self):
        self.status = 'Invalid'
        with self.assertRaisesRegex(ValueError, 'Apple'): self.create()
        self.assertTrue((self.output / 'dmg-notary-submission.json').exists())
        self.assertFalse((self.output / 'disk-image.json').exists())
        self.assertFalse(any(command[:3] == ['xcrun', 'stapler', 'staple'] for command in self.calls))

    def test_assets_reject_modified_image_and_wrong_candidate(self):
        self.create()
        with self.assertRaises(ValueError): dmg.assets(self.output, '1.2.3', '0' * 64)
        (self.output / 'Draftly-1.2.3.dmg').write_bytes(b'tampered')
        with self.assertRaises(ValueError): dmg.assets(self.output, '1.2.3', dmg.digest(self.output / 'Draftly.zip'))

    def test_native_validation_failure_does_not_write_manifest(self):
        def failing(command, capture=False):
            if command[:2] == ['codesign', '--verify']: raise RuntimeError('signature failure')
            return self.run_tool(command, capture)
        with self.assertRaises(RuntimeError):
            dmg.create(Path('/neutral/Draftly.app'), self.output, '1.2.3', 'test profile', failing)
        self.assertFalse((self.output / 'disk-image.json').exists())
