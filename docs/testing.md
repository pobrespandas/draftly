# Test structure

Updated: 19 October 2026.

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

`TestUndoTextView` supplies the same Undo manager to three app test suites.
Each suite retains its own editor setup and grouping rules.
Do not combine fixtures when the setup is part of the behavior under test.

## Duplicate cases removed

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
process-wide state and concurrent app reports remain unreliable. Core tests run
concurrently. Tests still exercise their explicit concurrent tasks. The runner
never retries a failure. Use `--concurrent-app` for the open diagnostic case.
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

## Refactoring acceptance

The API suite split preserved all cases except the three duplicates above.
Test discovery was compared with the previous commit. All 542 test references
in the API matrix resolve. Compatibility classifications and the five original
action fixture files are unchanged. Production code and package targets are
unchanged.

Automatic checks passed: 170 app tests in 29 suites, 264 core tests in 33 suites,
24 Python tests, the normal matrix check, and the whitespace check.
No visible UI or cloud acceptance ran. Strict parity remains pending.

## Core command boundary acceptance

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
