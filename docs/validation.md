# Validation

Run `swift test` and `scripts/build-app.sh --local` before a release.

For the current implementation and remaining work, read [project status](status.md).
The sections below are historical records. Their test counts describe each run.
The user removed session evidence and all screenshots on 19 October 2026.
Artifact paths in older records are historical and may no longer exist.

## Recorded interface check

On 2026-10-18, the local Debug app was checked with Computer Use on macOS 27.0.1.
The check covered capture with keyboard focus, Markdown editing, tags, save and
reopen, undo and redo, revision history, and a second independent window.
After comparison with the installed Drafts app, the check also covered repeated
empty capture without saved drafts, saving after typing, selected-text task
conversion, undo from the editor bar, the command palette, group controls, and
the three-panel action inspector.

Directory import and native execution passed for Copy as Rich Text and Save in
Obsidian Vault. The exported Markdown file contained the expected content and
tags. A second export reported an existing file and did not overwrite it. The
global shortcut registered without an error. The full key combination created a
draft in the active app. Capture while another app is active still needs a check.

Live Reminders, Calendar, and Shortcuts calls still need the interface checks
below. The automated action suite uses a test host for those side effects.

## Left panel transitions

The installed Drafts app was used to check these transitions on 2026-10-18.
Draftly passed the same sequences through its toolbar, View menu, and shortcuts.

| Command | Result |
| --- | --- |
| Show filters with the draft list hidden | Show filters and the draft list |
| Hide the draft list with filters visible | Hide both panels |
| Show the draft list after hiding both | Show only the draft list |
| Hide filters | Keep the draft list and active filters |

The initial widths are 240 points for filters and 280 points for the draft list.
The first toolbar separator tracks the filter divider. The controls after the
draft list toggle share one toolbar section. Panel changes keep active
filters and the selected draft. Menu titles show the available Show or Hide
command. The panel shortcuts take priority over action shortcuts with the same
key combination.

The native layout test changes a panel width, hides both panels, and checks the
restored widths and controller identity. State tests also check the Actions API
and Quick Search entry points.

The filter options menu was compared with the installed Drafts app. It has
Show Search, Single Tag, Multiple Tags, All Tags, and Only Current Tags. The live
check confirmed that Only Current Tags hides assigned tags when the list shows
untagged drafts. All Tags restores the full tag list. The original draft and
filter state were restored after the check.

The toolbar icons and filter header spacing were adjusted from this comparison.
The toolbar and editor footer still have spacing and control differences.

## Automated checks

The suite checks persistence after reopening a store, immutable content revisions,
archive and trash filters, workspaces, backup restoration, conflict copies,
unsupported backup versions, UTF-16 selections, templates, HTML escaping, and
10,000 drafts with a 100,000-character document.

Action tests check the five reference snapshots, shared script state,
cancellation, unsupported steps, failure on the final step, native permission
errors, and installation URL encoding. These tests do not call live services.

## Mac interface checks

1. Create a draft. Type Markdown and Unicode text. Check the save indicator.
2. Switch drafts, reopen the app, and check the saved text.
3. Undo and redo edits. Check that an action edit can also be undone.
4. Add tags and a flag. Search for the draft. Save and select a workspace.
5. Archive, trash, and restore a draft. Test batch operations.
6. Restore a revision. Check that the later content remains in history.
7. Import each reference action from its directory URL. Inspect its steps.
8. Run Copy as Rich Text. Paste into a rich text editor.
9. Run Save in Obsidian Vault. Choose a temporary folder. Check the file. Run
   again and check that create mode does not overwrite it.
10. Test the global capture shortcut, menu bar, and two independent windows.
11. Export a full backup. Import it into a separate test store.
12. Test Markdown preview, Shortcuts, AppleScript, Reminders, and Calendar.
    Deny permissions first. Check that errors keep the source text.

Use `--ui-testing` to run with a separate temporary library and no iCloud.
Use `--local-only` to disable iCloud for a launch. These options do not delete
existing stores.

## iCloud acceptance gate

The initial signing attempt used a Personal Team. The paid team now provisions
CloudKit and push notifications. The current signed test launch reached the server,
but its first setup failed despite the correct portal assignment. A dedicated QA
container then passed a real server round trip between independent local stores.
See [icloud-distribution.md](icloud-distribution.md) for the current evidence.

After accepting the main container, use two Macs with the same iCloud account:

1. Create and change drafts, tags, workspaces, and actions on each Mac.
2. Confirm that both libraries converge.
3. Disconnect one Mac. Edit on both Macs. Reconnect it.
4. Confirm that the winning draft and both saved content revisions are available.
5. Trash and restore a draft. Confirm the result on the second Mac.
6. Disable network access and restart. Confirm that local editing still works.
7. Sign out of iCloud. Check the error state and local data.

CloudKit sync is eventual. The UI must not promise an immediate server save.
Create a backup before testing account changes or production schemas.

## Window transition regression checks

The DraftlyTests target covers failed capture with a saved draft and a temporary
draft. It also checks successful capture, workspace filter removal, draft
pinning, window floating, the new draft timeout, and preview transitions. Save failures use an
injected writer. These checks do not change the user's library.

For interface checks, open all four panels. Confirm that the footer buttons and
character count fit. Choose another group in the editor action bar. Confirm
that its action buttons appear. Toggle list preview, tags, and date options.
Restart the app and confirm that these options remain saved. Open Markdown
preview with the eye button below the editor. Confirm that it appears in the
center panel. Switch back to text with the eye button and Option-Command-P.
Check that the draft content and selection remain unchanged.


## Toolbar motion and draft list comparison

On October 18, 2026, both apps were compared on the same Mac. Temporary frame
samples found a toolbar reversal during filter collapse. The draft list toggle
moved from x=245 to x=145, then to x=180, and back to x=145. The content panel
continued in one direction. The tracking separator caused the reversal.

The toolbar now tracks a separate divider with a minimum leading position of
140 points. The content panel can collapse past that position. After this change,
45 samples for each transition showed no reversal. The toggle moved from x=245
to x=145 on close, and from x=145 to x=245 on open. The temporary sampler was
removed from the app. The native layout test checks that the tracking divider
stays visible and keeps its minimum width when filters collapse.

The draft list now uses inset selection, larger text, tag capsules, a date on
the right, and row heights that depend on the content and list options. A new
empty draft does not add a row until it is saved. The list keeps keyboard focus
when a draft opens. Reloads preserve selection and ignore programmatic selection
notifications. The context menu uses the table view event handler.

Computer use checks confirmed that Down opens the next draft, Shift-Down selects
two drafts, and the context menu opens. No archive or trash operation was run on
the user's drafts. Tests cover focus requests and the empty draft row count.
Exact parity is not claimed. Toolbar spacing, row separators, and the editor
footer still need comparison.

## Draft context menu acceptance — 2026-10-19

The context menu captures selected draft IDs in visible order. A right click
outside the selection targets only that row. Move and flag commands assign one
common value. Save, duplicate, merge, and Trash removal use one local transaction
per operation. The tests inject a failure before commit and verify rollback.

The test suite covers mixed selections, failed editor saves, target order,
metadata on duplicates, merge output, tag changes, independent Info and Versions
targets, cancelled and failed action batches, menu enablement, shortcut conflicts,
legacy JSON import, JSON metadata round trips, CSV escaping, and Trash removal.
Trash removal retains action history and removes the drafts' revisions.

Computer Use checks ran against a separately signed QA bundle with a distinct
bundle identifier and `DraftlyUITesting=true` in its Info.plist. This flag uses
a fresh temporary library and disables CloudKit. The normal bundle does not
contain this flag. The command-line `--ui-testing` option uses the same isolated
storage mode. Each test launch now uses a separate temporary directory.

The interface checks created two disposable drafts and confirmed:

- Multiple selection disables Open in New Window/Tab, Info, and Versions.
- Merge creates a third draft, keeps both sources, and follows list order.
- Info for a different row does not replace the editor's current draft.
- Open in New Window loads the target. Open in New Tab creates a second tab.
- Add Tags changes the target row without changing the editor's draft.
- Move to Trash removes only the right-clicked draft from Inbox.
- Empty Trash shows the draft count and permanent deletion warning. Cancel
  leaves the draft in Trash. Permanent deletion was tested in memory, not by UI.
- The JSON save dialog writes an export to `.build/menu-qa/QA-export.json`.
  The file contains the selected draft, tags, dates, syntax, flag, and Trash state.
- Copy's reserved shortcut shows a conflict message and disables Save in the
  action inspector. The action remains available from the command menu.

The QA bundle was closed after the checks. No draft operation ran against the
user's normal library. External sharing services were listed but not invoked.
The final local Xcode build and 74 automated tests passed.

## Main window visual pass — 2026-10-19

The local Xcode build and 75 tests passed (30 app tests and 45 core tests).
The new layout test checks all four panel widths at 850, 1033, and 1200 points.
It checks that the panels fit without exceeding the available width.

Computer Use used `DraftlyVisualQA.app` with `DraftlyUITesting` enabled.
Each launch used a new temporary library without CloudKit. Test drafts used
neutral text, Unicode, Markdown, tags, and a flag. The checks covered editing,
preview, tag entry, flag changes, multiple selection, and panel toggles.

The narrow check found a wrapped Filters heading and a clipped editor count.
Both were corrected. A second screenshot confirmed the corrections at 850 × 600.
The toolbar uses its native overflow menu at this width. Long action names
use an ellipsis. They do not overlap adjacent controls.

Final screenshots are in `research/screenshots/main-window-2026-10-19/`:

- `light-850x600.png`
- `light-1033x734.png`
- `light-1200x800.png`
- `dark-1200x800.png`
- `dark-panels-closed.png`

The screenshots retain panel widths from the narrow check. They are not
aligned overlays against Drafts. The reference window was 1082 × 764 points.
The one-point tolerance has not been verified. The full active/inactive matrix,
Reduce Motion, undo across panel toggles, and new frame-by-frame motion samples
remain unverified in this pass. Earlier motion results are not new evidence.


## Roadmap implementation and screenshot follow-ups — 2026-10-19

The final local Xcode build and 96 tests passed: 38 app tests and 58 core tests.
The checks include persistent capture buffers, failed saves, search results and
keyboard routing, native row commands, atomic tag changes, XML-RPC values and
faults, Mustache directory partials, action success options, backup compatibility,
group metadata, workspace options, command conflicts, and editor layout.

Computer Use used a distinct `DraftlyRoadmapQA` bundle and temporary libraries.
It confirmed:

- Capture opens in its own panel. Closing and reopening keeps its text. Saving
  creates a draft and hides the panel. A full quit and restart preserved pending
  Unicode text and line breaks. The first-open focus issue was corrected with a
  native text view. The final check confirmed focus before typing. A screenshot
  is in `research/screenshots/roadmap-2026-10-19/capture-restored.png`.
- Quick Search opens separately, searches archived drafts, and leaves the main
  editor unchanged on Cancel. Up/Down and Return were verified after fixing
  native field key routing. The field receives focus when the panel opens.
- Changing Quick Search to Command-Shift-K in QA Settings opens the search panel.
  The normal app's shortcut preferences were not changed.
- Native row accessibility actions expose Trash and Archive. Archive moved the
  disposable target out of Inbox. A horizontal scroll command did not expose the
  swipe buttons. A physical two-finger swipe still needs verification.
- Rename Tag updated the sidebar and editor tags. Delete Tag removed the tag
  and kept the draft. The menu has Rename Tag and Delete Tag in that order.
- The idle editor tag field shows rounded capsules. Clicking it keeps native
  token editing and suggestions. A neutral screenshot is in
  `research/screenshots/roadmap-2026-10-19/rounded-editor-tags.png`.
- The organization manager created a group and a workspace. The workspace
  editor exposes saved list and search options.
- The actual status `NSMenu` opened through a QA-only hook. Its entries, order,
  recent drafts, and enabled Quit were visible in the accessibility tree. The
  screenshot tool did not include the popup layer. Icon appearance at the real
  status-bar anchor is still unverified.

A signed build was attempted with provisioning updates enabled. Xcode reported
that the configured team is a Personal Team and cannot provision iCloud and Push
Notifications. No live sync result is claimed. The signing configuration was not
changed to an invented team identifier. Two-Mac tests remain blocked on access.

The roadmap is not complete. Remaining work includes the full member-by-member
API audit, native service and permission checks, remaining import option mappings,
full theme and syntax parity, configurable global capture, exact visual overlays,
the full animation and Reduce Motion matrix, large-library UI measurements,
and signed installation/update tests. Earlier passing tests do not close those
acceptance gates.

## Core Actions audit — 2026-10-19

Implemented corrections and limits are in `docs/research/core-actions-audit.md`.
The normalized reference matrix records 149 reviewed core and helper entries.
Each entry has a targeted test association. These associations do not prove full
contract parity. Full syntax grammar, advanced find, access dates, and native
entry-point acceptance remain open.

Automated verification: 117 Swift tests (41 app tests and 76 core tests) passed.
The five original action fixtures passed with their original scripts. Three
Python reference-parser tests passed. The local Xcode build passed. The diff
whitespace check passed. Logs are `/tmp/draftly-core-audit-tests.log` and
`/tmp/draftly-core-audit-build.log`.

Computer Use verification used DraftlyCoreQA with a new temporary library.
The `Core acceptance` action ran from the native Actions menu. It changed Unicode
text, performed undo and redo, assigned a tag, and saved and applied a workspace.
The visible result confirmed one row, title ascending, and hidden row tags.
Evidence: `docs/research/screenshots/core-actions-2026-10-19/native-acceptance.png`.
The QA app was closed after the check. No draft operation ran on the user's
normal library. The normal app was not replaced or restarted during this pass.

A user-requested visual comparison found a separate tab-bar difference. Drafts
starts the tab bar after the filter sidebar. Draftly spans the full window and
moves that sidebar down by about 36 points. The search-field height, header
button sizes, and header spacing also differ. This pass records those findings;
it does not claim a visual fix.

## Visual parity correction — 2026-10-19

Implemented: the filter panel is a native full-height sidebar. The tab bar starts
after that sidebar. Showing tabs does not move the filter content down. Initial
widths remain 240 points for filters and about 280 points for the draft list.
The sidebar uses its native material. The folder selection uses the accent color
in an active window and a neutral color in an inactive window. The search field
requests 30 points of layout height. Its native cell controls its drawn inset.
The window content minimum permits an outer size of 850 by 600 with tabs visible.

Automated checks: 118 Swift tests passed (42 app tests and 76 core tests). The new
test checks native sidebar behavior. Existing tests check widths, resizing,
collapse, and retained controllers. The local Xcode build and diff whitespace
check passed. Logs: `/tmp/draftly-visual-tests.log` and
`/tmp/draftly-visual-build.log`.

Computer Use checks used a temporary library in DraftlyVisualQA. With tabs open,
filters closed and reopened at 240 points. The list returned to about 280 points.
Light and dark screenshots are in
`docs/research/screenshots/visual-parity-2026-10-19/`. The narrow screenshot is
1700 by 1200 pixels at 2x scale, which confirms an outer size of 850 by 600.
The narrow toolbar exposes its native overflow control.

The normal app was closed through Quit and reopened from the visual-parity
build. Its 13 drafts remain present. No draft operation ran against that library.

This fixes the reported tab-bar layout difference. Full one-point visual parity
is not closed. A matched reference capture set, populated row typography,
all panel states, and new animated frame measurements remain to be checked.

## Note typography — 2026-10-19

Implemented: 14-point bold list titles, 13-point previews, 10-point tags, compact
row spacing, relative day labels, and 24-hour timestamps. Shared preview and
height logic prevents different text measurements. Fixed line heights keep two
preview lines visible after selection. Native table emphasis controls selected
text colors. Mouse events reach the table through noninteractive cells.
The System editor font is available without replacing saved font choices.

Automated verification: 121 Swift tests passed (45 app tests and 76 core tests).
The new presentation tests cover paragraph separators, source preservation,
preview height caps, query snippets, and regional date formatting. Local build
and diff whitespace checks passed. Logs: `/tmp/draftly-row-tests.log` and
`/tmp/draftly-row-build.log`.

