"""Check the release workflow's environment and execution gates."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


def jobs():
    # macOS runners include Ruby and its standard YAML parser.
    result = subprocess.run(['ruby', '-rjson', '-ryaml', '-e',
        'print JSON.generate(YAML.load_file(ARGV.fetch(0)).fetch("jobs"))',
        str(ROOT / '.github/workflows/release.yml')], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


class ReleaseWorkflowPolicyTests(unittest.TestCase):
    def test_candidate_artifact_retains_dmg_and_notarization_receipts(self):
        step = next(s for s in jobs()['candidate']['steps']
                    if s.get('name') == 'Save verified candidate for review')
        expected = {'Draftly.zip', 'Draftly.zip.sha256', 'candidate.json',
                    'signing-report.json', 'notary-submission.json', 'READY',
                    'Draftly-1.2.3.dmg', 'Draftly-1.2.3.dmg.sha256',
                    'disk-image.json', 'dmg-notary-submission.json'}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate = root / '.build/release-candidates/v1.2.3'
            candidate.mkdir(parents=True)
            for name in expected:
                (candidate / name).write_text('neutral artifact transfer fixture')
            transferred = set()
            for pattern in step['with']['path'].splitlines():
                pattern = pattern.replace('${{ env.RELEASE_TAG }}', 'v1.2.3').strip()
                transferred.update(p.name for p in root.glob(pattern))
            self.assertEqual(transferred, expected)
        recovery = next(s for s in jobs()['candidate']['steps']
                        if s.get('name') == 'Preserve incomplete notary submission for recovery')
        for name in ('dmg-notary-submission.json', 'Draftly-*.dmg'):
            self.assertIn('/' + name, recovery['with']['path'])
        self.assertEqual(recovery['if'], 'failure()')

    def test_sensitive_jobs_require_the_release_environment_and_prerequisites(self):
        configured = jobs()
        self.assertEqual(configured['candidate']['environment'], 'release')
        self.assertEqual(configured['candidate']['needs'], 'rehearsal')
        self.assertEqual(configured['stage']['environment'], 'release')
        self.assertEqual(configured['stage']['needs'], 'candidate')

    def test_sensitive_jobs_are_gated_and_staging_is_not_resume_enabled(self):
        configured = jobs()
        candidate = configured['candidate']['if']
        stage = configured['stage']['if']
        self.assertEqual(candidate, "${{ vars.DRAFTLY_RELEASE_SIGNING_ENABLED == 'true' || (github.event_name == 'workflow_dispatch' && inputs.resume_run_id != '') }}")
        self.assertEqual(stage, "${{ vars.DRAFTLY_RELEASE_STAGING_ENABLED == 'true' }}")

    def test_only_main_dispatch_can_reach_release_credentials(self):
        configured = jobs()
        trusted = "github.ref == 'refs/heads/main' && github.event_name == 'workflow_dispatch' && inputs.operation == 'release'"
        self.assertEqual(configured['preflight']['if'], "${{ " + trusted + " }}")
        self.assertEqual(configured['preflight']['runs-on'], 'ubuntu-latest')
        self.assertEqual(configured['rehearsal']['needs'], 'preflight')
        self.assertEqual(configured['rehearsal']['if'], "${{ " + trusted + " && needs.preflight.outputs.package == 'true' }}")
        preflight = json.dumps(configured['preflight'])
        self.assertNotIn('secrets.', preflight)
        self.assertIn('scripts/release-changes.py', preflight)
        source = (ROOT / '.github/workflows/release.yml').read_text()
        self.assertNotIn('  push:', source)
        dispatcher = (ROOT / '.github/workflows/release-tag.yml').read_text()
        self.assertNotIn('secrets.', dispatcher)
        self.assertNotIn('actions/checkout', dispatcher)
        self.assertIn('gh workflow run release.yml --ref main', dispatcher)
        self.assertIn('actions: write', dispatcher)

    def test_candidate_guard_accepts_only_the_first_trusted_main_dispatch(self):
        steps = jobs()['candidate']['steps']
        step = next(step for step in steps if step.get('name') == 'Build the signed candidate')
        command = 'bash scripts/release-candidate-ci.sh'
        self.assertEqual(step['run'].count(command), 1)
        guard = step['run'].replace(command, "printf 'candidate accepted'")
        cases = [
            ('workflow_dispatch', 'refs/heads/main', '1', True),
            ('push', 'refs/heads/main', '1', False),
            ('workflow_dispatch', 'refs/heads/work', '1', False),
            ('workflow_dispatch', 'refs/heads/main', '2', False),
        ]
        for event, ref, attempt, accepted in cases:
            with self.subTest(event=event, ref=ref, attempt=attempt):
                result = subprocess.run(['bash', '-eu', '-c', guard], capture_output=True,
                    text=True, env={'PATH': '/usr/bin:/bin', 'GITHUB_EVENT_NAME': event,
                                    'GITHUB_REF': ref, 'GITHUB_RUN_ATTEMPT': attempt})
                self.assertEqual(result.returncode == 0, accepted, result.stderr)
                self.assertEqual('candidate accepted' in result.stdout, accepted)

    def test_publication_requires_lock_and_preserves_final_recovery_state(self):
        steps = jobs()['stage']['steps']
        names = [step.get('name', '') for step in steps]
        ordered = ['Acquire or verify the site writer lock',
                   'Stage the feed without promoting the site',
                   'Verify and stage the GitHub draft',
                   'Publish and verify the GitHub assets',
                   'Promote and verify the public site',
                   'Release the writer lock after public verification',
                   'Preserve the staging checkpoint']
        positions = [names.index(name) for name in ordered]
        self.assertEqual(positions, sorted(positions))
        for name in ordered[3:6]:
            step = steps[names.index(name)]
            self.assertEqual(step['if'], "${{ vars.DRAFTLY_RELEASE_PUBLICATION_ENABLED == 'true' }}")
            self.assertNotIn('always()', step['if'])
        self.assertEqual(steps[-1]['if'], '${{ always() }}')
        promote = steps[names.index('Promote and verify the public site')]
        self.assertIn('--lock-journal', promote['run'])
        self.assertIn('--journal', promote['run'])
        self.assertEqual(promote['env']['DRAFTLY_RELEASE_PROMOTION_ENABLED'], 'YES')

    def test_publisher_check_uses_no_signing_secrets_and_requires_main(self):
        job = jobs()['verify-publisher']
        self.assertEqual(job['environment'], 'release')
        self.assertIn("github.ref == 'refs/heads/main'", job['if'])
        self.assertIn("inputs.operation == 'verify-publisher'", job['if'])
        self.assertEqual(job['permissions'], {'contents': 'read', 'id-token': 'write'})
        self.assertNotIn('secrets.', json.dumps(job))
        self.assertNotIn('needs', job)
        self.assertTrue(all('package-release.py' not in step.get('run', '') for step in job['steps']))

    def test_firebase_auth_uses_the_website_project(self):
        configured = jobs()
        auth = next(step for step in configured['stage']['steps'] if step.get('id') == 'firebase_auth')
        projects = json.loads((ROOT / 'website/.firebaserc').read_text())
        self.assertEqual(auth['with']['project_id'], projects['projects']['default'])


if __name__ == '__main__':
    unittest.main()
