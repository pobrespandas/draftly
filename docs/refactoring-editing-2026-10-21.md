# Inspector and personalization refactoring — 21 October 2026

## Reference and baseline

Cloning is paused for this behavior-preserving delivery. The reference is
20ddcf1. Annotated tag: pre-refactor-editing-2026-10-21. The tree was clean and
main matched origin/main. Existing WIP branches remain unchanged. Only the
installed main app was running. No prior build or test process was active.

The local Xcode build passed. The checked Swift runner verified 630 core and
539 app methods. All 67 Python tests passed. Logs remain outside Git in /tmp.
An earlier run overlapped a build and failed the timeout case in
AsyncWindowOpeningTests.cancellationAndTimeoutDrainTheOpeningWaitBeforeReturning.
The focused run and the complete run without a concurrent build passed.
The test assumes that its host starts before a real five-second deadline.
Production rejects a request that expires before host dispatch. This is a
pre-existing timing risk, not evidence of a refactoring regression. Keep the
contract assertion. Do not mask it with retries or a larger timeout.

## Accepted diagnosis

1. ActionEditor owns step defaults, add, remove, move and selected-step state
   inside its SwiftUI form. Extract ActionEditingCopy. Keep save, export,
   shortcut validation and dismissal in the view. Preserve imported data and
   exact selection rules. Risk: bindings, payloads and selection can change.
2. EditorLayoutPreferences coordinates library writes, local preferences and
   file bookmarks in view closures. Extract concrete InstalledThemeCommands.
   Keep panels, confirmation, errors and the temporary theme in the view.
   Preserve effect order, including a saved theme after selection fails.
3. Editor Settings and Workspace Settings repeat theme option construction.
   Share pure options. Keep their different selection tags, stored references,
   missing-reference behavior and resolution policies.
4. AppThemeContractTests and AutomationEditorContextTests repeat the same
   offscreen editor and Undo connection. Share only that fixture variant and
   add explicit disconnection. Keep names, assertions and grouping rules.

ActionCatalog and inspector field descriptors already have clear owners.
Action, group and Workspace reorder policies differ. No generic reorder layer,
script rewrite, test deletion or historical document deletion is justified.

## Contracts and retained backlog

Keep Note, public APIs, action and step identities, unknown imported fields,
original scripts, library and backup formats, preferences, editor state, Undo,
Nerd Fonts and the integrated preview. New types are internal app or test types.

The per-view Workspace sort-state mismatch, list-option fallbacks and unsaved
Workspace presentation are functional follow-ups. Visibility differences and
platform execution semantics remain open. Do not fix them in this delivery.
No identity, signing, iCloud or installed-app replacement belongs to this work.

## Stage results

1. Action editing copy: implemented. ActionEditingCopy owns the temporary action,
   step selection and unchanged step operations. The view keeps save, export,
   shortcut checks and dismissal. Seven new characterization methods cover all
   current step defaults, imported and disabled data, identity, selection,
   removal, movement and explicit persistence. All 24 affected methods passed
   across editing-copy, inspector-fields, catalog and import suites. Local Xcode
   compilation and matrix structure passed. Native bindings remain pending.

2. Theme commands: implemented. InstalledThemeCommands owns the existing
   save/select, install/select, reload/select and delete/bookmark sequences.
   EditorLayoutPreferences retains dialogs, confirmation and temporary edits.
   Eight new methods cover imported data, slots, save/install/delete failures,
   retained effects after selection failure and bookmark ownership. All 23
   affected methods passed across command, preference, file application and
   import suites. Local Xcode compilation passed. Independent review found no
   behavior change. Native theme bindings remain pending.

3. Theme options: implemented. ThemePickerOptions supplies ordered labels,
   identity and references to both views. Editor tags and Workspace tags remain
   distinct. Three new methods cover exact representations, Unicode, homonyms,
   file labels and rename-stable identity. All 16 affected methods passed across
   picker, preference and Workspace suites. Local Xcode compilation passed.
   Independent review found no behavior change. Native picker checks are pending.

4. Offscreen editor fixture: implemented. ScriptUndoEditorFixture owns the
   shared connection and explicit disconnection for only AppThemeContractTests
   and AutomationEditorContextTests. Fonts, callbacks, content, test names and
   assertions stay in their consumers. Conditional grouping variants remain
   separate. No tests were removed. All 21 affected editor/Undo methods passed
   across five suites. Local Xcode compilation passed.

Full integration and the manual inspector/theme session remain pending.
Automatic checks stay headless and use temporary data. Run compilation and
tests separately. Native checks use a separate manual session and neutral data.
Keep raw captures, logs and generated QA packages outside Git.

## Closure

Each stage has its own scoped Conventional Commit and validated push. Update
this record and the local handoff after each stage. Full Swift and Python runs
and a local build accept integration. Native inspector and theme checks remain
separate from automatic results. This delivery does not close Draftly parity.
Resume the retained inspector, Workspace, Settings and personalization backlog
only when feature work resumes.
