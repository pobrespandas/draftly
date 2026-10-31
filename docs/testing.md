# Testing Draftly

Updated: 31 October 2026.

## Run the checks

Run commands from the repository root. Use the [development guide](development.md)
for Xcode requirements and local app builds.

For the complete Swift checks:

```sh
python3 scripts/run-swift-tests.py
```

The runner checks that every discovered test has a result. It reports failures
and incomplete runs instead of treating a successful process exit as enough.
Tests use temporary data and offscreen editors. They must not open or move
visible windows, request permissions, play sounds, or use personal data.

For Python checks, use Python 3.12, as CI does, in a separate environment:

```sh
python3.12 -m venv .build/test-venv
source .build/test-venv/bin/activate
python -m pip install 'Pillow>=10,<13' 'cryptography>=44,<46'
swift package resolve
python -m unittest discover -s scripts -p 'test_*.py'
```

Resolving packages supplies the pinned Sparkle tools used by signature tests.
For website changes, also run:

```sh
node --test website/release.test.mjs
```

Automated tests do not prove that native services or synchronization work on
a real Mac. Use [manual QA](manual-engine-qa.md) for those separate checks.
The sections below explain fixture boundaries and retain dated test records.

## Boundaries

Core scripting API tests are in `Tests/DraftlyCoreTests/Actions/API`.
Each file covers one API area. Test names stay stable when a test moves.
The API matrix points to the suite and test that assert each contract.
A suite result does not prove every member of its API.

Core support code is in `Tests/DraftlyCoreTests/Support`.
`ScriptTestFixture` connects an isolated library, editor, host, and runner.
`ScriptTestAction` builds scripts with the shared assertion helper. Tests can
supply a local script helper when the contract needs it.
`APIContractHost` supports the API contract suites. Other hosts stay separate
when their allowed operations, failures, or callback order differ.
`TestPreferences` creates a unique preferences domain. Each test calls `close()`
in `defer` to remove that domain.

`TestUndoTextView` supplies a stable Undo manager to offscreen editor tests.
`ScriptUndoEditorFixture` connects that text view, coordinator and script callbacks
for AppThemeContractTests, AutomationEditorContextTests and
AdvancedFindReplacementTests. Each consumer calls `close()` in defer to
disconnect callbacks and remove Undo actions. Each caller
keeps its font, content and change callback. Other suites retain their own setup
and grouping rules. Do not combine fixtures when setup is part of the contract.

ActionEditingExecutionFixture shares only the windowless library, Unicode
source, selection and runner for Prompt and Create Draft editing flows. It
retains an optional host because the runner holds that host weakly. Each suite
keeps its own action definitions, assertions and save checks. Configuration,
Workspace and Undo fixtures retain their different responsibilities.

## Historical duplicate cases removed

These cases repeated checks in `DraftVersionContractTests`. Their matrix
references now point to the retained tests. No contract status changed.

| Removed test | Retained test in DraftVersionContractTests |
| --- | --- |
| versionCreatedAtIsATypedReadOnlyTimestamp | versionPropertiesHaveStableReadOnlyValuesAndTheCurrentDraftRelation |
| versionDeleteReturnsVoidAndRemovesOnlyThatRevision | versionDeleteReturnsVoidAndPersistsOnlyTheChosenDeletion |
| versionDeleteStorageFailureThrowsAndRestoresTheRevision | versionDeleteFailureThrowsAndPreservesHistoryAfterAnUnrelatedCommit |

The retained cases check typed dates with millisecond precision, read-only
values, deletion results, unchanged content, storage failure, and restored
history. The failure case also checks an unrelated later commit. Snapshot
persistence, unique identities, missing relations, Unicode, and range limits
remain separate cases. Similar names alone do not establish duplication.

## Background execution

