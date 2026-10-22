# Advanced Find refactoring — 22 October 2026

## Reference and base

The clean reference is 11e8955. Main matched origin/main. The annotated tag is
pre-refactor-find-2026-10-22. No earlier work was discarded. No build, test or
QA process was active at the start. The installed app remains unchanged.

Before editing, complete serial runs passed 650 app and 650 Core methods.
Separate fresh reports match all 1,300 discovered identities. All 68 Python
tests and the local Xcode build passed. Logs and reports stay in /tmp under
draftly-find-refactor-*. Earlier concurrent worker and window-opening timing
risks remain recorded. No retries or production timeout changes belong here.

## Accepted boundary

AdvancedFindView currently renders fields and results and also performs editor
selection, navigation, replacement, synchronization and saving. Extract only
those commands into AdvancedFindCommands. Keep query options, bindings, errors,
result previews, focus and dismissal in the view. EditorFindQuery remains the
existing matching and replacement engine. No public API or new search engine
is needed.

Preserve current behavior:

- Navigation uses UTF-16 ranges and the safe editor selection. Previous uses
  a strict comparison with the selection start. Next starts at the selection
  end and excludes an identical match. Both directions wrap.
- A zero-length match advances without adding a character offset. A single
  zero-length match can select itself again. No results cause no effects.
- Selecting a result synchronizes the editor without saving or changing focus.
- Replace All updates content, clamps selection, synchronizes, reports the
  change and flushes, in that order. Invalid queries do nothing. A valid query
  with no matches still follows the existing command sequence if called; the
  view separately disables its button.
- A failed save retains changed editor text, the error and unsaved state.
  It does not add rollback. Undo and Redo keep their current native bridge.

The domain model is unchanged. Search acts on the current draft, not on the
draft-list selection. Native find and preferAdvancedFind routes stay unchanged.
No stored schema, backup format, identity, syntax rule or script changes.

## Stages

1. Extract the commands and characterize navigation, zero-width results,
   Unicode selection, empty results and isolation between editors. Run affected
   tests and local compilation before the scoped implementation commit.
2. Characterize replacement order, literal and regex results, persistence,
   failures and native Undo/Redo. Reuse only the existing offscreen Undo fixture
   and disconnect it explicitly. Keep existing contract test names.
3. Verify complete Swift reports against inventory, Python tests and matrix
   structure. Run local compilation without overlapping Swift tests. Perform a
   separate isolated manual QA check. Update architecture, status and handoff.

## Results

1. Commands extracted. Four characterization methods cover forward/backward
   boundaries, wrapping, zero-width matches, missing/invalid results and current
   editor isolation. All 34 affected app methods and five Core query methods
   passed. Local Xcode compilation passed. Independent review found the command
   comparisons and effect order unchanged. Query state, previews and focus stay
   in the view. Replacement integration and manual checks are next.

The accepted functional and compatibility backlog remains separate.
