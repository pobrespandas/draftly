"""Check runner selection without building an app or using user data."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('ci_scope', Path(__file__).with_name('ci-change-scope.py'))
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class CIChangeScopeTests(unittest.TestCase):
    def test_docs_and_empty_changes_need_no_expensive_checks(self):
        for paths in ([], ['README.md', 'docs/release-rehearsal.md'], ['.gitignore']):
            with self.subTest(paths=paths):
                self.assertFalse(any(scope.select_checks(paths).values()))

    def test_website_and_release_tools_have_independent_checks(self):
        self.assertEqual(scope.select_checks(['website/public/index.html']),
                         dict(native=False, tooling=False, website=True, matrix=False))
        self.assertEqual(scope.select_checks(['scripts/package-release.py', '.github/workflows/release.yml']),
                         dict(native=False, tooling=True, website=False, matrix=False))

    def test_native_inputs_and_drivers_keep_native_contract_coverage(self):
        for path in ['Sources/Draftly/App.swift', 'Tests/Example.swift', 'Resources/App.icns',
                     'Vendor/Library.h', 'Package.resolved', 'Configuration/Info.plist',
                     'Draftly.xcodeproj/project.pbxproj', 'scripts/build-app.sh',
                     'scripts/run-swift-tests.py', '.github/workflows/ci.yml']:
            with self.subTest(path=path):
                result = scope.select_checks([path])
                self.assertTrue(result['native'])
                self.assertTrue(result['tooling'])
                self.assertTrue(result['matrix'])

    def test_matrix_unknown_mixed_and_forced_changes(self):
        self.assertTrue(scope.select_checks(['docs/research/action-api-matrix.json'])['matrix'])
        self.assertTrue(all(scope.select_checks(['unknown-build-input']).values()))
        self.assertTrue(all(scope.select_checks([], force=True).values()))
        selected = scope.select_checks(['README.md', 'website/public/release.mjs', 'Sources/App.swift'])
        self.assertTrue(all(selected.values()))

    def test_missing_or_zero_revision_forces_checks(self):
        for base in ('', '0' * 40, '--help', 'not-a-revision'):
            with self.subTest(base=base):
                self.assertIsNone(scope.changed_paths(base, 'a' * 40))

    def test_git_diff_includes_deletions_and_renames_and_cli_reports_booleans(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()
            git('init', '-q'); git('config', 'user.email', 'qa@example.invalid'); git('config', 'user.name', 'QA')
            (root / 'README.md').write_text('neutral')
            git('add', '.'); git('commit', '-qm', 'initial')
            base = git('rev-parse', 'HEAD')
            (root / 'Sources').mkdir(); (root / 'README.md').rename(root / 'Sources/Input.swift')
            git('add', '-A'); git('commit', '-qm', 'move')
            head = git('rev-parse', 'HEAD')
            result = subprocess.run([sys.executable, scope.__file__, '--base', base, '--head', head],
                                    cwd=root, text=True, capture_output=True, check=True)
            self.assertIn('native=true', result.stdout)
            self.assertIn('tooling=true', result.stdout)
            self.assertIn('website=false', result.stdout)
            missing = subprocess.run([sys.executable, scope.__file__, '--base', 'b' * 40, '--head', head],
                                     cwd=root, text=True, capture_output=True)
            self.assertNotEqual(missing.returncode, 0)


class CIResultTests(unittest.TestCase):
    def results(self, selected):
        results = {'plan': {'result': 'success', 'outputs': selected}}
        for name, job in [('native', 'macos'), ('tooling', 'tooling'), ('website', 'website'), ('matrix', 'matrix')]:
            results[job] = {'result': 'success' if selected[name] == 'true' else 'skipped'}
        return results

    def test_documentation_native_and_full_results(self):
        for paths in ([], ['README.md'], ['Sources/App.swift'], ['website/index.html'], ['unknown']):
            selected = {key: str(value).lower() for key, value in scope.select_checks(paths).items()}
            scope.verify_results(self.results(selected))

    def test_failed_cancelled_or_unexpectedly_skipped_checks_fail(self):
        selected = dict.fromkeys(scope.SCOPES, 'true')
        for job in ('plan', 'macos', 'tooling', 'website', 'matrix'):
            for state in ('failure', 'cancelled', 'skipped', None):
                results = self.results(selected); results[job]['result'] = state
                with self.subTest(job=job, state=state), self.assertRaises(ValueError):
                    scope.verify_results(results)

    def test_missing_selection_or_missing_job_fails(self):
        for name in scope.SCOPES:
            results = self.results(dict.fromkeys(scope.SCOPES, 'false'))
            del results['plan']['outputs'][name]
            with self.subTest(name=name), self.assertRaises(ValueError):
                scope.verify_results(results)
        results = self.results(dict.fromkeys(scope.SCOPES, 'true')); del results['tooling']
        with self.assertRaises(ValueError):
            scope.verify_results(results)


def workflow_jobs():
    workflow = Path(scope.__file__).resolve().parent.parent / '.github/workflows/ci.yml'
    parsed = subprocess.check_output(['ruby', '-rjson', '-ryaml', '-e',
        'print JSON.generate(YAML.load_file(ARGV.fetch(0)).fetch("jobs"))', str(workflow)], text=True)
    return json.loads(parsed)


class CIWorkflowPolicyTests(unittest.TestCase):
    def test_native_runner_depends_on_selection_and_required_gate_runs_after_skips(self):
        jobs = workflow_jobs()
        self.assertEqual(jobs['plan']['runs-on'], 'ubuntu-latest')
        self.assertEqual(jobs['macos']['needs'], 'plan')
        self.assertEqual(jobs['macos']['if'], "${{ needs.plan.outputs.native == 'true' }}")
        self.assertEqual(jobs['tooling']['if'], "${{ needs.plan.outputs.tooling == 'true' }}")
        self.assertEqual(jobs['result']['name'], 'Build and test on macOS')
        self.assertIn('always()', jobs['result']['if'])
        self.assertEqual(set(jobs['result']['needs']), {'plan', 'macos', 'tooling', 'website', 'matrix'})
        self.assertIn('scripts/ci-change-scope.py --verify-results', jobs['result']['steps'][-1]['run'])


    def test_script_runner_resolves_real_sparkle_tools_before_contract_tests(self):
        steps = workflow_jobs()['tooling']['steps']
        commands = [step.get('run', '') for step in steps]
        self.assertLess(commands.index('swift package resolve'),
                        commands.index("python -m unittest discover -s scripts -p 'test_*.py'"))