Computer Use inspected Drafts and tested neutral notes in DraftlyRowsQA. The
final selected row retains two preview lines, both tags, a full timestamp, and
readable text in light and dark modes. A short note and an unselected long note
were also checked. Screenshots are in
`docs/research/screenshots/note-typography-2026-10-19/`.
The QA app was closed. The normal app was quit with save and reopened with the
updated build. It contains the user's 14 drafts. No test drafts were added to
that library. Its saved Fira Code Nerd Font choice remains unchanged.

## Main window comparison — 2026-10-19

Reference: installed Drafts 54.1.1. Its Markdown editor settings show SYSTEM at
17 points, line height 1.1, and zero paragraph spacing. The user approved changing
the normal Draftly font. Its font is now System at 17 points. Nerd Fonts remain
available. Local margins are now 8 points horizontally and 24 vertically. These
values need an aligned measurement before final acceptance.

Implemented:
- The toolbar uses the standard sidebar tracking separator with the real split
  view. The previous proxy split view placed the filter button after the sidebar.
  The native separator places it inside the sidebar toolbar area. Native spaces
  separate draft navigation from the draft-list toggle.
- Search previews show matching lines with original one-based line numbers.
  Height measurement uses the same text and font weight as the row. The existing
  Preview Search Matches option still controls this behavior.
- Action titles use 13 points. Footer symbols use 11 points. Versions and Action
  Log have distinct history symbols. The footer supports horizontal scrolling
  when its controls do not fit.

Automated: 122 Swift tests passed: 46 app tests and 76 core tests. Tests cover
matching lines, Unicode, original line numbers, and the real toolbar separator.
Panel controller retention, widths, collapse, and rapid state changes still pass.
The local Xcode build passed. Logs: `/tmp/draftly-parity-tests.log` and
`/tmp/draftly-parity-build.log`. No storage format or public API changed.

Live verification used 50 neutral notes in a temporary DraftlyParityQA library.
Some temporary notes also have tags and flags. Four filter toggles restored
240-point filters and a 280.5-point draft list before the narrow-size checks.
The toolbar filter button moved to the same sidebar region as Drafts. The normal
app restarted with 64 drafts, including the 50 requested test drafts, and retained
System font. It is left with 50 results for `visual-qa-20261019`.

Screenshots are in `research/screenshots/main-parity-2026-10-19/`. They contain
only temporary notes. The captures precede the final native toolbar-space change.

| Capture | Image pixels | Requested window points | Evidence |
| --- | --- | --- | --- |
| light-1033.jpg | 2066 x 1468 | 1033 x 734 | Light, actions open, single selection |
| light-1200.jpg | 2400 x 1600 | 1200 x 800 | Light, actions open |
| dark-1200.jpg | 2400 x 1600 | 1200 x 800 | Dark, actions open |
| dark-850.jpg | 1700 x 1200 | 850 x 600 | Native toolbar overflow and compact footer |
| dark-850-tabs.jpg | 1700 x 1200 | 850 x 600 | Tab bar with filters visible |
| inactive-capture-scale-issue.jpg | 2066 x 1468 | 1033 x 734 | Capture-scale defect; not measurement evidence |

Acceptance remains open. The capture service sometimes draws content at 1x on a
2x canvas. It also omits the open status menu from the window capture. Thus, the
current reference captures do not support a one-point comparison. The status
menu accessibility tree confirms its command order and a recent draft, but does
not prove visible icons. The following checks remain required:
- Matched reference captures at both primary sizes, with matching fonts, panels,
  search options, selection, and list order. Measure all static alignments.
- Final toolbar grouping and spacing after the native-space change.
- Full active/inactive and multiple-selection matrix; one, two, and three preview
  lines; multiple tabs and independent windows.
- Frame-by-frame transition measurements, orders during animation, Reduce Motion,
  and live selection and undo checks after those transitions.
- Visible status-menu icons, recent submenu, disabled states, and Quit with a
  pending edit in the temporary library.

The passed tests and screenshots do not establish complete visual parity.

## Actions and Merge follow-up — 2026-10-19

Implemented: typed configuration defaults, SelectPrompt item contracts, callback
result routing, battery availability, strict ranges and query errors, and a
library execution lease. The API matrix keeps manual evidence across refreshes.
Its 562 members include 356 unreviewed members. Full API parity remains open.
The inventory also records limits for 25 first-party step types.

Automated: 139 Swift tests passed (48 app, 91 core). Eight matrix-generator
tests passed. The matrix structure check reports no errors. These counts do
not prove full compatibility. The five original action scripts remain unchanged.
The unsigned macOS build passed.

Verified in use: a temporary native action tested Unicode editing, undo, redo,
SelectPrompt selection, saving, and a real battery read (0.19). Evidence:
`research/screenshots/actions-audit-2026-10-19/native-acceptance.jpg`.
External callback delivery and full SelectPrompt search remain unverified.

Merge now asks for a separator and an original-draft destination. Archive is
the default. Empty separator uses one newline. A nonempty separator occupies
its own line. Include blank line adds one blank line on each side. The UI uses
captured visible order. Cancel does not save or merge. Confirm saves the merged
draft and original movements in one batch. A failed batch rolls back both.
Tests cover Archive, Trash, Do Not Move, Unicode, separators, and rollback.
Computer Use verified cancel, default Archive, one merged Inbox draft, and both
originals in Archive in a temporary library. The separator padding behavior has
not yet been compared through a completed merge in Drafts. The dialog is not
certified as a one-point visual match.

## Merge visual comparison — 2026-10-19

Reference: installed Drafts 54.1.1. Opened Merge with the neutral visual notes.
Cancelled the reference dialog. No reference drafts were merged or moved.

Implemented: replaced the flexible form with native AppKit controls in a fixed
400 × 354 point sheet. Matched the 22-point content inset, 16-point bold title,
13-point body, 11-point captions, 12-point segments, divider, field, checkbox,
and bottom buttons. The text now uses the reference wording and two lines.
The segment control has explicit widths. It no longer clips the first segment.
The separator caption no longer truncates. Archive remains the default.

Verified in use: compared both open dialogs. Tested focus, separator entry,
checkbox availability, destination selection, and Escape cancellation in a
fresh temporary Draftly library. The final sheet has the expected field and
button positions. The reference capture has 1× content inside an 800 × 706
canvas; Draftly has 2× content in an 800 × 708 image. Compare the reference's
400 × 353 content region with Draftly at half scale. The one-point outer-height
difference remains. This is not a full pixel-difference certification.
Captures: `research/screenshots/merge-2026-10-19/drafts.jpg` and `draftly.jpg`.

Automated: unsigned build passed. All 139 Swift tests passed after the native
control change. The final changes only adjust label and icon positions.

## Main-window closure attempt — 2026-10-19

Reference: Drafts 54.1.1. Editor: System 17 pt, line spacing 2 pt in
Draftly, horizontal margin 8 pt, vertical margin 24 pt. Nerd Fonts remain
available. The 50 neutral contents were copied into a temporary QA library.
No personal draft content was changed.

### Implemented

- Shared row metrics now control drawing and height calculation. The date gap
  is two points. Bottom padding is six points. Two-line rows now have the
  measured 81-point pitch.
- Moved the draft-list search field up four points without moving the title or
  folder controls. Reduced the action title's leading gap by two points.
- Fixed the QA status-menu position for flipped views. The complete native
  menu now fits inside the captured window.
- Added an optional UUID for a persistent temporary QA library. Only builds
  with `DraftlyUITesting` use it. It always stays under `Draftly-UITesting`
  in the temporary directory. This made quit-and-reopen acceptance possible.
- Added `scripts/check-visual-capture.py`. It requires Pillow. It checks stated
  point dimensions and rejects the observed white-padding defect. Four tests
  cover the defect, valid 1x/2x images, wrong dimensions, and blank captures.

The toolbar spacing replacement did not pass. A custom spacer drew a glass
background. A fixed native spacer ignored the requested width. Both prototypes
were removed. The seven native spaces remain, now expressed as a single array
construction. They keep the controls separate. This part is still pending.

### Automated results

All 141 Swift tests passed: 50 app tests and 91 core tests. The unsigned Xcode
build passed. Four capture-check tests passed. A Merge test now compares notes
by identity. Reloading notes with equal dates can change their array order;
that order does not prove that the stored notes changed.

### Verified in use

- Captured Draftly at 1033 × 734, 1200 × 800, and 850 × 600 points.
  Raw sizes are 2066 × 1468, 2400 × 1600, and 1700 × 1200 pixels.
- Checked light/dark appearance, search shown/hidden, actions shown/hidden,
  one/two/three preview lines, single/multiple selection, and native overflow.
- Opened two tabs and an independent window. The tab bar starts after filters.
- Sent six rapid filter shortcuts. The selected notes and draft content stayed
  intact. This is not a frame-by-frame animation measurement.
- Enabled the real macOS Reduce Motion setting. Closed and opened filters.
  Selection and content stayed intact. Restored the original off setting.
- Inserted neutral text, toggled filters twice, and used Undo. After the UI
  settled, the text was restored and editor focus stayed on the same draft.
- Captured the complete status menu. All icons were visible. Order and
  separators match the supplied reference, with Draftly names. Checked the
  empty and populated Recent Drafts menus.
- Quit immediately after entering a new neutral draft. Reopened the same
  temporary library and confirmed the exact text. The extra note was then
  moved to Trash. It was not permanently deleted. Autosave timing was not
  instrumented, so this does not isolate the terminate-time flush from autosave.

### Measurements and evidence

See `research/screenshots/main-closure-2026-10-19/capture-manifest.json`.
It records dimensions and invalid captures. A valid geometry check does not
mean that the visual acceptance matrix passed.

The local list comparison uses the same 281 × 280 point region from both apps.
Both final images have 1x content inside a 2x canvas. The local region is read
without resizing. The first four title ink bands match: 24–31, 105–112,
186–193, and 267–274 relative to the crop. This confirms an 81-point pitch.
Selection borders and the first date baseline differ by no more than one point
in this region. Text antialiasing and date values are excluded.

Evidence: `rows-final-comparison-1x.png` and `row-measurements.json` in the same
folder. Earlier grid captures precede the final one-point row correction.

### Open acceptance items

This delivery does not close visual parity. The reference still returns 1x
content inside a 2x canvas. Border resizing did not produce the requested
reference sizes. The checker rejects those images for full-window measurement.

Toolbar spacing still differs. At the initial width, Last Draft was about four
points away from the reference position. A later reference resize also moved
its history cluster with window width. A responsive spacing solution remains
open. Action-panel width and the full one-point alignment matrix remain open.

Also pending: complete matched reference captures in all sizes and states;
frame-by-frame transition monotonicity; the full inactive-window color matrix;
clipboard-empty menu state; status-menu flows with no main window; and physical
trackpad swipe acceptance. The real Reduce Motion and quit/reopen checks above
replace those older pending entries only to the stated extent.


## Actions closure infrastructure and access dates — 2026-10-19

See `docs/research/core-actions-audit.md` for this pass. The local app build
passes. The Swift suite passes 151 tests. The audit tool passes 14 tests. The
matrix structure check passes. Strict parity still fails and must not be used
to claim closure. The temporary QA app confirms the Accessed sort menu and
movement of an opened neutral draft without changing its displayed edit date.
Full points 6–11 acceptance remains open.

The advanced-find follow-up passes two core matcher tests and one window test.
Computer Use confirms the separate sheet, Unicode query, Replace All, and native
Undo on a temporary draft. Drafts appearance and full behavior acceptance remain
open. The final local build passes after the action-bar connection.

## Core closure pass — 19 October 2026

The local build passed. The app target passed 63 tests. The core target passed
114 tests. The auditor passed 15 tests. These totals do not prove API parity.

Native checks used the isolated Core QA library. Custom task changes and Undo,
searchable SelectPrompt selection and cancellation, audio transcription, dictation
insertion and Undo, and dictation cancellation passed. Mac scanning returned the
documented empty string. No personal library operation was needed.

Core classification passes. Strict core parity remains open. See
`research/core-actions-audit.md` for limits and the member matrix for evidence.

## iCloud and personal build pass — 19 October 2026

Implemented: separate local, signed Debug, signed Release, and signed cloud test
outputs; private CloudKit scope; explicit Development environment; signing checks;
a Release ZIP and checksum; observed account and operation states.

Automatically tested: six sync state and storage tests, five signing tests,
and the existing regression suites. The final run passed 63 app tests and 120
core tests. All 24 Python tests passed with the bundled Python runtime. The
system Python lacks Pillow, so it cannot run the existing visual capture tests.

Verified in use: Apple generated profiles for the main and test apps. The test
app saved a neutral note. It reopened the same note after a signed rebuild.
Settings displayed a real setup error. The server reported `Invalid bundle ID
for container` despite the checked portal assignment. A dedicated QA container
then completed an upload. A second, empty local store downloaded the same note.
Its identity, content, tags, syntax, flag, folder, and dates matched. The app opened
it. This test used one Mac and no personal note.

Not accepted: the main container, two-Mac convergence, signed
installation and update on a second Mac, offline sync recovery, and notarized
Developer ID distribution. The development package covers registered Macs only.

## UTM CloudKit acceptance — 19 October 2026

The dedicated QA container passed the named Mac-plus-VM cases. Both clients
contain ten notes, eleven revisions, one Workspace, one group, one action, and
one execution record. Read-only comparisons found no note contract field
differences. Offline edits survived app relaunch and reached the host after
reconnection. Concurrent variants remain in both revision stores. The guest
displayed both variants and the successful neutral action log.

The guest installed signed package build 2. Signature verification passed. The
package retained the executable and library ID. All test note identities and
content survived replacement. This is not a binary migration test.

A guest editor refresh defect remains open: switching notes sometimes left
stale drawn text while the stored content and character count stayed correct.
The main container and notarized distribution still require acceptance. No new
source change or full test-suite run is claimed by this native validation. See
[UTM validation](utm-icloud-validation.md) for the case results and limits.

## Main CloudKit container — 19 October 2026

The actual main app identity and private Development container passed a server
round trip with two isolated stores on this Mac. The receiver started without
a local library. It received one neutral note and two revisions through
CloudKit. Native UI opened the note. Read-only comparisons matched all nine
listed note fields and revision identities. The personal library was not used.

The main guest package covers both devices. Console input was restored. The VM
received the note and both revisions. Return testing exposed an access-date
write that could replace remote content. The revision preserved the remote text.

Implemented: access updates use a separate generic record. They do not write
content or its modification date. Old note payloads and backups remain readable.
All clients need the new build to remove the old access-write behavior.

Automatically tested: 63 app tests and 121 core tests passed. The new regression
checks that access leaves the content record unchanged. It then applies remote
content and checks that both content and access survive reload. The signed build
compiled. These checks do not prove CloudKit scheduling or full conflict parity.

Verified in use: signed build 4 ran at the exact guest path. Its binary hash and
signature matched. Guest creation and return edits arrived on the Mac. Opening
on the Mac during the remote edit did not replace the edited text. Both stores
held two notes and eight matching revisions. All nine note contract fields
matched. Access records were still converging and are not claimed as identical.

Pending: repeat the broad main-container matrix with the corrected clients.
Developer ID, notarization, and broader signed Release updates remain open.
Evidence: `.build/main-cloud-evidence/guest-roundtrip-result.json` and the named
host and guest snapshots. The personal library was not used.

## Visual adjustments — 19 October 2026

Reference: Drafts 54.1.1. This pass used 50 neutral notes in an isolated local
library. It did not change the personal library or CloudKit records.

Implemented: one native flexible toolbar space replaces seven fixed spaces.
The real split tracking separator remains. The native tab bar stays visible
with one tab. Quick Search opens its own window from the toolbar. Search,
folder controls, count, and the Tags heading have shared alignment offsets.
The editor paints its background and invalidates it after draft replacement.
A new vector app icon is included in the app bundle.

Automatically tested: 13 tests passed across EditorRedrawTests,
ScriptEditorUndoTests, LibrarySplitViewTests, and DraftRowPresentationTests.
The redraw test checks Unicode selection and a blank area after long text is
replaced by short text. The local Xcode build passed. These tests do not prove
complete visual parity or the VM redraw result.