Run `python3 scripts/run-swift-tests.py` for a complete app and core run. The
runner compares discovered test identities with fresh xUnit results. It rejects
missing, duplicate, failed, skipped, or unexpected results even if Swift exits0.
Each target gets a fresh report. AppKit tests run serially because they share
process-wide state and concurrent app reports remain unreliable. Core tests also run serially by default. Earlier concurrent worker timeouts remain recorded in
[project status](status.md). To compare this refactoring with its serial base,
run each target with `swift test --no-parallel --filter TARGET --xunit-output
/tmp/UNIQUE-TARGET.xml`. Keep target reports separate; a combined command can
overwrite the report from another test process. Use the runner's
`test_inventory` and `verify_results` functions to compare both fresh Swift
Testing reports against `swift test list --skip-build`. Do not change timeouts
or retry failed tests to obtain a passing result. Tests still exercise their
explicit concurrent tasks. The runner never retries a failure. Use `--concurrent-app` for the open diagnostic case.
The inventory checks test methods; parameter cases depend on Swift Testing's
reporter and do not have a separate discovery inventory.
Use `--output-dir /tmp/draftly-tests` to retain logs and XML outside the repo.
The default removes temporary files after success and keeps them after failure.
Use direct `swift test --filter ...` for a
focused check; a focused result does not accept the complete suite.

Run Python tool tests with
`python3 -m unittest discover -s scripts -p 'test_*.py'` in the configured runtime.
Run `python3 scripts/audit-action-api.py --check` to check the matrix.

Tests must not show, activate, or move visible windows. AppKit layout fixtures
use `OffscreenTestWindow`, which rejects ordering and activation. Use
`TestMainQueue` to wait for queued work. Do not replace assertions with sleeps.
Visible animation checks require a separate manual session.

## Advanced Find refactoring check — 22 October 2026

AdvancedFindCommandTests checks selection, navigation, zero-width results,
empty results and editor isolation. AdvancedFindReplacementTests checks effect
order, saved content after reopening a temporary store, save failure and retry,
invalid queries, valid empty/no-match commands and native Undo/Redo. The tests
create no windows. Native synchronization uses the existing Undo fixture with
explicit initial selection and cleanup. Core query tests remain separate.

Complete serial reports match 660 app and 650 Core methods. All 1,300 baseline
method identities remain; ten methods were added. All 68 Python tests, local
compilation and matrix structure checks passed. Manual Advanced Find/native-find
regression checks ran separately. See the
[refactoring record](refactoring-find-2026-10-22.md) for scope and limits.

## Option refactoring check — 22 October 2026

The complete serial reports matched 650 Core and 650 app method identities.
All previous methods remain. Three step-value characterization methods and one
XML-RPC exit-event regression were added. No tests were removed or renamed.
The XML-RPC fixture now registers process termination before launch and retains
that event. Its bounded test-only wait reports a missing exit instead of hanging
in Process.waitUntilExit. The earlier incomplete run remains in the
[refactoring record](refactoring-options-2026-10-22.md). No production timeout,
concurrency policy or automatic retry changed. The manual check is separate.

## Historical test-refactoring acceptance — 19 October 2026

The API suite split preserved all cases except the three duplicates above.
Test discovery was compared with the previous commit. All 542 test references
in the API matrix resolve. Compatibility classifications and the five original
action fixture files are unchanged. Production code and package targets are
unchanged.

Automatic checks passed: 170 app tests in 29 suites, 264 core tests in 33 suites,
24 Python tests, the normal matrix check, and the whitespace check.
No visible UI or cloud acceptance ran. Strict parity remains pending.

## Historical Core command boundary acceptance

ScriptCommandTests adds seven boundary cases. They cover missing and wrong-type
values, query defaults and invalid options, UTF-16 limits and integer overflow,
selection clamping, save-before-load ordering and save failure, error priority,
and unchanged forwarding to native capability adapters. These tests do not
replace the existing scripting contracts or native Undo tests.

After this change, 170 app tests, 271 core tests, and 24 Python tests passed.
The local Xcode build passed with signing disabled. The normal matrix check
reported zero errors. No visible app or cloud acceptance ran.

## Async engine regressions

The five original action cases now run against both legacy and async entry
points with the same scripts and assertions. Worker tests cover cancellation and
late host replies. Async runner tests cover CPU responsiveness, typed timeouts,
queues, shared dynamic includes, unknown steps, and concurrent text preservation.
App tests cover scheduling, batch results, URL validation, and user or external
edits during a wait. They do not open visible windows.

HTTP uses an isolated URLProtocol fixture. Those tests do not establish socket or
redirect acceptance. The auditor requires fourteen engine contracts and rejects
missing, duplicate, or unnamed records during strict parity checks.
