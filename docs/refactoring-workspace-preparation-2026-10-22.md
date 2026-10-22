# Workspace preparation refactoring — 22 October 2026

## Reference and diagnosis

This stage implements R4 from the modularity audit. Its reference is b39c643,
which includes the validated R1 completion context. The worktree was clean and
no build or test process was active at the start. The branch is
agent/workspace-preparation-2026-10-22. The annotated reference tag is
pre-refactor-workspace-preparation-2026-10-22. No prior work was removed.

WindowModel.applyScriptWorkspace and saveAndApplyWorkspace repeated the same
reference resolution and external-theme file validation. A future preparation
change could reach only one entry point. Their later effects are different,
so a common apply/save/cancel pipeline would be unsafe.

## Implemented boundary and preserved effects

WindowModel now has one private prepareWorkspace operation. It calls the
existing WorkspacePresentationResolver, validates external theme files through
the existing validator, and returns the resolved Workspace. Both entry points
use it. No new service, resolver, protocol or state object was added.

| Entry point | Existing sequence, preserved by this change |
| --- | --- |
| applyScriptWorkspace | Prepare, then apply. It does not add action cancellation or save the definition. |
| saveAndApplyWorkspace | Prepare, save the resolved definition, call the existing user-edit cancellation helper, then apply. A preparation or storage error stops later effects. |
| apply | Call the existing user-edit cancellation helper first, then use the script application route within the existing error wrapper. Invalid preparation still follows cancellation. |

The cancellation helper itself is unchanged, including its arrangement cleanup,
script-command guard and pending/running checks. It remains in its callers.
Published window changes stay in applyResolvedWorkspace. Reference resolution,
unknown metadata, sort observers, local list preferences and per-folder order
keep their existing rules.

Preparation is not a new pure resolver. ThemeFileAccess.read retains its current
local bookmark behavior, including possible stale-bookmark refresh. This stage
adds no rollback, permission prompt, new message or new error policy. No public
API, Note identity, stored format, backup, syntax, editor selection or Undo
implementation changed. No project generation was needed: production stayed in
an existing file and SwiftPM discovers the new test file.

## Characterization and automatic verification

Before editing, the complete baseline passed Core674/app773 with XML results
matched to discovery. The local Debug build passed. The reference tag was then
created. The prior XML-RPC timing risk did not recur and remains separate.

WorkspacePreparationOrderTests passed against the original implementation before
production extraction. It has four methods and nine expanded cases:

- savingCommitsBeforeCancellationAndAppliesAfterCancellation observes the commit
  hook, stored-workspace publication and folder publication. The definition is
  committed before cancellation; application sees cancellation already set.
  It also checks resolved group identity, unknown metadata and editor state.
- scriptApplicationDoesNotSaveOrCancelPendingAction checks the distinct script
  policy while the window has pending work.
- preparationFailurePreservesEachEntryPointsCancellationOrder covers all three
  entry points with a missing group and a file theme without a local bookmark.
  No write occurs. Only the window apply route cancels. The missing-group case
  also has an inaccessible file theme, so reference failure keeps precedence.
- storageFailureDoesNotCancelOrApplyThePreparedWorkspace injects a commit error
  and checks that cancellation and application do not run.

The tests use the existing actionPending and actionTask fields with a controlled
pending task. They observe synchronous task cancellation, not a simulated final
Action execution report. Cleanup cancels and awaits the task, clears commit
hooks, and removes the isolated preference suite. Libraries are in memory.
No action script, native capability, visible window or personal data is used
by these four methods. No existing test was removed or renamed. Existing disk,
backup, retry, sorting, theme and real runner interruption tests remain separate.

The first new fixture compilation inferred Task<()?, Never> from try?. The
fixture was corrected to Task<Void, Never> before characterization. This was a
new test setup error, not a production failure. No timeout or retry rule changed.

After extraction:

- Focused checks passed 45 app methods in nine suites and six Core methods in
  one suite. These include Workspace contracts, sorting, persistence, themes
  and existing action interruption coverage.
- Complete Swift passed Core674/app777. XML results matched all discovered test
  identities. Source files stayed frozen during the complete run.
- All 68 Python tests passed.
- Local Debug compilation passed after Swift testing finished.
- Structural API matrix and diff checks passed.
- The strict engine gate retains six partial contracts and 18 diagnostics.

There was no new unresolved regression. Test totals are regression evidence,
not a new compatibility acceptance. Raw outputs stay in
/tmp/draftly-workspace-r4-* and are not tracked.

## Native verification and continuation

No new manual native session was needed for this private extraction. Existing
resolvers and window effects did not change. Automatic tests observe real model
publications without opening windows. They do not accept native permission
transfer, backup restoration through UI, or full Workspace parity.

No QA app was installed or launched. The usual Draftly app and its data stayed
unchanged. Main was not advanced by this task. The stage is published on its
isolated branch, based on R1. Update the local handoff with its commit.

R1 and R4 are implemented. The next proposed stage is R5: make Cloud QA preparation
callable and directly testable, with no import-time file write. R2 styling and
R3 text mutation remain unimplemented. Functional cloning, native capability
acceptance and the prior XML-RPC timing risk remain separate.
