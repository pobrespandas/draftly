"""Check version recommendations and release-note history."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('notes', Path(__file__).with_name('prepare-release-notes.py'))
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)


def commits(*messages):
    return [(str(i + 1) * 40, message) for i, message in enumerate(messages)]


class ReleaseNotesTests(unittest.TestCase):
    def test_semver_increment_and_zero_major_policy(self):
        for base, message, expected in (
            ('v1.2.3', 'fix(editor): preserve café', '1.2.4'),
            ('v1.2.3', 'feat(editor): add tools', '1.3.0'),
            ('v1.2.3', 'feat(api)!: remove old schema', '2.0.0'),
            ('v0.2.3', 'feat(api)!: remove old schema', '0.3.0'),
            ('v1.2.3', 'refactor(api): simplify\n\nBREAKING CHANGE: remove old field', '2.0.0'),
            ('v0.2.3', 'fix(editor): preserve text', '0.2.4')):
            with self.subTest(message=message):
                self.assertEqual(notes.recommended_version(base, commits(message)), expected)

    def test_prerelease_order_matches_semver(self):
        tags = ['v1.0.0-alpha.2', 'v1.0.0-alpha.10', 'v1.0.0-beta.1', 'v1.0.0', 'v1.0.1-alpha.1']
        self.assertEqual(sorted(reversed(tags), key=notes.channels.precedence), tags)

    def test_notes_keep_unicode_breaking_changes_and_legacy_subjects(self):
        rendered = notes.render('v1.3.0-beta.1', commits('feat(chat): add café 🐼',
            'fix(editor): preserve text', 'chore(api)!: remove field', 'Old legacy subject'))
        self.assertIn('Breaking changes', rendered)
        self.assertIn('chat: add café 🐼', rendered)
        self.assertIn('Other changes\n- Old legacy subject', rendered)
        self.assertLess(rendered.index('Breaking changes'), rendered.index('Features'))

    def test_write_preserves_history_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old = '# Changelog\n\n## [1.0.0]\n\nHistoric public notes.\n'
            (root / 'CHANGELOG.md').write_text(old)
            rendered = notes.render('v1.1.0-alpha.1', commits('feat(chat): new tool'))
            notes.write(root, 'v1.1.0-alpha.1', rendered)
            result = (root / 'CHANGELOG.md').read_text()
            self.assertIn('## [1.0.0]\n\nHistoric public notes.\n', result)
            self.assertEqual((root / 'docs/releases/v1.1.0-alpha.1.txt').read_text(), rendered)
            with self.assertRaises(ValueError):
                notes.write(root, 'v1.1.0-alpha.1', 'Changed')
            self.assertEqual((root / 'CHANGELOG.md').read_text(), result)

    def test_release_preflight_rejects_missing_or_different_changelog_entry(self):
        spec = importlib.util.spec_from_file_location('preflight_notes', Path(__file__).with_name('release-preflight.py'))
        preflight = importlib.util.module_from_spec(spec); spec.loader.exec_module(preflight)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            notes.write(root, 'v1.1.0-beta.1', 'Ready notes\n')
            preflight.validate_notes('v1.1.0-beta.1', root / 'docs/releases', changelog=root / 'CHANGELOG.md')
            (root / 'docs/releases/v1.1.0-beta.1.txt').write_text('Different notes\n')
            with self.assertRaisesRegex(ValueError, 'must match'):
                preflight.validate_notes('v1.1.0-beta.1', root / 'docs/releases', changelog=root / 'CHANGELOG.md')
