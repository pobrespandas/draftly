# Editor completion context refactoring — 22 October 2026

## Reference and scope

The reference is 5494342, which already contains the design-system documentation
and the local audit commit. Main matched origin/main at the start. The worktree
was clean and no build or test process was active. No previous work was removed.
The isolated branch is agent/editor-completion-context-2026-10-22. The annotated
reference tag is pre-refactor-completion-context-2026-10-22.

This stage implements R1 in the modularity audit. NativeEditor used its Touch Bar
model to obtain the current draft and candidate drafts for syntax completion.
That dependency joined unrelated responsibilities. The change adds an explicit
completion context and keeps Touch Bar configuration separate. It does not
change syntax rules, editor synchronization, Undo, persistence or public APIs.

## Implemented boundary

EditorCompletionContext contains currentDraft and drafts. Its completion method
keeps the existing construction order: use the supplied draft or create a draft,
replace its content with the callback source, override its identity only when
the session has a note ID, then call SyntaxDefinition.completion. Core remains
the authority for matching, ordering, templates and UTF-16 ranges.

NativeEditor accepts an optional MainActor context provider. It calls the
provider for each completion request after the existing session/syntax guard.
Without a provider it uses no current draft and an empty candidate list, as
existing standalone editors did. It keeps the existing weak-session guard and
view/callback structure. This stage does not redesign callback retention.

EditorBody supplies a weak-model closure that reads currentNote and library.notes
at invocation time. It does not cache those values when the view is created.
The callback no longer reads touchBarModel for completion. That model remains
only for configuring the custom Touch Bar. The two model-supplying Touch Bar
test constructors now supply the same explicit context. Existing call sites
without a model keep the empty-context behavior.

The generated Xcode project adds only the new source file, its build reference
and entries in the existing source group and build phase. Regeneration produced
the same contents. No build setting, identity, entitlement or scheme changed.

## Automatic verification

Before production edits, the complete baseline passed 674 Core and 767 app
methods, with XML reports matched to discovery. The local Debug build passed.
The earlier XML-RPC pre-transport timeout did not recur. It remains a prior risk;
no timeout, retry or concurrency policy changed here.

Three new characterization methods passed against the original implementation:

- installedCompletionCallbackReadsCurrentLibraryAtInvocation verifies updated
  library candidates and current-draft exclusion through the installed callback.
- installedCompletionCallbackRendersLiveSourceAndSessionIdentity verifies
  custom template completion, live Unicode source, the session ID and a new
  fallback identity when no saved ID or current draft exists.
- installedCompletionCallbackKeepsMissingSyntaxAndSelectionBehavior checks
  missing syntax, non-caret selection and an empty standalone candidate list.

The characterization suite passed 13 methods before extraction. The first case
then moved from the implicit model dependency to the explicit provider; its
name and behavioral assertions remain unchanged.

Three further methods check the new boundary through the installed callback:

- explicitCompletionContextIsLazyAndIndependentOfTouchBar checks that view setup
  does not read the provider. Consecutive calls see changed context without a
  view rebuild. An unrelated Touch Bar model cannot supply candidates or change
  the supplied context. Session identity still excludes the current draft.
- completionContextPreservesDraftMetadataWhenSessionHasNoID checks the supplied
  draft identity, tags, source override and a later session-ID override. Neither
  the supplied draft nor editor content is mutated by a request.
- missingSyntaxDoesNotReadTheCompletionContext checks the existing early exit.

The fixture owns a neutral offscreen hosting view. Cleanup disconnects session
callbacks and removes its content view. It does not show, activate or move a
visible window. The two real-library tests use in-memory storage and isolated
UserDefaults suites. No test name or existing assertion was removed.

Final results:

- Focused completion, Touch Bar, theme, Undo and replacement checks: 56 methods
  in eight suites passed.
- Complete Swift: 674 Core and 773 app methods passed. XML reports matched the
  complete discovered inventory. Source files stayed frozen during this run.
- Python: all 68 tests passed.
- Local Debug compilation passed after Swift tests finished.
- Structural API matrix and diff checks passed.
- Strict engine check retains six partial contracts and 18 diagnostics.

The unchanged totals of native and API acceptance remain separate from these
regression results. No compatibility status or archived reference changed.
Raw logs and reports remain in /tmp/draftly-completion-r1-* and are not tracked.

## Native verification and limits

No new native manual session was needed. The tests exercise the installed
NSViewRepresentable callback, not only the context value. Existing Touch Bar
preference and command tests still exercise their offscreen bindings. No system
capability, visible presentation or permission flow changed. No QA app was
installed or launched. The usual Draftly package and its data stayed unchanged.
There is no new real-device acceptance claim.

The base and final full runs passed without retries. The prior XML-RPC timing
risk remains separate. No new unresolved regression was observed. This stage
adds no custom syntax feature, native integration or UI parity acceptance.

## Continuation

R1 is complete in this branch. Update the local handoff with the published
commit and branch. The next proposed refactoring is R4: share Workspace
preparation while preserving the different save and cancellation sequences.
R2 styling, R3 text mutation and R5 Cloud QA preparation remain unimplemented.
Functional cloning work and strict engine checks remain separate.