Verified in use: Quick Search opened from the toolbar. Cancel returned to the
same editor with an empty list search and 50 drafts. The narrow toolbar showed
native overflow entries. Overflow invocation is not accepted by this pass.
The list retains the measured 81-point reference row pitch. The compared
list/editor divider differed by one point before the header adjustments.

Valid captures are in `research/screenshots/visual-close-2026-10-19`:
Draftly light 1033 x 734 points (2066 x 1468 pixels), Draftly light
1200 x 800 points (2400 x 1600 pixels), and Drafts 1115 x 645 points
(2230 x 1290 pixels). All have a 2x canvas without detected white padding.
The reference is suitable for regional comparison, not equal-size acceptance.

Pending: equal-size reference captures, the full state matrix, app icon checks
in Dock and Finder, rapid transitions, and the VM redraw check. The new dark
1200 x 800 and light 850 x 600 captures contain 1x content in a padded 2x canvas.
They are rejected for measurement. The original builds are not updated by the
isolated Visual QA build. This delivery remains open.

## QueryDate contracts — 19 October 2026

Implemented: the matrix now uses member-specific QueryDate evidence. Five
members passed review without a runtime change. The factory remains partial
because the archived return signature conflicts with its description.

Automatically tested: 59 tests passed in ActionAPITests and
QueryDateContractTests. Eight tests are new. They check value objects,
persistence, date fields, range types, and calendar boundaries across DST.
The auditor passed 15 tests and its regular matrix validation. The strict core
check remains red with 1271 diagnostics; this pass does not close that scope.

Verified in use: none in this pass. Native verification is not required for the
five reviewed value/model contracts. The factory return requires a check in
Drafts 54.1.1. See `research/core-actions-audit.md` for the reference hash and
the remaining inventory. No personal notes were changed.

## SelectPromptItem contracts — 19 October 2026

Implemented: omitted or invalid symbol names no longer display a fallback
document icon. The six item members now have specific test evidence. Three
value contracts are complete; three display contracts still need live checks.

Automatically tested: 65 core contract tests and a separate run of 11 native
control tests passed. The native test covers optional symbols. The matrix check
and 15 auditor tests passed. The isolated local Xcode build passed. The strict
core check still reports 1244 diagnostics. This does not close the core scope.

Verified in use: Drafts 54.1.1 displayed its Pro upgrade window when New Action
was selected. QueryDate.create() could not be run. The upgrade window was closed.
The matrix records this as blocked, not passed or unavailable. No purchase was
made and no personal note was changed. See the core audit for the saved UI text.

## SelectPromptItem live check and Version — 19 October 2026

Implemented: Version content, UUID, and creation timestamp now reject property
assignment. Revision deletion rolls back on a failed storage commit.

Automatically tested: six member-specific Version tests passed. The final
focused regression passed 71 tests. The earlier full core run passed 140 tests
before the new storage failure case. The regular matrix check and 15 auditor
tests passed. The isolated local Xcode build passed. Strict core acceptance
remains open with 1205 diagnostics.

Verified in use: SelectPrompt displayed Unicode title, smaller separate subtitle,
and the requested star icon. Missing and invalid symbols showed no icon.
Subtitle filtering returned the third item and selection retained its ID.
Cancel returned without changing editor text. Screenshots and the neutral action
are in `research/screenshots/select-prompt-item-2026-10-19`.
The three display contracts now pass. This is Draftly native acceptance, not a
visual comparison with the Pro-gated Drafts prompt editor.

## Draft, Editor, and Workspace contracts — 19 October 2026

Implemented: native line boundaries replace LF-only expansion. Workspace saves
roll back on error. Script loading and selection synchronize with the native
editor before the next statement. Undo cannot restore the previous draft after
a script loads and edits another draft.

Automatically tested: 18 new core tests and one new native undo regression were
added. The core suite passed 159 tests, including the five original actions.
The separate native regression run passed 36 tests across controls, window
transitions, undo, and redraw. The local Xcode build, matrix validation, and
15 auditor tests passed.
The strict core check still reports 1111 diagnostics. The core remains open.

Verified in use: the initial action exposed stale native undo state and failed.
After the correction, v2 passed loading, Unicode selection, CRLF ranges, editing,
undo, redo, and Workspace persistence and application. The query and visible list
both contained one neutral draft. Evidence and the reproducible action are in
`research/screenshots/three-core-contracts-2026-10-19`. This is contract
acceptance in Draftly, not a new comparison with Pro-gated Drafts scripting.

## Delivery one closure and next core contracts — 19 October 2026

Implemented: Draft UUID is read-only. UUID lookup accepts either letter case.
Titles use native line separators, including CRLF. Editor activation closes the
preview and restores native focus. Deactivation preserves other text controls.
The active property checks the editor view. Activation, deactivation, and draft
navigation return void.

Automatically tested: the final full run passed 234 core tests in 18 suites and
92 app tests in 15 suites. The five original action fixtures passed. New tests
cover metadata, Draft queries, editor properties, and Workspace application and
identity. The local Xcode build passed. Matrix validation reported zero errors.
All 15 auditor tests passed. Strict core acceptance remains open: 842 diagnostics.
These counts do not establish compatibility for unreviewed members.

Verified in use: the three delivery-one checks and isolated replay passed.
The updated app also passed CRLF title, strict UUID assignment, case-independent
identity, native activation and deactivation, UTF-16 selection, Undo, and Redo.
The neutral action and actual success message are saved in
`research/screenshots/delivery-one-2026-10-19/core-next-acceptance.json` and
`core-next-passed.txt`. The final editor contains “Core identity PANDA” and
“Neutral body”. This checks Draftly behavior, not Pro-gated Drafts scripting.

Pending: native Workspace installation URL acceptance, syntax-specific tab preferences,
Draft query reference dependencies and parent-tag behavior, native Draft.update
evidence, and the remaining core contracts. Draft.tags retains its legacy setter
and remains partial. The habitual app was not replaced by this isolated QA build.

## Main window visual pass — 19 October 2026

Implemented: shared row fonts, a lower date baseline, native toolbar spacing,
Actions width restoration, sidebar text, menu symbols, footer icons, and editor
margins. The canvas now follows the selected appearance. Stored user preferences
remain in use. This pass preserves the 81-point two-preview row pitch.

Automatically tested: the final full run passed 234 core and 100 app tests.
It includes the five original action fixtures. The local Xcode build passed.
All four capture-validator tests passed.
Geometry tests cover initial Actions width, first opening, saved widths, and
completion stability. Redraw tests compare native renders in both appearances.
A separate regression switches an explicit color scheme without changing text
or selection.

Verified in use: the Actions panel restored 260 points at the reference layout.
Four toggles preserved text and final widths. The first light-mode resize exposed
a black canvas; the corrected build now shows readable text at 1200 × 800,
1033 × 734, and 850 × 600 points. All three saved captures have valid 2x scale
and no white padding. The overflow control is visible at 850 points.

Acceptance remains open. The full paired state matrix and intermediate animation
frames are not verified. Manual appearance selection in Drafts opened its Pro
upgrade window. Rejected captures and exact remaining checks are recorded in
`research/visual-parity-2026-10-19.json`. Screenshots alone do not prove full
visual parity. The habitual app has not been replaced.

### Visual follow-up: overflow, animation, and Unicode count

Implemented: the navigation triangle uses an 11 × 6.5 point native template path.
The list summary divider moves down 2 points without changing header or row size.
The footer uses Foundation word tokens and keeps emoji symbols.

Automatically tested: 234 core and 109 app tests passed. The local app build passed.
Visible test windows sampled native presentation frames every 8 ms. Individual and
rapid transitions had intermediate frames without backward movement above 1 point.
They preserved saved widths, note identity, content, and UTF-16 selection. An
injected animation policy tested Reduce Motion without changing system settings.

Verified in use: at 850 × 600, toolbar overflow opened Quick Search and Command
Palette. Cancel preserved the selected note and list query. Actions closed and
reopened. The rebuilt app displayed 149c 26w for neutral fixture 50, matching the
recorded Drafts result. Other token cases only have Foundation test evidence.

Pending: the Mac locked before final captures. The triangle and divider changes
need pixel inspection. The full visual matrix remains open. See
`docs/research/visual-parity-2026-10-19.json` for evidence and limits.

### Visual follow-up: compact footer and long text

Implemented: compact footer spacing is six points. Pin and link symbols use
12 points. Native horizontal scrolling remains. Each footer caches the last
content and count. Unchanged content does not repeat tokenization.

A long-text test found overlapping Foundation token fragments. The counter now
unions overlapping ranges. It keeps adjacent Japanese and Chinese tokens separate.
Tests cover 100000 and 200000 character sequences and one 100000-character word.

Automatically tested: 234 core and 116 app tests passed. The local build passed.
The navigation image raster test passed. Its scope is the image, not final window
placement. All four capture-validator tests passed with the bundled Python runtime.
Logs: `/tmp/draftly-visual-cached-all.log` and
`/tmp/draftly-visual-cached-build.log`.

Native acceptance remains pending because the Mac is locked. Inspect the new
footer, scroll access, navigation placement, and divider after unlock. The cache
only removes unchanged-content work. Full typing performance remains unverified.

Tokenizer measurements are in
Session artifact removed at the user's request. Repeat this check when new acceptance is required.
Run `python3 scripts/benchmark-editor-statistics.py --runs 9` to repeat them
on an Apple silicon Mac. The report includes hardware, runtime, fixture hashes,
and samples. It includes Python callback overhead and excludes UI typing.

### macOS capture Services and append regression

Implemented: direct capture saves selected text as a new draft. Capture with
Options opens the capture window. The old service selector remains an adapter
for the options flow. The reader supports plain text, RTF, RTFD, URL, and legacy
pasteboard type names. It preserves Unicode, spaces, and line breaks.

A direct save keeps earlier pending capture text. A failed save retains incoming
text and reports the error. Append saves pending edits and updates every matching
editor before another flush. It preserves selection, focus, and native Undo.

Automatically tested: the targeted run passed 42 tests in four suites. The full
run passed 234 core and 154 app tests. The local Xcode build passed. The built QA
bundle contains both Services and matches source declarations. Its library UUID
is unchanged. Tests use in-memory libraries, temporary preferences, and private
pasteboards. They do not change personal notes or the general pasteboard.

Native acceptance remains pending because the Mac is locked. Invoke both Services
from another app after unlock. Check no main window, multiple windows, empty input,
clipboard preservation, and the actual menus. The normal app has not been replaced.
Session artifact removed at the user's request. Repeat this check when new acceptance is required.
Session artifact removed at the user's request. Repeat this check when new acceptance is required.

### Version storage, Prompt transport, and resumed visual review

The full run passed 254 core and 154 app tests. Twenty new contract tests cover
versions and Prompt responses. Revision save failures roll back and do not leak
into a later commit. SQLite reopen preserves accepted snapshots and rejects
failed snapshots. Prompt rejects malformed responses before publishing values.
The matrix check and 15 auditor tests pass. Strict core still reports 820 issues.

Native visual review resumed after unlock. The navigation triangle, pin, and link
match the measured reference dimensions within one point. Compact icons no longer
touch. The offset list divider needed a higher draw order; it now appears at the
reference vertical position. Native scroll indicators expose horizontal actions.
The 850-point footer can show the complete 149c 26w count. The editor action bar can
reach its final actions. Captures and AX evidence record these checks.

Six current captures pass size and padding checks at 2x. See
`screenshots/visual-pass-2026-10-19/verified-capture-index.json` under research.
The full visual matrix and native Services invocation remain pending.

### Actions toggle color

The Actions toggle now uses primary label color when open and secondary label
color when closed. The image changes only when visibility changes. A native
drawing handler keeps the toolbar from replacing the selected symbol color.
Five toolbar tests pass. They cover model updates, unchanged images on unrelated
updates, and contrast in light and dark appearances. The local build passes.
Native light captures confirm a darker open icon. Exact tint comparison with an
active Drafts window remains pending.

The final app suite passed 156 tests after this change.

### Settings and application menu

Settings now has General, iCloud, Bookmarks, Editor, and Shortcuts categories.
General includes local appearance, menu bar visibility, capture timeout, and the
preferred find interface. Native checks verified navigation, Light and System,
and both Cmd-F interfaces. The application menu has one Settings entry in the
reference order. Library Summary reads actual counts. Empty Trash uses the
existing confirmation and is disabled for empty trash.

A neutral bookmark was created and forgotten in the QA app. Its file stayed
intact. The initial save error preserved the name and did not create a record.
The exact cause of that first error is not proven. A fresh signed process with
balanced scoped access saved the bookmark. Two targeted tests verify inventory,
forgetting, and native file API read/write. The 770 by 438 point capture has valid
2× pixels. Full Settings parity, restart acceptance, real Action invocation,
permissions, menu icons, and the final accessibility change remain pending.

### HTML Settings and paste conversion

Added HTML settings for paste conversion, strong/emphasis/list marks, inline or
reference links, paragraph references, and ignore options. The editor uses the
local preferences. Explicit scripting conversion keeps its own supplied options.
Fixed UTF-8 entity decoding and preserved whitespace with a pre-wrap span.
Five targeted tests verify options, Unicode, paragraphs, reference placement,
selection replacement, Undo, and the unchanged private test pasteboard.
The full run passed 168 app tests and 256 core tests. The local build passed.
Native layout and paste acceptance remain pending because Computer Use closed
its native pipe. This does not establish full HTML conversion compatibility.

### HTML paste regression checks — 2026-10-19

- Implemented: opening HTML tag patterns require a complete tag name. This prevents body, input, and link from matching b, i, and li.
- Automatically tested: seven HTML preference tests pass. The new cases cover tag prefixes, Redo, and a plain-text-only clipboard. Three tag assertions failed before the fix.
- Build: local Xcode build passed. Log: `/tmp/draftly-html-regressions-build.log`.
- Real use: the new signed QA build opened. Computer Use lost its native pipe when Settings opened. The executable remained live. Settings layout and real paste remain pending.

### Markdown Settings option contracts — 2026-10-19

- Added specific output assertions for MultiMarkdown header labels, GitHub hard breaks, source positions, and safe-over-unsafe precedence.
- All five MarkdownPreferencesTests passed. Log: `/tmp/draftly-markdown-options-contracts.log`.
- These tests check the stored options through the renderer. They do not verify checkbox interaction, every Markdown option, or visual parity.
- Template `%%` delimiters still use MarkdownRenderer. The bundled MultiMarkdown extension flags have no escaped-line-break option. Both items need further work.

### HTML Preview action step and Markdown preferences — 2026-10-19

- The HTML Preview step now converts Markdown with the configured processor and options. Explicit HTML passes through unchanged. Conversion errors use the existing action error path.
- ActionTests.htmlPreviewStepUsesConfiguredMarkdownAndPreservesExplicitHTML checks saved strikethrough options, Unicode, unchanged source content, and exact HTML preservation.
- All 14 ActionTests passed, including the five original actions with unchanged scripts. Full Swift regression passed: 170 app tests and 260 core tests. Log: `/tmp/draftly-htmlpreview-all-tests.log`.
- Native preview acceptance and comparison with Drafts remain pending. Template percent delimiters still use the legacy converter.

### Configured Markdown template delimiters — 2026-10-19

- Added Templates.renderConfigured with throwing Markdown conversion. Actions use it for templates, file names, folders, and scripting processTemplate. Included templates use the same renderer and preferences. The existing nonthrowing Swift render function retains its legacy behavior.
- Specific tests check configured strikethrough, Unicode, included templates, escaped percent delimiters, source preservation, a clipboard step, and Draft.processTemplate.
- All 21 focused tests passed. Full regression: 170 app tests and 262 core tests passed. The five original Actions retain their scripts. Local Xcode build passed.
- Logs: `/tmp/draftly-template-preferences-targeted.log`, `/tmp/draftly-template-preferences-all-tests.log`, `/tmp/draftly-template-preferences-build.log`.
- Native preference changes through Settings and reference comparison remain pending. This does not close every template contract.

### Library Trash command without a window — 2026-10-19

