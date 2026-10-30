"""Check the release workflow's environment and execution gates."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent


def jobs():
    # macOS runners include Ruby and its standard YAML parser.
    result = subprocess.run(['ruby', '-rjson', '-ryaml', '-e',
        'print JSON.generate(YAML.load_file(ARGV.fetch(0)).fetch("jobs"))',
        str(ROOT / '.github/workflows/release.yml')], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


class ReleaseWorkflowPolicyTests(unittest.TestCase):
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
        self.assertEqual(configured['rehearsal']['if'], "${{ github.ref == 'refs/heads/main' && github.event_name == 'workflow_dispatch' && inputs.operation == 'release' }}")
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

    def test_starting_staging_for_an_existing_candidate_is_explicit(self):
        configured = jobs()
        guard = next(step for step in configured['rehearsal']['steps']
                     if step.get('name') == 'Validate recovery run ID')['run']
        for run_id, fresh, accepted in [('', 'false', True), ('123', 'false', True),
                                        ('123', 'true', True), ('', 'true', False),
                                        ('invalid', 'true', False)]:
            with self.subTest(run_id=run_id, fresh=fresh):
                result = subprocess.run(['bash', '-eu', '-c', guard], capture_output=True,
                    text=True, env={'PATH': '/usr/bin:/bin', 'RESUME_RUN_ID': run_id,
                                    'START_STAGING': fresh})
                self.assertEqual(result.returncode == 0, accepted, result.stderr)

        stage = configured['stage']['steps']
        restore = next(step for step in stage if step.get('name') == 'Restore the original staging checkpoint')
        prepare = next(step for step in stage if step.get('name') == 'Prepare the signed update feed')
        self.assertEqual(restore['if'], "${{ env.RESUME_RUN_ID != '' && env.START_STAGING != 'true' }}")
        self.assertEqual(prepare['if'], "${{ env.RESUME_RUN_ID == '' || env.START_STAGING == 'true' }}")
        for name in ['Acquire or verify the site writer lock', 'Stage the feed without promoting the site']:
            step = next(step for step in stage if step.get('name') == name)
            self.assertIn('[[ -n "$RESUME_RUN_ID" && "$START_STAGING" != true ]]', step['run'])
        history = next(step for step in configured['rehearsal']['steps']
                       if step.get('name') == 'Check published version and build history')
        self.assertIn('[[ -n "$RESUME_RUN_ID" && "$START_STAGING" != true ]]', history['run'])

    def test_release_history_mode_tracks_whether_staging_is_new(self):
        steps = jobs()['rehearsal']['steps']
        command = next(step for step in steps
                       if step.get('name') == 'Check published version and build history')['run']
        command = command.replace('python scripts/release-history.py --resume-candidate',
                                  "printf 'recover'")
        command = command.replace('python scripts/release-history.py', "printf 'new'")
        cases = [('', 'false', 'new'), ('123', 'false', 'recover'), ('123', 'true', 'new')]
        for run_id, fresh, expected in cases:
            with self.subTest(run_id=run_id, fresh=fresh):
                result = subprocess.run(['bash', '-eu', '-c', command], check=True,
                    capture_output=True, text=True, env={'PATH': '/usr/bin:/bin',
                    'RESUME_RUN_ID': run_id, 'START_STAGING': fresh})
                self.assertEqual(result.stdout, expected)

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
