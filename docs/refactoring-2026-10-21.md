# Refactoring work — 21 October 2026

## Current scope

The user paused the cloning plan. This phase preserves behavior and improves
responsibility boundaries. Resume feature work only after the user resumes it.
The complete Mac plan remains open.

## Reference and saved functional work

- Stable commit: `a415883`.
- Annotated reference tag: `pre-refactor-2026-10-21`.
- Separate local branch: `agent/wip-action-lookup-2026-10-21`.
- Saved work commit: `35a790c`. It is not part of the refactoring base.

The saved work contains the `Action.find` duplicate-name correction, specific
lookup and installation tests, a native fixture, and related matrix updates.
The original worker test failed because a save could change the first action
among equal names. Its correction sorts equal names by UUID during reload.
The saved work passed 455 app and 504 core test methods, an unsigned Xcode
build, and a final focused run after the test files were separated. Its native
fixture has not run. Keep the correction separate from refactoring commits.
The stable base still has the known defect. A green base suite does not prove
that duplicate-name lookup is correct.

No test, build, or push process was active at the start of this phase. Engine,
Scale, Restore and Visual QA apps and the callback helper were running. They
remain available for a separate manual session.

## Baseline

| Check | Result at the stable base |
| --- | --- |
| Swift app tests | 455 methods, 76 suites passed |
| Swift core tests | 502 methods, 91 suites passed |
| Default Python discovery | Existing environment error: Pillow is missing |
| Python discovery with bundled runtime | 38 tests passed |
| Matrix structure | 0 errors |
| Strict engine parity | 18 existing diagnostics; acceptance remains open |

Raw logs are local in `/tmp`. Keep conclusions here and historical results in
[validation](validation.md). The [API matrix](research/action-api-matrix.json)
owns member acceptance. Refactoring must not change its classifications.

## Prioritized diagnosis

| Priority | Problem and example | Proposed stage | Risk |
| --- | --- | --- | --- |
| High | `LibraryStore` owns catalog membership, IDs, visibility and order in addition to persistence. See its `groupNames`, `actionGroupIdentifiers`, `actionGroupRecord` and `orderedActions`. | Move these rules to one pure `ActionCatalog` value. Keep the library facade and all current comparisons. | Low. Keep storage reload and its known duplicate-name defect unchanged. |
| High | `WindowModel.updateWorkspaceSort` and `WorkspaceOptionsEditor.setSort` both encode `_sorts`, title/name and descending order. `Workspace.scriptSort` reads that format. | Use one concrete sort mutation rule. Preserve unknown fields, flags, defaults and caller error policies. | Medium. Old metadata and property-observer order matter. |
| High | Status headings contain old current totals. README describes partial multi-file imports. The glossary excludes history from backups, but code includes it. | Correct the current summary and definitions. Keep historical validation and matrix evidence. | Low. Keep referenced historical headings. |
| High | `BookmarkFileAccessTests` writes `UserDefaults.standard`. `NativeFileAdapter` already accepts a defaults dependency. | Pass that dependency through the native host and use an isolated suite. Keep file and host-routing coverage. | Low to medium. No permission or real preference changes in tests. |
| High | Python and Swift both implement editor token-counting rules. The Python benchmark hardcodes native option bits. | Later, measure production Swift code headlessly. Retain unique OS callback diagnostics. | Medium. Do not delete diagnostic coverage as redundant. |
| Medium | Success-only legacy/worker dispatch repeats across action and workspace tests. | Share that dispatch in test support. Keep named cases, both variants and full-report assertions. | Low. Preserve matrix test references. |
| Medium | Import, execution bootstrap and configuration prompts repeat configuration-default rules. | Extract the concrete field descriptor after characterization. Preserve confirmation and disabled-step behavior. | Medium. Validation policies differ by entry point. |
| Medium | The API auditor combines source indexing, reference I/O, evidence policy and CLI handling. | Isolate its test-reference index with an explicit root. Keep CLI and diagnostics unchanged. | Medium. Compare strict diagnostics before and after. |
| Medium | Native operation inventories and dispatch routes are separate. Window and automation execution lifetimes have several owners. | Characterize routing and lifetime decisions before extracting concrete coordinators. | High. Preserve cancellation, busy, owner-close and cleanup behavior. |
| Medium | Text transformations in `EditorActionBar` combine UTF-16 rules with focus and save effects. Marker navigation also has its own Markdown rule. | Characterize transformations, then separate pure edits from UI effects. | Medium. Connecting shared syntax rules would be a separate functional correction. |
| Later | Transaction recovery and group normalization span `LibraryStore` and `LibraryRecordPersistence`. Legacy and worker orchestration also repeat decisions. | Extract small pure decisions first. Keep transaction and execution boundaries until their differences are characterized. | High. Avoid a generic repository or executor rewrite. |