- Empty Trash in the application menu now depends on library contents, not a command window. It uses a shared library command. Window context menus use the same confirmation and validation.
- The app command saves registered editors before confirmation. A failed save cancels deletion and preserves the pending text. A changed Trash set cancels deletion after confirmation.
- Four focused tests passed. They cover no-window confirmation/cancellation, active drafts, empty Trash, changed Trash, and failed editor save. Tests use only in-memory libraries.
- All 173 app tests passed. Local Xcode build passed. Logs: `/tmp/draftly-trash-command-final-tests.log`, `/tmp/draftly-trash-command-app-tests.log`, `/tmp/draftly-trash-command-build.log`.
- Native menu state with no window and cancellation remain pending. No user draft was deleted for this acceptance.

### Pause checkpoint: initial execution sessions — 2026-10-19

- Added execution identity, current step, cancellation requests, and a final report with a typed reason. Legacy run and runResult use the report. Added cancellation checks between steps, queued actions, and host calls.
- Three session tests cover immutable finalization, result parameters, distinct identities, asynchronous timeout, cancellation, preserved completed effects, and skipped success effects.
- Full regression: 173 app tests and 265 core tests passed. Local Xcode build and whitespace checks passed. Logs: `/tmp/draftly-stop-check-tests.log`, `/tmp/draftly-stop-check-build.log`.
- This is an initial session implementation. Worker serial execution, the common async entry, removal of RunLoop polling, entry-point migration, and full engine acceptance remain pending.
- Settings reference-help controls compile. Their native visual and click acceptance remains pending. CUA reconnection still fails while the earlier QA process remains live.
- Work is paused at the user's request. No claim of complete Mac or engine parity is made.


## Repository cleanup 19 October 2026

- Split the app scene file into controller, delegate, commands, and Settings files.
  Regenerated the Xcode project. No library formats or public scripting APIs changed.
- Removed three toolbar-array assertions. Native layout, animation, and toggle
  contrast regressions remain. Removed two redundant test transcripts.
- Excluded generated C include fragments from separate compilation. The parser
  still includes their contents. The unused build-rule warnings are gone.
- Removed four old build logs and 78 generated cache/log directories. Preserved
  app products, signing data, frozen references, and local iCloud/VM evidence.
- Full Swift regression: 170 app tests and 265 core tests passed. All 24 Python
  tests passed. Matrix structure validation reported zero errors. The local
  Xcode build and whitespace check passed.
Session artifact removed at the user's request. Repeat this check when new acceptance is required.
- Added `status.md` for the current implemented/pending inventory. Updated the
  repository map and glossary. Native visual parity and the Actions worker
  remain pending; this cleanup does not close them.


## Git review and local reset 19 October 2026

The branch matches origin/main after fetch. No staging, commit, or push ran.
The commit grouping and ignore review are in `status.md`.

The review found that runReport no longer published the legacy busy message.
Restored the message and added a test for same-runner reentry and another runner
in the same library. Full Swift regression passed: 170 app tests and 266 core
tests. All 24 Python tests, matrix structure validation, the local Xcode build,
and whitespace validation passed.

The user explicitly confirmed permanent local reset without a recovery copy.
Drafts shared data and its app preferences were deleted. Draftly's local store,
34 QA libraries, and 14 preference domains were removed. Native inspection then
showed 0 drafts and empty editors in both apps. Drafts iCloud was verified off.
Draftly runs the new local build without a CloudKit container. No remote cloud
reset or VM reset ran.

Removed docs/research/evidence, all 148 local screenshot/capture artifacts,
three local build evidence folders, and ten more generated logs. Historical
results remain summaries. No new visual parity acceptance follows from this reset.


## Commit preparation — 19 October 2026

The user authorized commits and push after repository cleanup. Changes were
staged by behavior. Each code snapshot was compiled and tested in a temporary
directory, without replacing the open local app. The first extraction candidate
exposed pending identity and redraw corrections. Those corrections now precede
the extraction in history. No failing candidate was committed.

The commits cover core contracts, visual regressions, source extraction,
Markdown, capture, Settings, initial execution sessions, and repository cleanup.
This records implemented work. It does not close Mac parity or the async engine.

Final validation of the complete staged source passed: 170 app tests, 266 core
tests, 24 Python tests, and the normal matrix check with zero errors. The local
Xcode build passed with signing disabled. The whitespace check passed. A scan
for private key, GitHub token, and AWS access-key markers found no matches.
Signing files, local libraries, logs, evidence, and screenshots remain ignored.


## Architecture refactoring and background tests — 19 October 2026

The baseline tag is pre-refactor-2026-10-19 at commit 2fba5bd. The window,
preferences, execution, storage, native adapters, and view components were
refactored in separate commits. Public scripting contracts and data formats stay.

The user requested removal of tests that show or move visible windows. Three
visible-animation tests and their fixture were removed. The remaining AppKit
fixtures use OffscreenTestWindow, which rejects ordering and activation. Queue
synchronization has one helper. The visual matrix records the retired tests.
Visible animation acceptance requires a manual session; hidden tests do not
replace it. No Computer Use or real cloud acceptance ran for this refactoring.

Final verification passed: 170 app tests, 267 core tests, 24 Python tests, local
Xcode build with signing disabled, normal matrix validation with zero errors,
and whitespace validation. The original five action fixtures are unchanged.
All compatibility classifications match the baseline. Broad Mac parity remains
open. These totals describe regression checks, not API compatibility coverage.

## Test refactoring — 19 October 2026

The monolithic API suite was split into eleven API suites. Shared fixtures and
script builders remove repeated setup. Preferences use isolated domains with
explicit cleanup. Three native text-view fixtures now share one implementation.
Three duplicate version cases were removed; docs/testing.md records the retained
contracts. Discovery matches the baseline except for those three cases.

Final checks passed: 170 app tests in 29 suites, 264 core tests in 33 suites,
24 Python tests, normal matrix validation with zero errors, and whitespace
validation. All 542 matrix test references resolve. Compatibility classifications
and the original five action fixtures are unchanged. No production code changed.
No app was launched for visible UI or cloud acceptance. These totals describe
regression checks, not compatibility coverage. Strict parity remains open.

## Typed scripting command boundary — 19 October 2026

The 24 core operations now decode into ScriptCommand. Query options and UTF-16
range validation have shared types. Execution is separate from wire decoding.
Note and workspace inputs resolve at the same point as before, to preserve save
ordering and error priority. Other API and native capability adapters retain
their existing interfaces.

Seven new boundary cases passed. Full checks passed: 170 app tests in 29 suites,
271 core tests in 34 suites, 24 Python tests, the normal matrix check with zero
errors, whitespace validation, and a local Xcode build with signing disabled.
All 24 previous core operation names have typed routes. The matrix and original
action fixtures are unchanged. No app was launched. Native, visual, cloud, and
strict compatibility acceptance remain separate and pending as recorded.

## Async HTTP transport — 20 October 2026

ScriptHTTP now shares request construction and response conversion between the
legacy adapter and an async URLSession transport. The new path cancels in-flight
requests without RunLoop polling. Six isolated URLProtocol tests passed for
Unicode JSON, status and headers, HTTP errors, network errors, malformed inputs,
request encoding, authentication, and cancellation. No external network was used.
Redirects and real socket acceptance remain pending.

## Worker execution and include contracts — 20 October 2026

The new runAsync route owns a serial JavaScript worker, serialized host bridge,
continuation-based completion, scheduled timers, cancellation, and typed reports.
Legacy entry points remain. Shared configuration and success effects serve both
routes. Includes resolve UUIDs and runtime name templates in the same context.
Import keeps structural step UUIDs separate from include targets.

Original action cases passed on both routes without changing fixture scripts.
New cases cover reply expiry, duplicate completion, stale timers, CPU deadlines,
queues, includes, concurrent content changes, deleted notes, and stale initial
editor content. Remaining synchronous native capability waits and real external
entry-point acceptance are not closed by these tests.

## Async application entry points — 20 October 2026

Window actions, batches, run URLs, and App Intents await the common report.
Scheduling reserves the window before a Task starts. User navigation, creation,
typing, or an external text update cancels pending work. Scripted navigation and
Undo retain their behavior. A source window close cancels its action.

The final integrated run passed 178 app tests in 31 suites, 301 core tests in
38 suites, and the unsigned local Xcode build. Original fixtures are unchanged.
Computer Use used a temporary local library. Panel controls worked during a
delayed script; completion changed the text, and native Undo restored the source.
Closing a window produced a Cancelled history entry. Typing during a wait in the
final build cancelled the action and retained the new text. The QA app was quit;
the habitual app was not replaced. No screenshots were stored.

Real URL callback delivery, actual App Intent invocation, native permission and
cancellation variants, metadata concurrency, and remaining capability waits are
still pending. This delivery does not close strict engine or Mac parity.

## Engine evidence gate — 20 October 2026

The auditor now requires fourteen named engine contracts. An engine-only scope
checks that inventory without API object noise. Strict validation rejects removed,
duplicate, or unnamed entries. Four new tests passed; the full Python suite has
28 passing tests. The normal matrix check reports zero errors. All 554 stored
test references resolve. API member classifications and original fixtures stay.

The engine strict check remains open with 132 evidence diagnostics. These are
not a count of missing members or a compatibility percentage. The records remain
partial because native entry points and all contract branches are not accepted.

## Native asynchronous host waits — 20 October 2026

Implemented async callback URLs, shell scripts, and Shortcut process waits. Native
callback and Shortcut steps use the same JSON host boundary as scripts. Callback
tokens expire on completion, cancellation, or timeout. Process cancellation waits
for group termination and child cleanup. Worker shutdown drains host requests
before the library is released.

The integrated background run passed 192 app tests in 33 suites and 306 core tests
in 40 suites. New cases cover callback status and token isolation, process output,
literal arguments, timeout, cancellation, child descendants, native-step reports,
and library exclusion during host cleanup. The first full run exposed test timing
that let a deadline expire before the fake host started. The cleanup regression
now allows startup under parallel load; the repeated integrated run passed.
The unsigned local Xcode build and normal matrix check passed. These results do
not change member classifications.

The process tests execute neutral local processes. Shortcut tests use an injected
executable. Callback tests inject URL opening. Actual macOS callback delivery,
actual Shortcut execution, App Intent invocation, and other native capability
variants remain pending. No visible windows were opened by these tests.

## EventKit asynchronous waits — 20 October 2026

Calendar and Reminders API requests now await full-access authorization. Reminders
queries use the EventKit fetch token and cancel that request on timeout or caller
cancellation. Reminder and List in Reminders steps use the async host boundary.
The synchronous adapters remain available for legacy callers.

Twelve injected tests passed. They cover authorization status, denied access,
write-only upgrade, system errors, cancellation, timeout, repeated callbacks, and
late results. They do not request real permissions or create calendar items.
The full integrated run also passed. System permission dialogs cannot be withdrawn
by EventKit; cancellation ends the action wait and ignores any later grant.
The calendar event editor still uses a modal dialog. Real permissions and item
persistence remain pending; these cases are not native acceptance.

## Automation editor safety — 20 October 2026

URLs and App Intents share an injected action execution coordinator. It saves
pending visible edits before loading its private editor. Visible typing and stored
text changes cancel a pending action. The private editor retains the competing
text, so cancellation cannot flush stale text over it. Synchronous draft creation
and insertion mark their own mutations; this marker does not span native waits.

Five background tests passed: pending edits, failed saves, visible typing, external
stored text, and the action's own native editor changes. The full run passed 212
app tests in 36 suites and 306 core tests in 40 suites. Targeted automation and
native-host tests passed after restricting the mutation marker to text operations.
Real App Intent invocation and the full multiple-window acceptance remain pending.

## Real callback delivery and scene creation — 20 October 2026

Computer Use ran a separate local QA app and a neutral callback helper. Both used
QA-only URL schemes. The normal Draftly URL registration stayed unchanged.
The helper returned Unicode through macOS URL delivery. Success updated the draft;
cancellation and error stopped the following script and retained its text.
Typing during an eight-second callback wait cancelled the action. After the late
reply, the exact user text remained. Execution History showed the matching
Success, Cancelled, and Error entries. A neutral shell action also completed from
the interface and wrote its Unicode output into the editor.

The first real callback exposed an extra blank window. Moving URL receipt to the
application delegate alone did not fix it. Excluding the library and Settings
scenes from automatic external-event scene creation fixed the observed case.
The repeated success, cancellation, error, and late-reply checks kept the original
library window. Three routing tests and the unsigned build passed after this fix.
These observations do not prove cold-launch open/create/capture/run URLs, actual
App Intent delivery, actual Shortcuts, or the native 120-second timeout.

The helper source and neutral actions are reproducible inputs under scripts.
No screenshots were saved. The QA app was quit after the session.

## Speech, location, and persistent-library exclusion — 20 October 2026

Speech uses delegate completion and cancellable nonmodal notices. It retains
NSSpeechSynthesizer voice identifiers and the existing rate mapping. Location
uses authorization and location callbacks. Cancellation and timeout stop updates
and invalidate callbacks. Native speech steps use the async host boundary.
Injected tests produce no audio, windows, or permission requests. Real speech,
location, and notice acceptance remain pending.

Library exclusion now uses the canonical persistent-store URL inside the process.
Two LibraryStore instances opening the same file, including through a symlink,
share the gate. In-memory stores retain separate identities. This is not a
cross-process lock or a claim of full concurrent-store cache coherence.

The full background run passed 229 app tests in 38 suites and 309 core tests in
41 suites. The unsigned local Xcode build passed. Two engine records now have
specific defaults, results, errors, and per-case tests. Both remain partial;
actual overlapping entry points and the listed native cases remain pending.

## Cold-launch URLs and actual App Intents — 20 October 2026

Computer Use ran a separate QA app and a neutral control helper. The helper opened
normal draftly URLs with an explicit QA application target. The normal scheme
registration and personal library stayed unchanged. Create, Open, and Capture
passed from a confirmed stopped QA process. Capture restored its pending text
and appended the new neutral Unicode text.

A cold-launch Run requested confirmation, awaited a delayed script, changed the
stored draft, and returned success plus its Unicode success parameter to the
helper. Warm error and cancellation runs returned the corresponding callbacks.
The error case retained the text and did not run its following insertion step.

Shortcuts discovered Run Draft Action for the exact QA app. The ad hoc copy failed
communication; the system log reported a missing Team ID. Signing the same QA
bundle with the existing development identity for NM92LU2KKV fixed that setup
failure. Actual App Intent success returned the completion message. A delayed
failure returned Neutral failure, and context cancellation returned its cancellation
message. These checks do not accept timeout, busy, or concurrent-entry variants.

The reverse native Shortcut step reached its 60-second timeout and retained the
source text. The neutral Text shortcut existed and ran from the Shortcuts editor.
A direct command-line invocation also waited without output and was cancelled.
Therefore native Shortcut success remains unresolved; no compatibility exclusion
or successful acceptance was recorded. Two disposable shortcuts remain pending
user confirmation for deletion from iCloud. No screenshots were saved.

The manual automation QA executable used the 7a45c7a baseline, before this session's
speech/location adapters and canonical exclusion change. Those later changes have
automatic-test and build evidence only. Repeat their applicable native cases on
a fresh signed QA build before closing those contracts.

## Async native input and model adapters — 20 October 2026

Implemented:

- File transcription suspends for authorization, file selection, and recognition.
  Cancellation and deadlines close the picker and stop recognition. Picker Cancel
  returns empty text. `editor.transcribe()` uses this route when a window exists.
  It returns text without changing the editor. Live dictation remains separate.
- Calendar editing uses a nonmodal panel. Accept validates dates and checks
  cancellation before saving. Cancel does not save. Event creation uses the same
  async authorization and dialog boundary.
- Apple model requests suspend with a deadline and reject overlapping requests
  for one session. Cancellation waits for cleanup and discards the session.
  Tools require an active request. Discarded sessions invalidate cached tools.
  Core tool calls reject closed actions and mark their own stored changes.
- Prompts, selection prompts, alerts, and action confirmation suspend through the
  host boundary. The legacy and async prompt steps share payload and tag rules.
  Their synchronous legacy entry points remain available.

Automatic evidence uses injected drivers and presenters. It covers typed prompt
fields, button indices, invalid numbers, filtered selection indices, cancellation,
transcription cleanup, event validation and commit, model session exclusion, late
model tools, and async editor transcription. Cancellation fixtures now wait for
an explicit start signal, not an assumed delay. No test opens a visible dialog,
plays audio, or requests a real permission.

