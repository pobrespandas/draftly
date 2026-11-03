"""Check ready-only prerelease publication without network access."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('prerelease', Path(__file__).with_name('publish-prerelease.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
COMMIT = 'a' * 40
TAG = 'v1.2.3-beta.1'


class FakeGitHub:
    def __init__(self):
        self.items = []
        self.published = False
        self.interrupt = False

    def refs(self, tag):
        return COMMIT, COMMIT

    def releases(self):
        return self.items

    def create_draft(self, tag, notes):
        self.items.append(dict(id=42, tag_name=tag, name='Draftly ' + tag[1:], body=notes,
                               draft=True, prerelease=True, assets=[]))

    def upload(self, tag, paths):
        for path in paths:
            self.items[0]['assets'].append(dict(name=path.name, state='uploaded', size=path.stat().st_size,
                                                digest=release.stage.file_digest(path)))
            if self.interrupt:
                raise ValueError('Interrupted upload')

    def publish(self, release_id):
        self.published = True
        self.items[0]['draft'] = False


class PrereleaseTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        (self.root / 'Draftly.zip').write_bytes(b'neutral fixture')
        self.metadata = dict(sourceCommit=COMMIT, sha256=release.stage.file_digest(self.root / 'Draftly.zip')[7:])
        (self.root / 'candidate.json').write_text(json.dumps(self.metadata))
        (self.root / 'Draftly.zip.sha256').write_text(self.metadata['sha256'] + '  Draftly.zip\n')
        self.github = FakeGitHub()
        self.downloads = []

    def run_publish(self, **options):
        return release.publish(self.root, TAG, 'unused-test-key', 'Beta notes', enabled='YES',
            github=self.github, verify=options.get('verify', lambda *args: self.metadata),
            download=lambda *args: self.downloads.append(args))

    def test_publishes_only_complete_verified_assets_without_appcast(self):
        self.assertEqual(self.run_publish()['channel'], 'beta')
        self.assertTrue(self.github.published)
        self.assertTrue(self.github.items[0]['prerelease'])
        self.assertEqual({a['name'] for a in self.github.items[0]['assets']},
                         {'Draftly.zip', 'Draftly.zip.sha256', 'candidate.json'})
        self.assertEqual(len(self.downloads), 3)
        self.assertFalse((self.root / 'appcast.xml').exists())

    def test_failed_candidate_verification_creates_no_release(self):
        def fail(*args):
            raise ValueError('Not ready')
        with self.assertRaisesRegex(ValueError, 'Not ready'):
            self.run_publish(verify=fail)
        self.assertEqual(self.github.items, [])

    def test_interrupted_upload_stays_private_and_resumes_missing_assets(self):
        self.github.interrupt = True
        with self.assertRaisesRegex(ValueError, 'Interrupted'):
            self.run_publish()
        self.assertFalse(self.github.published)
        self.assertTrue(self.github.items[0]['draft'])
        self.github.interrupt = False
        self.run_publish()
        self.assertTrue(self.github.published)
        self.assertEqual(len(self.github.items[0]['assets']), 3)

    def test_does_not_repair_an_incomplete_public_prerelease(self):
        self.github.create_draft(TAG, 'Beta notes')
        self.github.items[0]['draft'] = False
        with self.assertRaisesRegex(ValueError, 'Do not repair'):
            self.run_publish()
        self.assertFalse(self.github.published)

    def test_real_api_marks_prerelease_and_never_latest(self):
        client = release.GitHub()
        bodies = []
        client.api = lambda path, *, body: bodies.append(body)
        client.create_draft(TAG, 'notes')
        self.assertEqual(bodies[0]['make_latest'], 'false')
        self.assertTrue(bodies[0]['draft'] and bodies[0]['prerelease'])
        def command(args, *, body):
            bodies.append(json.loads(body))
            return json.dumps(dict(id=42, draft=False, prerelease=True))
        client.command = command
        client.publish(42)
        self.assertEqual(bodies[1], dict(draft=False, prerelease=True, make_latest='false'))
