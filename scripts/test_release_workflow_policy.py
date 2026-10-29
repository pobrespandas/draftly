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


if __name__ == '__main__':
    unittest.main()
