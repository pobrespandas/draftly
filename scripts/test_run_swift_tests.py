import importlib.util
import json
import os
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
        environment = patch.dict(runner.os.environ, {"GITHUB_ACTIONS": "false"})
        environment.start()
        self.addCleanup(environment.stop)
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

    def test_target_execution_reuses_build_and_preserves_serial_policy_without_retries(self):
        for module in ["DraftlyTests", "DraftlyCoreTests"]:
            for concurrent in [False, True]:
                with self.subTest(module=module, concurrent=concurrent), \
                        patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 7)) as command:
                    with self.assertRaisesRegex(ValueError, "Swift tests failed"):
                        runner.run_target(module, self.expected, Path(self.folder.name), concurrent_app=concurrent)
                    self.assertEqual(command.call_count, 1)
                    args = command.call_args.args[0]
                    self.assertIn("--skip-build", args)
                    self.assertEqual("--no-parallel" in args, module != "DraftlyTests" or not concurrent)

    def test_discovery_must_succeed_before_any_built_target_runs(self):
        with patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 7, "", "build failed")), \
                patch.object(runner, "run_target") as target:
            with self.assertRaisesRegex(ValueError, "discovery failed"):
                runner.run(Path(self.folder.name))
        target.assert_not_called()

    def test_discovered_inventory_controls_each_target_run(self):
        inventory = "DraftlyTests.Suite/first()\nDraftlyCoreTests.Suite/second(worker:)\n"
        calls = []
        def execute(module, selected, output, **options):
            self.assertEqual((Path(self.folder.name) / "inventory.log").read_text(), inventory)
            calls.append((module, selected))
            return {module: len(selected)}
        with patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 0, inventory, "")) as discovery, \
                patch.object(runner, "run_target", side_effect=execute), patch("builtins.print"):
            runner.run(Path(self.folder.name))
        self.assertEqual(discovery.call_args.args[0], ["swift", "test", "list"])
        self.assertEqual(calls, [("DraftlyCoreTests", {"DraftlyCoreTests.Suite/second(worker:)"}),
                                 ("DraftlyTests", {"DraftlyTests.Suite/first()"})])

    def test_diagnostic_suite_is_forwarded_without_retries(self):
        with patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 7)) as command:
            with self.assertRaisesRegex(ValueError, "Swift tests failed"):
                runner.run_target("DraftlyTests", self.expected, Path(self.folder.name),
                                  test_filter="DraftlyTests.TypewriterScrollingTests")
            args = command.call_args.args[0]
            self.assertEqual(args[args.index("--filter") + 1], "DraftlyTests.TypewriterScrollingTests")
            self.assertEqual(command.call_count, 1)

    def test_incomplete_report_retains_zero_cli_exit_without_claiming_child_success(self):
        with patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 0)) as command:
            with self.assertRaisesRegex(ValueError, "no test report"):
                runner.run_target("DraftlyTests", self.expected, Path(self.folder.name))
        record = json.loads((Path(self.folder.name) / "process.json").read_text())
        self.assertEqual(record["scope"], "swift_cli")
        self.assertEqual(record["returnCode"], 0)
        self.assertEqual(record["verification"], "rejected")
        self.assertIsNone(record["signal"])
        self.assertNotIn("environment", record)
        self.assertEqual(command.call_count, 1)

    def test_signal_exit_is_recorded_before_reporting_a_test_failure(self):
        with patch.object(runner.subprocess, "run", return_value=CompletedProcess([], -11)):
            with self.assertRaisesRegex(ValueError, "Swift tests failed"):
                runner.run_target("DraftlyTests", self.expected, Path(self.folder.name))
        record = json.loads((Path(self.folder.name) / "process.json").read_text())
        self.assertEqual(record["returnCode"], -11)
        self.assertEqual(record["signal"], 11)
        self.assertEqual(record["verification"], "not_run")
        self.assertGreaterEqual(record["elapsedSeconds"], 0)

    def test_completed_report_records_verification_and_clears_stale_process_data(self):
        path = Path(self.folder.name) / "process.json"
        path.write_text('{"stale": true}')
        def complete(*args, **kwargs):
            self.write_report(self.cases())
            return CompletedProcess([], 0)
        with patch.object(runner.subprocess, "run", side_effect=complete) as command:
            self.assertEqual(runner.run_target("DraftlyTests", self.expected, Path(self.folder.name)),
                             {"DraftlyTests": 1, "DraftlyCoreTests": 1})
        record = json.loads(path.read_text())
        self.assertNotIn("stale", record)
        self.assertEqual(record["verification"], "passed")
        self.assertEqual(record["command"][0:2], ["swift", "test"])
        self.assertEqual(command.call_count, 1)

    def test_termination_trace_environment_is_passed_only_on_ci(self):
        for ci in ["false", "true"]:
            with self.subTest(ci=ci), \
                    patch.dict(runner.os.environ, {"GITHUB_ACTIONS": ci,
                        "DRAFTLY_TEST_EXIT_TRACE_LIBRARY": "/neutral/trace.dylib",
                        "DRAFTLY_TEST_SWIFT_EXECUTABLE": "/neutral/toolchain/swift"}), \
                    patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 0)) as command, \
                    patch.object(runner, "capture_native_crashes", return_value={"state": "scanned", "files": []}):
                with self.assertRaisesRegex(ValueError, "no test report"):
                    runner.run_target("DraftlyTests", self.expected, Path(self.folder.name))
                if ci == "true":
                    self.assertEqual(command.call_args.kwargs["env"]["DYLD_INSERT_LIBRARIES"], "/neutral/trace.dylib")
                    self.assertEqual(command.call_args.args[0][0], "/neutral/toolchain/swift")
                else:
                    self.assertNotIn("env", command.call_args.kwargs)

    def test_local_execution_does_not_read_system_crash_reports(self):
        with patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 0)), \
                patch.object(runner, "capture_native_crashes") as capture:
            with self.assertRaisesRegex(ValueError, "no test report"):
                runner.run_target("DraftlyTests", self.expected, Path(self.folder.name))
        capture.assert_not_called()

    def test_ci_execution_records_available_crash_diagnostics_without_accepting_bad_results(self):
        with patch.dict(runner.os.environ, {"GITHUB_ACTIONS": "true"}), \
                patch.object(runner.subprocess, "run", return_value=CompletedProcess([], 0)), \
                patch.object(runner, "capture_native_crashes", return_value={"state": "scanned", "files": []}) as capture:
            with self.assertRaisesRegex(ValueError, "no test report"):
                runner.run_target("DraftlyTests", self.expected, Path(self.folder.name))
        self.assertEqual(capture.call_count, 1)
        record = json.loads((Path(self.folder.name) / "process.json").read_text())
        self.assertEqual(record["nativeCrashReports"], {"state": "scanned", "files": []})
        self.assertEqual(record["verification"], "rejected")

    def test_crash_capture_excludes_old_unrelated_and_symlinked_reports(self):
        source = Path(self.folder.name) / "reports"; source.mkdir()
        destination = Path(self.folder.name) / "copied"
        good = source / "DraftlyTests-neutral.ips"; good.write_text("neutral crash fixture")
        old = source / "swift-test-old.ips"; old.write_text("old"); os.utime(old, (1, 1))
        (source / "OtherApp-neutral.ips").write_text("unrelated")
        (source / "xctest-link.ips").symlink_to(good)
        record = runner.capture_native_crashes(source, destination, 2)
        self.assertEqual(record["files"], [good.name])
        self.assertEqual(list(destination.iterdir()), [destination / good.name])
        self.assertEqual((destination / good.name).read_text(), "neutral crash fixture")

    def test_crash_capture_includes_the_swift_package_test_executable(self):
        source = Path(self.folder.name) / "reports"; source.mkdir()
        destination = Path(self.folder.name) / "copied"
        package = source / "DraftlyPackageTests-neutral.ips"
        package.write_text("neutral package crash fixture")
        (source / "OtherPackageTests-neutral.ips").write_text("unrelated")
        record = runner.capture_native_crashes(source, destination, 0)
        self.assertEqual(record["files"], [package.name])
        self.assertEqual((destination / package.name).read_text(), package.read_text())

    def test_crash_capture_is_bounded_and_handles_missing_directories(self):
        source = Path(self.folder.name) / "reports"; source.mkdir()
        destination = Path(self.folder.name) / "copied"
        for index in range(6):
            (source / f"DraftlyTests-neutral{index}.ips").write_text("neutral")
        with (source / "xctest-large.ips").open("wb") as file:
            file.truncate(2 * 1024 * 1024 + 1)
        record = runner.capture_native_crashes(source, destination, 0)
        self.assertEqual(len(record["files"]), 4)
        self.assertEqual(record["skipped"], 3)
        self.assertEqual(runner.capture_native_crashes(source / "missing", destination, 0)["state"], "unavailable")

    def test_delayed_ci_collection_uses_the_recorded_start_and_does_not_run_tests(self):
        record = Path(self.folder.name) / "DraftlyTests" / "process.json"
        record.parent.mkdir()
        record.write_text(json.dumps({"scope": "swift_cli", "startedAt": "2026-11-01T00:00:00+00:00",
                                     "verification": "rejected", "returnCode": 0}))
        with patch.dict(runner.os.environ, {"GITHUB_ACTIONS": "true"}), \
                patch.object(runner, "capture_native_crashes", return_value={"state": "scanned", "files": ["DraftlyTests-neutral.ips"]}) as capture, \
                patch.object(runner.subprocess, "run") as command:
            runner.collect_ci_crashes(Path(self.folder.name))
        command.assert_not_called()
        self.assertEqual(capture.call_count, 1)
        self.assertEqual(capture.call_args.args[2], 1793491200.0)
        updated = json.loads(record.read_text())
        self.assertEqual(updated["verification"], "rejected")
        self.assertEqual(updated["returnCode"], 0)
        self.assertEqual(updated["nativeCrashReports"]["files"], ["DraftlyTests-neutral.ips"])

    def test_delayed_crash_collection_refuses_local_execution(self):
        with patch.object(runner, "capture_native_crashes") as capture:
            with self.assertRaisesRegex(ValueError, "isolated CI runner"):
                runner.collect_ci_crashes(Path(self.folder.name))
        capture.assert_not_called()

    def test_inventory_ignores_build_noise_but_requires_unique_test_ids(self):
        output = "Building for debugging...\n" + "\n".join(sorted(self.expected))
        self.assertEqual(runner.test_inventory(output), self.expected)
        self.assertEqual(runner.test_inventory(output + "\nNewTests.Suite/newCase()"),
                         self.expected | {"NewTests.Suite/newCase()"})
        for bad in ["Build complete!", output + "\nDraftlyTests.Suite/first()"]:
            with self.assertRaises(ValueError):
                runner.test_inventory(bad)
