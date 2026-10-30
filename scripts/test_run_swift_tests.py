import importlib.util
from pathlib import Path
import tempfile
from subprocess import CompletedProcess
from unittest.mock import patch
import unittest

spec = importlib.util.spec_from_file_location("run_swift_tests", Path(__file__).with_name("run-swift-tests.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class SwiftResultVerificationTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.report = Path(self.folder.name) / "results.xml"
        self.expected = {"DraftlyTests.Suite/first()", "DraftlyCoreTests.Suite/second(worker:)"}

    def write_report(self, body, count=2, extra=""):
        self.report.write_text(f'<testsuites><testsuite tests="{count}" failures="0" errors="0" skipped="0" {extra}>{body}</testsuite></testsuites>')

    def cases(self):
        return ('<testcase classname="DraftlyTests.Suite" name="first()"/>'
                '<testcase classname="DraftlyCoreTests.Suite" name="second(worker:)"/>')

    def test_complete_results_match_individual_discovered_identities(self):
        self.write_report(self.cases())
        counts = runner.verify_results(self.expected, [self.report])
        self.assertEqual(counts, {"DraftlyTests": 1, "DraftlyCoreTests": 1})

    def test_zero_exit_without_report_or_with_missing_results_is_not_success(self):
        with self.assertRaisesRegex(ValueError, "no test report"):
            runner.verify_results(self.expected, [self.report])
        self.write_report('<testcase classname="DraftlyTests.Suite" name="first()"/>', count=1)
        with self.assertRaisesRegex(ValueError, "Missing results.*second"):
            runner.verify_results(self.expected, [self.report])

    def test_equal_counts_cannot_hide_replaced_or_duplicate_tests(self):
        self.write_report(self.cases().replace("second(worker:)", "other()"))
        with self.assertRaisesRegex(ValueError, "Missing results"):
            runner.verify_results(self.expected, [self.report])
        self.write_report(self.cases().replace("DraftlyCoreTests.Suite", "DraftlyTests.Suite").replace("second(worker:)", "first()"))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            runner.verify_results(self.expected, [self.report])

    def test_failure_error_or_skip_cannot_pass_with_zero_summary_counts(self):
        for tag in ["failure", "error", "skipped"]:
            self.write_report(self.cases().replace('name="first()"/>', f'name="first()"><{tag}/></testcase>'))
            with self.assertRaisesRegex(ValueError, "did not pass"):
                runner.verify_results(self.expected, [self.report])

    def test_root_failure_summary_cannot_be_hidden_by_passing_children(self):
        self.write_report(self.cases())
        self.report.write_text(self.report.read_text().replace("<testsuites>", '<testsuites errors="1">'))
        with self.assertRaisesRegex(ValueError, "errors"):
            runner.verify_results(self.expected, [self.report])

    def test_truncated_xml_and_inconsistent_summary_are_rejected(self):
        self.report.write_text('<testsuites><testsuite tests="2">')
        with self.assertRaisesRegex(ValueError, "report is incomplete or invalid"):
            runner.verify_results(self.expected, [self.report])
        self.write_report(self.cases(), count=3)
        with self.assertRaisesRegex(ValueError, "count"):
            runner.verify_results(self.expected, [self.report])

    def test_run_cannot_accept_a_stale_report_after_a_zero_exit(self):
        self.write_report(self.cases())
        with patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 0)):
            with self.assertRaisesRegex(ValueError, "no test report"):
                runner.run_target("DraftlyTests", self.expected, Path(self.folder.name))
        self.assertFalse(self.report.exists())

    def test_app_mode_is_explicit_and_failures_are_not_retried(self):
        for concurrent in [False, True]:
            with patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 7)) as command:
                with self.assertRaisesRegex(ValueError, "Swift tests failed"):
                    runner.run_target("DraftlyTests", self.expected, Path(self.folder.name),
                                      concurrent_app=concurrent)
                self.assertEqual(command.call_count, 1)
                self.assertEqual("--no-parallel" in command.call_args.args[0], not concurrent)

    def test_core_tests_run_serially_even_when_app_diagnostics_are_concurrent(self):
        for concurrent in [False, True]:
            with patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 7)) as command:
                with self.assertRaisesRegex(ValueError, "Swift tests failed"):
                    runner.run_target("DraftlyCoreTests", self.expected, Path(self.folder.name),
                                      concurrent_app=concurrent)
                self.assertEqual(command.call_count, 1)
                self.assertIn("--no-parallel", command.call_args.args[0])

    def test_diagnostic_suite_is_forwarded_without_retries(self):
        with patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 7)) as command:
            with self.assertRaisesRegex(ValueError, "Swift tests failed"):
                runner.run_target("DraftlyTests", self.expected, Path(self.folder.name),
                                  test_filter="DraftlyTests.TypewriterScrollingTests")
            args = command.call_args.args[0]
            self.assertEqual(args[args.index("--filter") + 1], "DraftlyTests.TypewriterScrollingTests")
            self.assertEqual(command.call_count, 1)

    def test_inventory_ignores_build_noise_but_requires_unique_test_ids(self):
        output = "Building for debugging...\n" + "\n".join(sorted(self.expected))
        self.assertEqual(runner.test_inventory(output), self.expected)
        self.assertEqual(runner.test_inventory(output + "\nNewTests.Suite/newCase()"),
                         self.expected | {"NewTests.Suite/newCase()"})
        for bad in ["Build complete!", output + "\nDraftlyTests.Suite/first()"]:
            with self.assertRaises(ValueError):
                runner.test_inventory(bad)
