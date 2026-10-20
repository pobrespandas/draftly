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

Run `swift test` for app and core tests. Run Python tool tests with
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