The final run passed 260 app tests in 42 suites and 313 core tests in 42 suites.
The unsigned Xcode build passed. Normal matrix validation passed with zero errors.
The strict engine gate still reports 120 evidence diagnostics. No API member was
promoted on the basis of these test totals.

Real system acceptance is pending for these new adapters. In particular, check
Return, Escape, Cmd-period, and window close in the actual prompt presenter;
transcribe a neutral file; check EventKit permission and persistence; and check
Apple model availability and tools. Existing manual acceptance used an older QA
executable. It does not accept this delivery. No screenshots were saved.

## Real async prompt keyboard acceptance — 20 October 2026

The first QA refresh copied only the Debug launcher. It retained an older
Draftly.debug.dylib. That batch did not verify a308158 and is invalid for the new
presenter. The checks below were repeated after copying every Mach-O file,
checking source and destination hashes before signing, and verifying the signed
bundle. The existing isolated local library was retained. The habitual app was
unchanged. The helper
now accepts installation URLs for actions, while it still checks the QA bundle
identity and test flag. Reproducible inputs are in
`scripts/fixtures/engine-prompt-actions.json`.

Prompt Return stored `café 🐼`. Escape and Cmd-period each cancelled, retained the
note, and released the runner for the next action. SelectPrompt filtered on the
subtitle Second and Return stored `Selected: two`. Escape cancelled its next run
without a text change. Execution History showed one prompt success, two prompt
cancellations, one selector success, and one selector cancellation. QA was quit
and no QA process remained. The helper remains available. No screenshots were
saved. The alert exposes no visible close control. Other window-close paths,
confirmation variants, and remaining native adapters still need acceptance.

## Engine boundary evidence — 20 October 2026

The focused EngineBoundaryContractTests run passed seven test methods with 13
expanded cases. Static include expansion accepts a 50-action chain and rejects
51; this is not a claim about every dynamic full-runner depth path. The real
queue accepts 100 executed actions, rejects 101, and retains the first 100 effects.
Queued async failure and cancellation stop later steps and queued actions, discard
success parameters, and keep completed effects. Separate root executions do not
share JavaScript globals. Pre-cancelled startup has no effects. Separator defaults
and invalid imported payloads have direct checks.

Engine evidence now names these and earlier specific assertions. The normal
matrix check passes. The strict engine check reports 44 evidence diagnostics.
All 14 engine records remain partial, with their native checks and remaining
limits stated. No object member or step classification changed. The change in
check output is not a compatibility percentage or a complete engine acceptance.


## Async dictation and isolated AppleScript — 20 October 2026

Implemented in f334fd1, d4f4425, and 824525f:

- Live dictation suspends for speech and microphone authorization. A nonmodal
  panel shows partial text. Done returns the latest text; Cancel returns empty
  text. Task cancellation and deadlines stop audio and recognition and close the
  panel. The editor scripting call forwards locale and does not insert text.
- AppleScript runs in a child process with JSON file requests and results. A
  dedicated launcher mode runs before SwiftUI or the library starts. Process
  cancellation terminates the child and waits for cleanup. Legacy descriptor
  conversion shares the implementation.
- JSON null maps to AppleScript missing value. Records keep user fields and known
  coded properties text, name, contents, and id. Other coded fields use their
  four-character key; their application-specific display names cannot be recovered
  from the descriptor alone. Duplicate decoded keys fail instead of losing data.

The final run passed 288 app tests in 45 suites and 322 core tests in 43 suites.
The unsigned Xcode build passed. These cases include dictation permission denial,
phase-specific cancellation and timeout, failed capture startup, delayed results,
AppleScript null and record values, helper errors, and process cleanup. The five
original action fixtures remain unchanged. Real dictation acceptance is pending;
no microphone permission or actual recording was used in this delivery.

A separate real helper invocation returned the exact Unicode, boolean, numeric,
null, and empty-list payload with exit zero. Computer Use then used the fully
refreshed, development-signed QA bundle. The source Debug library SHA-256 prefix
was 146394d6933cb349 before signing. The QA helper mode returned the exact native
record result before GUI checks began. The earlier launcher-only batch was
invalid and was not counted.

QA AppleScript success stored `AppleScript café 🐼`. During the eight-second
AppleScript case, direct neutral typing cancelled the action and immediately
showed `Neutral typing retained`. No helper child remained. Subsequent prompt and
selector actions completed; the delayed text did not replace the editor. Execution
History showed the matching AppleScript success and cancellation, prompt success
and two cancellations, and selector success and cancellation in the repeated batch
at 01:18–01:19 local time. The prompt Return, Escape, Cmd-period, filtered selector
Return, and selector Escape cases all passed with this verified executable.

The external URL confirmation now uses the same suspended presenter. Escape
returned a fresh `status=verified-cancel` callback to the local helper. The target
text stayed unchanged. Accepted external execution with the new presenter, timeout,
busy, concurrent entry, and source-close variants still need current-build checks.
QA and the helper were quit; no QA or helper process remained. No screenshots were
saved. Native speech, transcription, EventKit persistence, models, and further
AppleScript result types remain pending where their contracts require them.

## Native interruption and deadline regression — 20 October 2026

A caught native cancellation or timeout cannot issue later host calls from the
same script. The worker retains the typed interruption. Both script and native
steps stop before later effects or success disposition. New tests catch the
error in JavaScript and then attempt editor and clipboard changes; neither runs.

Native waits and worker replies check their absolute deadline when a result
arrives. A late reply cannot win because a timer task has not run. An injected
clock test advances past the deadline before returning a native response. The
runner returns timeout and keeps the source and archive state. The test uses a
30-second worker allowance to avoid timing out during unrelated parallel test
startup; its injected clock advances instantly. No visible window is involved.
These exact cases passed in the full 315-app/330-core run.

## Engine session defaults continuation — 20 October 2026

EngineDefaultsContractTests checks a new run after explicit cancellation in both
legacy and async routes. At its actual first host callback, the session is not
cancelled, has no report, and identifies step zero, the root action, and its step
UUID. The next run succeeds with a new execution ID. Its finished report belongs
to that same observed session. Both parameter cases passed in the final core run.
The common entry default now states only the window request behavior proved by
DraftCommandTests. It does not use that test as URL or App Intent evidence.
The normal matrix check passes. Strict engine acceptance remains open with 42
diagnostics. All 14 records remain partial with native checks pending.

## HTML, file selection, and composition delivery — 20 October 2026

Implemented:

- Interactive HTML uses continuations. It preserves returned JSON values and
  hideInterface. Cancel, close, navigation failure, process failure, task
  cancellation, and timeout finish once and remove WebKit callbacks.
- Export and bookmark selection use asynchronous native panels. The adapter checks
  cancellation before bookmark persistence and writes. Shared path resolution
  fixes /var versus /private/var bookmark aliases and rejects symlink escapes.
  Invalid write modes fail before any panel or bookmark change.
- Mail and Messages use retained service delegates. Injected tests cover service
  availability, canPerform, recipients, subject, Unicode, cancellation, errors,
  timeout, and duplicate replies. Unsupported options are explicit errors. An
  external composer cannot be recalled or closed through NSSharingService; the
  adapter only cancels its wait. No real recipient or content was authorized, and
  no real message or composer was used.

The final full run passed 315 app tests in 48 suites and 330 core tests in 47
suites. The unsigned Xcode build passed. All 32 Python tooling tests passed using
the bundled Python runtime with Pillow. The initial system Python could not load
Pillow; its incomplete run does not count. The first Swift run found a canonical
path regression, which was fixed before the passing full run. No test total is
used as evidence of complete member parity. Normal matrix validation passes;
the strict engine gate remains open with 42 diagnostics.

Computer Use used the isolated QA app after the new refresh script copied all
runtime and resource files, checked their hashes, and verified development
signing. The source Debug library hash prefix was a8487281945f6f60 before signing.
The normal app and its library stayed unchanged. The script also has a real
process-guard test with a temporary executable path that contains spaces and a
/var alias; this caught and fixed a path-spelling mismatch in the first guard.

The neutral fixtures are scripts/fixtures/engine-html-file-actions.json. Real
WebKit displayed HTML inside Draftly with native controls hidden. Its button sent
an object with Unicode and null, then continued. The next script verified null
and stored `café 🐼`. A second preview showed native Cancel/Continue. Cancel kept
that source text and did not run the next insertion step. Escape in the native
Save panel returned Cancelled and kept the source. A separate export saved
`Draftly neutral QA.txt` in a new temporary folder. Reading the actual file matched
`Export café 🐼\nSecond line` exactly. The source note stayed unchanged.
Execution History showed HTML Success, HTML Cancelled, File Cancelled, and File
Success at 01:34–01:35 local time. The neutral export and its temporary folder were
removed. QA and the helper were quit; no process remained. No screenshots were
saved.

Standalone HTML, real bookmark access after restart, timeout and permission
variants, external composer behavior, and further API options remain pending.
The engine and complete Mac plan remain open.

## Awaited print, sharing, and arrangement — 20 October 2026

Implemented: async print sheets, sharing outcomes, and arrangement requests.
showArrange uses a window-owned task and guards its captured draft and content.
The new first-party print, share, and openIn paths await their native result.
Cancel stops later steps and success effects. Legacy sync sharing is unchanged;
its immediate success and temporary file cleanup still require work.

Automatically tested: 350 app tests in 52 suites and 332 core tests in 47 suites
passed. The focused native batch passed 35 tests in four suites. These include
absolute deadlines, duplicate and late replies, file retention after handoff,
cleanup before handoff, cancellation, stale arrangement results, save failure,
selection, and native Undo/Redo. Drivers are injected; no window or printer opens
in these tests. The unsigned Xcode build passed. The 32 Python tests passed.
The matrix structure check reports zero errors. Strict engine acceptance still
reports 42 evidence diagnostics. No compatibility classification was promoted.

Verified in use: refreshed all executable images, resources, and frameworks in
the isolated development-signed QA bundle. Source Debug library hash starts with
b6c10a5587d8fbcd before signing. At 01:50 local time, native print Cancel and share
picker Escape kept the draft exactly café 🐼. Neither Late print nor Late share
was inserted. Execution History records both as Cancelled. No print or message
was sent. The print preview showed two pages for a short text; page sizing needs
review before print output acceptance.

At 01:51, UI QA Arrange result showed First and Second 🐼 as separate rows. Move
Up and Done saved Second 🐼 followed by First. QA Show Arrange opened the same
organizer; Cancel kept that content. Both UI actions appear as Success in history.
The automatic test establishes showArrange's immediate return. This native check
does not establish completion timing while its dialog remains open.

A URL attempt to call editor.arrange without a window-bound UI adapter returned
an explicit active-editor error before presentation. It is recorded as Error,
not accepted as URL/editor integration. Print and Share URL runs used an explicit
neutral draft UUID and external-action confirmation.

Pending: real print output, service completion and external composer ownership,
native arrangement Undo/navigation/window-close variants, and URL access to editor
UI operations. A transferred sharing file remains until the service callback.
If the service never replies, no cleanup time can be guaranteed. No screenshot
was saved. QA and its helper were quit after checking history.

## Template waits, automation arrangement, and print layout — 20 October 2026

Implemented: asynchronous template evaluation for first-party step text, fields,
URL encoding, included-action names, and script processTemplate requests. Dynamic
tags and recursive file loads suspend through the host boundary. Pure builders
retain validation and render order. Static tags and transforms share code with
the synchronous renderer. Arrange with explicit input no longer requires a
window-bound editor adapter. Other window operations retain their requirement.
Print layout fits actual text to paper, margins, and scale; HTML specifies UTF-8.

Automatically tested: 358 app tests in 53 suites and 344 core tests in 50 suites
passed. The 32 Python tests and unsigned local Xcode build passed. Matrix structure
has zero errors. Tests cover recursive native requests, escapes, custom overrides,
Unicode, missing templates, recursion limits, pure builder call order and errors,
script and first-party integration, secondary export fields, creation tags, and
typed template timeout without later insertion or archive. Automation arrangement
tests use no models, the target model, an unrelated model, and both models. They
check separate editor state, cancellation, and injected native timeout. These
checks do not establish an actual system permission or production timeout.

Verified in use: the QA bundle was fully refreshed and development-signed. Source
Debug library hash starts with 09c6472791e1728c before signing. At 01:59 local
time, the helper started QA via the explicit neutral draft UUID and Arrange URL.
After external-action confirmation, the native organizer showed First and Second
🐼. Done saved First followed by Second 🐼. The target was then selected to read
its saved content. History records Success. This replaces the earlier explicit
active-editor failure for this pure-text method only. Cold URL target selection
was not immediate in the window and needs separate review.

QA Print cancelled now showed Page 1 of 1 for the short neutral text. Cancel kept
the note First followed by Second 🐼 and did not insert Late print. History records
Cancelled. No print job was sent. QA and its helper were quit. No screenshot was
saved. Real template folder permissions, location, physical or PDF print output,
window-bound automation operations, and wider native acceptance remain pending.
Strict engine closure remains open; no status was promoted from these totals.

## Automation window context and startup routing — 20 October 2026

Implemented: fixed editor context for URL and App Intent actions, early busy
rejection, retained startup targets, typed App Intent errors, and nonblocking
showDictate. Cancellation and failure no longer reveal the URL target. Success
does not reselect an already visible result. This fixes a real regression where
URL showArrange opened its panel and then immediately cancelled it by selecting
the same draft.

Automatically tested: 379 app tests in 57 suites and 345 core tests in 50 suites
passed after the final route correction. The 32 Python tests and unsigned Xcode
build passed. Matrix structure has zero errors. Routing tests cover delayed model
registration, save failure and retry, invalid targets, explicit new selection,
new-window exclusion, and closed destinations. Context tests cover key/main/visible
selection, native Undo, save order, early busy without saves, cancellation, stale
text, and no retarget. Error tests retain final reason, result, and execution ID.
Dictation tests use injected presenters. They cover immediate return, cancellation,
recovery, selection changes, stored changes, save failure, owner release, and Undo.
They do not open a microphone, show a window, or request a permission.

Verified in use: the final isolated QA bundle was fully refreshed and signed.
Source Debug library hash starts with caf9b8271cd70940 before signing. The earlier
intermediate bundle is not accepted for the final showArrange correction. A cold
Open URL selected the neutral draft First followed by Second 🐼 without a manual
row selection. A warm URL QA Show Arrange then kept its native panel open after
the action returned. Move Up and Done changed the real editor to Second 🐼
followed by First. Cmd-Z restored First followed by Second 🐼.

A URL QA Async prompt keyboard was left waiting. The Window menu selected its
source window First. Closing that window closed the prompt, kept the saved text,
and recorded Cancelled at 02:10 local time. An Untitled window appeared after
close. The route did not explicitly reveal a cancelled result. Static review
found no cancellation path that opens a library window. The cause of the new
window is unresolved; do not claim full no-reopen acceptance. CUA or native
lifecycle behavior needs an isolated follow-up.

Native App Intent failures, busy and timeout from real accesses, multiple-window
selection, closure before execution starts, and the new voice path remain pending.
The strict engine gate is still open. QA and its helper were quit. No screenshot
was saved.

## Unknown-step import and observer control — 20 October 2026

Implemented: a per-execution owner-close subscription cancels the automation
child before startup or during a wait. Parent cancellation also cancels it.
Cleanup removes the subscription once. The worker validates the synchronous
limit before taking the smaller async/sync limit. Infinity no longer hides an
invalid synchronous setting. The separate QA helper now offers opt-in CGWindow
metadata monitoring without activating or controlling Draftly.

Automatically tested: 382 app tests in 57 suites and 350 core tests in 52 suites
passed. The unsigned Xcode build and 32 Python tests passed. The standalone helper
compiled, and its metadata self-check returned zero before NSApplication startup.
Deadline tests cover NaN, infinity, zero, negative values, sync and async modes,
and both directions of the smaller CPU limit. They assert typed failure and no
later clipboard, insertion, or Archive effects. Owner tests cover a synchronous
close before task creation, close during a wait, parent cancellation, and cleanup.
The dedicated import test covers JSON export, reimport, backup, restore, retained
identity, nested unknown data, disabled state, and execution after restoration.

