# Editor text mutation refactoring — 22 October 2026

## Scope and base

This stage implements R3 from the modularity audit. The base is 15d1610, the
completed editor styling stage. The attached worktree and primary checkout
were clean. No build or test process was active. Main remains at 5494342.
Previous branches and the usual app remain unchanged.

The branch is agent/editor-text-mutation-2026-10-22. The annotated reference tag
pre-refactor-editor-text-mutation-2026-10-22 points to 15d1610. Its annotation
records the baseline timing failures. No production edit preceded the baseline.

## Diagnosis

updateNSView and synchronizeScriptEdit both clear Undo for a changed draft,
remember the new identity, register the previous text and selection for a
same-draft edit, and assign session content. Each route implemented these rules.
A correction to this mutation could therefore require two changes.

A broad shared update operation would erase intentional caller policies. The
small boundary is Coordinator.replaceSessionText(in:changedNote:). It receives
the actual text view and the route's draft-change decision. It returns whether
it assigned content. It does not apply styles, select text, scroll, request focus,
publish changes or decide whether a route can run.

## Route behavior table

| Decision or effect | updateNSView | synchronizeScriptEdit |
| --- | --- | --- |
| Parent | Updates the coordinator parent first | Uses the current parent |
| Reentry | Sets updating for the update and restores it on exit | Returns if updating; otherwise sets and restores it |
| Draft change | Different identity or empty style cache | Different identity only |
| Shared mutation | Clears history and records identity on draft change; registers prior text and selection only for a same-draft text change; assigns different content | Same mutation, using its own draft-change decision |
| Styling | On text, style or draft change; updates cached theme and style | On text change only; does not update those caches |
| Display invalidation | On text or draft change | On text change only |
| Final selection | Sets and scrolls only when the safe range differs | Always sets the safe range; adds no explicit scroll |
| Focus | Updates focus token and requests focus only when active | Does not update the token or request focus |
| Change callback | No new callback during synchronization | No new callback during synchronization |
| Undo/Redo | Uses the existing restore operation | Uses the same existing restore operation |

The helper stays inside the coordinator. restore is unchanged, including its
inverse registration, session update, safe selection, highlighting, display
invalidation and callback order. No framework, protocol or new result type was
needed. The route guards and post-mutation sequences remain explicit.

Public APIs, Note, identities, scripts, formats, backups, styles and native find
behavior have no changes. No functional defect was repaired in this commit.
No project regeneration was needed: the only production edit is EditorView.swift.

## Characterization and tests

EditorTextMutationTests adds four methods with nine route cases. They passed
against the original code before extraction:

- shorterUnicodeEditRestoresTextAndSelectionThroughUndoAndRedo covers a shorter
  Unicode replacement, a safe view selection from an invalid requested range,
  a text no-op with a selection update, inverse registrations and callback count.
- loadingAnotherDraftClearsUndoAndKeepsRouteSpecificHighlighting covers equal
  and different content on a new identity. It checks that only the view route
  reapplies attributes when identity changes without a text change.
- emptyStyleCacheClearsHistoryOnlyInViewRoute checks the distinct draft-change
  policy and focus-token handling. The hidden editor is inactive, so no focus
  request is sent. A token change causes an actual representable update.
- scriptReentryLeavesTextSelectionHistoryAndIdentityUntouched checks the script
  guard and its next allowed update.

The fixture uses the real SwiftUI binding route in an OffscreenTestWindow, or a
text view with the real script coordinator. Each route keeps its own Undo manager.
It disconnects callbacks, delegate, text view and host explicitly. It does not
replace the existing script Undo fixture or combine different grouping policies.
No existing test was renamed or removed.

During fixture preparation, Swift rejected a private parameter type in an
internal test method. The route enum now has test-module visibility. A first
cache test also exposed a fixture assumption: assigning an identical SwiftUI
root does not force updateNSView. The test now changes the observed focus token.
These corrections preceded the passing characterization and production edit.
They were not production failures.

After extraction the focused run passed 79 methods in 11 suites. It includes
native editor bindings, redraw, styles, property contracts, scripting, range
Undo, automation context and advanced replacement. Complete final verification
is recorded below after the source and tests were frozen.

## Baseline verification

The initial concurrent Core674 run failed with three issues in two known cases:
AsyncHostDrainTests.scriptRequestKeepsLibraryBusyUntilCancelledHostCleanupReturns
(timeout: true) did not start its host before the deadline;
XMLRPCAsyncTests.actionInterruptionCancelsTransportAndStopsLaterSteps
(cancelled: false) did not reach its transport before timeout. These failures
precede all changes. Both risks were already recorded in previous stages.

A separate serial run of those two suites passed nine methods. The baseline app
suite passed781 with matching XML inventory. Python80 and the local Debug build
passed. No timeout, retry wrapper or scheduling rule was changed. A common cause
for the two timing failures is not established.

## Final verification

The complete final run passed Core674 and app785 with matching XML/discovery
inventories. The 79 focused methods and Python80 passed. The local Debug build
passed. The structural matrix has zero errors. The strict engine gate still has
six partial contracts and 18 diagnostics, outside this refactoring's scope.

Source and tests stayed fixed during the complete final run. Build and Swift
tests did not overlap. The initial timing failures did not recur in the final
run. They remain recorded risks, not resolved defects. No longer limit or retry
was added. Outputs use /tmp/draftly-text-mutation-*. No raw logs or screenshots
are versioned. Diff checks passed.

## Native verification and continuation

All automatic tests stay in memory or use hidden hosts and neutral data. They
do not show, activate or move windows, request permissions, play sounds or use
personal data. No manual Computer Use session is needed for this internal
extraction. This is not new visual parity, native feature or iCloud acceptance.
No QA app was installed and the usual app was not replaced.

R1 through R5 are implemented as bounded refactoring stages on stacked branches.
Main does not contain them until integration. Resume functional cloning from the
inspector, Workspaces, Settings and personalization work in the handoff, or make
a separate diagnosis before more refactoring. Strict engine acceptance and the
baseline timing risks remain independent. This stage does not complete Draftly.
