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
        self.assertEqual(configured['rehearsal']['if'], "${{ github.ref == 'refs/heads/main' && github.event_name == 'workflow_dispatch' }}")
        source = (ROOT / '.github/workflows/release.yml').read_text()
        self.assertNotIn('  push:', source)
        dispatcher = (ROOT / '.github/workflows/release-tag.yml').read_text()
        self.assertNotIn('secrets.', dispatcher)
        self.assertNotIn('actions/checkout', dispatcher)
        self.assertIn('gh workflow run release.yml --ref main', dispatcher)
        self.assertIn('actions: write', dispatcher)

    def test_firebase_auth_uses_the_website_project(self):
        configured = jobs()
        auth = next(step for step in configured['stage']['steps'] if step.get('id') == 'firebase_auth')
        projects = json.loads((ROOT / 'website/.firebaserc').read_text())
        self.assertEqual(auth['with']['project_id'], projects['projects']['default'])


if __name__ == '__main__':
    unittest.main()