## Small implementation stages

1. Preserve the functional work and establish the baseline. Correct current
   documentation without deleting history.
2. Extract the pure action catalog. Keep public methods, identities, ordering,
   persistence, formats and scripting behavior unchanged.
3. Isolate bookmark test preferences through the existing native-file boundary.
4. Share success-only test dispatch. Retain all named contract cases.
5. Review Workspace sort encoding as the next separate production subsystem.
6. Reassess configuration, auditor indexing, native routing, editing rules and
   execution boundaries using the diagnosis above.

Only one production subsystem changes at a time. Read-only reviews can run in
parallel. Each stage gets its own tests, build result and scoped commit.

## Test retention

Keep `OffscreenTestWindow` and injected native drivers. Automatic tests must
remain offscreen and must not request permissions, play sound or use personal
data. Computer Use belongs to a separate manual session when needed.

`CatalogActionAPITests` overlaps newer member tests, but also checks recent
identity after rename, ordered installation payload and configured values.
Keep that coverage. Host/driver and scripting tests also cover different
boundaries. Remove an assertion only after its replacement coverage is named.

## Resume cloning later

Read the stable API matrix and the saved functional branch before resuming.
The duplicate-name correction must be reviewed and merged independently; its
native acceptance remains pending. Review the saved code and tests separately
from its old status and matrix edits. Reconcile that evidence with the current
refactoring record instead of replacing current documentation with the WIP copy. Other Actions, engine, native integration,
inspector, workspace, visual, data and sync work remains in the Mac roadmap.

## Stage results

### 1. Pure action catalog

Implemented: internal immutable `ActionCatalog` owns available groups, group
identity lookup, visibility and presentation order. `LibraryStore` retains its
public methods and delegates to a fresh snapshot. There is no cache, protocol
or I/O in the catalog. Storage reload, transactions and the known duplicate
`Action.find` defect are unchanged.

Verified automatically: 455 app and 504 core methods passed. Two new pure
characterization methods cover supplied group order, first stored group,
implicit names, preferred positions, localized numeric names, UUID ties and
surface visibility. Existing persistence, restore, scripting and presentation
tests remain. Unsigned Xcode compilation passed. Matrix classifications are
unchanged; strict engine output matches all 18 baseline diagnostics exactly.

Manual verification: not required for this pure extraction. No visible window,
permission or sound check ran. Native parity acceptance did not change.

Next stage: isolate bookmark test preferences through the existing file adapter.

### 2. Isolated bookmark preferences

Implemented: `NativeActionHost` passes its existing file preferences and test
root through one computed file adapter. The default preferences remain
`.standard`. Bookmark removal uses the same dependency. All other host
dependencies and public scripting operations remain unchanged.

Verified automatically: 455 app and 504 core methods passed. The existing
bookmark integration method now uses a unique preferences suite and temporary
files on both host routes. It checks resolution, read, write, export, removal,
unrelated preference retention and retained input/output files. Test names
remain unchanged. Unsigned Xcode compilation and matrix structure passed.
No test was removed. No manual UI session was required.

Next stage: share success-only execution dispatch in test support. Preserve
all contract cases and leave report, cancellation and timing assertions explicit.

### 3. Shared success-only test execution

Implemented: `ActionTestExecution` owns the legacy/worker success dispatch in
test support. Seventeen call sites use it. Two duplicate local helpers were
removed. Full reports, timing, cancellation and transport tests remain explicit.

Verified automatically: all 455 app and 504 core methods passed. The four
changed suites retain all 25 named methods, including both routes in 15
parameterized methods. All 79 expectations and 19 requirements remain. No
fixture, script or test method was removed. The five original action fixtures
are unchanged. Matrix structure passed and strict engine diagnostics match
the baseline exactly. Production is unchanged from the stage 2 Xcode build.

The broad catalog integration test remains because its recent-action identity,
ordered installation and configured-value assertions have distinct coverage.
No manual UI session was required. Next: characterize Workspace sort writers
before moving their shared dictionary mutation.

### 4a. Workspace sort characterization

Before production changes, four new methods covered 15 sort-state cases.
The window retains missing/invalid/non-object metadata unchanged. Valid edits
preserve outer and unknown fields, other folders and existing flagged values.
Folder observers restore the saved sort and direction. The options editor
keeps its different recovery policy and sorted JSON encoding.

All 19 methods in the four relevant workspace suites passed on the original
writers. Tests use in-memory data and isolated preferences, without windows.
Next: move only shared dictionary mutation to WorkspaceOptionsEditor. Keep
parsing, encoding and error policy at each caller.