Verified in use: the full development-signed QA refresh used source Debug library
hash prefix 84449a7bfbd8c787 before signing. The updated helper was also signed.
The helper had no window titles because macOS withheld them. No new permission
was requested. PID498 initially had visible normal window16182. Closing it in a
no-action control left zero visible normal windows. Direct qa.getAXState then
created visible window16188 under the same PID. This reproduces the observation
effect without any action or callback. It supersedes the earlier unresolved
Untitled-window report for this tested path.

The action case opened the neutral target explicitly and ran the URL prompt.
The Window menu selected First. Closing it closed the prompt. Two separate helper
Refresh readings showed zero visible normal windows. QA was not observed directly
between those readings. An explicit Open URL then reopened the target for content
and history checks. Text remained First followed by Second 🐼. History recorded
Cancelled at 02:19 local time. This verifies cancellation without an unexpected
visible reopen in that source-close case. More window combinations remain open.

The neutral engine-import-actions fixture was imported through the helper. The
inspector displayed futureStep, futureOption, and nested JSON with null. Export
Action wrote one file in a fresh temporary directory. Its rawPayload parsed equal
to the exact source object, including Boolean, null, and café 🐼. isEnabled stayed
false. The temporary export and directory were removed. Cancel left editing
unchanged. QA Disabled future step then recorded Success. QA Enabled future step
recorded Error with Unsupported steps before its preceding Must not run insertion.
The draft remained unchanged; both history entries are at 02:21.

The engine unknown disabled imports contract is now complete on this evidence.
This closes that named engine contract only. Inspector editing, separator import,
and the remaining API contracts keep their own acceptance. The strict engine
gate now has 39 diagnostics across thirteen partial records. One engine record
is complete. The 562-member API inventory is unchanged. QA and the helper were
quit; the helper monitor was turned off. No screenshot or raw log was saved in Git.
## Inclusion and queue regression checks — 20 October 2026

Implemented: the legacy runner now clears pending queue entries after failure or
cancellation. The async runner already cleared them. Completed effects remain.
The next run previously cleared these entries at startup; they did not execute
after the failed run, but they remained retained until then.

Specific tests cover selected UUID resolution, shared globals in included
scripts, disabled cycles, dynamic subtree cycle rejection, depth 50/51, repeated
sibling includes, and child failure/cancellation in both entry routes. Queue
tests cover timeout, current stored draft content, final callback parameters,
and fresh JavaScript globals with final parameter aggregation. They do not
require an undocumented shared JavaScript parameter object between queue items.

These checks are automatic evidence. Native callback receipt, configuration
precedence, and remaining entry-point acceptance stay open. No engine matrix
record is promoted by these tests alone.

## Imported separator presentation — 20 October 2026

Implemented: a shared presentation model retains separator identity and order.
The action list shows a non-executable heading and horizontal line. The editing
bar and Actions menu use dividers. Search, the palette, and executable pickers
exclude separators. Edit, Duplicate, and Delete remain available in the list.
Storage and raw imported payloads retain their existing format.

Automatically tested: six presentation cases cover visibility, groups, order,
headings, search, and payload retention. A library backup/restore case checks
separator identity, explicit order, and unknown null, Boolean, and Unicode fields.
The full run passed 388 app tests in 58 suites and 361 core tests in 54 suites.
Python32, the unsigned Xcode build, and the structural matrix check passed.
Strict engine parity still reports 39 diagnostics. Counts do not prove parity.

Verified in use: the complete isolated QA build had source Debug library hash
90d02b9dea4e0af1 before signing. Imported the neutral separator fixture. Observed
A, the B heading with a horizontal line, then C. B had no executable button.
Its context menu exposed Edit, Duplicate, and Delete. Changing B Order from 0
to 1 and saving moved it after C. Searching Neutral section returned no actions.
The neutral notes stayed unchanged. QA was quit after this check.

Pending: native bar/menu/picker checks, restart and native backup restoration,
and comparison of separator appearance with Drafts. Source-array order is not
accepted as an imported order contract. Direct engine execution of a separator
still has no accepted reference behavior. The separator engine record remains
partial. No screenshot or temporary export is stored in the repository.

## Native queue cancellation and separator restart — 20 October 2026

Verified in use on the same isolated QA build: separator Order 1 survived quit
and restart. The editing bar showed two action buttons and a divider, with no
separator button. The Actions menu exposed A and C and no executable B entry.
Native picker and full backup restoration remain pending.

Imported engine-queue-actions.json. Only the cancelling child has Archive as an
after-success effect. Root and later actions keep the draft. This isolates the
child result; completed effects of earlier actions are not rolled back.
Native URL confirmation and queue execution retained the child's exact neutral
Unicode text in Inbox. Neither ERROR sentinel appeared. History recorded
Cancelled for the root. The helper received case=queue and result=cancel without
the root success parameter. The counter-enabled helper showed one received
callback and remained at one after inspecting the saved draft. This is bounded
observation, not proof that no callback can ever arrive later. The first checks
used a helper without a counter; only the repeated check establishes the count.

The helper now counts received callbacks in memory and resets on Open. A request
identity prevents an old delivery completion from replacing a newer result.
Callback forwarding is unchanged. The helper compiled, its metadata self-check
passed, and no visible window opened during that automatic check. QA and helper
were quit after manual checks. Captures and raw logs remain outside the repo.

The matrix now links specific executed inclusion and queue regression cases.
It removes the stale claim that full-run dynamic depth is untested. The 50/51
boundary is a Draftly safety limit; the Drafts limit has not been established.
All three records remain partial. Error, timeout, multiple targets and remaining
native entry points still require acceptance. Matrix structure has zero errors.

## Native queued failure and timeout — 20 October 2026

Verified in use on the same isolated QA build: imported the extended neutral
queue fixture and ran the failure and timeout roots through URL confirmation.
Failure saved Queue failure completed write — café 🐼, then called context.fail.
The helper observed one qfailure-20261020-a error callback with Neutral queued
failure and no root success parameter. The draft remained in Inbox. History
recorded Error with that message. No child or later-action sentinel appeared.

Timeout saved Queue timeout completed write — café 🐼 in an allowAsync step and
omitted script.complete. The production scriptTimeout was 120 seconds and was
not changed. At 02:43 local time, the helper observed one qtimeout-20261020-a
error callback with The action operation timed out before it completed. The
draft retained the exact text in Inbox. History recorded Error with the timeout
message. Neither sentinel ran and Archive was not applied. Opening and closing
filters during the wait succeeded; their original state was restored. After
inspecting the draft and history, the helper still showed one callback.

Distinct case values identify each sequential request. These counts describe
the observation interval. The helper counts every received callback and does
not correlate it internally with a request identity. Both QA apps were quit.
No screenshot or raw session log is tracked. The fixture JSON has seven unique
actions; only child actions have an Archive effect. This turn changed fixtures
and acceptance records, not application code. The earlier full suites and build
remain the application-code baseline. Separate targets, App Intents, and other
native entry paths remain pending. The queue contract stays partial.

## Native queue with separate source and target — 20 October 2026

Verified in use: created a separate neutral destination and opened the existing
source in the isolated QA window. The multi-draft fixture validated a unique
target, saved Queue source retained in the source, and queued the cancelling
child on the destination. Native URL confirmation used the matching editor.
After cancellation, the editor showed Queue child completed write — café 🐼
in the destination. Both drafts remained in Inbox. Inspecting the source again
showed its exact retained content. No later sentinel text appeared. The helper
showed one qmulti-20261020-a cancel callback and remained at one after inspection.
Both QA apps were quit. The fixture now has eight unique actions.

This accepts separate-target cancellation through a matching visible URL owner.
It does not accept separate-target failure/timeout or App Intents. The headless
cancel route intentionally does not reveal a draft, while the matching visible
owner stays on the last processed target. Code inspection confirms that the
automation output returns the final editor identity, not the root identity.
No implementation change was needed. The queue record remains partial.

## Native inclusion cycle safety — 20 October 2026

Verified in use on the isolated QA build: imported the neutral cycle fixture.
Static A included B and B included A. URL execution returned An included action
refers to itself before the first script ran. Source stayed Queue source retained.
The helper observed one staticcycle-20261020-a error callback.

The dynamic root saved Cycle completed root write, selected its child through
the selected template tag, and reached a child with a static self-cycle. The
same error stopped the child script and root tail. The completed root text
remained in Inbox, Archive was not applied, and the helper received no discard
success parameter. It observed one dynamiccycle-20261020-a error callback and
remained at one after inspection. History recorded one Error per root. Both QA
apps were quit. Counts describe the observation interval; captures stay temporary.

Automatically tested: the focused inclusion, boundary, and execution API run
passed 35 methods in three suites. Specific cases cover full-run dynamic depth,
static expansion, repeated siblings, cycle errors, and retained prior effects.
The last complete application suites/build remain the code baseline; this turn
changed fixtures and acceptance records only.

The circular inclusion engine safety contract is complete on this evidence.
The archived reference does not define cycle-error wording or a numeric maximum.
The tested 50/51 limit is a Draftly safety policy, not verified equality with a
Drafts limit. Native equivalence across all entry points remains the separate
common asynchronous entry points contract. Two engine records are complete and
twelve remain partial. Strict engine parity still fails with 36 diagnostics;
the full Mac plan and the API member inventory remain open.

## CPU deadline and unreturned promise gap — 20 October 2026

Verified in use on the current isolated build: QA CPU deadline wrote CPU
completed write, then entered an infinite loop. The production synchronous
deadline remained ten seconds. Filters closed while the worker was running and
were restored afterward. URL execution delivered one cpu-20261020-a error
callback with the timeout message, no discard parameter. Text remained in Inbox;
the following insertion and Archive did not run. History showed Error at 02:50.
The count stayed at one after inspection. Both QA apps were quit. Direct UI and
App Intent CPU deadline checks remain pending.

Automatically tested: four invalid async limits (zero, negative, infinity, NaN)
failed explicitly before script effects. A new unreturned Promise.reject case
exposed a gap: the worker observes only the returned evaluation promise. A
discarded rejection waits for timeout instead of reporting its rejection reason.
The first focused run failed on classification and message. The retained test
marks only those two assertions as known issues. Other assertions still require
no later effects, no success parameters, preserved text, and no Archive. The
repeat ran two methods with four parameterized limit cases and two known issues.
This is recorded failure evidence, not accepted promise compatibility. The
matrix remains partial. No Promise replacement was added that would miss native
async-function promises or change valid catch behavior.

The frozen reference does not define collision precedence for included configured
values. Current root/child type conversion and child overrides need comparison
before choosing a policy. They remain a specific shared-inclusion limitation.

## Worker request authorization — 20 October 2026

Implemented: a per-worker authority registers serialized host requests before
dispatch. The receiver consumes the exact token, execution, step, deadline,
operation, and payload once. Altered requests do not consume the valid grant.
Consumed or revoked tokens cannot register again in that authority lifetime.
Cancel and close invalidate it. Existing session, step, and deadline guards stay.

Specific automatic cases cover six altered fields, revocation, expiration,
permanent invalidation, and concurrent consumers. Tests also call the real
receiver while a real runner waits at a fake host: wrong execution/step and
unknown/replayed tokens produce no unauthorized effects. The valid action then
continues and saves. These are internal boundary tests, not external UI attacks.

## Discarded rejection correction — 20 October 2026

Implemented: the runtime installs the JavaScriptCore unhandled-rejection SPI.
This observes intrinsic async-function promises as well as Promise.reject;
Promise is not replaced. Runtime ownership stays on the worker. Step and close
epochs reject callbacks after completion. Missing SPI support reports an error.
The earlier known classification/message issues are removed from the test.

Automatically tested: 388 app tests in 58 suites and 373 core tests in 58 suites
passed with no known issues. Cases include discarded rejections, async throws,
then-handler throws, normal catch/await handling, ended steps, and closed
runtimes. The unsigned Xcode build passed. Initial direct-runtime tests exposed
an invalid device fixture; it now supplies an object and requires a clean
bootstrap before checking rejection behavior.

Verified in use on a full isolated build refresh with Debug image hash prefix
655d52883b226fcc before signing: discarded rejection returned Error: Neutral
discarded rejection and retained Promise completed write in Inbox. Its tail,
Archive, and discard success parameter were absent. Intrinsic async rejection
returned Error: Neutral intrinsic rejection without changing that text. The
caught control saved Caught rejection completed and returned success. History
showed Error, Error, and Success at 02:57. The helper observed one correctly
identified callback per sequential case. Both QA apps were quit.

The earlier unreturned-rejection gap is resolved for these cases. The promise
and host-lifetime records remain partial for their other native requirements.
No total test count is used as API parity evidence. The system SPI dependency
is documented in actions-engine.md; public distribution remains out of scope.

## Busy cancellation and concurrent windows — 20 October 2026

Automatically tested: a CPU-bound action publishes a host marker after an earlier
effect and then loops. Cancelling its parent task returns cancelled, not timeout,
preserves that effect, suppresses its tail/Archive/parameters, and releases the
library for another successful action. With a configured 0.25-second synchronous
limit, this run measured 0.267919875 seconds from cancellation to result. This is
one measured run, not a production latency guarantee or acceptance threshold.

Three real-worker cases across consecutive steps passed: an old rejected timer
and an intrinsic promise waiting on an old timer cannot fail the next waiting
step; a caught intrinsic rejection leaves no sticky failure. Epoch checks alone
do not identify promise creation time. Late sources must also use the worker's
invalidated timer/callback paths. These tests exercise those actual paths.

Verified in use on QA image655d52883b226fcc: two independent windows opened the
source and destination drafts. QA Busy owner saved Busy owner retained in
AppWindow-2 and waited thirty seconds. A URL request on the distinct target in
AppWindow-1 returned An action is already running in this library. The second
draft kept Queue child completed write — café 🐼. The owner later returned
success with owner=finished; its history showed Success at 03:02. The helper
first showed the identified busy error, then count2 with the identified owner
success after its counter reset for the second Open. Both results were observed;
the final count alone is not per-request evidence. Both apps were quit.

This accepts the tested two-window URL overlap. Intent overlap and remaining
variants stay pending. No application source changed in this turn. Focused new
tests ran in the background; the previous full-suite/build baseline remains.

## Shortcuts fixture cleanup — 20 October 2026

The user confirmed permanent deletion of only Draftly QA Text — disposable and
Draftly QA Intent — disposable. Deleted each by its exact named confirmation in
Shortcuts. The library count changed from 41 to 39. A search for Draftly QA
returned no results. Cleared the search and quit Shortcuts. Earlier acceptance
records remain historical; the fixtures are no longer installed. The existing
CLI timeout limitation is not resolved by this cleanup.

## Strict evidence checks — 20 October 2026

Implemented: complete contracts cannot cite a directly disabled test/suite or a
test body containing withKnownIssue. The check reads the exact referenced
methods, including contract cases and supporting tests. Unrelated known issues
in the same file do not reject a complete record. Partial records can retain
known failures as evidence. Comments and string literals do not create methods
or failure markers. Missing cited methods also reject complete evidence.

An optional file field resolves suites whose names differ from their source
file. It must name an existing Swift file inside Tests. Absolute, escaping,
missing, and external symlink paths are rejected. The receiver-identity evidence
now names its actual source file. This remains lexical source validation; it
does not prove execution or inspect transitive helper calls.

Automatically tested: 37 Python tooling tests passed. Fixtures cover disabled
tests/suites, known issues, unrelated methods, case/supporting evidence, missing
methods, fake method text, alternate files, and path restrictions. Structural
matrix check has zero errors. Strict engine acceptance still has 36 diagnostics.
Application code did not change; its prior build/test acceptance is unchanged.

## Native selected identity and template inclusion — 20 October 2026

Verified in use on QA image655d52883b226fcc: imported the neutral inclusion
fixture with child UUID70F92D63-EC90-4AE9-A0C6-88D6FD068D11. Renamed that child
from QA Original child to QA Included renamed child in the inspector and saved.
The root's selected-UUID step retained its obsolete name. The next include used
the child's new name through a template tag. Both shared the same visits global.
Native URL execution saved Included visits: 2 — café 🐼, recorded Success at
03:10, and delivered one observed matching success callback with visits=2 and
shared=retained. Cleared action search and quit both QA apps.

