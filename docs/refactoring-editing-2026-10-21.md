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

## Integrated automatic results

The checked runner verified 630 core and 557 app methods. All 1,169 baseline
method identities remain. Eighteen characterization methods were added; none
was deleted or renamed. All 67 Python tests passed. Matrix structure has zero
errors. The final local Xcode build passed. No build overlapped a Swift test run.
The pre-existing deadline test passed in this integration run. Its earlier
failure remains recorded above; this delivery does not change engine timing.

Core models, storage, backup definitions, scripting, original action fixtures,
capability code, signing configuration and identifiers have no diff from the
reference. The Xcode project only registers the three new internal app sources.
The matrix and compatibility classifications are unchanged. Passing test totals
do not prove Drafts parity.

## Manual results

Computer Use ran after automatic tests finished. It used a fresh temporary app,
preferences domain and local library. The package published no Services or URL
schemes. CloudKit and global capture shortcuts were disabled for that session.
The habitual signed installation was neither opened by this check nor replaced.

Verified in use:

- Actions: add a clipboard step with its current default, edit its text, move it
  before the script step, delete it and observe the first remaining selection.
  Cancel leaves no new action. Save and reopen preserve name, script and disabled
  state. Rename and toggle followed by Cancel preserve the saved values.
- Themes: cancel a new theme and confirm its absence. Save a custom theme and
  reopen its color. Cancel an edit and confirm the prior name and color. Rename
  and save while keeping selection. Install and select a neutral file theme,
  then invoke Reload without an error. Built-ins precede installed themes;
  only file themes have the existing File suffix.
- Workspaces: show the same labels plus No Override. Select a file theme, save,
  and reopen with that selection. Cancel a rename and retain the saved name.
  The first batched select/name/save gesture did not retain the theme; it is not
  credited. Explicit select, observe, save and reopen passed. No production
  defect was established from the batched gesture.
- Editor: neutral Unicode text remains after organization and theme changes.
  Undo removes the typed tail; Redo restores it. No personal data was used.

Storage failures and partial effects have automatic characterization. They were
not induced in the manual session. This is a refactoring regression check, not
new acceptance of the full inspector, native integrations or Drafts parity.

QA quit normally. Its exact registration was retired. Its package, exported
preferences, file fixture and closed library were moved together to recoverable
Trash under DraftlyRefactorQA-95wjducz. No QA installation or process remains.
No screenshots or raw logs were added to Git.
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

## Final outcome and resume point

All four accepted changes are complete. No new regression was observed in the
checks above. Each implementation stage has a scoped commit and validated push:
d5b1b3f (editing copy), 548576c (theme commands), ae9573b (theme options), and
d368d48 (test fixture). The reference tag is published. The final documentation
commit records integration and manual results. Existing WIP branches remain.

Cloning remains paused. When requested, resume the Workspace per-view sort-state
mismatch: visible rows use Workspace.scriptSort while model labels can start
from top-level sort fields. Reproduce it in WorkspaceSortStateTests and fix it
in a separate functional commit. Then address list defaults and unsaved Workspace
presentation, followed by pending inspector, Settings and personalization work.
Keep the earlier engine/API, native acceptance, identity-permission and cloud
follow-ups. This stage does not close the Draftly Mac roadmap.
