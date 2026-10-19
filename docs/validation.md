# Validation

Run `swift test` and `scripts/build-app.sh --local` before a release.

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