This accepts those native identity and shared-global cases. It does not settle
configured-value precedence. The frozen reference distinguishes current action
configuration from explicit Action.configuredValues access to another action;
it does not specify a winner for included duplicate keys. Requires configuration
before first use is explicit in the reference, but Draftly lacks both the prompt
and state that distinguishes defaults from confirmed configuration. Those remain
implementation work. No guessed precedence or first-party import key was added.
The shared-inclusion record remains partial.



## Required first-use configuration — 20 October 2026

Implemented: `configurationKey.data.requiresInitialConfiguration` requests typed
configuration before execution. Imported defaults do not confirm user choice.
Each accepted required step records its identity, key, and type in namespaced
action metadata. Unknown values and payloads remain intact. Static includes
prepare before root effects. Dynamic includes prepare before child effects.
Confirmation belongs to the root action. Duplicate-key and child-value precedence
remain an open reference comparison; this change does not settle that contract.

Automatic: `swift test` passed 388 app tests and 390 core tests. The two new suites
contain fourteen test methods. They cover typed values, invalid responses,
confirmation reuse, new required fields, optional and disabled steps, atomic
rollback, cancellation, concurrent edits, ephemeral actions, and static/dynamic
inclusion ordering on both runner routes. Existing original scripts were not
changed. An initial expectation incorrectly allowed a response to edit an already
confirmed field. The corrected case expects the prior value to remain. The full
regression run passed after that correction.

Native: pending. The repeatable fixture is
`scripts/fixtures/engine-configuration-actions.json`. Keyboard cancellation,
accepted input, reuse after restart, and included-action prompts need manual QA.
No screenshot or raw log is retained in the repository. This record does not close
shared-inclusion parity.

Build: unsigned Xcode Debug build passed. Tooling: all 37 Python tests passed.
The matrix structure check reports zero errors. The strict engine gate retains
36 diagnostics; this feature does not promote the shared-inclusion record.


## Native first-use configuration — 20 October 2026

The isolated QA app was refreshed from the passing Debug build. Its Debug library
hash starts with 3d28cc07b2ff04f6 before development signing. Computer Use ran the
configuration fixture through the QA helper and normal run URLs.

Passed: the imported default appeared but still required confirmation. Changing
the text and pressing Escape cancelled without changing the source. The next run
showed the original default again. Configure accepted `Accepted café 🐼
configuration` and the editor displayed that exact value. After Quit and relaunch,
the same action ran without a configuration prompt and retained that value.

Static included configuration prompted before the root script changed text.
Escape kept the prior accepted text. Dynamic inclusion prompted after its root
script; Escape retained `Completed root before include`. The child and tail
outputs did not replace it. Execution History showed Cancelled for the first text
run and both inclusion runs, and Success for acceptance and post-restart reuse,
at 03:20–03:22 local time. QA and the helper were quit after inspection.

A helper input attempt inserted text into the existing URL instead of replacing
it. It created one extra neutral note in the isolated library. Setting and reading
the whole URL corrected delivery before the recorded configuration checks.
A transient invalid capture size during the restart check was resolved by reading
the same app again; the action was not restarted because of that observation.

Pending: native addition of a required field, Boolean and number controls, and
duplicate-key/child-value reference precedence. Static and dynamic inclusion
fixtures are now stored with the text fixture. No screenshots or raw logs were
added. This evidence does not close the shared-inclusion contract.


## Native typed configuration and schema change — 20 October 2026

Computer Use ran `engine-configuration-typed-actions.json` in the isolated QA app,
using the same Debug build as the previous check. The Boolean control initially
showed true. The number field showed 2.5. Switching the Boolean off and entering
`not-a-number` produced Enter a valid number. After OK, the form retained the
unchecked control and invalid input. Changing the number to zero and choosing
Configure succeeded. The script checked JavaScript types before writing
`{"enabled":false,"amount":0}` to the editor. History recorded Success at 03:23.

The action editor showed stored values false and zero. Its native export contained
those strings and the namespaced confirmation signatures. A revised native-format
installation payload retained the action and required-step identities, confirmed
values, and observed confirmation signatures, then added a required string field.
This was a constructed revision, not an unchanged export round trip. The next run
prompted only for New required neutral field. Accepting Added café 🐼 produced
`{"added":"Added café 🐼","enabled":false,"amount":0}`. History recorded Success
at 03:25. This proves that this imported revision did not prompt for the prior
confirmed fields. It does not prove all imported option or unknown-field behavior.

The temporary exported file was removed. QA and the helper were quit. Native
configuration collision and child-value precedence remain pending. No full
shared-inclusion acceptance is claimed.


Automatic persistence check: `swift test --filter
InitialConfigurationPersistenceTests` passed one method with two cases. Native
JSON export/import and backup restore used fresh in-memory stores. Full stored
action equality includes confirmation metadata, step identities, and unknown raw
payload. Each restored action ran without prompting and kept typed false and zero.
An added required key prompted alone; the next run reused its confirmation.
This is specific persistence evidence. It does not prove CloudKit convergence.
The previous full regression and build remain the latest full checks; this change
adds tests and fixtures only.


## Native completion and step lifetime — 20 October 2026

Computer Use used `engine-completion-actions.json` in the isolated QA app. The
Debug image remained 3d28cc07b2ff04f6 before signing. All three checks used normal
run URLs with a distinct callback case value for each run.

Completion epoch isolation passed. Step one saved an old Script handle, scheduled
a 100 ms stale timer, and called complete twice. Step two called that old handle
and scheduled its own 1000 ms completion. The final step required that the current
timer had run and the stale timer had not. It wrote Timer lifetime verified —
café 🐼. One success callback arrived. This also checks that the old completion
cannot advance step two before its current timer.

Duplicate completion failure passed. A completed write preceded a timer callback
that called complete twice and then context.fail. The note retained Completed
before duplicate failure in Inbox. The following sentinel script and Archive did
not run. The helper received one error callback with Neutral duplicate completion
failure. Returned rejected promise also passed: one error callback contained
Neutral returned rejection, the prior text stayed in Inbox, and the tail did not
run. Execution History at 03:28 recorded Success, Error, and Error respectively.
Transient observation errors were resolved by reading the same app. No action
was restarted because of a capture error. Both QA apps were quit after the check.

Automatic: the focused run of AsyncActionRunnerTests, EngineClosureContractTests,
WorkerPromiseEpochTests, ActionExecutionSessionTests, and ExecutionActionAPITests
passed 45 methods in five suites. The record cites specific normal, default, and
error cases; the total does not establish other contracts.

The completion/timer record is complete for this defined contract. URL/App Intent
timeout, busy, capability cancellation, and shared configuration acceptance remain
in their own open records. Returned rejection evidence does not close timeout.
No production code, screenshots, or raw logs were added in this check.

Matrix structure passed with zero errors. The strict engine check now reports
33 diagnostics, reduced from 36 by this one completed record. Three of fourteen
engine records are complete. These counts are not API compatibility percentages.


## Direct UI CPU deadline and automation timeout mapping — 20 October 2026

Computer Use selected QA CPU deadline from the action-list search in the isolated
QA app, using Debug image 3d28cc07b2ff04f6 before signing. The action wrote CPU
completed write before its infinite loop. Filters closed at the 4.7 second
observation and reopened at 8.6 seconds. The timeout appeared by the 11.5 second
observation. These are sampled observations, not a precise execution duration.
The configured synchronous limit remains 10 seconds. Inbox and the prior text
remained; the tail sentinel and Archive did not run. History recorded Error at
03:31 with the timeout message. App Intent CPU timeout remains pending.

Automatic: the focused AutomationTimeoutBoundaryTests and
AutomationEditorContextTests run passed nine methods. The new case executes a
real worker timeout with an injected 20 ms async limit through
AutomationActionExecution. It checks the final timeout report, retained execution
identity in AutomationActionError, error callback mapping without success
parameters, completed saved text, no tail or Archive, and one history record.
Existing busy-before-save tests cover two owner contexts.

This is coordinator and mapping evidence. RunDraftActionIntent.perform still
uses the shared AppController, and ApplicationURLRouter uses native confirmation
and callback delivery. The test does not invoke the App Intents framework or
prove one external callback delivery. Native acceptance remains separate.


## Current-build native queued timeout — 20 October 2026

The same isolated QA image ran QA Queue timeout root through a normal run URL.
The child wrote Queue timeout completed write — café 🐼 and waited without calling
complete. The root had queued a later sentinel action and added a success
parameter. The child requested Archive on success. The production async deadline
remained 120 seconds; it was not reduced for this manual check.

The helper showed no callback at about 0.8, 28.2, 62.4, and 111.8 seconds. By the
132.2 second observation it showed exactly one error callback, with the timeout
message and no root success parameter. These sampled observations bracket the
result; they do not measure an exact 120-second duration. The editor retained the
child text in Inbox. Neither the child sentinel nor the later queued action ran.
History recorded QA Queue timeout root Error at 03:34.

The action search was cleared, then QA and the helper were quit. This repeats the
older queued-timeout evidence on the current image. It does not cover separate
queued target timeout or App Intent timeout. Matrix structure passed; strict
engine remains at 33 diagnostics. Python37 passed. No production execution code
changed for these timeout checks.


## Atomic action installation by URL — 20 October 2026

Implemented: the action installation URL now decodes the full set, then calls
LibraryStore.saveActions once. The old per-action save loop could retain earlier
writes after a later storage error. The router shows the library only after the
batch succeeds. A missing library returns an explicit error. The run-action path
is unchanged.

Automatic: URLActionInstallationTests passed four methods. They cover a malformed
later entry, injected batch failure while replacing an existing action and adding
a new action, successful preservation of disabled unknown steps/raw Unicode
payload, and an unavailable library. Reload after a failed batch retains the
original action set. The combined automation/context/install run passed thirteen
methods. ApplicationURLActionTests passed both target-resolution regressions.
The unsigned Debug Xcode build passed.

Native: no new failure-injection UI check was run. Earlier native import evidence
uses the prior QA executable; this new transaction behavior is backed by specific
store/route tests. The isolated QA bundle still contains image3d28cc07b2ff04f6.
Refresh it before accepting later source-level changes through Computer Use.


## Automation cancellation before startup — 20 October 2026

Implemented: a cancelled task now receives a not-started cancellation report from
AutomationActionExecution.run. It no longer throws a raw CancellationError before
window resolution. The report retains the root action and target note identities.
This lets callers use the same typed cancellation mapping as a running action.

Automatic: AutomationPrestartCancellationTests passed. Cancellation precedes the
resolver, pending draft save, script effects, and history creation. Pending user
text remains dirty and stored text stays unchanged. AutomationActionError maps
the returned report to cancelled. The focused automation/context/boundary run
also passed. This background case does not prove native Shortcut delivery.


## Actual action intent method — 20 October 2026

Implemented: RunDraftActionIntent has an internal optional execution environment,
isolated on MainActor. When absent, perform obtains the current AppController
context. Tests supply a temporary library, window models, host, and model resolver
per intent instance. No global test override or fake execution result is used.
The name and uuid parameters and default initializer remain. Apple's AppIntent
reference uses @Parameter for visible inputs:
https://developer.apple.com/documentation/appintents/appintent .

Automatic: seven RunDraftActionIntentTests methods call the actual perform. They
cover a saved success and exact message, real CPU and async deadlines, busy window
reservation before pending-save, invalid/missing UUID, missing action/library,
script failure, and cancellation before startup and during a worker wait. The
marker host returns a neutral clipboard marker without touching the real clipboard.
These are in-process intent-method checks, not system Shortcuts invocation.

The first full run exposed setup timing in the old automation timeout test and
the new intent timeout case: a 20 ms deadline could expire before setup writes.
The corrected tests commit preparation in an earlier step. Only the waiting or
CPU step uses the short deadline. The limit was not increased to hide the race.
The corrected full run passed 401 app methods and 391 core methods.

Build: unsigned Debug Xcode compilation and App Intents metadata extraction passed.
Comparison with the prior RunDraftActionIntent metadata found only a different
ordering of resolvableInputTypes. Those lists have the same members. All other
metadata matched, including parameter names, titles, required flags, value types,
output, and identity. executionEnvironment is not an exposed parameter. The
temporary metadata copy was removed. Native Shortcut dispatch remains pending.

Review found another open boundary: a headless owner is absent from supplied
WindowModels. A second automation request can flush pending window edits before
the runner rejects its library as busy. A specific overlap regression and a
preflight check against the shared library gate are the next correction.


## Reject headless-owner overlap before pending saves — 20 October 2026

The first actual-intent regression reproduced the gap: the second request returned
busy, but had already saved pending target text. Three assertions failed for
save count, stored content, and dirty state. The owner was a real headless intent
waiting in the worker, not a synthetic busy flag.

Implemented: ActionRunner.isExecuting(in:) reads the canonical library execution
gate. Automation checks that gate before resolving a window or flushing pending
edits. WindowModel checks it before a single action and before batch preparation
and each batch iteration. Rejection returns a busy report or updates the existing
batch status. It does not save a scratch draft or change the selected draft. The
runner still acquires the gate when execution starts; this query does not replace
that authoritative exclusion.

Automatic: the final full run passed 402 app methods and 391 core methods. The
headless owner rejects five accesses: actual intent perform, immediate and
scheduled window actions, and immediate and scheduled batch actions. All retain
the pending target text, dirty state, stored content, and selection without a
second history record or runner start. Cancelling the owner records Cancelled
and finishes its host once. No real clipboard, window, or permission is used.
Fixtures construct dirty state directly so auto-save timing cannot race this
preflight check.

The canonical store test also checks the read-only query during execution and
after cancellation for two store wrappers, with and without a symlink. The focused
EngineClosureContractTests run passed its three methods. Native Shortcuts dispatch
and the new pre-save guard through system delivery remain pending.

Final unsigned Debug Xcode build and metadata extraction passed. Only name and
uuid remain exposed for RunDraftActionIntent. Python37 and matrix structure
passed. The strict engine result remains separately recorded; native gaps are
not cleared by this automatic run.


## Native Shortcuts delivery and exclusion — 20 October 2026

The isolated QA bundle was refreshed and development-signed from f55ab35. Its
Debug image hash starts with 870884f2388974b4 before signing. Shortcuts created one
new fixture, Draftly QA Engine — disposable, using Run Draft Action from the exact
Draftly Engine QA app search. The two earlier disposable shortcuts remain deleted.

At 03:51 the caught-rejection control returned QA Caught rejection completed in
Shortcuts and recorded Success. The CPU action then used its production 10-second
limit. Shortcuts showed the timeout error by the 13.4-second observation. QA kept
CPU completed write in Inbox without the tail or Archive; History recorded Error
at 03:52. This completes the remaining native Intent CPU-deadline check.

For exclusion, two QA windows held different drafts. A URL started QA Busy owner
on the first draft. A Shortcut Intent requested QA Busy rejected request on the
second. Shortcuts showed the busy error while the owner still waited. The second
editor retained Queue child completed write — café 🐼 with its old modified date.
The helper had no owner callback at that point and later received exactly one
success with owner=finished. History recorded the owner Success at 03:54.

The reverse check started QA Busy owner through Shortcuts with the QA editor left
Untitled and no selected draft. The owner was independent of that editor. A URL
requested the rejecting action on the other draft. It received exactly one busy
error callback. The Untitled editor stayed empty and the target retained its old
content/date. Shortcuts later returned QA Busy owner completed. The helper count
remained one. History recorded the owner Success at 04:00 and no new rejected run.

These native checks plus the specific passing contract tests close synchronous
deadline and process-local cross-window exclusion. They do not close all entry
points, cancellation adapters, or external callback lifetimes. The gate has no
cross-process exclusion claim.

## Native Intent queue timeout on another draft — 20 October 2026

A fifth neutral note contained only Queue timeout target neutral. The fixture
engine-queue-multiple-timeout-actions.json selected that unique marker, retained
Queue source retained before timeout on the root, queued the existing timeout
child on the other note, and queued a later sentinel on the root. Shortcuts ran
this root with the production 120-second async limit.

