"""Check release selection with disposable repositories and no network."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import unittest
from unittest.mock import patch
from git_test_fixture import temporary_git_repository

spec = importlib.util.spec_from_file_location('release_changes', Path(__file__).with_name('release-changes.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseChangesTests(unittest.TestCase):
    def test_latest_stable_version_ignores_drafts_and_prereleases(self):
        def item(tag, **options):
            return dict(tag_name=tag, draft=False, prerelease=False, **options)
        self.assertIsNone(release.latest_tag([]))
        self.assertEqual(release.latest_tag([item('v0.2.0'), item('v0.10.0'),
            dict(tag_name='v9.0.0', draft=True, prerelease=False),
            dict(tag_name='v8.0.0', draft=False, prerelease=True)]), 'v0.10.0')
        for value in ([{}], [item('unversioned')], [item('v01.2.3')]):
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.latest_tag(value)

    def test_package_boundaries(self):
        for path in ['Sources/App.swift', 'Resources/App.icns', 'Vendor/module.h',
                     'Configuration/Draftly.entitlements', 'Draftly.xcodeproj/project.pbxproj',
                     'Package.resolved', 'scripts/build-app.sh', 'scripts/package-release.py',
                     'scripts/release-dmg.py', 'unknown-build-input']:
            with self.subTest(path=path):
                self.assertTrue(release.package_path(path))
        for path in ['README.md', 'Tests/Core.swift', 'website/public/index.html',
                     '.github/workflows/ci.yml', 'scripts/ci-change-scope.py',
                     'scripts/test_package_release.py', 'docs/releases/v1.0.0.txt']:
            with self.subTest(path=path):
                self.assertFalse(release.package_path(path))

    def test_version_only_docs_and_tests_do_not_release_but_metadata_and_source_do(self):
        with temporary_git_repository() as repository, patch.object(release, 'ROOT', repository.root):
            root, save = repository.root, repository.commit
            (root / 'Configuration').mkdir()
            info = root / 'Configuration/Info.plist'
            value = dict(CFBundleVersion='1', CFBundleShortVersionString='0.1.0', CFBundleIdentifier='test.app')
            info.write_bytes(plistlib.dumps(value)); base = save('base')
            self.assertFalse(release.changed_package(base, base))
            value.update(CFBundleVersion='2', CFBundleShortVersionString='0.1.1')
            info.write_bytes(plistlib.dumps(value)); (root / 'README.md').write_text('neutral')
            head = save('version and docs'); self.assertFalse(release.changed_package(base, head))
            value['CFBundleDisplayName'] = 'Updated'; info.write_bytes(plistlib.dumps(value))
            metadata = save('metadata'); self.assertTrue(release.changed_package(head, metadata))
            (root / 'Sources').mkdir(); (root / 'README.md').rename(root / 'Sources/Input.swift')
            source = save('rename into source'); self.assertTrue(release.changed_package(metadata, source))
            (root / 'Sources/Input.swift').unlink()
            deleted = save('delete source'); self.assertTrue(release.changed_package(source, deleted))
            with self.assertRaises(subprocess.CalledProcessError):
                release.changed_package(deleted, source)

    def test_invalid_revisions_stop_instead_of_allowing_a_release(self):
        with self.assertRaises(ValueError):
            release.changed_package('--help', 'a' * 40)


    def test_explicit_recovery_does_not_query_or_rebuild_release_history(self):
        import sys
        accepted = subprocess.run([sys.executable, release.__file__, '--resume-run-id', '123'],
                                  text=True, capture_output=True)
        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        self.assertEqual(accepted.stdout.strip(), 'package=true')
        for value in ('0', '-1', '1 extra', '123\n'):
            rejected = subprocess.run([sys.executable, release.__file__, '--resume-run-id', value],
                                      text=True, capture_output=True)
            with self.subTest(value=value):
                self.assertNotEqual(rejected.returncode, 0)
                self.assertNotIn('package=true', rejected.stdout)