The child write was visible at the 6.4-second observation. Shortcuts still ran
at 92.8 seconds and showed the timeout by 129.6 seconds. These observations bracket
the result; they do not measure an exact duration. Both notes remained in Inbox.
The child retained Queue timeout completed write — café 🐼. The source retained its
root text. Neither the child tail nor the later queued action ran. Window menu
selection confirmed library-AppWindow-1, the original matching root window, now
displayed the final child target. History recorded the root Error at 03:57.

Shortcuts, QA, and the helper were quit after inspection. The new shortcut stays
installed for remaining cancellation checks. Its final settings are QA Busy owner
and the neutral root UUID. Its later permanent removal requires its own approval.
The new target marker has become the child text, so repeat the preparation before
running the multi-draft timeout fixture again. No screenshots or raw logs were
added to the repository. Separate-target failure remains pending.

Matrix structure passed. The strict engine gate now reports 27 diagnostics, down
from 33 after these two specific records closed. Five records are complete and
nine remain partial. These counts are not API compatibility percentages.


## Worker executor ownership — 20 October 2026

Implemented: ActionScriptWorker now checks its dispatch queue at queue entry,
evaluation, host requests and responses, state checks, timer/deadline callbacks,
finish, and explicit close/release. Construction runs inside the checked onQueue
body. The creation event marks completed initialization; bootstrap host requests
can occur before that event. ActionScriptRuntime and the legacy MainActor route
were not changed.

The optional internal probe emits only phase, per-instance queue-key match, and
main-thread state. It uses DispatchQueue.getSpecific with an actual private key;
it does not report a constant ownership result. No JSContext or JSValue crosses
through the probe.

Automatic: WorkerExecutorOwnershipTests ran the actual worker with a controlled
MainActor host suspension. One case completed through its timer; one cancelled
while suspended. Every captured event belonged to the worker queue and was off
the main thread. Explicit close was the last event and occurred once before close
returned. The focused ownership/promise/queue/async runner run passed 20 methods
in four suites. The full regression passed 402 app methods and 392 core methods.
The Original Drafts actions suite passed all five unchanged scripts through both
legacy and async routes. The unsigned Debug Xcode build passed.

Scope: close is observed after runtime.close and runtime=nil on the owner queue.
It does not prove the destructor thread or timing of arbitrary objects inside
JavaScriptCore's garbage collector. Native permission/dialog and CPU-bound task
cancellation cases still need acceptance on this assertion build. The prior
Shortcuts evidence identifies its earlier image explicitly. The worker record
remains partial. No screenshots or raw logs were added.

### Initial action catalog — 20 October 2026

Implemented: new empty libraries seed Copy, Share, Add to Reminders, Add Calendar
Event, Save to File, and Markdown Preview. The list order matches that sequence.
Each entry has its runnable step and icon. An existing nonempty catalog receives
no new defaults. These entries are editable library data.

Automatically tested: DefaultActionCatalogTests passed both disk-backed cases.
The cases check all six names, step types, group, icons, unique identities,
reopen identity, retained user edits, and an existing custom catalog.

Native verification: this check did not execute sharing, file panels, Calendar,
or Reminders. Their permissions and dialog variants retain their separate
acceptance status. Catalog loading does not prove native execution parity.

### Workspace snapshots — 20 October 2026

Implemented: Save Workspace, visible rows, and scripting currentWorkspace now
use one snapshot. It includes tag presence, advanced API options, unknown
metadata, list options, and all current basic filters. Save validates group and
theme references before persistence. An invalid reference keeps the sheet open
and leaves storage and the current view unchanged.

Applying a workspace now sets its API metadata after the basic controls. Their
sort observers previously overwrote imported per-folder order during application.
The new reopen regression detected this change before the correction.

Automatic cases cover disk save/reopen, equivalent restored rows, date and flag
filters, per-folder metadata, unknown fields, missing group rejection, scripting
tag presence, and unchanged editor text and selection. Native sheet acceptance
is pending. The settings UI still needs dates, flag options, accessed and
per-folder order, groups, and themes. This change does not close that delivery.

Validation result: the focused Workspace run passed 10 methods in two suites.
The full background run passed 405 app methods and 394 core methods. It compiled
the changed app and tests. No visible windows or native permission requests ran.
These totals are regression evidence, not a compatibility percentage.

### Workspace filter and order controls — 20 October 2026

Implemented: Workspace Settings exposes flag status, flagged inclusion in Inbox
and Archive, and order for each folder. Order includes modified, created, title,
and access date, ascending direction, and flagged-first. These controls update
the same API options that queries and visible rows evaluate. They replace the
old global sort control, which could be ignored by an imported folder override.

Start and end filters expose none, relative days, or an absolute date. Each
filter selects modified, created, or accessed date. The existing evaluator keeps
unknown access dates outside an active access filter and last in access order.
Options edits preserve unknown top-level, folder-order, date, and metadata fields.
The settings sheet still edits a value copy; Cancel does not persist that copy.
The mutation adapter validates JSON before serialization and leaves state intact
on error. An invalid Date payload initially caused an Objective-C exception;
the new validation rejects that case with a Swift error.

Automatically tested: the focused run passed 13 methods in three suites.
WorkspaceOptionsEditorTests checks effective order, flags, date filters, unknown
access dates, retained unknown fields, copy isolation, invalid values, and disk
reopen. Existing application and snapshot cases also passed.

Native verification: pending. No native window or permission dialog opened in
these tests. Geometry and controls must be checked with the refreshed QA build.
Group/theme controls, shared theme storage, and the other Settings contracts
remain open. This entry does not close Workspaces or personalization.

Regression result: 408 app methods and 394 core methods passed. The unsigned
Xcode Debug app build passed after project regeneration. Native acceptance stays
pending; these counts do not prove visual or API parity.

### Workspace presentation selectors — 20 October 2026

Implemented: Workspace Settings has action-list and action-bar group selectors,
and light/dark preferred-theme selectors. Group and custom-theme choices store
identities. No Override removes only that option. Missing references remain
visible until the user replaces or clears them. Save resolves all references
before persistence. Changing a reference retains its unknown fields and removes
obsolete name, UUID, and type fields before setting the new identity.

Automatically tested: the new reference mutation case checks retained unknown
fields, custom-to-built-in theme changes, group identity resolution, and clearing
one reference without removing another. The full run passed 409 app methods and
394 core methods. The unsigned Xcode Debug build passed.

Verified in native QA: refreshed all runtime images and signed the isolated app.
The pre-sign Debug library SHA-256 starts with 61365f518ab762a2. Created the neutral
QA Workspace options 🐼 in the isolated library. Selected Inbox order Accessed,
Flagged First on, absolute Start Date 20 October 2026 on Modified, Action List
Imported, and Dark Appearance Dark. Save and reopening Edit retained all values.
Changing Flagged First off and cancelling retained the saved on value when Edit
was reopened. Cancelling the first new workspace left the list empty. The form
scrolls to controls; its visible sections and date field were inspected.

Limits: no comparison with Drafts geometry, custom-theme native selection,
relative-date input, full application to the main window, or process restart was
accepted in this check. Library Organization tab labels visibly overlap; repair
and recheck that layout. Shared themes are still local preferences and require
the planned library migration. QA was quit; the neutral workspace stays for the
remaining checks. No screenshot or raw log is tracked.

### Library Organization section layout — 20 October 2026

Implemented: replaced the collapsing tab strip with a native segmented section
picker. The picker has a bounded width and switches the existing section bodies.
The previous strip drew all three labels on top of each other in the native QA
sheet. No library operation or stored format changed.

Build: the unsigned Xcode Debug app build passed. No automatic window tests were
added for this visual correction.

Verified in native QA: refreshed and signed the isolated app. Opened Library
Organization and inspected Groups, Actions, and Workspaces. All section labels
are separate and legible. Each selection showed its corresponding list and
controls. The saved QA Workspace options 🐼 remained in Workspaces. The app was
quit after inspection. This check accepts this layout regression only; full
Drafts inspector comparison remains pending. Captures stayed transient.

### Shared theme definitions and local migration — 20 October 2026

Implemented: EditorThemeDefinition uses stable UUIDs and generic theme records.
It keeps unknown JSON fields structurally, including nested arrays and objects.
JSON whitespace and key order are not retained. Theme saves, deletion, migration,
and restore roll back on storage failure. Name and color validation runs before
writes. Themes are an optional backup field; version-one backups without that
field remain readable. The Core Data schema is unchanged.

Editor rendering, Settings, Workspace selectors/resolution, and the scripting
theme catalog now read library themes. Built-in and custom references remain
distinct, including a custom theme named Dark, Light, or Default. Theme editing
uses a temporary copy and reports save errors without dismissing the sheet.

Startup migrates legacy editor.themes once per device and library. A generic
migration marker commits with the themes. Local legacy data is removed only
after success. The existing library definition wins when its UUID already exists;
a conflicting name with another UUID returns an error. Migration errors remain
visible and keep legacy data for retry. A device-specific local marker identity
lets a second Mac migrate its own definitions. A prior migration prevents deleted
themes from being imported again. Theme choice, font, margins, and other device
preferences stay local.

Automatically tested: five core cases cover old shape, unknown fields, reopen,
backup compatibility, validation, rollback, migration markers, and deletion.
Three app cases cover local preference preservation, invalid data, retry after
storage failure, two device identities, and no reimport after deletion. Existing
Workspace tests now use actual library themes instead of global theme defaults.
The focused migration run passed all eight cases. Full regression and build
results follow. No native windows or permission requests ran in these tests.

Pending: native create/edit/cancel/restart, restored theme application, full
Drafts theme import, and connected Mac+VM sync. Shared record storage does not
prove synchronization acceptance. Execution history backup remains separate.

Final regression result: 412 app methods and 399 core methods passed. The
unsigned Xcode Debug build passed. These totals show regression coverage only;
native UI and connected sync acceptance remain pending.

### Shared themes native create, cancel, restart, and Undo — 20 October 2026

Verified in isolated QA on Debug image 57c6cac3f5d8643d before signing: created
QA Neutral Theme 🐼 with text F0F0F0, background 17324D, heading 007AFF, and dark
appearance. Save selected the theme. Reopening Edit showed the saved values.
Changed background to FFFFFF and cancelled. Quit was confirmed by the app
inventory, then QA was launched again. Settings retained the selected theme.
Edit showed background 17324D and the other saved values. Cancel did not persist
its temporary change. Font, size, spacing, and layout controls kept their values.

The editor rendered the neutral Busy owner retained draft with the dark blue
background and light text. Appended a neutral suffix and selected owner. Changed
the selected theme to System in Settings. After closing Settings, the editor
still had the full text and owner selection. Undo removed the suffix. Redo
restored it. Undo restored the neutral source again before Quit. The QA inventory
confirmed the app stopped. The new theme remains available; the local selection
is System. No personal library, screenshot file, or raw log was used or tracked.

This accepts the tested create/save/edit-cancel/restart/render/selection/Undo
path. It does not accept backup restore in the native app, every theme reference,
Drafts theme import, migration from actual legacy preferences, or Mac+VM sync.
Those checks stay pending. No source code changed in this verification.

### Drafts theme file import — 20 October 2026

Implemented: Editor Settings offers Import Theme for .draftsTheme and JSON files.
The native file panel reads a selected file with scoped access. Import validates
the file before opening a review copy. A name conflict offers Replace, Import as
New, or Cancel. Replace retains the existing identity; New requires a unique
name in review. Cancel does not save. Save uses the atomic library operation.

The parser validates UTF-8 JSON, required containers, strings, supplied Boolean,
hexadecimal colors, and named color references. It maps normal foreground,
editor background, heading color, and dark appearance. It supports text.heading
from the official sample and text.header from the guide. The complete original
source stays under draftsSource, including unknown fields and unapplied scopes.
The review explicitly states the current rendering limits. This is partial
visual theme support, not full Drafts theme parity.

Reference: the official theme-format page and official light sample were archived
on 20 October 2026 with URLs and SHA-256 hashes under theme-format-reference.
This new theme reference does not change the frozen Actions reference.

Automatic tests: nine parser methods cover named/literal colors, fallbacks,
identity, unknown data, malformed fields, unsupported values, and backup recovery.
A separate offline contract test checks the archived official sample hash,
expected mapped colors, and complete retained source. Full regression and build
results follow. Native import, replacement, cancellation, and full styling remain
pending. No dialog was opened by an automatic test.

Regression result: 412 app methods and 409 core methods passed. The unsigned
Xcode Debug build passed. The new import button and native file workflow still
need Computer Use acceptance on a refreshed isolated build.

### Native Drafts theme import and file-type correction — 20 October 2026

Native import exposed a file-panel defect. The .draftsTheme file was disabled,
although typing its full path allowed Open. The installed Drafts registration
reports com.agiletortoise.drafts.theme for that file. Requesting the extension
with a JSON supertype returned a different dynamic type. The panel now uses the
extension's actual type without adding a JSON conformance requirement. JSON
files remain supported. Apple UTType documentation was checked through Context7.

Automatically tested: ThemeImportFileTypeTests passed three cases using actual
filesystem content types for .draftsTheme, .json, and .txt. The supported files
match the panel filter; .txt does not. These tests create no windows. The unsigned
Xcode Debug build passed. The earlier 412 app/409 core full regression remains
separate evidence; no new full run is claimed for this small filter correction.

Verified across the initial and corrected QA builds: the same neutral
.draftsTheme was enabled after the correction. The corrected pre-sign Debug
library hash starts with 4c61b327186d3b7a. Open showed the imported name, mapped colors, dark appearance, and rendering
limit notice. Cancel left only System and QA Neutral Theme 🐼 in the catalog.
A later import Save installed QA Imported Theme café 🐼. Updated the neutral
source background from 17324D to 112233, imported again, selected Replace,
reviewed, and saved. Edit showed 112233. The catalog had one imported entry and
one prior neutral entry, with no duplicate after replacement. The app was quit.
The imported fixture remains selected in QA. No personal library was changed.

Limits: Import as New rename, cancellation at the name-conflict alert, native
UUID inspection, restore, full scope/interface styling, and sync remain pending.
No screenshot or raw log is tracked.

### Imported theme scope rendering — 20 October 2026

Implemented: exact theme scope resolution supplies colors, weight, traits, and
relative size. Named editor colors resolve independently from interface colors.
The renderer applies Markdown heading/level, bold, italic, strike, inline-code,
quotation, and link scopes. Custom syntax ranges use their exact supplied scopes.
Selection and caret use imported interface colors. Unspecified scope fields keep
the current attributes. Full theme equality invalidates the editor cache, so a
source-only style change no longer waits for a text or basic-color change.

The user font is the base. Relative size factors are Draftly policy: extraSmall
0.8, small 0.9, normal 1, large 1.1, extraLarge 1.2. The reference specifies size
names and relative behavior, not exact factors. These factors need comparison
with Drafts and are not accepted as measured parity. Theme source has no inferred
ancestor scope inheritance. Normal text style is applied before syntax styles.
Edits to imported basic colors update their known source fields while retaining
other scopes and unknown data. Unchanged source remains structurally unchanged.

Automatically tested: resolver cases cover nine weights, five sizes, all 16
trait combinations, malformed options, exact matching, and source retention.
App tests inspect actual text attributes for Markdown/custom scopes, UTF-16
selection, monospace, heading size, underline/strike/italic, and colors. A source-
only change updates hosted editor attributes and caret/selection colors. Hosted
checks use an offscreen test window; no window is shown or moved. A core edit
case checks source/basic-field coherence. Full regression and build follow.

Pending: native rendering and Undo acceptance for this new path, remaining
built-in syntax scope mappings, active-link styling, current-line highlighting,
other interface colors, and comparison of relative sizes. The UI notice still
states that unsupported styling is retained without being applied. This does
not close complete theme parity or the broader Mac plan.

Regression result: the full run passed 415 app methods and 416 core methods.
A final focused editor run passed both methods after making text.heading take
precedence over the legacy text.header alias. Its fixture includes conflicting
alias styles and checks that the legacy italic trait does not leak into the
chosen heading style. The full run was before this last alias correction.
The unsigned Xcode Debug build passed after the alias correction. QA has not yet
been refreshed for this renderer; native acceptance remains pending.
