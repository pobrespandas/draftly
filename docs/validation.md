# Validation

Run `swift test` and `scripts/build-app.sh --local` before a release.

For the current implementation and remaining work, read [project status](status.md).
The sections below are historical records. Their test counts describe each run.
The user removed session evidence and all screenshots on 19 October 2026.
Artifact paths in older records are historical and may no longer exist.

## Settings and personalization — 22 October 2026

Complete Core681/app815 passed with XML/discovery matching. Python80 and matrix0
passed. Baseline Core had three WorkerPromiseEpochTests timeout issues; focused
characterization passed. Both results are retained. No deadline or retry changed.
The [Settings record](settings-personalization-2026-10-22.md) lists the functional
regressions, native shortcut/editor/theme checks and remaining acceptance.
This is not full Settings, visual, physical-key or iCloud acceptance.

## Action inspector — 22 October 2026

Core679/app810 passed with XML and discovery inventory checks. Python80, local
Debug and signed Release builds passed. Structural matrix check returned0.
Strict engine acceptance remains six partial contracts and18 diagnostics.
Specific control, shortcut and atomic Save cases are in the
[inspector record](action-inspector-2026-10-22.md). That record also separates
manual Cancel/Save, symbol search, editing and step-order checks from Pro and
execution limitations. No accepted microphone check was repeated.

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

### Native imported scope rendering and editor preservation — 20 October 2026

Verified in isolated QA Debug image 6db19889a60171b9 before signing: replaced the
neutral imported theme with explicit heading size, bold/underline, italic,
inline-code foreground/background/monospace, strike, selection, and caret styles.
Created Theme scope QA 🐼 with neutral Markdown and Unicode. The visible editor
showed the larger colored heading, bold underline, italic text, highlighted
monospace code, strike, and orange caret. Selected café 🐼, switched to System,
and returned to the editor with that selection and the text intact. Undo removed
the pasted fixture text. Redo restored it. The saved fixture remains in QA.

Selected the imported theme again and edited its heading color to #FF00FF in
Settings. Save succeeded. The existing heading became magenta without changing
the draft. This checks that edits to known source fields reach the renderer.
A possible visual weight difference prompted an added attribute assertion: the
italic run has italic but not bold traits. Both focused editor methods passed.
No source fix was required for that observation. QA quit was confirmed.

Limits: this is native Draftly acceptance for the tested Markdown scopes and
transition. It is not a measured Drafts font/size comparison. Custom syntax and
all weight/size combinations retain their automatic evidence but still need
native coverage. Other built-in syntax mappings, active links, current-line and
remaining interface colors, restoration, and sync remain open. The local QA
selection is the imported theme; its heading is #FF00FF. The library has six
neutral drafts. No screenshot file or raw log is tracked.

### Active link theme rendering — 20 October 2026

Implemented: Link Mode applies an imported link scope to detected URL ranges and
AppKit link presentation attributes. Scope lookup uses text.linkModeLink first,
then text.activeLink, then text.link. This is the current mapping policy; it still
needs comparison with Drafts. Exact scope fields retain their existing behavior.
The editor records its original optional link attributes once. Removing a theme
or disabling Link Mode restores that original value, including nil defaults.
Text attributes are rebuilt, so disabling Link Mode also removes link targets.
No test opens a URL or sends network traffic.

Automatically tested: the new hosted-editor regression first failed four color
assertions on the previous renderer. It now passes through theme on/off and Link
Mode on/off transitions. It checks URL targets, storage colors, actual AppKit
link colors, native attribute restoration, Unicode selection, and unchanged text.
The focused run passed five methods in the rendering and redraw suites. Hosted
checks use an offscreen window only. The earlier full regression is separate
evidence; this entry does not claim a new full run.

Native acceptance and exact Drafts scope precedence remain pending. Other syntax
and interface theme coverage, current-line highlighting, backups and sync stay
open. No source theme or public scripting contract changed.
The unsigned Xcode Debug build passed after the link rendering correction.
QA still has the earlier renderer and needs refresh before native acceptance.

### Native active link theme check — 20 October 2026

Verified in use: refreshed isolated Engine QA from the Debug build. The debug
library hash before signing starts with aedb832f1923da7b. Imported the neutral
theme with text.linkModeLink foreground #00FF88 and underline. Created Link QA
café 🐼 with https://example.invalid/neutral. Link Mode showed the green,
underlined URL. Selected café 🐼 and disabled Link Mode. The URL returned to
normal text; the Unicode selection and full content remained unchanged. No URL
was opened. QA quit was confirmed from the app inventory. Seven neutral drafts
remain. No screenshot or raw log is tracked.

This closes native acceptance for that color and mode transition only. Native
theme removal while Link Mode is enabled and measured Drafts scope precedence
remain pending. Automatic transition checks retain their separate evidence.

### General Settings reference inspection — 20 October 2026

Read-only inspection of installed Drafts 54.1.1 confirmed these General controls:
Launch at login; Show main window at launch; Show in menu bar; Index drafts in
Spotlight; Show custom TouchBar in editor when available; main window, quick
capture, and capture clipboard shortcuts; New draft after; action After Success
move behavior; and advanced find preference. Marked integration, Developer Mode,
and Disable Drafts Pro also appear. Their presence does not add them to the
agreed scope or prove implementation in Draftly. No option was changed.

Observed values were login off, main window on, menu bar on, Spotlight on,
TouchBar on, new draft after 30 minutes, and Create New Draft after a successful
move. These are current reference values, not verified factory defaults. Startup
choices, configurable global shortcuts, and the other included missing controls
need implementation and acceptance. Do not infer Restore Last Draft from this
inspection. Startup must preserve explicit URL/menu routing and pending edits.

### Launch at login — 20 October 2026

Implemented: General Settings uses SMAppService.mainApp registration. The model
reads the system status, including external changes after app activation. It
keeps approval pending distinct from enabled. Registration and removal errors
remain visible. Overlapping changes cannot start a second operation. No local
Boolean substitutes for system registration. A missing service disables the
control with an explicit installation message.

Reference: Apple ServiceManagement SMAppService mainApp, status, register, and
unregister documentation was consulted on 20 October 2026. These framework
contracts do not change the frozen Actions reference.

Automatically tested: three isolated methods cover registration, approval,
external status refresh, removal, both failure paths, and overlapping removal.
They use injected operations; no test changes login items or opens Settings.
Full regression passed 419 app methods and 416 core methods. The unsigned Debug
build passed. These counts do not prove compatibility of unrelated contracts.

Verified in use: refreshed signed isolated Engine QA. General shows Launch at
login off and disabled, with the installation message. The actual service status
maps to notFound. This proves the unavailable UI path on this QA installation.
It does not prove registration, removal, approval, persistence, or launch at an
actual login. Those checks remain pending on a service-capable installation.
No system login item was added. Main-window-at-launch and configurable global
shortcuts remain pending.

### Main window at launch — 20 October 2026

Implemented: General Settings stores Show main window at launch locally, with
the previous enabled default. When disabled, the library scene suppresses its
default presentation and restoration. Explicit requests still use openWindow.
The app installs that opener at scene startup, without requiring a LibraryView.
A request received before scene setup waits and replays once. It retains the
pending draft identity. Replacing the opener does not replay a completed request.
The app delegate handles a Dock reopen with no visible windows as an explicit
request. Changing the preference does not close or replace an active editor.

Automatically tested: the two added methods cover compatible defaults, stored
choice, queued requests, replacement of the opener, and delivery of the selected
draft without creating another note. Existing pending routing checks cover save
failure and window ownership. Full regression passed 421 app and 416 core
methods. Tests do not show windows or activate the app. The unsigned Debug build
passed before native checks; final build results are recorded below.

Verified in use on isolated QA: disabled the preference, quit, and started QA.
The read-only helper reported zero visible normal windows and zero total window
records. A URL then opened Busy owner retained with its existing content. Quit
again and sent the same URL to the stopped app; a new process opened the correct
draft. Closed the main window and used the capture shortcut. The independent
Capture window opened with its previous neutral buffer intact. Opened Settings
without a main window, restored the preference, quit, and started again. The
main window opened. The seven saved drafts were retained. No screenshot or raw
log is tracked.

Native Dock reopen, multiple restored windows, failed-save startup, and signed
installation variants remain pending. The last cleanup removed the redundant
LibraryView opener and added the Dock delegate path after the native sequence.
Those two final changes do not have new native acceptance. This entry does not
close all startup, Settings, or engine acceptance.

After the final opener cleanup and Dock handler, all ten focused preference and
pending-routing methods passed. The final unsigned Xcode Debug build passed.

### Configurable global shortcuts — 20 October 2026

Implemented: General has recorders for Main Window, Quick Capture, and Capture
Clipboard. The existing capture default stays Control-Option-Command-N. The
other two remain unset for compatibility. Clear disables a binding. Escape
cancels recording. Delete clears it. Recording stores the physical key code
and display key. Earlier command preferences remain readable. The global
assignments use the same normalized conflict validator as actions and commands.
New assignments also require Command, Control, or Option. Existing imported
actions retain their shortcuts.

The app registers each enabled key with Carbon. It reports individual register
errors. It routes an event only when its signature and registered identity match.
Reload and termination release registrations. Recording suspends registrations
and restores them on completion, cancellation, or window focus loss. Only one
recorder is active at a time. Menu Quick Capture uses the configured binding.
Handler installation failure has an explicit error path. These statements
describe implementation, not full native acceptance.

Automatically tested: three core methods cover old data, defaults, physical key
persistence, clearing, normalized global/command/action conflicts, invalid
assignments, and malformed override fallback. One app method checks legacy
key-code and Carbon modifier conversion without registration. Existing command
contracts remain green. Full regression passed 422 app and 419 core methods
before the final malformed-key fallback and handler-error changes. After those
changes, all six focused methods passed and the unsigned Debug build passed.
No automatic test registers a global shortcut or opens a window.

Verified in use on isolated QA: Command-Q was rejected with a Quit conflict
without quitting. Recorded Control-Option-Command-J/K/L for the three entries.
Escape retained the existing capture assignment. Restart preserved all three.
The configured capture shortcut opened the independent capture window when
sent inside QA. Clear removed the main and clipboard assignments. Restored the
original capture shortcut. Seven drafts and the neutral capture buffer remain.
The system clipboard was not read or changed for this sequence.

An attempted synthetic shortcut from the helper app did not open capture. Its
cause is unresolved: no assertion is made that registration or global event
delivery passed. Verify physical delivery from another app, Main Window and
Capture Clipboard routing, system conflicts, focus-loss cancellation, and
non-US keyboard layouts. The final handler-error and malformed-override changes
were built and automatically tested after the native sequence; QA needs refresh
before their native checks. Settings and global shortcut acceptance remain open.

### Global shortcut event lifetime — 20 October 2026

Implemented: each registration now receives a fresh process-local identity.
Reload, recording suspension, and shutdown invalidate the active identity map.
A Carbon callback queued before a reload cannot route through the replacement
binding. Identity exhaustion reports an error instead of wrapping to an old ID.
This fixes a lifetime risk found during review. It does not explain or close the
separate failed synthetic delivery attempt from another app.

Automatically tested: stale IDs stay inactive after replacement and suspension;
an allocated but unregistered ID cannot route; the UInt32 limit cannot wrap.
All three app mapping/lifetime methods and three core global shortcut methods
passed. The unsigned Debug build passed. No test registers a system hotkey.
Native physical delivery and late event acceptance remain pending. Refreshed QA
before this identity change and left it open for a requested physical key check.
The installed image does not yet contain this last lifetime correction.

### After Success navigation reference — 20 October 2026

Read-only inspection of Drafts General confirmed exactly two choices for When
Action “After Success” Moves Draft: Create New Draft and Open Next Draft. Create
New Draft is the current selection; this is not a verified factory default.
Closed the menu and Settings without changing a value. Draftly has not connected
this preference yet. Its integration must preserve script-selected drafts, final
automation results, failed saves, and the agreed batch selection behavior. The
current single and batch execution paths are separate; do not add navigation
only to one path and claim full acceptance.

### After Success move navigation — 20 October 2026

Implemented: General exposes Create New Draft and Open Next Draft. The local
preference defaults to Create New Draft and treats unknown stored values the
same way. A successful action with an explicit Archive or Trash disposition
uses the preference only when that disposition moved the original draft and
the editor still shows it. Script-selected drafts remain selected. Error,
cancellation, timeout, and failed pending saves do not trigger navigation.

Create New Draft opens an unsaved scratch draft. It does not insert an empty
library record. Open Next Draft uses the captured visible order, skips drafts
that are no longer visible, then checks preceding drafts in reverse order. If
none remain, it opens a scratch. The preceding-draft fallback is Draftly policy
until comparison with Drafts can verify it. A disposition that leaves an already
archived draft unchanged does not trigger navigation.

Single context commands share the navigation helper. Multiple-target commands
keep the agreed last-processed-draft behavior. That deliberate batch rule is not
claimed as measured Drafts parity. Headless execution retains its result flow;
it has no existing window to navigate.

Window execution now keeps the processed draft identity separate from the
post-action editor selection. The legacy report-returning adapter remains.
Automation uses the outcome identity. URL routing does not reopen an older
result over an already handled visible owner. Success parameters and the runner
report are unchanged. Navigation from an action does not cancel its own task.

Automatically tested: eight methods cover successful Archive/Trash, scratch
creation, visible order and fallback, failure, cancellation, timeout, failed
pending saves, script-selected editors, unchanged destinations, automation
identity, single and multiple context commands, and defaults. Full regression
passed 432 app and 419 core methods. The unsigned Debug build passed. No test
shows a window. Native Settings persistence, action-panel execution, URL display
behavior, selection/focus/Undo, and exact Drafts behavior remain pending. QA is
still on the earlier image for the requested physical global-shortcut check.
This entry does not close Settings or full action acceptance.

### Native After Success navigation — 20 October 2026

Verified in use on isolated Engine QA. Refreshed from the Debug build; the debug
library hash before signing starts with 5abde529d2c39aa1. Imported the reproducible
settings-navigation-actions.json fixture. Both actions appeared in the Actions
menu. Created Navigation A café 🐼 with a neutral second line. Ran QA Navigation
Archive. The action completed and the editor became an empty Untitled scratch.
Last Draft reopened the original text. Its Archive control was disabled and
Move to Inbox was enabled. The original content was retained.

Changed General to Open Next Draft. Created Navigation C café 🐼, then Navigation
B café 🐼, with the list sorted by Modified descending. Ran QA Navigation Trash
on B. The action completed and selected C, the next visible row, with its full
text intact. Quit QA, confirmed that it stopped, and restarted. General still
showed Open Next Draft. Restored Create New Draft and confirmed the value.

Three neutral drafts were added. Inbox now shows eight drafts. A remains in
Archive and B remains in Trash. No permanent deletion occurred. No screenshot
or raw log is tracked. QA remains open with the original capture shortcut for
the pending physical global-key check. The helper remains open.

This accepts the tested Actions-menu paths and preference persistence. It does
not accept action-panel invocation, native URL result presentation, Undo across
navigation, fallback at the end of the list, or exact Drafts action behavior.
Their automatic or earlier evidence remains separate. No new source behavior
changed in this verification turn, so the prior build and test results apply
only at their recorded scope.

### Native panel and URL navigation — 20 October 2026

Verified in use on the same isolated QA image, 5abde529d2c39aa1 before signing.
Created Navigation Panel café 🐼 with neutral text. Opened the action panel,
searched for QA Navigation Archive, and ran its button. The action completed
and the editor became an empty Untitled scratch. This accepts the tested panel
path with Create New Draft.

Created Navigation URL café 🐼. Draft Info showed identity
638B9094-2E65-45F4-B038-4C5EBF784204. Sent draftly://run through the helper, using
QA Navigation Archive and a neutral success callback with case=navigation.
Confirmed Run Action. The visible owner became an empty Untitled scratch. The
original was not reopened over it. The helper showed one success callback and
still showed one on a later observation. This accepts that visible-owner URL
presentation path; headless and other termination paths retain separate evidence.

In the new scratch, pasted Navigation scratch Undo café 🐼. Undo restored empty
text. Redo restored the full Unicode string. Last Draft then reopened Navigation
URL café 🐼 with both original lines unchanged and Archive disabled. This accepts
Undo/Redo within the new scratch and retention of the archived original. It does
not prove preservation of an older draft's Undo stack across navigation.

Two more neutral originals and the scratch were added. The two originals remain
in Archive. Inbox shows nine drafts. The action panel remains open with its QA
search. General remains Create New Draft; capture keeps its original global key.
QA and the helper remain open for the physical-key check. No source change,
screenshot, or raw log was added in this verification turn. Exact Drafts action
behavior, list-end fallback, multiple-window native navigation, and remaining
Settings acceptance stay open. No new automatic test run is claimed.

### Execution history backup — 20 October 2026

Implemented: version 1 backups now include optional runs. Older backups without
the field remain readable and do not remove existing history. Export includes
all stored execution records, including records whose draft or action no longer
exists. IDs, dates, status, messages, and relations are retained. Restore remaps
a run's draft relation when it creates a conflict copy of that draft. A run-ID
collision with different data keeps both records. Identical records keep their
identity without duplication. Duplicate run IDs within an incoming backup are
rejected before any write. All restore writes share the existing transaction.

ActionRun now preserves unknown JSON fields through storage and backup. The
generic lossless JSON value moved to JSONValue. ThemeJSONValue remains a public
alias, so existing theme APIs retain source compatibility. Known date fields
continue to use the encoder/decoder date strategies. No Core Data schema or
public scripting identifier changed. Credential storage and local file grants
remain outside the backup contract.

Automatically tested: six methods cover exact metadata and unknown fields,
large numeric values, Unicode, disk reopen, repeated restore, older backups,
orphan records, conflicting drafts/logs with relation remapping, atomic failure,
duplicate identities, and date strategy compatibility. Full regression passed
432 app and 425 core methods. No test opens a window or accesses a user library.
Native export/import/restart and connected Mac+VM synchronization remain pending.
This entry does not accept the full backup or synchronization matrix.

The unsigned Xcode Debug build passed after the history backup changes.

### Atomic file import — 20 October 2026

Review found that the native Import command saved actions and notes one at a
time. A later storage error could retain part of the same file. Implemented a
shared LibraryFileImport service and connected the command to it. Each action
file uses saveActions once. Each note file uses saveNotes once and retains the
existing content-conflict copy rule and imported dates. Different contents with
the same identity within one file now receive separate identities, so the later
entry cannot overwrite the earlier text. Backup files use restore, including
execution history. A recognized invalid backup fails instead of becoming text.
The native file reader scopes access to each selected URL.

The atomic boundary is one file. A multi-file selection retains earlier files
when a later file fails. This is explicit behavior, not a claim that the whole
selection is one transaction. Text and malformed JSON retain distinct routes.

Automatically tested: five methods cover action replacement/new-record rollback,
note/revision rollback, successful retry, imported metadata, duplicate identities
with distinct content, backup history routing, invalid backup rejection, and
plain text versus invalid JSON. Full regression passed 432 app and 430 core
methods. The unsigned Debug build passed. Final focused checks add one-commit
assertions for action and note files; their result is recorded below. No test
opens a panel or accesses a user library. Native import failure injection and
full export/import/restart acceptance remain pending.

All five final focused import methods passed, including the commit-count checks.

### Native backup recovery and restart — 20 October 2026

Refreshed Engine QA from the Debug build. The debug library hash before signing
starts with 3351ca8f3b8d6ce4. Used File → Export Full Backup and saved a temporary
JSON file outside the repository. The file contained 13 notes, 60 revisions,
75 execution records, 58 actions, two themes, and one workspace. All 75 execution
records retained their draft IDs. Syntax and explicit action-group arrays were
empty, so this fixture does not accept their native recovery.

Created a separately signed Recovery QA app and a new local test-library ID,
98F6AD04-1040-47D9-8F4D-DB28F9D5B600. Its initial window showed zero drafts. The
first Go To selection used a stale path and imported a neutral theme fixture as
plain text. This was an automation mistake. It does not count as backup evidence.
It left one extra note and revision in the destination. No user data was used.

Repeated Import with the Go To field set explicitly to the exported JSON path.
Confirmed the selected filename before Open. The import completed. Actions →
Execution History showed the restored success, error, and cancellation entries.
Quit Recovery QA, confirmed the process ended, restarted it, and exported a new
full backup through the native menu. Compared decoded JSON records by identity
with decimal number parsing. Every source record matched field for field:
13 notes, 60 revisions, 75 runs, 58 actions, two themes, and one workspace. There
were no missing or changed source records. The destination had only the one
extra neutral note and revision from the earlier selection mistake. This is a
merge-recovery check into a separate test library, not whole-file equality.

The comparison includes execution dates, messages, statuses, note/action links,
and complete source theme data. It proves persistence through the tested native
import/restart/export sequence. It does not prove all possible unknown fields,
conflicting identities, denied permissions, or a forced native storage failure.
Those retain separate automatic evidence or pending checks. No new automatic
test run is claimed.

Recovery QA quit was confirmed. Its temporary bundle, library, and two temporary
backup files remain outside the repository for repeat checks. Engine QA and the
callback helper remain open for the physical global-key check. No screenshot or
raw backup is tracked. Connected Mac+VM synchronization, nonempty syntax/group
recovery, native conflict recovery, signed updates, and the rest of the approved
Mac plan remain open.

### Native backup content conflict and history remapping — 20 October 2026

Used the separate Recovery QA library from the previous acceptance. Opened
Navigation URL café 🐼 in Archive, identity
638B9094-2E65-45F4-B038-4C5EBF784204. Added a neutral final line, Current recovery
edit café 🐼. Import flushed that edit before the file panel opened. Selected
the original history backup by its exact path and confirmed its filename.
Import completed without replacing the current editor text. Archive showed
both the edited note and the unedited recovered note.

Exported the result through File → Export Full Backup to a temporary file.
Decoded JSON comparison confirmed the edited original retained its identity and
full new text. The recovered copy, 49879704-0B6E-4529-A748-EE2877916DC3, retained
all source fields except its new identity. Its source revision received a new
identity and the new note relation. The source execution also received a new
identity and that relation. All other execution fields, including date, action
identity, status, and message, matched the source. The original execution stayed
unchanged and linked to the edited original. Every source action, theme,
workspace, and execution record remained present and unchanged.

The export held 15 notes, 63 revisions, and 76 execution records. These include
the earlier extra neutral fixture and its revision. The global Execution History
sheet showed both corresponding Archive successes. It was not a note-filtered
view. Selecting the recovered copy after export recorded a normal new access;
the exact field comparison used the export made before that selection.

Recovery QA quit was confirmed. The conflict export remains temporary, outside
the repository. This accepts the tested native content-conflict graph. It does
not accept every metadata conflict, repeated conflict import, forced native
storage failure, or connected synchronization. The previous restart acceptance
and automatic conflict contracts remain separate. No source code or test suite
changed in this verification turn.

### Typewriter selection scrolling contract — 20 October 2026

Review questioned whether TextKit could resolve an empty caret range. The new
checks passed against the existing implementation, so no production calculation
changed. Two background methods cover the end of a long Unicode document with
and without a trailing newline, disabled viewport preservation, and repeated
enabling/disabling without text or selection changes. All three cases passed.
They use text and scroll views without a visible window, key registration, or
user data.

The tests assert movement to the late caret and stable disabled viewport state.
They use a fixed document frame. They do not prove exact centering with automatic
text-view height, short documents, resizing, live Settings persistence, or Drafts
visual parity. Those native checks remain pending. No full regression or new
app build was needed for this test-only change; prior results remain separate.


### Markdown preview line layout — 20 October 2026

Implemented: removed paragraph `white-space: pre-wrap` from the preview page.
That rule overrode processor output. A soft line break occupied two lines;
an explicit break occupied three. Code blocks keep their own whitespace rules.

Tested automatically: one offscreen WebKit contract measures actual line height
for Unicode paragraphs. It expects one line for a GitHub soft break, two for
Hard breaks, two for an escaped break, and two preserved code lines. Three
paragraph assertions failed before the change. All four measurements pass after
the change. The test uses no window, network, or persistent website data. The
full regression passed 435 app methods and 430 core methods. The unsigned Debug
build passed. These totals do not establish API or visual parity.

Native verification: Engine QA was refreshed with the changed build. Its Debug
library hash before signing starts with cd1f2519c81913f7. Settings opened, but
Computer Use then returned “native pipe closed before response” twice. The live
Hard breaks toggle, preview refresh, and comparison with Drafts remain pending.
No native result is accepted from this attempt. The physical global shortcut
check also remains pending; the user will report its result. No screenshot or
raw log was added to the repository.


### Conflict restore failure and retry — 20 October 2026

Added one disk-backed contract for an existing note and execution that conflict
with a backup. A forced commit failure leaves the full exported destination
unchanged. Reopening the disk library preserves that same graph. Retrying then
creates exactly one recovered note, remaps its execution and revisions, and
retains the existing text and execution. All seven history-backup methods pass.
No production code changed. No visible window or personal library was used.

This covers retry after a failed transaction. It does not cover idempotence
after a successful conflict import. Code review shows each successful conflict
restore currently assigns a fresh note identity and fresh related identities.
Repeated successful import can therefore add another recovered variant. That
case remains open; a safe solution must identify a prior recovery without
merging distinct intentional notes with equal content. Native checks remain
blocked by the Computer Use connection failure, including after runtime reset.


### Repeated successful conflict import — 20 October 2026

Implemented: conflict recovery derives a stable UUID from the record kind, its
encoded source identity and payload, and a collision attempt. The hash input has
a versioned namespace. A matching identity is reused only if its full payload
matches. A note's newer access date is retained and does not cause another copy.
An edited recovery advances to a separate identity and keeps the edit. Revision
and execution identities use the remapped note relation. There is no schema or
backup format change and no content-only match across unrelated note identities.
Random recovery identities created by older importers remain untouched; the
first new import can create an additional stable recovery beside them.

Tested automatically: two new contracts cover disk reopen, access, repeated
import, editing a recovered variant, related revisions and executions, and an
unrelated identical note. All nine history-backup methods pass. Full regression
passed 435 app methods and 433 core methods. The unsigned Debug build passed.
The existing failed-conflict rollback/retry contract also passes with this change.
Record comparisons ignore top-level array order because fetch order is not part
of the backup contract; identities and all record fields are compared.

Native verification remains pending because Computer Use cannot connect. This
change does not accept connected synchronization, collision races across devices,
or every backup metadata variant. The earlier open repeated-import finding is
resolved for the tested automatic contracts, not for the entire backup roadmap.


### Draft action log contracts — 20 October 2026

Implemented: ActionLog bridge fields now use nonwritable, nonconfigurable
properties, as required by the archived reference. The host maps success/error
status spellings without case sensitivity to completed/failed. Stored execution
payloads are not rewritten. Other status strings retain the previous lowercase
behavior; unknown future values are not accepted as documented status parity.

Tested automatically: the readonly test first failed at uuid. A separate status
test failed for imported ERROR. Both pass after their changes. Two methods check
draft filtering, newest-first order, Date millisecond precision, typed values,
owner identity, absent action, Unicode log text, readonly fields, independent
arrays, unsaved empty history, status spellings, and unchanged stored records.
Full regression passed 435 app methods and 435 core methods. The unsigned Debug
build passed. Matrix structure has zero errors. Specific evidence replaces the
previous generic association for Draft.actionLogs and the tested ActionLog
members. These records remain partial.

Native comparison, missing draft ownership, related-action lookup variants,
log deletion/error paths, device and coordinate values, and host read failures
remain separate acceptance work. No new native check ran because Computer Use
remains disconnected. The installed QA image has not been refreshed.


### Action log deletion and action identity — 20 October 2026

Implemented: deleteRun now uses the batch pre-commit hook and rolls back and
reloads on failure, like revision deletion. Errors reach the calling script.
The script-facing delete still returns undefined, including an absent target.

Tested automatically: deletion first failed the storage-error assertion on both
the legacy and worker routes. Both cases now pass. The disk-backed test checks
failed deletion retains the target, retry deletes it, repeated deletion returns
undefined, unrelated history stays present, the draft stays present, and reopen
retains the final state. A separate method checks action identity after rename,
a deleted related action, and a new action that reuses its old name. This method
passed the existing implementation; no action lookup change was needed.

All four log-contract methods pass, including the two deletion cases. Full
regression passed 435 app methods and 437 core methods. The unsigned Debug build
and matrix structure check passed. ActionLog.action and ActionLog.delete now
carry specific evidence; their classification remains partial. Legacy records
without actionID, native deletion, missing draft ownership, device/coordinate
values, and other required native variants remain pending. No personal data or
visible window was used. The installed QA image remains unchanged.


### Prototype-named template tags — 20 October 2026

Implemented: tag dictionaries and tag merges now have no JavaScript prototype.
Both runners share parsed-JSON hydration between steps. This avoids object
literal semantics for __proto__. Mustache receives JSON-compatible data and
partials through parsed JSON instead of the native dictionary bridge, which
also lost that key. Non-JSON Swift values retain the previous native bridge.
The bundled Mustache Context cache now has no prototype and uses a safe own-key
lookup. Its license remains unchanged.

Tested automatically: the original contract failed at the exact __proto__ value
on both runners. After the dictionary fix it exposed a second loss in Mustache.
All three methods now pass, including both runner cases. They cover __proto__,
constructor, toString, repeated hasOwnProperty lookup, exact Unicode text, void
setter return, both renderers, later native/script steps, and shared hydration.
They also cover additional-value precedence, partials, a __proto__ partial,
unchanged inputs, and a Swift Date alongside an unrelated rendered field.
Full regression passed 435 app methods and 440 core methods. The unsigned build
and matrix structure passed. Prior matrix test references remain recorded as
additional evidence. These template members remain partial.

Native attempt: Computer Use inventory and QA launch worked after the earlier
connection failure. Engine QA was refreshed to the pre-template build, Debug
hash 0d81c6a9c25f18e0 before signing. Sending Command-Comma then failed with
“native pipe closed before response”; a state read also failed. No live Settings
refresh or template parity was accepted. The current template fix is not yet
installed in QA. The physical global-key result remains pending.


### Additional contract test evidence guard — 20 October 2026

Implemented: strict parity now checks both supportingTests and the historical
additionalAutomatedTests field. It rejects malformed collections with a clear
diagnostic instead of aborting. Existing evidence remains unchanged.

Tested automatically: the new alias case first failed because a missing test
was ignored; the malformed supporting collection also raised an exception.
All 38 Python tooling tests now pass with the bundled runtime and Pillow. The
system Python attempt lacked Pillow and does not count as a complete run. Cases
cover valid/missing references, malformed collection values, known-issue tests,
and preservation of the historical field during reference refresh. No network,
visible window, Swift source, or app data was involved.

The normal matrix check has zero errors. Strict core reports 800 diagnostics;
strict engine reports 27. These are acceptance diagnostics, not member counts
or compatibility percentages. Both strict gates remain open. No new Swift
regression or app build was required for this Python-only change.


### Draft identity cache keys — 20 October 2026

Implemented: the execution-local draft cache now has no JavaScript prototype.
Invalid identifiers such as __proto__, constructor, and toString no longer
return inherited objects or functions. Valid cached drafts retain their identity
and pending local values.

Extended the existing find contract instead of adding a duplicate test. Both
legacy and worker cases first failed at __proto__ and now pass. All 36 metadata
methods pass. Full regression passed 435 app and 440 core methods. The unsigned
Debug build passed. This does not add native Drafts comparison evidence.


### Workspace native state across scripting — 20 October 2026

Implemented: the scripting representation now carries a private native-state
payload for manual order, tagged filtering, all list options, and non-API script
metadata. APIValues restores that state before applying exposed script fields.
Query, update, application, default creation, and installation share the decoder.
The payload is removed before saving API metadata to prevent recursive growth.
Old representations without it retain compatible defaults. Invalid payloads
throw before persistence. No Core Data or library format change was required.

Tested automatically: the new query contract first failed on both runners before
save, because searchTitlesOnly and case sensitivity were lost. Four methods now
pass on both routes. They cover native query equivalence, repeated update, applied
state, installation, backup recovery, manual order, tagged filtering, full list
options, non-API metadata, default-copy identity, unchanged source defaults,
current-window snapshots, script-field precedence, and malformed-state rejection.
Application tests capture the workspace passed to the window adapter; they do
not assert real visible rows. Full regression passed 435 app and 444 core methods.
The unsigned Debug build and matrix structure passed.

Workspace.create, query, and update were returned to partial classification.
Their old native evidence remains in nativeVerificationHistory. It did not cover
this retained-state regression. Native verification must repeat the affected
query, application, and default-copy cases before closure. Strict core now reports
809 diagnostics; engine remains separately recorded at 27. These are diagnostic
counts, not a compatibility percentage. The full Mac goal remains open.


### Editor navigation retains cached draft selection — 20 October 2026

Implemented: nextDraft and previousDraft remember the current selection before
calling the window adapter, as load and new already do. A retained Draft object
therefore reports its last UTF-16 selection after navigation. Void returns and
other editor operations retain their existing behavior.

Extended the two existing navigation methods to cover legacy and worker routes,
Unicode selection, skipped drafts, and no-wrap boundaries. All four cases first
failed at the retained selection assertion and now pass. All 12 editor-property
methods pass. No visible window was created or moved by these navigation cases.
Full regression passed 435 app methods and 444 core methods. The unsigned Debug
build and matrix structure check passed. Specific references replace generic
associations for Editor.nextDraft, Editor.previousDraft, Draft.selectionStart,
and Draft.selectionLength; earlier tests remain as supporting evidence.

Native focus, visible navigation, and the remaining member-specific error cases
remain pending. These entries remain partial. The read-only editor audit found
this defect and ran no compiler or UI. The installed QA image is unchanged.


### Shared deletion transaction — 20 October 2026

Implemented: action, workspace, revision, execution, and theme deletion now use
one guarded helper. It invokes the batch pre-commit boundary, rolls back and
reloads on failure, and propagates the error. Duplicate rollback wrappers were
removed. Public method names and return types remain unchanged.

A new disk-backed method has action and workspace cases. Both first failed
because the injected boundary was not used. They now pass. It checks the context
has no pending changes after failure, retained records survive an unrelated save
and reopen, retry persists deletion, and other records remain. Fourteen focused
methods passed across deletion, version, and action-log contracts. Full regression
passed 435 app methods and 445 core methods. The unsigned Debug build passed.
This uses injected pre-commit failure, not an actual filesystem outage. Native
inspector deletion and real storage-error presentation remain pending.

Computer Use diagnostics: Engine QA is still running. Two local service crash
reports from 05:56 show an Array.remove assertion in SkyComputerUseService. This
is evidence of a tool-service failure, not proof of its cause or a Draftly fault.
A full AX read later returned cgWindowNotFound. Rebinding then reported that the
Mac is locked and automatic unlock failed. The user was asked to unlock it. No
system setting changed; no raw report was added to the repository.


### Mustache rendering stays in the action context — 20 October 2026

Implemented: MustacheTemplate render and directory render now call the bundled
engine in the action's existing JavaScript context. The async route no longer
sends rendering to MainActor or creates a second context there. File access
continues through the host. JSON value conversion is retained before rendering,
including the prior Date-to-ISO behavior. The standalone Swift renderer and the
legacy host operation remain available. Legacy action execution retains its
existing executor; this change does not claim to move that route to a worker.

Two worker tests first failed because rendering requested the host. They now
pass with a host that rejects every non-device request. The output case covers
HTML/text escaping, nested sections, partials, and Date conversion. A bounded
nested render reaches the actual engine, hits the typed script timeout, and
then renders correctly in the next step. All nine focused methods passed across
worker rendering, Draft tag contracts, and template APIs. Full regression passed
435 app methods and 447 core methods. The unsigned Debug build and normal matrix
check passed. Worker and Mustache evidence remains partial.

Native responsiveness, cancellation, directory permissions/iCloud Drive, and
comparison with Drafts remain separate acceptance work. The Mac unlock question
is pending. No visible window or user content was used by the automatic tests.


### Directory Mustache names and factory methods — 20 October 2026

Implemented: directory partial collection has no JavaScript prototype. A file
named __proto__.mustache is now available as a named template and as a partial.
Instance createWithPath/createWithTemplate methods now delegate to the retained
static methods. This supports the instance method form in the frozen inventory
without removing existing static calls. Each factory returns a fresh object.

Extended the existing directory method to both runners instead of adding a
duplicate test. Both cases first failed because __proto__ was reported missing.
The instance case then failed because its method was absent. Both now pass.
Cases cover default HTML contentType, static compatibility, fresh instance
factories, named and repeated prototype partials, text/HTML escaping, missing
templates, and traversal rejection before invalid file paths reach the host.
These use an injected file host, not a real cloud folder. Nine focused methods
and the full regression passed: 435 app methods and 447 core methods. The
unsigned Debug build and matrix structure passed.

Three Mustache members now have partial classifications and specific evidence
instead of obsolete generic test strings. The old strings remain in history.
Real iCloud Drive, persistent folder permissions, invalid-input variants, and
comparison of factory forms with Drafts remain unaccepted. The Mac unlock
question is still pending; no QA update or native check occurred this turn.


### XML-RPC asynchronous transport — 20 October 2026

Implemented: the async host now routes xmlrpc through awaited serialized HTTP
transport, like http. It no longer falls through to the MainActor synchronous
HTTP adapter. Shared request/response helpers keep the legacy XML conversion
path consistent. Legacy execution retains its synchronous adapter. A private
runner transport closure defaults to the existing async HTTP implementation and
allows isolated tests without real network access.

Three specific methods pass, including cancellation and timeout cases. They
check POST/XML headers and escaped Unicode body, decoded output through both
the serialized service and real JavaScript entry point, typed XMLRPCResponse,
fault fields, HTTP failure, and malformed transport envelopes. A runtime thread
check confirms the serialized service reaches transport off the main thread.
The action test waits for the injected transport to start, allows a MainActor
turn, then checks cancellation/timeout, transport cleanup, no later clipboard
statement, unchanged source text, and release of the library execution gate.

The initial full run expired short test host budgets before XML-RPC reached its
transport. Reports confirmed typed timeouts. Test budgets now allow startup
under suite concurrency; production limits are unchanged. Full regression then
passed 435 app methods and 450 core methods. The unsigned Debug build and matrix
structure passed. No before-change runtime test is claimed for this new service
interface; source review established the previous synchronous dispatch gap.

These tests use injected transport, not a server or a new URLSession stopLoading
probe. Existing HTTP URLProtocol checks remain separate evidence. Real local
server, native automation, date/binary mapping, CDATA, and complete XML grammar
acceptance remain pending. XMLRPC.request now has a partial classification and
specific evidence; its old generic reference remains in history.


### Float toolbar state — 20 October 2026

Implemented: Float on Top uses an outlined symbol when off and a filled symbol
when on. Model updates refresh the image only when this state changes. The size
stays at 12 points.

Automatic: all three ReferenceToolbarLayoutTests methods passed. The new case
checks both transitions, equal image size, and image retention during unrelated
selection changes. The unsigned Debug build passed. Tests use offscreen windows.

Native: refreshed the stopped Engine QA bundle and opened it through Computer
Use. Clicked Float on Top twice. Screenshots confirmed the filled and outlined
states. Moved the pointer into the empty editor to inspect the outlined state.
No content changed. Drafts was also toggled twice and restored. This check does
not close the full toolbar alignment or appearance matrix.


### Shared application mark — 20 October 2026

Implemented: the icon renderer uses one notes-and-pencil geometry for the color
application icon and the monochrome menu image. The menu image is a vector PDF
with template tinting for the system appearance. Xcode copies both resources.
The application mark keeps the blue-purple tile and increases rear-page contrast.

To regenerate, run `swift scripts/render-app-icon.swift /tmp/Draftly.iconset`,
then `iconutil -c icns /tmp/Draftly.iconset -o Resources/Draftly.icns`. Copy
`/tmp/Draftly.iconset/DraftlyMenuMark.pdf` to `Resources/`. Run the project
generator if resource build rules change.

Checks: rendered the 256-pixel color icon and a PDF raster preview. Inspected
both. The unsigned Debug build passed and included the PDF resource. Refreshed
Engine QA and launched it. Dock, Finder, app switching, and the actual menu bar
mark still need direct visual acceptance. Do not treat resource previews as
that acceptance. No generated preview or screenshot is stored in the repo.


### XML-RPC CDATA correction — 20 October 2026

The earlier source review inferred CDATA loss from the missing foundCDATA
delegate method. Runtime tests did not reproduce that loss on this Mac. The
unchanged production parser preserved mixed text, entities, CDATA Unicode,
implicit string values, struct member names, and fault text. A parser-only case
also preserved Latin-1 bytes with an XML encoding declaration. This does not
verify the HTTP transport character-set path. Do not record a production fix.

Seven focused XMLRPCTests and XMLRPCAsyncTests methods passed. The async reply
fixture now contains CDATA and passes through the actual JavaScript API with
injected transport. Params and error have specific partial evidence. Real
server, native use, complete grammar, and date/binary mapping remain pending.
This change adds tests and audit records only. It does not claim a new full
regression or a full XML-RPC acceptance.


### XML-RPC response structure — 20 October 2026

Implemented: responses must contain one params or fault block. Each param must
contain one value. A typed value cannot contain multiple type elements. The
parser now rejects these ambiguous structures instead of ignoring extra nodes.
The change keeps the existing array of response parameters for compatibility.
It does not claim to enforce all XML-RPC grammar or extension rules.

Reference: https://xmlrpc.com/spec.md, response format, consulted 20 October
2026. This protocol source does not replace the frozen Drafts API reference.

Automatic: the new parameterized contract failed before the change with 12
issues. All five malformed structures pass after the change. Eight focused
XML-RPC methods passed. Full regression passed 436 app methods and 453 core
methods. The unsigned Debug build and matrix structure check passed. Native
server acceptance, date/binary mapping, and remaining grammar are still open.
Engine QA remains open with the prior visual build; do not claim this parser
change is installed there. No new screenshot or raw log is stored in the repo.


### XML-RPC loopback HTTP acceptance — 20 October 2026

Automatic integration: a Python standard-library server binds an ephemeral
127.0.0.1 port and serves three neutral replies. The test uses the production
serialized XML-RPC service and URLSession transport. It checks actual POST
headers and escaped Unicode parameters, a CDATA success reply, a fault with
code and Unicode text, and an ambiguous XML response. The process stops after
three requests and has bounded server waits. No windows or permissions open.

The focused case passed. Full regression passed 436 app methods and 454 core
methods. Matrix structure passed. This tests real loopback HTTP, not native
app automation or external servers. Date/binary representation, transport
character sets, network cancellation, and full grammar remain separate. The
archived Drafts API does not specify enough detail to accept JavaScript binary
representations or date timezone rules without further comparison. No new
production code or app build is part of this tests-only change.


### XML-RPC fault field contracts — 20 October 2026

Implemented: the parser requires a numeric faultCode and string faultString.
Missing fields and wrong types return an invalid-response error. They no longer
produce a fabricated zero code or a string code. No faultCode is published for
these invalid responses.

Automatic: four malformed fault cases failed before the change with five
issues. Full regression then passed 436 app methods and 455 core methods. The
existing async failure case now runs a real JavaScript XMLRPC.request call and
checks negative numeric code, Unicode error, false success, HTTP 200, and empty
params. The unsigned Debug build and matrix structure passed. faultCode,
statusCode, and success now have specific partial evidence. Native app checks,
remaining XML grammar, and untested server variants are still pending. QA has
not been refreshed for these parser changes. The full plan remains active.


### XML-RPC real HTTP cancellation — 20 October 2026

Automatic integration: the loopback fixture can now hold a request without
sending a reply. The test waits for the server to receive that request, cancels
the production serialized service task, and checks its error envelope. The
server confirms TCP EOF before it exits. This proves connection cleanup for
this pending real HTTP request, not only cancellation of an injected closure.
The fixture startup and cleanup code is shared by the two loopback tests.

Both focused cases passed. Full regression passed 436 app methods and 456 core
methods. Matrix structure passed. No production change or new app build was
needed. Native UI cancellation, native timeout, other network conditions, and
remaining XML-RPC contracts still require their own acceptance. No external
server, visible window, or personal library was used.


### Native action-list promise checks — 20 October 2026

Verified in use: quit Engine QA through its app menu and confirmed its process
was absent. Refreshed it from the latest unsigned Debug build and signed the QA
bundle. Installed executable SHA-256:
`839cc0f6069c115a3dbd6b4c0a66e5cb0767dca54f3368b3fbc47cdfc6c40aca`.
The update preserves the isolated library and callback scheme.

Imported scripts/fixtures/engine-promise-actions.json through File > Import.
Created one neutral source draft and ran all three actions from the Imported
action list. Discarded rejection showed its expected error and retained the
completed write in Inbox. Neither its following error-marker insertion nor
archive disposition ran. Intrinsic async rejection showed its expected error
and kept that text. Caught rejection wrote its expected result and completed.
Execution History showed Error for the first two actions and Success for the
handled rejection. Closed the history and left the neutral result open in QA.

No production code or automatic test changed. The previous full regression
remains app436/core456. Matrix structure passes. The strict engine gate still
has 27 diagnostics: this action-list check does not accept remaining entry
points, returned rejection, timeout, or cancellation variants. No screenshot or
raw log is stored in the repository. The full Mac plan remains open.


### Native returned rejection and wait timeout — 20 October 2026

Verified in use on Engine QA executable 839cc0f6069c115a. Added two neutral
fixtures to engine-promise-actions.json. Imported only the two new records
through a temporary subset file, to avoid duplicate earlier actions.

Returned rejection wrote its neutral text, failed with the expected message,
and left the draft in Inbox without the following error-marker insertion.
The async timeout action started near 09:53:20 UTC with the production default
120-second limit. While waiting, Filters and Actions panels closed and reopened.
Action rows stayed disabled. No content was edited during the wait. The final
history at local 06:55 recorded an operation timeout. Earlier text remained in
Inbox, with no error-marker insertion or archive disposition. A caught-rejection
action then succeeded, which checks that subsequent execution was available.

The error toast was not captured before it disappeared. Execution History is
the observed timeout evidence. This is not a precise latency measurement or
CPU-bound worker acceptance. The gate stays partial for remaining entry points
and cancellation checks. JSON fixture validation and matrix structure pass.
No production code changed and no new Swift regression is claimed. The previous
full run remains app436/core456. QA remains open on the neutral caught result.


### Native cancel command — 20 October 2026

Implemented: Actions > Cancel Running Action calls the existing window
cancellation operation. A shared window state property controls availability.
The command has no new keyboard shortcut. It cancels the current window run;
it does not claim to cancel unrelated headless automation or other windows.

Automatic: a new case in ActionEditorInterruptionTests checks availability,
completed tag retention, no stale delayed write, no following insertion or
archive, typed cancellation, and a successful later run. All five focused
methods passed. Full regression passed app437/core456. The unsigned Debug
build passed. No visible windows opened in these automatic tests.

Native: quit QA before refresh. Installed signed executable SHA-256:
`e5a1cf74cfe4bf4437f0b2783c5de309c8f9b8611cae50e21466052e0f5afb7f`.
Computer Use confirmed the menu command disabled at rest and enabled during
QA Native async timeout. Cancelled that run from the menu. Its prior write
remained in Inbox with no tail insertion or archive. Command disabled again.
QA Caught rejection then succeeded. Execution History showed Cancelled for
the interrupted action and Success for the next run. Closed history. QA now
has two neutral drafts and remains open. No screenshot is stored in the repo.

Remaining cancellation entry points and host capabilities retain their pending
status. During this check, other runnable menu actions remained enabled while
busy; their availability needs a separate correction. Do not treat this new
command as full menu or engine acceptance.


### Action availability during execution — 20 October 2026

Implemented: menu, action list, action bar, and command palette use the window
canRunActions state. It requires a current draft and no pending or active run
in that window. The palette submit path keeps the sheet open when execution
is unavailable. Cancel keeps its separate availability. The core library gate
still rejects conflicting runs from other windows or headless callers. This
change does not provide a shared busy publisher across windows.

Automatic: extended the existing explicit-cancellation test with availability
checks before, during, and after the run. All five ActionEditorInterruptionTests
methods passed. The unsigned Debug build passed. The prior full regression
remains app437/core456; it was not repeated for these presentation guards.

Native: refreshed stopped Engine QA. Signed executable SHA-256:
`090bff45a8f2e28b596b90415661c83daedc23e5ec06772441f746992b671852`.
Started the neutral async wait from Actions. Every runnable menu action became
disabled while Cancel remained enabled. Opened the palette, filtered to the
caught-rejection action, and pressed Return. The sheet stayed open with its
query and did not execute. Closed the sheet and cancelled the waiting run.
The menu actions became enabled again and Cancel became disabled. The draft
kept its prior write in Inbox. Closed the menu. No personal text changed.

The action bar and list share the tested predicate, but this turn did not
inspect their native disabled appearance. Cross-window busy presentation also
remains pending. These limits do not claim full UI or engine acceptance.


### Library execution availability across windows — 20 October 2026

Implemented: ActionRunner publishes busy state from the existing library
execution gate. Each WindowModel subscribes using the same execution identity.
The current value reaches windows created during a run. Run availability now
includes that state. Cancel remains limited to the owning window. No polling,
storage format change, or action routing change is added.

Automatic: extended the existing cancellation case with another window, a
window created while busy, and an independent library. Shared-library windows
block runs; the independent library stays available. All recover after owner
cancellation. The first run exposed an incomplete fixture: the independent
window had no current draft. Added a neutral draft to test its intended state.
Full regression then passed app437/core456. The unsigned Debug build passed.

Native: updated stopped QA to signed executable SHA-256:
`fa4f515c36a19fe557292b8ee73c1ed02e8a06e94456c55b7f4b20f69876ff4c`.
Started the neutral wait on an existing draft in window 1. Created window 2 and
loaded a different neutral draft. All run menu items were disabled there; Cancel
was also disabled because it did not own the run. Switched to window 1 through
the Window menu and cancelled. Window 2 then showed enabled run entries and
successfully executed QA Caught rejection. Both windows remain open; no new
personal note or screenshot was created.

This accepts the tested menu and ownership path. Native independent-library,
headless automation busy presentation, and every list/bar appearance remain
separate checks. Other engine contracts and the full Mac goal remain open.


### Native CPU worker responsiveness — 20 October 2026

Verified in use on signed QA executable fa4f515c36a19fe5. Imported the existing
engine-deadline-actions.json fixture through File > Import. Ran QA CPU deadline
from Actions on the neutral current draft. Its script writes and saves text,
then enters a continuous loop. Filters closed and reopened. The script reached
the production synchronous limit. Text remained in Inbox with no later
error-marker insertion or archive disposition.

Repeated the run to make active state explicit: Filters closed, then the Actions
menu still showed enabled Cancel and disabled run entries. This verifies that
the transition happened before termination. An attempted subsequent Cancel lost
to the deadline. History recorded Error with the operation-timeout message for
both runs. This does not accept CPU cancellation. Closed history and restored
Filters. Both QA windows remain open, with the second on neutral CPU result.

No source or tests changed. The previous automatic result remains app437/core456.
The native check improves CPU responsiveness evidence but does not close native
permission/dialog, CPU cancellation, or all worker lifetime acceptance. No
screenshot or raw log is stored in the repository.


### Native CPU cancellation — 20 October 2026

Verified in use on QA executable fa4f515c36a19fe5. The first batched attempt
again found the run already ended. History showed timeout. This attempt does
not accept cancellation. Repeated with elapsed-time observations inside the
Computer Use sequence. After action start, the menu showed enabled Cancel at
about 1.96 seconds. Submitted Cancel by about 2.71 seconds. The immediate state
did not yet show completion. A later observation showed the cancellation status;
Execution History recorded QA CPU deadline as Cancelled.

The completed write stayed in Inbox. No tail marker or archive ran. Closed
history and ran QA Caught rejection successfully. This checks recovery of the
execution gate. It does not measure the full cancellation latency. The worker
sets its cancellation flag and finalizes when JavaScriptCore reaches its
interruption checkpoint; this is not an instant-abort claim. The earlier
automatic CPU test also reports latency near its configured synchronous limit.

No code, test, or build changed. The previous full result remains app437/core456.
Native permission/dialog, remaining entry-point, and lifetime checks remain
pending. The strict worker and task-cancellation contracts remain partial.
Both QA windows remain open; the second shows the neutral caught result.


### Native worker prompt boundaries — 20 October 2026

Verified in use on QA executable fa4f515c36a19fe5. Imported the existing
engine-prompt-actions.json fixture through File > Import. Ran both actions
from the Actions menu in window 2 on neutral text.

Prompt: edited its text field, then clicked Cancel. The field edit was discarded
and the draft kept its previous text. Reopened the prompt, entered Accepted
café 🐼, and accepted. The draft received that exact Unicode text.

SelectPrompt: cancelled first and confirmed the draft stayed unchanged. Then
reopened, searched for Second, and observed only Two Second. Pressed Return.
The draft became Selected: two. This verifies subtitle search and selected
identity, not every SelectPrompt option or visual layout.

Execution History showed Cancelled and Success for each action. Closed history.
The second QA window remains on Selected: two; both windows remain open. No
personal text, external service, or permission setting was used.

No code, test, or build changed. Previous full automatic result is app437/core456.
Matrix structure passes. Prompt and SelectPrompt show retain their current
classification; remaining fields, options, timeout, window-close, and permission
dialog paths require separate acceptance. Worker and host lifetime remain
partial. No screenshot or raw log is stored in the repo.


### Retain logs before failed execution — 20 October 2026

The suspected visual duplication was not reproduced. A screenshot showed each
message once. Computer Use AX text repeated some selectable message strings.
No presentation change is warranted from that observation.

Implemented: async error/cancellation and legacy error logs now retain earlier
console output. Error details append to that output. Legacy cancellation keeps
its existing log behavior. A supplied context.cancel reason remains exact; a
generic cancellation summary does not replace it. Repeated console calls and
multiline messages stay intact. Successful log output is unchanged. Existing
history is not rewritten, and previously discarded output cannot be recovered.

Automatic: the first four cases failed before the change with eight issues,
including ActionLog.log reads. Full regression then caught two custom-cancel
reason expectations. Preserved that contract and added context.fail coverage.
The final six expanded cases pass on both runners. Full regression passed
app437/core457. The final unsigned Debug build passed.

Native: refreshed stopped QA to signed executable SHA-256:
`1c671b32048654b7c8fdb6dbf6479401a43be391b2b3c5fb5c0c82be4096c298`.
Imported engine-log-actions.json and ran both actions on Selected: two. The
draft stayed unchanged. History visibly retained both intentional repeated
Unicode lines and multiline output for Error and Cancelled. Error also showed
its final failure reason. Closed history. No screenshot or raw log is retained
in the repository. Matrix structure passes; ActionLog remains partial for its
remaining acceptance. QA now has one open window after application refresh.


### Cancellation reason defaults — 20 October 2026

Implemented: async cancellation no longer adds a generic summary to the stored
script log. Omitted context.cancel text adds no log text, as the frozen Context
reference states. Explicit reasons and earlier console output remain intact.
Final status and the runner/UI cancellation message stay available separately.
Existing history is unchanged.

Automatic: four expanded cases cover both runners with omitted and Unicode
reasons. The async omitted-message case failed before the fix. Full regression
passed app437/core458 after the fix. Then added direct checks for undefined
return, completion of the current script, and no actionNotification even when
both notification options are enabled. The final six focused methods passed
with those assertions. The unsigned Debug build passed. No visible windows or
permissions opened during these automatic checks.

Native: refreshed stopped QA. Signed executable SHA-256:
`0b424aa7419475235601614dd059607f570866e7bed1c42f21135fc37f56c14b`.
Imported only the two new engine-log-actions cancellation records through a
temporary subset. Ran both on Selected: two. Screenshot and history showed
Cancelled with no message for the omitted reason, and one exact Unicode reason
for the explicit case. Draft content stayed unchanged. Closed history.
Native current-script continuation and enabled-notification variants remain
pending. Context.cancel stays partial with these precise limits. No screenshot
or raw log is retained in the repo.


### Native Context.cancel current-script acceptance — 20 October 2026

Verified in use on QA executable 0b424aa741947523. Imported the native-format
engine-cancel-continuation-actions.json fixture. Its script stores the return
from context.cancel, then writes and saves a neutral draft. The observed text
was Current script finished café 🐼. That path requires an undefined return.
The following insertText marker and Archive disposition did not run; the draft
stayed in Inbox. History recorded Cancelled with the exact supplied Unicode
reason.

Opened the action inspector without changing it. Notify on Success and Notify
on Error were both on, and Archive was selected. Cancelled the inspector edit.
No notification permission dialog appeared. The automatic host-call assertion
checks that cancellation makes no notification request; no actual notification
was sent as a test. Closed history and left the neutral result open.

Context.cancel is now complete for the frozen valid-input contract. Evidence
covers both runner routes, void return, current-script completion, subsequent
step/disposition stop, omitted and explicit reason, and notification suppression.
No cancellation-specific throwing error is defined for valid string input.
Host operations after cancellation have their own contracts. Prior partial
limits and native evidence remain in matrix history. This one member does not
close Context, the engine, or the full plan. No production code changed this
turn. The previous full run is app437/core458 plus its final focused assertions.

Read-only parallel audit next work: reproduce no-wait callbackResponses entries
and prototype-named CallbackURL parameters before changing source. Audit paths:
Bridge.js CallbackURL, ActionAsyncHost.swift callback case, and
ActionStepExecutor.swift callback case. Workspace native retained-state restart
acceptance also remains open; the adapter tests are not drawn-row evidence.

The strict parity validator returned zero diagnostics for Context.cancel after
this evidence update. This is a member check, not a core or global gate pass.


### Shared icon refinement — 20 October 2026

Implemented: the application icon and menu template use one stacked-sheet path.
The mark has two text lines, a folded corner, and wider strokes. The application
uses white ink on the existing blue-purple tile. The menu uses black template
ink. macOS sets its display color. Both assets come from render-app-icon.swift.

Checked: regenerated every ICNS size and the vector menu PDF. Inspected the
256-pixel application render and the 18-point menu render, plus an enlarged menu
render. The menu path stays within its canvas. The unsigned Debug build passed.
Both bundled resources match the source assets byte for byte. No automatic UI
test ran. Dock, Finder, and live menu appearance remain unverified for this
revision. Temporary renders and build logs stay outside the repository.


### No-wait callback response collection — 20 October 2026

Implemented: CallbackURL.open and callbackUrl steps publish response parameters
only when they wait for a response. A successful no-wait launch does not append
an empty response, replace callback tags, or expose host response data on the
instance. Both runner routes use this rule. Launch return values stay unchanged.

Automatic: CallbackResponseContractTests has four cases for script/step and
legacy/worker routes. Each checks an empty collection and unchanged callback
tag after no-wait launch. The next waiting reply is at index zero with exact
Unicode data. All four cases failed before the fix and passed after it. Full
regression passed app437/core459. The unsigned Debug build passed.

Verified in use: imported engine-no-wait-callback-actions.json in isolated QA.
The installed executable SHA-256 was
358de71c6dda4b38c69ed9c3d5a70da5335190e298b12984861bcefbed319c19.
Both script and step actions passed their no-wait assertions. The next local
helper response retained Native café 🐼 at index zero. The editor showed the
expected step and script result text. History showed Success for both actions.
Closed history and quit QA before its next resource update. No external message
was sent. Context.callbackResponses remains partial for other response variants.
No screenshot or raw log is stored in the repo.


### Installed icon inspection — 20 October 2026

Refreshed the stopped Engine QA bundle from the successful Debug build. Started
QA and opened Finder Get Info for that installed application. The small icon
and large preview show the new stacked-sheet path and folded corner. Finder
showed a gray treatment in this session; no system appearance setting changed.
Closed Get Info. Live Dock and menu-template inspection remain pending:
Computer Use timed out when it selected com.apple.dock and
com.apple.systemuiserver. QA window and Finder controls still worked. This does
not prove those two icon surfaces. No screenshot is stored in the repository.


### Callback parameter names — 20 October 2026

Implemented: CallbackURL stores configured parameters in a dictionary without
a prototype. The __proto__ key is data instead of an inherited setter. URL
construction, repeated-key replacement, and return values stay unchanged.

Automatic: parameterNamesRemainDataAndRepeatedKeysReplaceTheirValue checks both
runners. The URL retains __proto__, constructor, toString, and a Unicode key.
Each repeated key has one exact Unicode value. The base query remains present.
addParameter returns undefined. After correcting a test-only EditorSession
property name, both cases failed with the missing __proto__ key before the fix.
All six cases in the callback suite passed after it. Full regression passed
app437/core460. The unsigned Debug build passed.

Verified in use: refreshed stopped Engine QA. Executable SHA-256:
89c842d3998026d19faf3a1927312136e3a6969f2427ee0cb92f6650f6ed6844.
Imported engine-callback-parameter-actions.json. The action checked the encoded
URL without opening a destination. All assertions passed. The editor showed
Callback parameter keys preserved café 🐼 and the completion message appeared.
General value conversion and invalid URL behavior remain pending. CallbackURL
is not complete. No screenshot or raw log is stored in the repository.


### Returned callback parameter keys — 20 October 2026

Implemented: both callbackUrl step routes parse serialized response data with
JSON.parse. They no longer interpret returned parameters as object-literal
source. This preserves an own __proto__ key without changing response ordering
or callback tags. Script CallbackURL.open already preserved this data.

Automatic: returnedParameterNamesRemainOwnProperties covers script/step and
legacy/worker routes. Before the fix, both step cases failed because __proto__
was lost; both script cases passed. After the fix, all four cases pass, including
constructor, quotes, a newline, Unicode, own-key count, and a callback template
tag. All ten callback cases passed. Full regression passed app437/core461.
The unsigned Debug build passed. The QA helper compiles for macOS 26 and passes
its existing window-inventory self-test without opening a window. Matrix
structure passes. The engine strict gate still has 27 diagnostics; no engine
closure is claimed.

Native pending: prepared engine-callback-response-key-actions.json and added
parameterKeys=true to the local QA helper. This option returns fixed neutral
keys. The Mac locked before helper update or fixture execution. Do not count
this fixture as native acceptance. The installed QA executable remains
89c842d3998026d19faf3a1927312136e3a6969f2427ee0cb92f6650f6ed6844,
which predates this incoming-response fix. The new app is in
.build/refactor-check/Build/Products/Debug/Draftly.app. The new helper executable
is /tmp/draftly-callback-response-helper. Quit both QA apps before replacing
their installed bundles or executable. Then sign, open QA, import the fixture,
and verify the expected text and Success history. No screenshot or raw log is
stored in the repository.


### Shortcut no-wait execution — 20 October 2026

Implemented: script and Run Shortcut step requests now pass waitForResponse
through both runner routes and the native host. The default remains true.
False returns after a successful process launch. It does not wait for output,
append a callback response, expose a script result, or replace shortcut_result.
Launch failure remains explicit. Waiting mode still returns the real output.

NativeProcessExecutor shares launch, process-group isolation, timeout, and
termination cleanup for awaited and detached processes. A detached process owns
its input folder and error handle until exit. Completing or cancelling the
launching action does not cancel an external effect already launched. The
existing native 60-second limit still applies. Later detached errors or output
cannot change the completed action. App termination recovery is not verified.

Automatic: waitOptionReachesTheHostAndControlsResponses has twelve cases across
both runners, script/step, and omitted/true/false options. A test-only tag
priority setup was corrected before the valid red run. That run failed eight
cases with ten issues: missing step option forwarding or fabricated no-wait
responses/tags. All twelve pass after the fix. The host fixture returns output
even for no-wait, so the test verifies that the core ignores that output.

ShortcutLaunchTests has six background process tests. File markers and an
explicit release gate verify return-before-exit, delayed input access, cleanup,
default awaited output, legacy no-wait, caller cancellation after launch,
detached timeout, and launch failure. These use neutral local executables.
They do not run Shortcuts, open windows, request permissions, or play audio.
The final cancellation fixture has a bounded marker wait instead of an
unbounded stream wait. The full run includes that final version.

Full regression passed app443/core462. The unsigned Debug build passed. Matrix
structure passes. The strict engine control still has unresolved contracts;
these tests do not close the motor or Shortcut API.

Native pending: the Mac remains locked. Actual Shortcuts execution, permission
and callback variants remain pending. The existing shortcut named Draftly QA
Engine — disposable calls Run Draft Action; do not reuse it as an output-only
fixture or assume it tests no-wait. No installed QA bundle was replaced this
turn. The incoming callback-key native check from the previous turn also stays
pending. No screenshot or raw log is stored in the repository.


### Shortcut error diagnostics — 20 October 2026

Implemented: both native Shortcut routes use one failure-message function.
A failed process with empty or whitespace-only stderr now reports its exit
status. A nonempty diagnostic stays unchanged, including Unicode and its final
newline. A failed process never returns a file that it wrote before failing.

Automatic: shortcutFailureKeepsDiagnosticsAndNeverReturnsOutput has six cases
for legacy/async and empty/whitespace/Unicode diagnostics. Both empty variants
failed on both routes before the fix. All six pass after the fix. Each case
checks removal of the temporary input folder after failure. The executable is
a neutral local fixture; it does not run Shortcuts or display a window.

failedShortcutDoesNotPublishAResultAndStopsFollowingSteps adds four core cases
for script/step and both runners. Script cases check initial created/empty/
undefined state, false return and error status, the exact Unicode diagnostic,
and no successful response, result, or result-tag replacement. The script then
calls context.fail explicitly. Step cases propagate the native error directly.
Both forms stop the following clipboard step and Archive, retain the earlier
clipboard effect, and return the exact failure reason. This does not make all
caught API errors fatal; scripts can inspect a false return.

Full regression passed app444/core463. The unsigned Debug build passed. Native
Shortcuts acceptance remains pending while the Mac is locked. No installed app
was replaced. Matrix structure passes. Shortcut status remains partial for
cancelled, timeout, invalid, typed results, and native behavior. No screenshot
or raw log is stored in the repository.


### Included step ownership — 20 October 2026

Automatic: includedStepsKeepTheirOwnerAndOneExecutionIdentity has six cases:
legacy/async with selected name, UUID, or a template name. Each case includes a
nested action and mixes native steps with JavaScript host requests. The host
observes the actual current-step metadata during five effects. Their owner
sequence is root, child, leaf, child, root. Step UUIDs, global indices, step
types, and the single execution UUID match. Only the root history entry is
created. All seven inclusion methods pass, including the final mixed-step
version of this case. No visible window, permission, or audio operation ran.

The suspected static-inclusion owner defect was not reproduced. The flat
expansion prepares and validates configuration; execution walks the original
action steps and records each included owner. Production code did not change.
This test guards that distinction during later refactoring. It does not settle
configuration-key precedence or queue confirmation policy. The shared-inclusion
contract remains partial for its listed acceptance. Matrix structure passes.
The prior full regression remains app444/core463; this turn ran the seven
focused inclusion methods. No screenshot or raw log is stored in the repo.


### Native action definition fields — 20 October 2026

Implemented: DraftAction, ActionStep, and ActionPresentation retain unknown
JSON fields at their original object level. The codecs use the existing
JSONValue type and one private helper. Known fields keep their current names,
types, required status, and optional encoding. No unknownFields container is
added to normal exports. Unknown data cannot override typed identity, step
type, enabled state, or presentation settings. Existing rawPayload stays
unchanged. No Core Data schema changed. Fields already discarded by older
versions cannot be recovered by this change.

Automatic: nativeUnknownFieldsSurviveEditsRepeatedImportAndBackup has native
single-object and array cases. Before the fix, both lost unknown fields at
all three levels, with six failed assertions. After the fix, both retain null,
Boolean, decimal, Unicode, and nested array values after known-field edits,
two export/reimport cycles, backup restoration, and execution. The disabled
future step stays disabled; the supported script succeeds. Original identities,
sourceURL, and rawPayload stay intact. No recursive payload wrapper is added.

futureFieldsCannotReplaceIdentityOrExecutionSettings verifies that typed fields
win over colliding future keys. An external field named unknownFields also
round-trips as ordinary flat JSON data. Full regression passed app444/core466,
including the final export-shape assertion and the original action fixtures.
The unsigned Debug build passed. Matrix structure passes.

Native pending: the Mac is locked. The installed import/inspector/export path
for native future fields is not verified. The unknown-disabled-import record
returns to partial for this newly identified gap in its acceptance. Earlier
foreign-payload native evidence stays in history. Strict diagnostics can rise
when an earlier classification lacked required coverage; this is not a claim
that execution regressed. Wrapped and mixed native imports need their own
preservation review. No installed app or personal library changed. No screenshot
or raw log is stored in the repository.


### Installed callback, native import, and Shortcuts checks — 20 October 2026

Native checks used Draftly Engine QA and its isolated library
1CBCA092-DAB6-4BFC-9FEC-E4216CDE78AD. The signed executable SHA-256 was
d58f3e5b45380631ea93b0364d0b63856b598ab0d57890bd0dc1a98cae7075b4.
No production code changed during these checks.

QA Returned callback keys passed with the updated local callback helper. The
editor showed Returned callback keys preserved café 🐼. History showed Success.
The script checked own prototype-named keys, quotes, newlines, and callback tags.
This closes that native response-key variant, not all callback contracts.

The native future-fields fixture passed import, inspector edits, execution,
restart, and export. The edited name, description, and disabled step value
persisted. Thirteen export assertions passed: identities, enabled state, script,
three future objects, sourceURL, and rawPayload stayed intact. No synthetic
unknownFields wrapper appeared. Wrapped and mixed native imports still need
review. The import contract remains partial for that coverage.

The neutral Shortcut Draftly QA Output — disposable contains Wait 5 seconds
and Text Native shortcut output café 🐼. It completed from the Shortcuts editor.
Keep this fixture; deletion can also remove its iCloud copy.

QA Shortcut no-wait script and QA Shortcut no-wait step passed. The editor
reported 5 ms and 2 ms. History showed Success for both. Their assertions checked
empty responses and an unchanged result tag. These checks prove launch return,
not completion of the detached Shortcut. QA Shortcut waited script reached the
60-second native timeout. No following editor write ran. The app remained
responsive. The waited step fixture has not run.

Two direct shortcuts run controls also stayed pending without output. They were
terminated after 47 and 66 seconds. The fixture worked in the Shortcuts editor;
the cause of the CLI stall is not established. Actual waited output and typed
responses remain pending. No transport fallback or success claim was added.

Fixtures are stored in scripts/fixtures/engine-native-action-fields.json and
scripts/fixtures/engine-shortcut-wait-actions.json. Raw exports and logs stay in
/tmp. No screenshots are stored in the repository. No new automatic tests or
build ran in this native-only check. The last full regression remains
app444/core466 with a successful unsigned build.

The generic Shortcuts x-callback control stayed pending and was cancelled from
Actions > Cancel Running Action. The app showed the cancellation, restored
enabled actions, and kept the editor text. No output callback was accepted.
This control does not establish that the URL route fixes the CLI stall.


### Grouped and mixed native action imports — 20 October 2026

Implemented: ActionImporter now detects each entry in arrays and actions
wrappers before it applies the Drafts format mapping. Native decoding keeps its
required shape. Foreign steps still read their data payload. JSONValue keeps
decimal precision before native decoding. No library schema changed.

Automatic: containersPreserveNativeEntriesAndForeignStepData covers four cases:
plain/wrapped with native-only/mixed entries. Before the fix, three cases lost
native fields. After the fix, all four preserve the complete native action,
including UUIDs, shortcut modifiers, options, disabled unknown steps, sourceURL,
rawPayload, future fields, and a precise decimal. Mixed imports keep order and
the foreign script payload. Existing export, backup, restore, and collision
cases pass. Full regression passed app444/core467. The unsigned Debug build
passed. Matrix structure passes.

Native: grouped and mixed installed import checks remain pending. The earlier
single native import acceptance does not prove these containers. The import
contract stays partial. Do not replace the running QA bundle until it quits.
The next native check can wrap engine-native-action-fields.json in actions and
add a foreign data-shaped script entry. Import into the isolated QA library,
then edit, restart, and export both entries. Compare identities and payloads.
No screenshots or raw logs are stored in the repo.


### Queued error and cancellation on another draft — 20 October 2026

Automatic: queuedInterruptionOnAnotherDraftKeepsEffectsAndStopsTheQueue adds
four cases for legacy/async runners and error/cancel outcomes. Each case queues
an action on a separate target, then queues another action on the source.
The target keeps its completed Unicode edit and clipboard effect. The source
stays unchanged. The later step and queued action do not run. Archive does not
apply. The final report keeps the root identity, clears success parameters,
and selects only the matching error or cancel callback. One root history entry
remains. All five QueueAcceptanceTests methods pass. Full regression passed
app444/core468. Production code did not change, so no new app build was needed.
Matrix structure passes. No visible windows or permissions were used.

Native acceptance on separate targets and all required entry routes remains
pending. This test does not settle queued confirmation policy or replace native
checks. The queue contract stays partial. The last unsigned build remains the
successful grouped/mixed import build at 565413c.


### Installed wrapped mixed import — 20 October 2026

Native: refreshed the isolated Engine QA bundle from the successful build at
565413c after normal Quit and confirmed process exit. Signed executable SHA-256:
0170b10a3847c64a3116de7dec02a1f84d453af551949f4eafcab7389b8a4436.
Imported engine-mixed-container-actions.json through File > Import. Both entries
appeared in Actions. The native action completed with Native future fields ran
café 🐼. The foreign action completed with Container foreign ran café 🐼.

After another normal Quit and confirmed exit, reopened QA and exported a full
backup through File. Data comparison passed complete native action equality,
foreign UUID, exact foreign rawPayload, and foreign executable script. This
verifies wrapped mixed dispatch, execution, restart, and backup export. It does
not claim container inspector edits or native restore. The import contract
remains partial for those remaining checks. The QA library stays isolated.
The reproducible input is tracked; raw backup and logs stay in /tmp. No new
automatic tests or build ran. Last regression remains app444/core468.


### Native container editing and recovery — 20 October 2026

Native: used the same isolated QA library and signed image0170b10a3847c64a.
Opened QA Container native through the action-list context-menu inspector.
Changed name to QA Container native edited, description to Container edit
café 🐼, and disabled-step value to Container literal café 🐼. Saved, quit,
confirmed process exit, reopened, and exported a full backup. Complete native
object comparison matched exactly those three expected changes. Future fields,
identities, disabled state, sourceURL, rawPayload, and supported script stayed
intact.

Restored the previous neutral QA backup through File > Import. The app showed
Import complete. The original action name returned in Actions. It completed
with Native future fields ran café 🐼. A second UI backup export contained
exactly the same action definitions as the restored backup, for every action.
No personal library changed. Temporary backups remain in /tmp.

This completes the added native-format/container preservation acceptance.
Together with the recorded enabled-unknown rejection, disabled-unknown
execution, atomic import, export, backup, restore, and codec cases, the unknown
disabled imports engine contract returns to complete. This does not close the
other engine contracts or certify every imported presentation option. No new
automatic tests or build ran. Last regression remains app444/core468.

Inspector follow-up: Library Organization > Actions exposes each row as one
combined accessibility element. A double-click and one observed Edit coordinate
click produced no visible inspector during this session. The action-list
context menu did open it. Review that management path separately; no cause or
fix is established by these observations.

Matrix structure passes. The engine strict gate reports 28 diagnostics for
remaining contracts, down from 30. These are diagnostics, not a compatibility
percentage. The full Mac goal remains open.


### Library Organization editor access — 20 October 2026

Implemented: management rows now use a scroll view with explicit bordered
buttons. The screen does not use row selection. This exposes Edit and reorder
controls separately instead of combining a row into one accessibility element.
Action editing uses a local sheet, as group and workspace editing do. It no
longer sets the parent window editor while dismissing management. Cancel and
Save return to the same management section. Stored action formats do not change.

Native: on isolated Engine QA image99a067dd93e833bb, Actions > Manage Actions
and Workspaces > Actions exposes individual Edit/up/down buttons. Edit on
QA Container native opened the inspector. Changed its name, cancelled, and
reopened: the original name remained. Saved description Management save café 🐼
and reopened: the description remained. Cancel returned to management. Group
Edit opened its editor; Cancel returned without changing the group. Done
closed management. No personal library changed.

Earlier List rows remained combined after an explicit button style and contain
accessibility modifier. Those changes alone did not resolve Computer Use access.
The final scroll view passed the native path. This evidence does not prove how
a physical click behaved in the old build or establish a SwiftUI internal cause.
The platform button-style API was checked against Apple documentation through
Context7; the frozen Drafts reference did not change.

Automatic: ten existing ActionCatalogPresentationTests and
WorkspaceOptionsEditorTests methods passed. The final unsigned Debug build
passed. No new UI-opening automatic test was added. The native check establishes
this presentation path; the inspector's wider visual parity, all options, and
workspace management acceptance remain open. No screenshot or raw log is
stored in the repository.


### Native UI owner-close cancellation — 20 October 2026

Native: used isolated Engine QA image99a067dd93e833bb and the unchanged
engine-promise-actions.json fixture. Started QA Native async timeout from
Actions. Observed Async timeout completed write before finalization. Used
Command-W. The next observation showed an Untitled editor; Cancel Running
Action was disabled. Started the fixture again and pressed the observed native
window close button. The next observation again showed Untitled.

Execution History showed two new Cancelled entries. The two completed writes
remained in Inbox. No ERROR tail text appeared and Archive did not apply.
Then ran QA Caught rejection, which completed with Caught rejection completed.
The library was available for the next run. No production code changed.

This verifies UI cancellation at the observed close boundaries. It does not
claim a persistent no-window state: Computer Use returned an Untitled window
after both operations. It does not verify URL or App Intent owner-close
callbacks, multiwindow ownership, or late native capability responses. The
common-entry contract stays partial. Existing ownerLifetimeCancelsItsChildAnd
RemovesObserverOnce covers injected owner-close and parent-task cancellation
automatically; this manual check does not replace the other native entry paths.
No new tests or build ran. The last full regression remains app444/core468.
No screenshots or raw logs are tracked.


### URL owner-close callback and real observer — 20 October 2026

Native: used isolated Engine QA image99a067dd93e833bb, the unchanged promise
fixture, and the local helper. The first URL target was not open in the editor,
so it ran without a window owner. Loaded that target and edited it to Concurrent
QA edit café 🐼. The background action cancelled and the helper received one
cancel callback. This is concurrent-edit evidence, not owner-close evidence.

Repeated with target A386D93F-D3D8-49EB-8F7F-205612F74D93 already visible.
The confirmed run URL used QA Native async timeout and distinct success/cancel/
error callbacks with case=owner-close-visible. Observed Async timeout completed
write in the visible editor, then pressed the native window close button. The
helper received exactly one callback with that case and result=cancel. History
showed Cancelled. Completed text remained in Inbox without the tail or Archive.
After inspecting history and text, the helper counter remained one. No external
message was sent. No persistent no-window state or unbounded absence of late
callbacks is claimed. Native App Intent and multiwindow ownership remain open.

Automatic: realObserverFiltersByOwnerAndStopsAfterRemoval uses actual
registerOwnerClose with two deferred, never-shown windows. A foreign-window
notification produces no delivery. The owner notification delivers once.
Repeated removal is safe; later owner/foreign notifications stay silent. Both
windows remain invisible. This covers the real subscription object filter and
removal, separately from the existing injected execution-lifetime tests.

Full regression passed app445/core468. No production code changed and no new
app build was needed. Matrix structure passes. Common-entry acceptance remains
partial. Raw logs stay in /tmp; no screenshots are tracked.


### Native URL ownership with two windows — 20 October 2026

Native: isolated Engine QA image99a067dd93e833bb. Opened target draft
A386D93F-D3D8-49EB-8F7F-205612F74D93 in library-AppWindow-1. Used File >
New Window to create Untitled library-AppWindow-2. Sent a confirmed run URL
for QA Native async timeout with local success/cancel/error callbacks carrying
case=two-window-owner. The current window remained Untitled window2.

Pressed window2's native close button. Window1 still showed Async timeout
completed write. The helper received zero callbacks. Then pressed window1's
native close button. The helper received exactly one callback with
case=two-window-owner and result=cancel. This extends the single-owner URL
check with a real non-owner close. It does not verify same-draft ownership
preference, App Intent cancellation, or all late capability responses.

The helper's read-only window monitor ran during the check and was disabled
afterward. It included auxiliary window records, so its normal-window count
is not used to assert exactly two library windows. The observed library IDs
and editor contents identify the two windows. No screenshot or raw log is
tracked. No production code, new test, or build changed. Last full regression
remains app445/core468. Matrix structure passes. Common-entry parity stays
partial for the other required variants.

Follow-up: after closing window2, window1's menu bar did not expose Actions or
Visual QA. Raise and editor click did not restore those entries in Computer
Use. AppController clears commandWindow when its registered window closes.
Review whether the remaining visible model needs a deterministic fallback.
The observation alone does not establish the cause or physical-click behavior.

Read-only review found an existing restoration path: didBecomeKey registers
the actual key model, and focused commands prefer their focused model. A nil
commandWindow between key events is not enough to prove a defect. Do not add
an arbitrary hash-table fallback. Next check must establish foreground/key/main
state at the missing-menu moment. No production fix follows from this evidence.


### Native App Intent owner-close — 20 October 2026

Native: isolated Engine QA image99a067dd93e833bb. Used existing Shortcut
Draftly QA Engine — disposable, editor ID D11EC900-D6B4-48DD-AE0D-7CD51353D655.
Set Run Draft Action name to QA Native async timeout and Draft UUID to
A386D93F-D3D8-49EB-8F7F-205612F74D93. Opened that draft in QA through the
local helper before running the Shortcut. Shortcuts showed Stop while QA
completed its initial editor write. Pressed the owner's native window close
button. Shortcuts displayed QA Native async timeout cancelled. After OK, it
returned to Run and displayed that cancellation beside the action.

QA showed the completed text in Inbox without the tail or Archive. History
showed Cancelled. Changed only the action name to QA Caught rejection and ran
the same Shortcut. It completed and displayed QA Caught rejection completed.
QA History showed Success. The library was not left busy.

The existing Shortcut now keeps QA Caught rejection and the QA UUID above. It
remains a neutral reusable fixture; do not delete it without confirmation. No
new Shortcut was created or external message sent. This closes the single-owner
Intent cancellation variant. It does not claim same-draft multiwindow owner
preference, all native dialogs, or late response variants. The native UI shows
the cancellation message; typed reason identity has separate automatic tests.

Automatic: thirteen existing error/observer/editor-context methods passed.
RunDraftActionIntentTests also passed, including actual perform cancellation
and typed pre-start cancellation. No production code or app build changed. The
last full regression remains app445/core468. Matrix structure passes. No raw
logs or screenshots are tracked. Common-entry parity remains partial.


### Native delayed reply after cancellation — 20 October 2026

Implemented in the manual helper only: a separate field now shows a pending
reply delay, the number of successful NSWorkspace opens, and the last open
result. It does not count an open as a completed Draftly action. The target
remains restricted to the isolated QA callback scheme and callback host.
No Draftly production code changed. Compiled the helper, passed its window
inventory self-test, quit the installed helper, confirmed process exit,
replaced its executable, and signed the test bundle locally.

Native: isolated Engine QA image99a067dd93e833bb. Imported the unchanged
engine-native-actions.json fixture. Ran QA Native late, cancelled through
Actions > Cancel Running Action, and completed QA Caught rejection in one
observed UI sequence before the eight-second reply. The helper first showed
Reply pending: 8.0 seconds. It later showed Replies opened: 1, Last open
succeeded: true, Delay: 8.0 seconds. This is the actual NSWorkspace open result,
not an acknowledgement that Draftly accepted the expired response.

After that open, History still showed QA Native late as Cancelled and
QA Caught rejection as Success. The editor retained Caught rejection completed;
Must not replace edited text did not appear. This verifies the expired native
callback cannot run the old tail or overwrite the subsequent completed action
in this sequence. It does not cover a reply arriving during a second pending
wait, every native capability, or unbounded future delivery. Host-request and
task-cancellation contracts remain partial for other acceptance.

No screenshot or raw log is tracked. The helper input fixture stays unchanged.
Last full regression remains app445/core468; only existing router tests were
rerun for this helper/native acceptance change. The app was not rebuilt.


### Expired callback during a new native wait — 20 October 2026

The manual helper accepts an optional replyValue query field. Its default stays
Native café 🐼. The helper shows the last opened reply value so two requests can
be distinguished. No production app code changed. Compiled and locally signed
the helper after normal Quit and confirmed process exit. Its inventory
self-test passed.

Native: isolated Engine QA image99a067dd93e833bb. Imported the reproducible
engine-callback-overlap-actions.json. Started QA Expired callback with an
eight-second expired response, cancelled from Actions, and started QA Fresh
callback with a ten-second fresh response in one batched UI sequence. The
helper showed the second request pending. It then showed one successful native
URL open with value expired, followed by a second successful open with value
fresh. The fresh action asserted exactly one response with value fresh before
writing Fresh callback isolated café 🐼. History showed expired Cancelled and
fresh Success. The expired action's throwing tail did not run.

This verifies the two-request sequence and distinct response data. The native
open observations do not measure the precise app-handler delivery time. The
helper does not treat a successful URL open as accepted action completion.
Other capability and entry variants remain pending.

Automatic: extended cancellationReleasesTheWaitAndRejectsLateDelivery instead
of duplicating its setup. After cancellation, it starts a new pending request,
checks that its callback differs, rejects the expired callback, then delivers
the new token and verifies the fresh Unicode response. All six router methods
pass. Full regression passed app445/core468. Matrix structure passes. No
visible automatic test or new production build ran. No screenshots or raw
logs are tracked.


### Imported editing bar options — 20 October 2026

Implemented: import shortName and keyUseIcon into optional presentation fields.
Old libraries keep the existing icon default. Native export and backup preserve
these fields and the original payload. The editing bar uses the selected text
or icon. Its accessibility label keeps the full action name. The inspector
exposes Label and Show Icon on its temporary edit copy.

Automatic: seven catalog tests and eight import/preservation tests passed.
The unsigned app build passed. The full app suite passed 446 tests. The full
core run did not finish and was stopped; it is not an accepted full regression.
The cause remains unresolved. The last complete core regression was 468 tests.

Native: isolated Engine QA image cfe943f562b25968b. Imported the neutral
scripts/fixtures/action-bar-label-actions.json fixture. The bar showed a star
and Text café 🐼. Both buttons retained their full action names in accessibility
and ran their scripts. The editor showed each expected Unicode result.
The new inspector controls still need a native edit/cancel check. This change
does not close inspector parity or imported color and visibility contracts.
No screenshots or raw logs are tracked.


### Full regression recheck — 20 October 2026

Confirmed that the stopped core test process was absent before a new run.
Repeated the full suite with the current committed editing bar change.
The command completed with exit zero: app446/core471. Matrix structure also
passes. The earlier incomplete run did not reproduce. Its cause is unknown;
this recheck does not establish a fix for that stall. Native inspector
edit/cancel acceptance and the remaining roadmap contracts stay pending.


### Editing bar inspector acceptance — 20 October 2026

Native: isolated Engine QA image cfe943f562b25968b. Opened QA Bar text action
through Library Organization. Label showed Text café 🐼 and Show Icon was off.
Changed both values and cancelled. Reopened the action: both original values
remained. Saved Label as Saved café 🐼 with Show Icon on. Reopened and confirmed
both saved values. Restored the original label and icon choice with Save.
The main bar again showed the star and Text café 🐼. No draft text changed.

This closes the native edit/save/cancel check for these two controls. It does
not close all imported presentation options or inspector visual parity.
No production code changed. No screenshot is tracked. The latest full test
result remains app446/core471; no tests were rerun for this manual check.


### Imported action tint implementation — 20 October 2026

Implemented: optional tintColor in action presentation. Foreign imports retain
its string value. Native encoding and backups preserve unknown color names.
The list and editing bar share a named-color mapping. An unknown or absent
name uses the prior surface default. The unsupported-step warning keeps its
orange priority. The inspector exposes the color and retains unknown choices.
Native palette comparison and inspector acceptance remain pending.

Automatic: eight catalog and eight import/preservation tests passed. The
original five fixtures check their explicit color names. Backup and export
checks retain a future color name. Full core passed471. Full app ran447 tests
with two failures at the five-second start-marker wait in automation safety.
All five AutomationActionExecutionTests passed in a separate recheck. The
cause under the full run remains unresolved; the full app run is not accepted.
Matrix structure passes. No screenshots or raw logs are tracked.

The unsigned app build also passed for the tint change.


### Automation readiness test synchronization — 20 October 2026

Refactored the two existing automation cancellation tests. Subscribe to draft
publications before starting the action. Wait for its saved ready tag instead
of polling for five seconds. Finish the signal stream when the action ends,
so an early result produces a test error instead of a lost readiness signal.
The script stays pending until cancellation; a later insert step must not run.
Removed the half-second completion race from these editor-safety tests.
No production code changed. This does not establish the cause of the earlier
full-run failures or replace separate timer and callback contract tests.

Automatic: all five automation safety methods passed. The full regression
then completed successfully: app447/core471. No visible windows were opened.
Native tint comparison remains pending. No raw logs or screenshots are tracked.


### Native action tint acceptance — 20 October 2026

Updated the isolated QA app after normal Quit and confirmed process exit.
Signed executable SHA256:
1b8988d3183ec0675c0e5d3125665b1c22b3e155a9b82124b3a8039db45e5d20.
Imported scripts/fixtures/action-tint-actions.json with stable test identities.
The editing bar showed green text and an orange star. The action list showed
green and orange stars. The inspector read Green for the imported text action.
Saved Purple and reopened: Purple remained. Selected Green, cancelled, and
reopened: Purple remained. Restored Green with Save. No draft text changed.

Drafts reference: its action table is empty. Add Items shows New Action,
New Separator, and Visit Directory disabled. Exact palette comparison cannot
be accepted from this state. Named-color rendering and inspector save/cancel
are verified in QA; other colors, appearance modes, and exact Drafts palette
comparison remain pending. No screenshot is tracked. No production code or
build changed after the accepted app447/core471 regression.


### Native import evidence fields — 20 October 2026

Corrected the unknown disabled imports matrix entry. Its passed native record
now has the required date and evidence link at the nativeVerification level.
The existing dated checks and the Native container editing and recovery record
support those fields. No new acceptance or production behavior is claimed.

Extended the existing auditor evidence test: nested dated checks alone must
not satisfy the required top-level date and evidence fields. All25 auditor
tests pass. The engine strict gate now reports27 diagnostics. Other engine
contracts remain partial. This is a record correction, not a compatibility
percentage or a newly completed engine capability.


### Native queued failure and cancellation on another draft — 20 October 2026

Added a multi-draft failure root to engine-queue-actions.json. It uses the
existing failing child and later-action sentinel. Imported the fixture in
isolated QA image1b8988d3183ec067. Created exactly one Queue target neutral
draft and a separate source through the editor.

Ran the failure root from Actions. History recorded Error with Neutral queued
failure. The target retained Queue failure completed write — café 🐼; the source
retained Queue source retained. Both appeared in Inbox. The editor stayed on
the target. Neither the child's later insertion nor the later queued action
replaced the retained text.

Reset the neutral target text and selected the source. Ran the existing
multi-draft cancellation root. History recorded Cancelled with Neutral queued
cancellation. The target retained Queue child completed write — café 🐼 and the
source stayed Queue source retained. Both stayed in Inbox. The editor stayed
on the target. No sentinel text appeared.

Automatic: all five QueueAcceptanceTests methods passed, including parameterized
legacy/async failure and cancellation, timeout, retained effects, and callback
selection. Matrix structure passes. No production code or new build changed.
The last full regression remains app447/core471. Native URL/Intent queue
interruption variants remain pending. No screenshot or raw log is tracked.


### Native URL queued interruption callbacks — 20 October 2026

Used isolated QA image1b8988d3183ec067 and engine-queue-actions.json.
The local helper opened draftly://run for each multi-draft root, with the
neutral source UUID and all three callback URLs. Each callback URL used
only draftly-engine-echo://received, a distinct case value, and a result value.
Confirmed Run Action in the external-link dialog for each run.

Failure: helper showed exactly one callback, case=queue-url-failure,
result=error, errorMessage=Neutral queued failure. It had no root success
parameter. The native failure alert showed the same message. After dismissal,
the source and retained target write stayed in Inbox. The editor showed
Queue failure completed write — café 🐼, without the sentinel text.

Reset the target to Queue target neutral and selected the source again.
Cancellation: helper showed exactly one callback, case=queue-url-cancel,
result=cancel, with no success parameters. The editor showed Queue child
completed write — café 🐼. The source remained Queue source retained, and both
were visible in Inbox. Neither later-work sentinel appeared.

This verifies the current-image URL error/cancel selection for queued actions
on another draft. It does not close native App Intent queued interruption,
all callback variants, or unbounded duplicate delivery. No production code,
fixture, build, or tests changed. Last full regression remains app447/core471.
No raw logs, exported data, or screenshots are tracked.


### Native App Intent queued interruptions — 20 October 2026

Used the existing Draftly QA Engine — disposable shortcut, editor identity
D11EC900-D6B4-48DD-AE0D-7CD51353D655, with isolated QA image1b8988d3183ec067.
Set Run Draft Action to the multi-draft failure root and the neutral source
UUID. Shortcuts showed an error alert and inline Neutral queued failure.
The target retained Queue failure completed write — café 🐼. The source remained
Queue source retained. Both remained in Inbox; no sentinel text appeared.

Reset the target and selected the source. Set the action name to the multi-draft
cancellation root. Shortcuts showed QA Queue multi-draft cancellation root
cancelled. The editor retained Queue child completed write — café 🐼 on the
child. The source stayed unchanged and both remained in Inbox. History recorded
Error and Cancelled for the matching roots. The shortcut parameters were then
restored to QA Caught rejection and its earlier neutral target UUID.

This verifies queued failure/cancellation propagation through actual Intent
perform calls. It does not verify every asynchronous queued interruption,
window-lifetime combination, or current-image production timeout entry.
No production code, build, or test changed. Last full regression remains
app447/core471. No screenshot or raw export is tracked.


### Native queued URL owner-close cancellation — 20 October 2026

Added QA Queue multi-draft pending root to engine-queue-actions.json. It queues
the existing asynchronous timeout child on the neutral target and a sentinel
on the source. Used isolated QA image1b8988d3183ec067. Opened the root through
the local helper's draftly://run URL and confirmed Run Action.

Observed Queue timeout completed write — café 🐼 in the target editor with action
buttons disabled. Closed the visible owner using its close button while the
child was pending. The helper showed exactly one callback with
case=queue-owner-close and result=cancel. After reopening QA, both retained
target text and Queue source retained were visible in Inbox. No later-work
sentinel appeared. History recorded the pending root as Cancelled. A later
helper observation still showed the same single callback.

This covers a URL-owned window closing after the queue loads another draft.
It does not cover queued Intent owner-close or all multiwindow combinations.
Automatic: nine editor-context/owner-observer methods and five queue methods
passed without visible windows. Matrix structure passes. No production code
or build changed. Last full regression remains app447/core471. No screenshots
or raw logs are tracked.


### Native queued Intent owner-close cancellation — 20 October 2026

Used isolated QA image1b8988d3183ec067 and the existing disposable Engine
shortcut. The first run did not have a matching visible source: the window
kept another draft with the same title while the headless run updated its
source. Stopped that run through Shortcuts. It is not owner-close acceptance.
The earlier queued Intent failure/cancel checks prove result propagation and
retained writes, but do not establish exact source UUID or visible ownership.

Opened the intended neutral source with draftly://open and its UUID. Re-entered
the shortcut UUID through paste and Tab before Run. This time the visible
window followed the queued child and showed its retained write while Shortcuts
showed Stop. Closed that window. Shortcuts showed QA Queue multi-draft pending
root cancelled. After reopening QA, source and child writes remained in Inbox,
no sentinel appeared, and the latest root history entry was Cancelled.

Restored both shortcut fields through paste and Tab. This verifies actual
Intent owner-close after a queue changes the editor target. It does not prove
why the initial field/run selection differed. Future identity-sensitive checks
must commit each field and verify the visible owner before closing it.

No production code, build, fixture, or tests changed. Latest full regression
remains app447/core471. Matrix structure passes. Current-image production
queued timeout entry combinations and other native capabilities stay pending.
No screenshot or raw log is tracked.


### Current-image native queued URL timeout — 20 October 2026

Used isolated QA image1b8988d3183ec067 and the pending multi-draft root from
engine-queue-actions.json. Opened the source by UUID, reset the neutral target,
and ran through the local helper with all three callback URLs. No test timeout
setting was applied. ActionRunner retains its production scriptTimeout of120.

The child wrote Queue timeout completed write — café 🐼 and remained pending.
Cancel Running Action was enabled while other actions were disabled. At the
57.243-second observation, callback count was zero. At135.644 seconds, the
helper showed exactly one error callback with case=queue-production-timeout
and the timeout message. No root success parameter was present. These times
are observation times, not an exact measurement of deadline delivery.

The native error alert showed the same timeout. After dismissal, source and
child writes remained in Inbox, the editor stayed on the child, and no later
sentinel text appeared. History recorded the root as Error with the timeout
message. This closes the current-image queued URL timeout check. Current-image
UI and Intent queued timeout checks remain pending. No production code, build,
fixture, or tests changed. Last full regression remains app447/core471.
No screenshot or raw log is tracked.


### Current-image native queued Intent timeout — 20 October 2026

Used isolated QA image1b8988d3183ec067 and the disposable Engine shortcut.
The first run cancelled early and the editor showed an added question mark.
The cause of that edit is unknown. That run is not timeout acceptance.
Confirmed its terminal result before preparing another run.

Reset the neutral target, opened the source by UUID, and ran again without
editing shortcut fields. Shortcuts showed Stop, and the visible owner followed
the pending child. Stop remained at the56.427 and110.268-second observations.
At134.674 seconds, Shortcuts showed The action operation timed out before it
completed. These are observation times, not exact deadline delivery times.
No timeout override was applied; the production limit remains120 seconds.

After dismissal, source and target writes remained in Inbox. The target editor
kept Queue timeout completed write — café 🐼, without later sentinel text.
History recorded the latest pending root as Error with the timeout message.
Restored the shortcut action and UUID through paste and Tab. This closes the
current-image queued Intent timeout check. The UI entry remains pending.
No production code, build, fixture, or tests changed. Last full regression
remains app447/core471. No screenshot or raw log is tracked.


### Editing during a pending queued action — 20 October 2026

Attempted the current-image UI production timeout with the pending multi-draft
root. The child first showed its expected retained text. At54.514 seconds,
Cancel Running Action was disabled and the window title was Q. History showed
Cancelled. The source of this edit is unknown. This is not timeout acceptance.
Did not overwrite Q or restart the native test. UI timeout acceptance remains
pending; earlier URL and Intent timeout acceptance stays separate.

Extended the existing visibleTypingCancelsAutomationAndRetainsTheNewText test
with direct and queued cases. Both use the owned WindowModel path without a
visible window. The queued case waits for the saved child readiness signal,
checks that the editor loaded the child, then types. It asserts cancellation,
saved user text, preserved source text, and no replacement by later steps or
the later queued sentinel. No new duplicate test setup was added.

Automatic: all five automation safety methods passed, including both typing
cases. The47 queue/boundary/runner/API methods passed separately. Full regression
passed app447/core471. Matrix structure passes. No production code or build
changed. No raw logs or screenshots are tracked.


### Reject ambiguous backup identities — 20 October 2026

Implemented: restore validates unique identities in notes, revisions, workspaces,
actions, action groups, syntaxes, themes, and execution history before writing
records. A duplicate returns an error that identifies the record kind. Backup
version and encoding stay unchanged. This replaces the history-only identity
check. Theme save validation remains separate because it also serves batch
editing outside restore.

Expanded the existing duplicate-history test across all eight collections.
Before the fix, five collections accepted duplicate identities, reached commit,
and changed the destination backup. After the fix, all eight throw before the
batch commit hook and leave the complete existing destination backup unchanged.
No visible windows or personal libraries are used.

Automatic: nine history/backup methods passed, including eight parameterized
identity cases and existing disk reopen, conflict recovery, legacy, and rollback
checks. Full regression passed app447/core471. Unsigned app build passed.
Matrix structure passes. Native import error presentation has not been checked
for this change. The installed QA app is still image1b8988d3183ec067; it has not
been replaced with this build. Sync and signed-update acceptance stay separate.
No screenshots or raw logs are tracked.


### Native duplicate-backup rejection — 20 October 2026

Updated isolated QA after normal Quit and confirmed process exit. Signed image
SHA256 ca22fd5931d5b495c596b19f312d977ac05ab2c0cea6362f6e02d22e79b048c0.
The prior edited Q/remaining-text draft was preserved. No pending action ran.

Exported a full QA backup through File. Imported the neutral reproducible
backup-duplicate-drafts.json fixture. The app showed The backup contains
duplicate draft identities. Dismissed the error and exported another full
backup. Decoded equality and exact byte equality both passed. The exports had
8 notes,70 revisions,61 actions,64 runs, and empty group/syntax/theme/workspace
collections. Neither rejected fixture draft appeared.

During the second export, the save dialog offered to replace the input fixture.
Cancelled that replacement, corrected the temporary name and folder, verified
them, and saved. The tracked fixture stayed unchanged. Both exported backups
remain temporary in /tmp and are not tracked.

This verifies native draft-duplicate rejection, error presentation, and no
change to existing exported records. Other duplicate kinds have automatic
coverage; this does not claim native coverage for each kind. No production
code or tests changed after the accepted app447/core471 and build. iCloud and
signed-update acceptance remain separate. No screenshots are tracked.


### Reject invalid recognized imports without text fallback — 20 October 2026

Implemented: file import recognizes explicit backup, action, and draft-export
JSON shapes before applying plain-text fallback. An invalid recognized shape
now propagates its decode error even when its extension is txt. Successful
note imports still use one atomic batch with the existing conflict handling.
Action shapes keep precedence over draft-like future fields. Unclassified
JSON in a text file remains literal text.

Automatic: four malformed recognized inputs failed before the fix because
they were saved as raw text. They now throw and preserve the complete existing
backup. The action batch rollback/retry test also retains an unknown content
field without treating the action as a note. The existing text-route test
covers literal unclassified JSON. Full regression passed app447/core472.
Unsigned app build and matrix structure pass. No visible automatic tests ran.

Native error presentation for this route change remains pending. Installed QA
still has imageca22fd5931d5b495; it was not updated. This does not close broad
import compatibility, sync, or UI timeout acceptance. No screenshots or raw
logs are tracked.


### Native recognized invalid text imports — 20 October 2026

Updated isolated QA after normal Quit and confirmed process exit. Signed image
SHA256 13f8e82cecd3ed0e1d8679b83ac75361a68be6183497d74fe35cd7b667ccdffb.
Exported the full existing library before either import.

Imported scripts/fixtures/import-invalid-drafts.txt. It contains one valid
neutral note and one note without content. The app showed A draft has no
content. The subsequent full backup export matched the original byte for byte.
Neither the valid prefix note nor raw JSON was added.

Imported scripts/fixtures/import-invalid-actions.txt. It contains one valid
neutral action and one action step without a type. The app showed An action
step has no type. The next full backup also matched the original byte for byte.
The valid prefix action was not installed and raw JSON was not added as a note.

Both comparisons covered the existing8 notes,70 revisions,61 actions,64 runs,
and empty remaining collections. Confirmed the selected fixture in the native
open panel before importing. Temporary exports remain in /tmp. No personal
library changed. This verifies both recognized-format error paths through
File Import, not all import formats or cloud recovery. No production code or
tests changed after the accepted app447/core472 and build. No screenshots or
raw exported backups are tracked.


### Atomic multi-file import — 20 October 2026

Implemented a multi-file LibraryFileImport entry. Multiple files are applied
in order to an isolated in-memory library initialized from the current backup.
Only changed records are persisted to the destination, in one transaction.
No destination publication occurs during preparation. Existing generic records
outside the imported collections remain untouched. Single-file import keeps
its existing path. File Import reads all selected files before applying them.
No library format or public scripting contract changed.

Automatic: the prior sequential path failed two new regressions: a second-file
error kept first-file changes, and a successful mixed import committed twice.
Both pass after the fix. Tests also inject destination commit failure, reopen
the disk store, retry with one commit, and check imported dates/tags/flag/syntax.
A backup-plus-text case verifies all eight collections and note/action/history
relationships, with success and commit-failure variants. Full regression passed
app447/core475. Unsigned build and matrix structure pass.

Native multiple-file picker acceptance remains pending. Installed QA is still
image13f8e82cecd3ed0e and was not replaced. Preparing a batch copies the current
backup to memory; large-library cost has not been measured. This does not close
performance, cloud recovery, or the pending UI timeout check. No screenshots
or raw logs are tracked.


### Native multi-file import acceptance — 20 October 2026

Updated isolated QA after normal Quit and confirmed exit. Signed image SHA256
785e0548ab98a23c6a0e865e90215b7e8a1534b2e27406581359249f825d2224.
Exported a full baseline backup. In File Import, selected both
import-batch-first-action.json and import-invalid-drafts.txt with Command-click.
Confirmed both selection states before Open. The app showed A draft has no
content. The full backup after rejection was byte-identical to the baseline.
The valid first action was not installed.

Selected import-batch-first-action.json and import-batch-last-note.txt together.
The app showed Import complete and9 drafts. Export comparison found exactly
one new action, one new note, and one related revision. The note matched the
fixture UTF-8 text exactly. The stable action identity and futureBatchField in
rawPayload remained intact. Every prior record stayed equal, including all
history. No fixture action was executed.

Quit normally, confirmed process exit, reopened, and exported again. Raw bytes
differed because action/note array order changed. Canonical comparison by ID
passed for every collection and field. This is data equality, not byte equality
across restart. The rejected-lot before/after byte comparison remains valid.
Temporary full backups stay in /tmp. No personal library changed.

This verifies native multi-selection, all-or-nothing rejection, successful
mixed import, retained unknown action data, and restart persistence. Large-
library staging cost and cloud convergence remain pending. No production code
or tests changed after the accepted app447/core475 and build. No screenshots
or raw exported backups are tracked.


### Reproducible library scale measurements — 20 October 2026

Added the optional DraftlyLibraryBenchmark executable. It creates fresh local
stores and removes its temporary directory. It does not open an app or use
CloudKit. The normal scale test still checks its data; it no longer imposes
two arbitrary two-second limits. Timing acceptance has no fixed threshold.

Run:
`swift run -c release DraftlyLibraryBenchmark --notes 10000 --samples 5 --storage sqlite`

Measured on Mac14,6, Apple M2 Max,12 logical processors,64 GiB RAM, arm64,
macOS27.0.1 build26A434, Swift6.4. The fixture contains10,000 notes and10,000
revisions, fixed identities/dates, Unicode text, and even/odd tags. Encoded
baseline size is3,727,846 bytes. Fixture SHA256:
9e6b4803d18fcb75b8071b2b568d4e0c3f8bad258cd282e25bd871dee0942448.
Each of five samples uses a fresh SQLite store. No warm-up sample is discarded;
filesystem caches are uncontrolled. Store construction is outside restore timing.

| Operation | Median ms | Maximum ms |
| --- | ---: | ---: |
| Baseline restore | 586.167 | 947.194 |
| Two-file atomic import | 1092.570 | 1296.808 |
| Workspace query | 17.014 | 18.597 |
| Save edited100,000-character document | 196.603 | 244.264 |

The import includes staging, final persistence, and reload. Query filters by
tag and text and returns5,000 notes. Document input has100,000 Swift characters
and114,285 UTF-16 units; one character changes without changing its length.
Every sample verifies baseline note/revision data, imported identity and
metadata, query count, and stored document text. The report includes samples,
minimum/median/maximum, configuration, environment, fixture hash, and the hashes
of LibraryStore.swift and LibraryFileImport.swift.

Automatic: a small memory smoke run, help, and five invalid-option paths passed.
The release five-sample SQLite run passed its data checks. Full regression
passed app447/core475. No application sources or installed QA changed.
The import remains synchronous on MainActor. These core timings do not accept
visible responsiveness, scrolling, selection, typing, Undo, memory usage, iCloud,
or cold-cache performance. Native scale acceptance remains pending. Raw JSON
and compiler logs stay in /tmp; no screenshots or raw reports are tracked.


### Export the scale fixture — 20 October 2026

The benchmark accepts `--export-baseline /tmp/fixture.json`. This mode writes
the same deterministic backup used for measurements and reports its record
counts, byte count, and SHA256. It does not run the measurements. An existing
file causes an error and remains unchanged.

The release export of 10,000 notes and 10,000 revisions passed. Its hash matched
the measured baseline. A second export to the same path failed without changing
the file. Native import into the separate, local Scale QA app caused UI reads
to time out. A later process sample showed an idle main thread. This does not
establish the cause or accept native scale performance. Row rendering and
selection still need investigation. No screenshots or raw reports are tracked.


### Draft table snapshot consistency — 20 October 2026

Implemented: table callbacks now use the displayed note snapshot. Row counts,
heights, cells, selection, swipe commands, and context menus no longer compute
a new filtered and sorted list for each request. The next view update replaces
the snapshot before it reloads the table. No public API or storage format changed.

Automatic: the offscreen regression reproduced incorrect row count, height, and
swipe availability when the model query differed from the displayed snapshot.
It now passes, including invalid row bounds and an empty replacement snapshot.
All eight row presentation tests pass. The full Swift test command passes.
No test opens a window. Native scale responsiveness still needs verification;
this correction does not establish the cause of the earlier UI timeouts.

Native follow-up: the unsigned Xcode build passed. Updated only the separate
Scale QA app and kept its local library identity. Relaunch showed 10,000 drafts.
Selected Note 5665, scrolled five pages, and selected Note 2275. The editor
showed the matching Unicode content. These observations completed without a
timeout; they are not precise latency measurements. The fixture gives every
note the same date. Selection caused tied rows to change order. The workspace
comparator has no identity tie-break for modified, created, or title order.
That separate ordering defect remains pending. No personal library changed.
Full automatic regression passed app448/core475.


### Stable workspace sort ties — 20 October 2026

Implemented: modified date, created date, and title sorts use ascending UUID
order when their primary keys compare equal. Access-date sorting already uses
this rule. The primary direction and per-folder flagged-first rule remain in
effect. Reload order no longer controls ties. This fixes a defect observed
while selecting notes with equal dates in Scale QA. It does not claim that
Drafts uses the same internal tie-break.

Automatic: a regression checks all four sorts in both directions with three
input permutations and flagged-first folder settings. Before the change, it
reported 18 failed assertions for modified, created, and title ties. After the
change, the full run passes app448/core476. No visible window opens.
Native verification of this second correction remains pending. The installed
Scale QA app still has only the earlier table-snapshot correction.


### Native stable ordering and scale search — 20 October 2026

The Xcode build passed. Updated and signed only Scale QA, with unchanged local
library identity. Executable SHA256:
069a7daee78411e49789160e1cc807f1d0c90ef4c9f3dc50438dafe793c2fe1f.
The app showed 10,000 drafts. Rows Note 0 through Note 5 kept their positions
after selecting Note 2 and Note 4. Searching for the quoted phrase Note 9999
returned one row. Selecting it loaded the expected Unicode content. Clearing
the query restored 10,000 rows and kept Note 9999 open. No content was edited.

Setting the native vertical scrollbar to 1 then timed out. The same process
remained live (PID 67145), near one CPU core. A one-second sample captured
layout and display work on the main thread. A later Computer Use observation
also timed out. This is not a crash or completed scale acceptance. Do not
restart solely because observation timed out. Inspect this process again and
investigate the long-scroll layout before accepting scale performance. Raw
samples remain in /tmp. No screenshot or raw evidence is tracked.


### Table-owned hosting size — 20 October 2026

The long-scroll process was still live near one CPU core after three minutes.
The sample includes table cell creation, hosting root updates, layout, and
display work. It does not prove a single cause. No restart was attempted.

Implemented: row hosting views use an empty sizingOptions set. The table
delegate and the existing four edge constraints own row dimensions. SwiftUI
content no longer contributes minimum, ideal, or maximum sizing constraints.
Apple documents these options at:
https://developer.apple.com/documentation/swiftui/nshostingsizingoptions

Automatic: an offscreen hosted-cell regression failed both intrinsic-size
assertions before the change and passes afterward. Full regression passes
app449/core476. Native long-scroll acceptance remains pending. This is a
layout correction supported by a regression, not proof that the observed
timeout is fixed. The installed Scale QA process still uses the prior build.

Native follow-up: the prior process recovered and showed rows 9994–9999 with
scrollbar value 1. It then quit normally. The new unsigned Xcode build passed.
Updated and verified the separate Scale QA signature. Executable SHA256:
fc64e7153b2480ce6d3a3089549b11f6b4bb500b2c7e27f7a6635ba0ae43b275.
Relaunch showed 10,000 drafts. Setting its scrollbar from 0 to 1 again exceeded
the 30-second Computer Use limit. The sizing correction therefore does not
resolve the long-jump acceptance. Keep that issue open and inspect repeated
cell creation, scrolling animation, and layout before making another change.
No note was edited. The running process must be rechecked before replacement.


### Long-scroll diagnostic follow-up — 20 October 2026

Rechecked the same Scale QA process, PID 68297. It remained live near one CPU
core for more than two minutes. A second one-second sample includes native
accessibility attribute requests leading into NSHostingView accessibility
children and SwiftUI graph updates, in addition to layout and display work.
A new Computer Use app observation timed out. No process was restarted.

The samples do not isolate scroll cost from accessibility inspection cost.
The next native check must separate the input operation from the observation.
After this process recovers, use keyboard navigation and a screenshot before
a full accessibility read. Compare ordinary scrolling with the scrollbar AX
value setter. Do not classify a scrollbar setter timeout alone as a measured
user scroll latency. Long-scroll acceptance remains pending. Raw samples stay
in /tmp. No production change follows from this diagnostic alone.


### Native scale observation correction — 20 October 2026

The same process recovered without restart and showed rows 9994–9999 at
scrollbar value 1. Selected Note 9999; its editor content matched. The combined
selection and observation call took about 22 seconds; that is tool wall time,
not isolated selection latency. Home returned a screenshot with rows near
9767. Subsequent accessibility diffs incorrectly reported no change. A full
read confirmed rows 9766–9772 and scrollbar value 0.9772056778718564.

Use full accessibility reads for scale checks. A no-change diff does not prove
that the table did not move. A later ordinary five-page upward scroll returned
rows 9959–9965, kept Note 9998 open, and completed with its full observation
in about 1.62 seconds. Command-Up selected the previous note; it did not prove
a jump to the first row. No content changed. Ordinary scroll and selection
have native evidence; the whole-list jump and isolated latency remain open.
Do not report the earlier AX setter timeout as general scrolling failure.


### Native separator execution picker — 20 October 2026

Used the existing isolated Engine QA app and nine-note library. Opened Run
Action from the neutral batch note context menu and cancelled. Imported
scripts/fixtures/engine-separator-actions.json through File > Import after
confirming its exact selected filename. The app reported Import complete.

Reopened Run Action and expanded its native popup. Engine separator QA showed
A Before section and C After section. B Neutral section was absent. Cancelled
the popup and dialog without running an action. The editor stayed blank and
the list still showed nine drafts. This accepts executable-picker exclusion
only. Backup restoration and reference appearance remain pending. The engine
contract stays partial. No source code or installed app changed in this check.


### Native separator backup round trip — 20 October 2026

On Engine QA image785e0548ab98a23c6a0e865e90215b7e8a1534b2e27406581359249f825d2224,
exported the full library to /tmp, imported that exact backup through File >
Import, observed Import complete, and exported again. This tests restoration
into the same library, not reconstruction in an empty store.

Comparison by record identity passed for all fields in every collection:
9 notes,71 revisions,65 actions,64 runs; other collections were empty. Separator
A0A29910-B452-4C8A-BF38-89854D18653D retained its identity, Order0, empty steps,
isSeparator metadata, raw payload, and unknown null/false/Unicode values.
The restored execution picker still showed A and C and omitted B. Cancelled
without execution. The editor stayed blank. Raw backups remain in /tmp.

This accepts the native same-library round trip and picker behavior. An empty-
library native restore, grouped/mixed separator import variants, and Drafts
appearance comparison remain pending. The engine contract stays partial.


### Native empty-library backup restoration — 20 October 2026

Created a separate signed Draftly Restore QA app from the existing Engine QA
build. Bundle ID: com.andrestobelem.draftly.restore-qa. Local library ID:
906AE94F-B222-48F0-A83D-B2F6AF2E0E65. CloudKit is disabled. Its URL scheme
is draftly-restore-qa. First launch showed zero drafts and a blank editor.

Imported the exact prior neutral QA backup through File > Import. The app
reported Import complete and nine drafts. Exported the rebuilt library through
File > Export Full Backup. Comparison by identity passed for every collection
and field:9 notes,71 revisions,65 actions,64 runs. All revision note IDs resolve
to restored notes. Separator identity, metadata, empty steps, Order0, raw payload,
and unknown null/false/Unicode fields match the source. Other collections are
empty in this fixture; this run does not verify nonempty workspace, group,
syntax, or theme restoration. No action ran and no personal library changed.
Raw backups remain in /tmp.

This closes the native empty-store reconstruction check for the separator
fixture and its populated collections. Reference appearance and grouped/mixed
separator variants remain pending. The engine contract stays partial.


### Separator container preservation cases — 20 October 2026

Expanded the existing containersPreserveNativeEntriesAndForeignStepData test.
It now covers eight cases: array or actions wrapper, native-only or mixed
foreign/native entries, and a normal or separator native entry. Mixed input
also contains a foreign separator with a fixed captured identity and unknown
null/false/Unicode data. Assertions check source order, exact native data,
separator identity, raw foreign payload, and equality of every action after
backup restoration into an empty memory store. Disabled unknown native steps
and options remain intact. No production code changed.

The focused ImportedActionPreservationTests run passed all five methods,
including eight container cases and two native future-field cases. Automatic
tests do not open a window. Native grouped/mixed separator presentation still
needs its own check. No additional full regression or Xcode build was required
for this test-only change; the last full run remains app449/core476.


### Native mixed separator container — 20 October 2026

Added scripts/fixtures/engine-mixed-separator-actions.json with stable IDs.
The actions wrapper mixes native normal/separator records with foreign normal/
separator records. All steps are empty. Unknown native and foreign data remain
in the fixture. Imported it through File > Import in Restore QA and observed
Import complete. Nine notes and the blank editor remained unchanged.

The execution picker showed A Native normal and D Foreign normal. It omitted
B Native separator and C Foreign separator. Cancelled without execution.
Opened the Mixed separator QA group. Native and foreign separators appeared
as labels with lines; A and D appeared as action buttons. Display order was
A,C,D,B: B explicitly has Order1; the other entries default to Order0. This
does not accept source-array order as a sorting contract. A focus change
interrupted the first cancel attempt; a fresh full state located Cancel and
confirmed the dialog closed. No action ran. No screenshot is stored.

This accepts the mixed actions wrapper and named-group presentation. A separate
exported action-group container format and exact Drafts appearance comparison
are not established by this check. The contract stays partial.


### Foreign notification option mapping — 20 October 2026

Supplemental reference, separate from the frozen scripting archive:
https://tools.getdrafts.com/wizards/mail
Fetched20 October2026. HTML SHA256:
06f20696b5dcbd707b98fd81568add2ed0c0975f943e9fd3ebc2af84cb2c92bd.
Its notificationType selector maps0 to None,1 to Error, and2 to Info. The
current official action guide describes none, errors-only, and all outcomes:
https://docs.getdrafts.com/docs/actions/editing-actions#notification
The frozen19 October scripting reference contains no notificationType member.
This source does not establish visibility, flags, group, or platform codes.

Implemented: foreign notificationType1 enables error notification;2 enables
success and error;0 disables both. Absent or unknown values keep the existing
quiet defaults. Full raw payload remains intact, including unknown values.
Native Draftly typed options remain unchanged.

Automatic: the new tests failed30 assertions before the fix. They now pass
all four codes on both legacy and async routes, checking exact host-call count
for success, error, and cancellation after native export/reimport. They also
check all five original fixtures and the absent-field default. Cancellation
never notifies. The fake host emits no native notifications or sounds. Full
regression passed app449/core478. The original scripts remain unchanged.
Native banner/inspector checks and timeout-specific import policy acceptance
remain pending. No new installed build is claimed.


### Imported execution log level — 20 October 2026

Implemented foreign logLevel using the supplemental official mail wizard
reference recorded above:0 None,1 Error,2 Info. Added an optional integer field
to ActionPresentation. Missing values keep complete history for old libraries.
Unknown integer values remain intact and use complete history. Native export
and backup carry the optional field; no Core Data schema change is needed.

Both runner paths use one recording helper. None suppresses the execution
record. Errors records Error outcomes, including timeout, and omits Success
and Cancelled outcomes. All records every outcome. Reports, completed effects,
error messages, and notifications remain independent. The action inspector
exposes None, Errors, and All. An imported unknown integer stays selectable
as Unknown and is not silently replaced. Existing edit-copy cancellation
behavior remains in effect. Native inspector behavior is not yet verified.

Automatic: the new policy test failed10 history assertions before the change.
Eight cases now check four levels on both runners across success, error, and
cancellation after backup restoration, including retained raw payload and
level value. Two legacy-library cases confirm absent-field native round trip
and complete success history. No test opens a window or emits notifications.
Full regression passed app449/core479 before the final absent-field test was
added. The subsequent focused suite passed both methods and ten cases. The
unsigned Xcode build passed. Native history/inspector checks and a specific
imported timeout case remain pending. No installed app was updated.


### Native imported log policy — 20 October 2026

Updated only Restore QA after normal quit and confirmed process exit. Signature
verification passed. Executable SHA256:
294c9c874705d96762a31e881b9074eb2ebe0616666828c9909a2825d9978af5.
Imported scripts/fixtures/action-log-policy-actions.json through File > Import
after verifying the selected filename. The six actions have stable IDs, neutral
scripts, and notificationType0. Selected the existing neutral batch note.

Ran all six actions from the action list. Completion messages matched success,
error, or cancellation. Execution History then showed exactly these new rows:
QA Log1 Error/Error, QA Log2 Success/Success, QA Log2 Cancel/Cancelled. It
showed no QA Log0 Error, QA Log0 Success, or QA Log1 Success entries. Existing
history remained visible. The editor retained the neutral text and nine notes.

Opened QA Log1 Error in the inspector. Log Level showed Errors and both
notification switches were off. The picker offered None, Errors, All. Changed
to None and pressed Cancel. Reopened the inspector: Errors remained selected.
Cancelled again. This verifies imported policy, native history filtering, and
editor cancellation. It does not verify saving a changed policy, restart after
editing, an imported timeout, or actual notification banners. No screenshot
or raw exported library is tracked. No personal library changed.


### Native log-level save and restart — 20 October 2026

On the same Restore QA build, changed QA Log1 Error from Errors to None and
committed the inspector with Return. Reopened the editor and confirmed None.
Cancelled, quit normally, confirmed the process was absent, and relaunched.
The inspector still showed None. Restored Errors, saved, reopened, and verified
Errors before cancelling. A focus change interrupted one attempt; a fresh full
state identified the open menu before resuming. No action ran in this check.

This accepts native inspector Save and restart persistence for a known imported
log level. The fixture ends at Errors. It does not cover unknown-level native
editing, imported timeout, or notification banners. Nine notes remain intact.


### Legacy CPU deadline classification — 20 October 2026

Extending the imported log-policy test with a CPU timeout exposed a separate
engine defect. All four legacy cases returned reason error instead of timeout.
Worker cases returned timeout. The legacy path installed the JSC limit without
a deadline state, so it only received the generic JavaScript exception.

Implemented: retain ScriptExecutionDeadline in the legacy script runtime and
pass it to the existing limit callback. Check the timeout state before treating
the evaluation exception as a generic error, including the async wait loop.
The state stays alive while JSC can reference it. No JavaScript value crosses
executors. Production limits remain unchanged. This does not move the legacy
runner off MainActor or change the new worker route.

Automatic: the expanded policy test now checks CPU timeout for levels0,1,2,99
on both routes, with a short limit only for the endless script. It verifies
final report reason, history inclusion, raw/typed persistence, and unchanged
text. Four classification failures reproduced before the fix. Full regression
passed app449/core480; unsigned Xcode build passed. Existing deadline tests
continue to check that later steps and success disposition do not run.
Native reproduction of this legacy adapter correction remains pending. The
installed Restore QA app still has the preceding build.


### Imported policy CPU and timer deadlines — 20 October 2026

Expanded the existing notification and history policy cases. Each code0,1,2,99
now checks success, explicit error, cancellation, initial CPU timeout, and CPU
timeout inside an asynchronous timer on both runner routes. Short deadlines
apply only to the endless test script. Normal outcomes retain the production
synchronous default. Tests use a fake host; no banner or sound is emitted.

The cases require reason timeout for both deadline locations. They check exact
notification count and history inclusion independently. None suppresses its
respective effect; Errors applies once on timeout; All applies once. Cancel
still never notifies. Backup/export fields and editor text remain intact.
The focused four-suite run passed20 methods, including the expanded policy
cases and existing completion/worker deadline cases. No production code changed
after e458703. The matrix now links these specific tests as supporting evidence
for initial and asynchronous deadline contracts. Native verification status
remains unchanged. The last full run is app449/core480; this focused run covers
the subsequent test-only edits.


### Native timer CPU deadline and menu responsiveness — 20 October 2026

Added a seventh stable-ID action to action-log-policy-actions.json. It starts
an async timer with an endless loop, then has an insertText sentinel and
Archive disposition. NotificationType0 prevents native banners and sounds.
LogLevel1 records the failure. Imported the fixture into the unchanged Restore
QA image294c9c874705d96762a31e881b9074eb2ebe0616666828c9909a2825d9978af5.
This uses the async worker, not the legacy adapter corrected afterward.

Selected the neutral batch note and ran QA Log1 Timer CPU Timeout. At918ms
the action button was disabled. At1700ms the File menu was open and its items
were readable. These are tool observation times. The production synchronous
limit remained10 seconds; no preference or deadline was changed. Menu response
therefore occurred before the expected limit while CPU work was pending.

After completion, History contained exactly one matching Error row with the
timeout message. The editor retained the exact neutral text, no tail sentinel
appeared, and Inbox retained all nine notes. Archive did not run. Closed History.
Escape did not reliably dismiss the native menu through the tool; after a fresh
app state, the menu's exposed Cancel action closed it. The process stayed live.

This accepts native timer CPU failure, error-only logging, preserved text and
disposition, and opening a menu during worker CPU work. It does not measure
precise timeout latency or verify legacy native execution, every UI control,
or native notification banners. No screenshot or raw output is tracked.


### Native UI queued production timeout — 20 October 2026

Used Restore QA image294c9c874705d96762a31e881b9074eb2ebe0616666828c9909a2825d9978af5.
Created two new neutral drafts, Queue target neutral and Queue source neutral.
Filtered the Imported action list to QA Queue multi-draft pending root. Ran
that action from the list. The editor followed the child to its separate draft
and showed Queue timeout completed write — café 🐼. No text was edited and no
window was closed during execution. The library has11 notes after this check.

The action remained disabled/pending at41199ms and107067ms observations. It
was enabled/final at130517ms. These are observation times around the unchanged
production120-second limit, not a precise timeout-duration measurement. History
showed a new root Error with the timeout message. The editor stayed on the child.

Exported the result through the native backup command. Compared against the
prior nine-note backup: exactly two new note IDs have exact contents Queue
source retained and Queue timeout completed write — café 🐼. Both remain in
Inbox with no trash date or ERROR sentinel. Exactly one new root history row
has Error status, the timeout message, and the new source note ID. Raw backup
stays in /tmp. No personal library changed.

The focused regression passed5 app methods and25 core methods. The auditor's
25 Python tests passed. This closes the last named native gap in queue
cancellation; that contract is complete. Other engine contracts remain partial.
Reconciled stale native summaries for common entry points, callback selection,
and host lifetime against their already recorded checks. No unrelated contract
was promoted. The full API inventory is562 members:104 complete,157 partial,
296 unclassified,3 unavailable,2 excluded. These are inventory counts, not a
compatibility percentage. The earlier global strict check reported4913 field
diagnostics before this queue evidence update; it is not a member count.

After the queue update, the structural matrix check passes. Strict engine
parity reports24 diagnostics for the remaining eight partial contracts. The
queue contract has no remaining strict diagnostic. This does not close Mac.


### Native Intent promise rejection variants — 20 October 2026

Used the existing Draftly QA Engine — disposable shortcut in Shortcuts.
Engine QA image785e0548ab98a23c6a0e865e90215b7e8a1534b2e27406581359249f825d2224
handled the Intent. Changed only Action Name and Draft UUID, committed with
Tab, and verified both visible values before running. Targeted the neutral
batch fixture note A52FA8DB-A020-40D3-AF18-25654E97CCE7.

Actual Run Draft Action returned the expected error alert for QA Discarded
rejection, QA Intrinsic async rejection, and QA Returned rejection. History
showed three corresponding Error rows. Selected the result in Engine QA: its
full content was Returned rejection completed write, with no tail marker, and
Inbox still held nine notes. Archive did not run. A later QA Caught rejection
Intent completed successfully; Shortcuts displayed completion and History
showed Success. The visible editor became Caught rejection completed.

Restored the shortcut to QA Caught rejection and its prior UUID
A386D93F-D3D8-49EB-8F7F-205612F74D93, committed with Tab, and verified the
fields. No shortcut was deleted or sent externally. No screenshot is tracked.
The focused promise/runtime/epoch run passed8 methods in3 core suites.

This accepts the direct Intent rejection variants and recovery. The older
discarded/intrinsic/caught URL callback checks are recorded in Discarded
rejection correction. A direct returned-rejection URL callback check is not
yet linked. Keep the promise contract partial until that specific gap closes.
Other capability-specific cancellation checks remain in their own contracts.


### Native returned promise URL callback — 20 October 2026

Used the local callback helper to target Engine QA image
785e0548ab98a23c6a0e865e90215b7e8a1534b2e27406581359249f825d2224.
Built draftly://run for QA Returned rejection and neutral fixture UUID
A52FA8DB-A020-40D3-AF18-25654E97CCE7, with separate identified success/error/
cancel destinations. Used percent-encoded spaces. Confirmed the native Run
Action prompt named the expected action and existing neutral target.

The helper received exactly one callback: case returned-rejection-url, result
error, errorMessage Error: Neutral returned rejection. It had no discard
success parameter. Engine QA also showed its error alert; dismissed it. The
full editor content was Returned rejection completed write. Inbox still had
nine notes, with no tail text or Archive. History showed the new Error row.
After closing History, helper count remained one with the same error fields.
No personal library or shortcut setting changed in this check.

This supplies the missing direct returned-rejection URL acceptance. The earlier
UI and URL discarded/intrinsic/caught checks, direct Intent variants, and
production UI/queued URL/Intent wait-timeout evidence remain linked in the
matrix. The promise rejection and asynchronous timeout contract is complete
for its named cases. Capability-specific cancellation and final late callback
contracts remain separate and partial. No automatic code changed; the prior
focused promise/runtime/epoch run passed8 methods. No screenshot is tracked.

Structural matrix check passes. Strict engine parity now reports21 diagnostics
for seven remaining partial contracts. The promise contract has no strict
diagnostic. This closes that contract only, not the engine or Mac plan.


### Native final callback merge and late response — 20 October 2026

Used Engine QA image785e0548ab98a23c6a0e865e90215b7e8a1534b2e27406581359249f825d2224
and the local helper. External URL A Before section completed with one success
callback. Its target originally contained two position query items. The final
callback had exactly one position=before and retained existing=café 🐼 +.
No action source was changed.

For QA Native late, the first attempt completed successfully before the next
cancel click. Its callback and Success history are controls, not cancellation
evidence. A batched retry cancelled and produced one x-cancel; its baseline
text already equalled the tail marker, so it cannot prove tail exclusion.

Prepared distinct Caught rejection completed text with the caught control.
Sent a new identified run URL and confirmed the prompt named that target.
Cancelled through the enabled Actions menu in one observed sequence. At1977ms
the helper showed exactly one final-late-verified cancel callback. At14829ms
it still showed one cancel, while Replies opened had increased to5 and its
8-second delayed native open reported success. The editor still contained
Caught rejection completed, rather than Must not replace edited text. Inbox
retained nine notes; History showed Cancelled for the final attempt. The native
open result is an observation of OS delivery, not an exact app-handler timestamp.

The focused regression passed1 app timeout-boundary method and27 core methods
in execution API/session suites. Together with linked error, queued timeout,
and busy acceptance, this closes final callback selection for its named cases:
correct destination, one final callback, parameter replacement/Unicode, no
success leakage, and no second finalization after a late response. Remaining
capability/entry contracts stay separate. No screenshot or raw output is tracked.

Structural matrix check passes. Strict engine parity now reports18 diagnostics
across six other partial contracts. Final callback selection has no remaining
strict diagnostic. The engine and full Mac goal remain open.


### Native task cancellation during prompts — 20 October 2026

Used Engine QA image785e0548ab98a23c6a0e865e90215b7e8a1534b2e27406581359249f825d2224
on the selected neutral fixture. Ran QA Async prompt keyboard from Actions.
Changed its field, opened Actions while the prompt remained pending, observed
Cancel Running Action enabled, and selected it. The prompt closed. The editor
retained Caught rejection completed and the action reported cancellation.
WindowModel.cancelActions cancels both the owning task and runner; this is not
just the prompt's own Cancel button.

Repeated with QA Async selection keyboard. Searched Second and observed the
filtered Two Second row. Cancelled the running action from Actions. Selection
was not applied and the draft stayed unchanged. A separate prompt Escape check
also discarded edited text. Reopened SelectPrompt: search was empty and both
choices were present. Searched Second and pressed Return; the editor became
Selected: two. History showed three matching Cancelled outcomes followed by
SelectPrompt Success. Closed History. No OS permission or external data was used.

Focused regression passed6 app prompt methods and4 core methods across host
interruption, cleanup, and defaults suites. Automated tests use fake presenters
and do not open windows. Native evidence accepts task-owned prompt cleanup,
keyboard cancellation, fresh selection state and recovery. It does not accept
transcription, EventKit, Apple model cancellation, or OS permission dialogs.
Those engine contracts remain partial. No screenshot is tracked.


### Native on-device model unavailability — 20 October 2026

Added engine-apple-model-cancel-actions.json with a stable identity. It uses
only the onDevice mode, clears toolSets, and uses a neutral prompt. It checks
isAvailable before requesting a response. If unavailable, it requires respond
to return undefined and lastError to contain the explicit availability error.
If available, it requests a long neutral response for task-cancellation QA.
No private-cloud or third-party provider is requested.

Imported and ran the fixture in Engine QA image
785e0548ab98a23c6a0e865e90215b7e8a1534b2e27406581359249f825d2224.
The unavailable branch completed with exact editor text Apple model unavailable:
The selected Apple Intelligence model is unavailable on this Mac. The Cancel
Running Action command was disabled after completion; no generation was pending.
NativeActionHost constructs NativeModelAPI without a test backend. Its mode
list uses FoundationModels.SystemLanguageModel.default.isAvailable. This is
the current system availability response, not a simulated failure. The cause
(language, configuration, or model readiness) was not established.

No permission, model download, or system setting changed. This accepts only
the unavailable onDevice response and lastError path. Native cancellation of
an actual generation remains blocked by current availability. Do not mark
ModelSession globally unavailable or accept its successful-response contracts.
PCC remains unchecked. The focused injected-backend model suite passed7 app
methods, including cleanup, deadline, overlap, cancellation and tool lifetime.
No automated test opens a window or requests the real model. No screenshot is
tracked. The other native capability work can continue independently.


### Native transcription task cancellation — 20 October 2026

Read System Settings privacy pages without changing controls. Speech access
was enabled for Draftly Visual QA, DraftlyCoreQA, and Drafts. The Calendar page
showed a Draftly entry with no access; that label does not establish Engine QA's
authorization state. No Calendar grant was added. Visual QA's bundle identity
is com.andrestobelem.draftly.visual-close, with local library
6f947773-92ee-4bd9-a0ae-3e06b5c9377f and CloudKit disabled.

Updated the existing stopped Visual QA app with the full current built MacOS,
Resources, and Frameworks directories. Kept Info.plist and its ad-hoc signing
type; signature verification passed. Executable SHA256:
fc4f02d4d2ea7dbb9eb65f523e3ae7d75154ab2990d0ec66bf89c5b3c91e6e55.
The installed path was selected explicitly because old build products share
its bundle ID. Initial launch showed zero drafts. Created one neutral note and
imported engine-transcription-cancel-actions.json. No new permission prompt
appeared. The action opened the audio picker using its existing speech grant.

Cancelled the owning task through Actions > Cancel Running Action while the
picker was open. The picker closed; exact neutral Unicode text remained.
History recorded Cancelled. No file was selected for this first check.

For recognition-phase cancellation, generated a120-second mono16kHz16-bit PCM
WAV of zeros in /tmp. No microphone, voice, personal file, or playback was used.
SHA256:4395f2569b32c91407f267c835a96159b9d03c7a2303907ee10d716713ae1e0a.
Selected that exact file. At1237ms observation the picker had closed and the
action remained pending; Cancel Running Action was enabled. Cancelled it.
The draft still contained Transcription cancellation neutral café 🐼, with no
ERROR tail. History showed a second Cancelled row. This accepts cancellation
during selection and recognition, not recognition accuracy or successful text
transcription. The speech service may process the synthetic silence under the
existing grant. No private audio was supplied.

Focused regression passed12 app transcription methods and3 core methods across
host interruption/cleanup suites. Fake-driver tests do not request permissions
or open windows. Native EventKit cancellation remains pending; onDevice model
generation cancellation remains blocked by availability. No screenshot or WAV
is tracked. The QA app remains on its one neutral note.


### Prepared EventKit cancellation fixture — 20 October 2026

Added scripts/fixtures/engine-eventkit-cancel-actions.json for a manual check
of task cancellation during event creation. The second step inserts an ERROR
marker if execution continues. JSON parsing and the fixture structure passed.
The native check has not run. It must not save an event. Calendar permission
and dialog cancellation remain pending; this fixture does not prove acceptance.


### Native EventKit task cancellation — 20 October 2026

Ran engine-eventkit-cancel-actions.json in installed Draftly Visual QA, local
library 6f947773-92ee-4bd9-a0ae-3e06b5c9377f, with CloudKit disabled.
Executable SHA256:
fc4f02d4d2ea7dbb9eb65f523e3ae7d75154ab2990d0ec66bf89c5b3c91e6e55.
The native Create calendar event dialog opened without a new permission prompt.
No permission changed. This establishes an existing usable Calendar grant,
not which similarly named entry appeared in the earlier privacy page.

Edited the neutral title, then used Actions > Cancel Running Action. The dialog
closed and the editor retained Transcription cancellation neutral café 🐼.
The ERROR tail did not run. Opened the action again: the original neutral title
and notes appeared, without the discarded edit. Clicked Cancel in that dialog.
The editor remained unchanged. History showed two EventKit rows, both Cancelled.
Save Event was never pressed. The save closure is reached only after an accepted
dialog result; this check did not create an event or inspect private calendars.

The focused NativeEventDialogTests and NativeEventKitWaitTests run passed
18 tests. It covers cancel-before-save, late acceptance after cancellation,
authorization errors, timeout, duplicate callbacks, and reminder fetch cleanup
with injected hosts. It does not open windows or request real permissions.
Native permission-request cancellation and successful Calendar saving remain
outside this check. Actual model generation cancellation remains blocked by
current system availability. The task cancellation contract remains partial.


### Native awaited Shortcut responses — 20 October 2026

Inspected the existing Draftly QA Output — disposable shortcut. It contains
Wait 5 seconds, Text Native shortcut output café 🐼, and Stop and Output.
A direct editor run completed with that exact output. No shortcut was edited
or deleted. Then ran the existing QA Shortcut waited script and waited step
actions from Engine QA's Actions menu. Executable SHA256:
785e0548ab98a23c6a0e865e90215b7e8a1534b2e27406581359249f825d2224.

The actions completed with measured fixture times 5238 ms and 5199 ms. Their
assertions checked the exact Unicode result, one callbackResponses entry,
and shortcut_result template tag. History showed Success for both actions.
The earlier native timeout remains part of the record; this run proves the
success path now worked with the existing shortcut, not why it stalled before.

A separate QA Shortcut callback control run recorded Cancelled. During that
run, a new draft with text So appeared without an agent edit. Its origin and
the cancellation trigger were not established. Do not use that run as callback
success or cancellation acceptance. The new draft was left unchanged. Engine
QA now has 10 drafts and no pending action. History was closed. The scratch draft
retains the exact text Shortcut waited step finished in 5199 ms café 🐼.

NativeProcessExecutorTests and ShortcutLaunchTests passed 15 tests. These use
local process fixtures; they do not open windows or invoke real Shortcuts.
Real native callback timeout and other permission/capability variants remain
pending. No screenshot or raw process log is tracked.


### Duplicate editor preflight writes — 20 October 2026

Found a preflight regression with two editors on the same draft. When the
dirty owner was flushed first, the clean duplicate wrote its old text back.
The owner then restored its pending text. The final result looked correct,
but the intermediate stale save could create revisions and sync changes.
A save spy reproduced Pending → Stored → Pending without any visible window.

Automation preflight now calls synchronizeStoredEditor before each flush and
once after all flushes. That existing method skips dirty editors. It refreshes
clean editors from current storage, so model enumeration order cannot cause
a clean duplicate to save its stale text. Pending edits still use flush and
retain the existing error path. This does not resolve simultaneous conflicting
dirty edits or change window selection policy.

Added cleanDuplicateEditorCannotOverwritePendingOwnerText with both owner
orders. The original code failed for owner-first order. The correction passed
both orders, retained Unicode text, used the selected owner's runner, and made
no old-content write. Focused automation and Intent suites passed 23 tests; the
full run passed 450 app and 480 core tests. Tests use in-memory libraries and do
not create or activate windows. Native two-window acceptance remains pending.

The unsigned local Xcode build passed. Matrix structure check passed with
zero errors. No installed QA app was replaced for this change.


### Native duplicate-window URL owner selection — 20 October 2026

Updated the stopped Visual QA app from the local build of 0b91f58. Kept its
Info.plist, local library, and ad-hoc signing type. Signature verification
passed. Executable SHA256:
87fb326b8af993eef9e2450d5f6156b9807203f97c86a8a2c457a2c8624d24fd.
Debug library SHA256:
58c64335164f32d5233b44db496a77267a5a6abd200adc6a19bce09b11115302.
No permission changed and CloudKit remained disabled.

The manual callback helper now has an explicit Engine QA/Visual QA selector.
It opens only the named installed app and checks the expected bundle identity
and DraftlyUITesting flag. Engine QA remains the default. The read-only window
monitor still targets Engine QA and its label now says so. Compiled the helper
and passed its window-inventory self-test before replacing its stopped copy.

Imported engine-window-owner-actions.json into Visual QA. Reused its single
neutral draft, UUID 2CD5AB10-6A3A-4E79-A2AF-33A4E4AC41DB. Set its text to
Alpha 🐼 Beta café Gamma and used Open in New Window. Both native windows
displayed that same draft. Window IDs were library-AppWindow-1 and library-AppWindow-2.

Selected Alpha in Window 1 while the duplicate had a different selection.
Sent a run URL with the exact UUID through the helper's Visual QA target and
confirmed Run Action. The helper received one success callback, selected=Alpha.
Then activated Window 2 through the native Window menu, confirmed its window ID,
and selected Gamma. The second URL run returned one success callback with
selected=Gamma. Both windows displayed the final text
Owner:Alpha 🐼 Beta café Owner:Gamma. No second note was created.

This accepts visible same-draft URL ownership in both activation orders and
content propagation between clean editors. It does not prove App Intent
selection, minimized-window fallback, or a timed pending edit before autosave.
The automated regression covers that preflight write boundary. Both QA windows
remain open on the one neutral draft; the helper has no pending reply timer.
No screenshot is tracked.


### Draft and Editor URL contract cases — 20 October 2026

Added DraftURLContractTests.fullCustomURLsAreReturnedAlongsideHTTPS for both
legacy and worker runners. It checks HTTPS with an escaped query, draftly://,
shortcuts://, tel:, and mailto: URLs. It checks exact order, duplicate
occurrences in an unsaved detached draft, unchanged editor reads, Unicode
surroundings, no matches, and empty content. No production code changed.

The archived Draft.urls and Editor.urls contracts promise full valid URL
strings for HTTP(S) and custom schemes. They do not specify every lexical
boundary. An exploratory opaque custom URI case such as obsidian:open was
not retained as a required assertion without native comparison. Do not infer
that all opaque schemes are supported, or add broad matching rules that could
treat ordinary colon-separated prose as a URL. Punctuation boundaries also
remain unverified. Both members remain partial.

The focused run passed 4 core methods across this suite and SyntaxActionAPITests,
plus 9 app methods in AutomationEditorContextTests. The new method expanded to
both runners. No window, permission prompt, or private URL was used. These
assertions do not establish native Drafts parity or all URL contracts.


### Draft update worker and rollback coverage — 20 October 2026

Refactored the two existing Draft.update contract tests to run on legacy and
worker execution. They check the void return, shared identity, immediate
editor-model updates, content, tags, flags, and exact storage-error result.
The storage-error case now performs an independent later commit and restores
a backup. It verifies that rejected text and revisions do not reappear.
No duplicate test methods or production changes were added.

The coordinator's focused run passed 48 methods across DraftMetadataContractTests,
WorkspaceDateBoundaryContractTests, and WorkspaceFilterContractTests. The two
update methods each passed both runner variants. These are in-memory checks;
native selection and Undo acceptance remain pending. No window opened.


### Workspace calendar-day boundary coverage — 20 October 2026

Added WorkspaceDateBoundaryContractTests for the shared filter evaluator.
The archived QueryDate contract ignores time components and includes the
whole selected calendar day. The test fixes the Gregorian calendar and
America/New_York time zone. It checks 8 March 2026 (23 hours) and 1 November 2026
(25 hours), created/modified/accessed fields, absolute dates, and relative
±1 day. For each start/end boundary it checks one millisecond outside, the
start, one millisecond before the next day, and the next day itself. Unknown
access dates stay unknown and are excluded from active access-date filters.

All six parameter combinations passed. No production defect was demonstrated.
The combined coordinator run passed 48 methods in three suites. This is direct
evaluator evidence; it does not establish JS property reconstruction, native
window results, or persistence after restart. Existing property tests remain
recorded separately, and startDate/endDate stay partial. No window opened.


### Native callback timeout and late delivery — 20 October 2026

Extended only the manual helper's reply-delay cap from 10 to 150 seconds.
Compiled and replaced its stopped copy, then passed its inventory self-test.
Added engine-native-timeout-actions.json: a callback step requests a neutral
reply after 130 seconds, followed by an ERROR insertion sentinel. Production
callback and host limits remain 120 seconds. No permission or setting changed.

Imported the fixture into Engine QA image
785e0548ab98a23c6a0e865e90215b7e8a1534b2e27406581359249f825d2224.
Sent a run URL for scratch UUID A52FA8DB-A020-40D3-AF18-25654E97CCE7.
Its confirmation showed the expected Shortcut waited step text. The other
draft So was not edited. Confirmed Run Action and measured observations from
that click. At 112976 ms, the helper still showed zero final callbacks and a
pending 130-second reply. At 126983 ms, it showed one error callback with
The action operation timed out before it completed. The reply was still pending.

At 138811 ms, the helper reported one native reply open, successful, with
Delay 130 seconds and value Expired timeout reply. The final callback count
remained one error. At 163971 ms, after checking the draft and history, that
count was still one. Target text stayed exactly
Shortcut waited step finished in 5199 ms café 🐼, with no ERROR sentinel.
History had one new root Error row with the timeout message. Closed History.
Engine QA still has 10 drafts; no action or reply timer remains pending.

This proves final timeout, stopped subsequent steps, and ignored late native
reply for the combined host/callback path at production limits. Both limits
are 120 seconds; the observation does not establish which timeout won the race
or the precise app-handler delivery timestamp. It does not accept all native
permission or capability lifetimes. Focused ActionCallbackRouterTests passed
6 app methods and CallbackResponseContractTests passed 3 core methods. These use
injected URL openers and do not control visible windows. No screenshot is tracked.


### Native Draft.update selection and Undo — 20 October 2026

Imported draft-update-native-actions.json into Visual QA image
87fb326b8af993eef9e2450d5f6156b9807203f97c86a8a2c457a2c8624d24fd,
with debug library 58c64335164f32d5233b44db496a77267a5a6abd200adc6a19bce09b11115302.
Used its single neutral draft in Window 1; both windows were already open.
Selected café in Owner:Alpha 🐼 Beta café Owner:Gamma. The action appended
a new line Updated café 🐼 through draft.content and update(), added update-qa
and flagType 2, and asserted void return, immediate editor content, shared
find identity, and unchanged UTF-16 selection. It completed successfully.
The native editor displayed the new line with café still selected. The tag
appeared in the sidebar and tag control; the flag icon became filled.

Command-Z removed only the appended line. Command-Shift-Z restored it. The
café selection remained after both operations. History recorded Success.
After closing History, activated the confirmed Window 2; it displayed the
same final content and metadata. No permission changed or private text was used.

This fills the recorded native acceptance for Draft.update. Normal and exact
storage-error tests on both runners remain the automated contract evidence.
The failure test also checks a later independent save and backup restoration.
Draft.update is complete for its archived contract; this does not close Draft,
Editor, the engine, or all native error paths. No screenshot is tracked.


### Editor void return contracts — 20 October 2026

The archived Editor signatures declare void for undo, redo, showFind,
showArrange, and showDictate. Their shared bridge wrapper returned the host
value, so a host response of true escaped into scripting. The existing
interface test failed on both legacy and worker routes at showFind.

The bridge now discards the host result for these five methods. It still
synchronizes the draft after Undo/Redo and forwards all arguments. Methods
arrange, dictate, scanDocument, and transcribe keep their documented results.
The interface test now runs on both routes and asserts void returns, including
activation and draft navigation, while retaining string-return checks.
No real dictation, scanning, arrangement dialog, or permission is invoked.

The agent's focused Editor/persistence run passed 23 methods. The coordinator
full run passed 450 app and 482 core methods after integration. The test count
is regression evidence, not a compatibility percentage. These five members
remain partial where their other defaults, errors, or native paths are not
accepted. Existing native checks do not validate this new build's return value.

The unsigned local Xcode build and matrix structure check passed. Installed
QA apps still use their previously recorded builds.


### Read-only action catalog properties — 20 October 2026

The archived Action and ActionGroup properties were marked readonly but their
constructors copied writable fields. Reflect.set could change an action's
identity, name, separator state, or configuration reference. Renaming a group
could also retarget its dynamic actions query. The new named cases failed
on both runners before the correction.

Action now defines uuid/name/isSeparator/configuredValues as non-writable
own properties. ActionGroup does the same for uuid/name. Configuration is
injected at construction and shares the context.configuredValues reference.
Its contents remain mutable; this change does not deep-freeze the dictionary
or settle included-action configuration precedence. Installation URLs and
group action queries keep the original identity after rejected assignments.

ActionCatalogReadOnlyContractTests passed both cases on both runners. The
agent's catalog/configuration/inclusion regression passed 29 methods; the
coordinator full run passed 453 app/484 core methods. These are automatic
contracts, not native inspector acceptance. Members retain partial status
for the other unresolved parts of their contracts. No window opened.


### Shared syntax indentation — 20 October 2026

Editor.preferredTabString previously returned a fixed Tab while the editing
buttons inserted/removed two spaces. Added local indentation preferences per
syntax: Tab, 2 Spaces, or 4 Spaces. Missing, invalid, or unknown options use Tab
for compatibility with the existing getter and native key. String entries
for unknown syntax names are preserved when another preference changes.
Settings > Editor exposes Syntax and Insert controls. Preferences stay in
UserDefaults and are not included in library records, backups, or sync.

The native Tab key, scripting getter, and built-in Indent/Outdent actions
now share that value. The native insertion uses insertTab and the documented
insertText(_:replacementRange:) user-input path. Outdent removes the selected
configured prefix; space modes also remove a shorter leading space run. It
does not remove a different indentation style. The five original imported
action scripts were not changed. Regenerated the Xcode project for the new
source file; the final unsigned build passed.

Automatic EditorIndentationTests cover isolated defaults, per-syntax reload,
unknown-value fallback/preservation, unchanged library backup data, native
UTF-16 selection replacement with no window, and Indent/Outdent on both
runners for all three styles. Changing syntax updates the getter without
changing content or selection. Reflect.set cannot assign the getter. Full
regression passed 453 app/484 core methods; final indentation/property checks
passed 15 methods after adding the readonly assertion. No automatic test
opens or activates a visible window.

Updated stopped Visual QA, retaining Info.plist/local data/ad-hoc signature;
signature verification passed. Executable SHA256:
9db58717ac543a171d3bd0fbf90e6525e364f5bfc63a247dae90a4c3a52ba420.
Debug library SHA256:
aa57edf4b0acb85bd72f94f82f5c0e6b8da2b46a15796156202843a522d0ebb5.
Changed Markdown from Tab to 4 Spaces in native Settings. Selecting Updated
and pressing Tab inserted four spaces, leaving the following source space.
Undo restored Updated and its selection; Redo restored the insertion. Undid
again, then selected Updated and used Indent: exactly four spaces appeared.
Selecting that prefix plus Updated and using Outdent restored the source.

Changed Markdown to 2 Spaces. Undo of the prior Outdent still restored the
four-space edit and selection; Redo restored the source. Quit/relaunch kept
Markdown = 2 Spaces in Settings. The existing neutral note retained its final
text and metadata. Settings closed; one QA window remains on that one note.
No new permission or screenshot. This accepts the archived preferredTabString
contract and local preference behavior, not visual parity of all Settings.


### Native action catalog identity acceptance — 20 October 2026

Imported action-catalog-readonly-actions.json into Visual QA image
9db58717ac543a171d3bd0fbf90e6525e364f5bfc63a247dae90a4c3a52ba420.
The fixture contains one runnable action and one separator in Native catalog QA.
The action verified its exact stored UUID/name, false separator state, the
other entry's true separator state, group name and UUID shape, and matching
identities through find/getAll/group.actions. Missing lookups returned undefined.
Reflect.set rejected each readonly property and left the original values intact.
History recorded Success and the editor displayed Catalog readonly passed café 🐼.
No permission changed. The separator was not offered as a runnable menu item.

Expanded the existing readonly tests with both separator states. The group
case now renames its implicit group through the library, restores a backup,
and queries it through scripting on both runners. Group UUID and member UUID
survive; the old name is absent and the new name matches. The focused catalog
run passed 7 methods; the final identity/restore run passed 2 methods with four
runner variants. No automatic test opens a visible window.

This closes Action.name/uuid/isSeparator and ActionGroup.name for the
archived contracts. ActionGroup.uuid remains partial because the legacy
identifier algorithm has the collision described below. configuredValues remains partial: reference sharing and
readonly replacement are tested, but typed values from another action and
inclusion precedence need separate acceptance. Action.recent currently derives
usage from saved logs. Behavior when log policy omits a run needs comparison;
it is not accepted as log-independent history. No speculative behavior change
was made. Installation formats and complete ActionGroup methods remain separate.
QA retains one neutral note, its update-qa tag and flag, Markdown 2 Spaces, and
no open History. No screenshot or raw log is tracked.


### Action group identifier collision found — 20 October 2026

Before closing ActionGroup.uuid, compiled the current ActionGroupRecord
structure extracted verbatim from PresentationSettings.swift into a temporary
Foundation-only probe. Distinct valid names BAAAAAAAAAAAAAAAA (B plus 16 As)
and ?AAAAAAAAAAAAAAA (question mark plus 15 As) both produced
3F414141-4141-4141-4141-414141414141. The legacy sixteen-byte rolling algorithm
is not collision-safe. The probe did not open or change a library.

Readonly and rename/restore checks passed, but they do not prove uniqueness.
ActionGroup.uuid stays partial. Next: reproduce creation of both names through
the library in an isolated test, prevent replacement/data loss, and assign a
collision-safe identity while preserving existing stored and implicit IDs.
Do not replace every legacy group ID without a migration. No production
change for this issue has been made yet.


### Collision-safe group identity allocator — 20 October 2026

Added ActionGroupIdentity to reserve stored IDs, retain available preferred
IDs, and resolve legacy name collisions with deterministic SHA256-derived IDs.
The legacy constructor and identifier function remain unchanged. Six pure
tests passed for the known collision, input order, stored and preferred IDs,
and an occupied hash candidate. No test opened a window.

Library saves, scripting, and workspace consumers do not use this allocator
yet. The stored-group overwrite defect remains open. Next: add a failing
library regression, connect allocation to atomic saves and all consumers,
and verify restore and reopen. ActionGroup.uuid remains partial.


### Group save collision protection — 20 October 2026

Two isolated regression tests first failed with six issues: a new colliding
group replaced the stored group and retargeted its action; batch saves accepted
duplicate IDs. Single-group saves now allocate an unused identity for a new
legacy collision. Materialized implicit groups use the same reserved mapping.
Batch saves reject duplicate IDs before writes. Existing rename behavior stays
covered by the organization and both-runner catalog tests.

The final focused run passed 14 methods in four suites. The collision test also
checks backup restore and SQLite reopen. A separate case preserves an implicit
group and its action when a colliding explicit group is added. No automatic
test opens a window. Native verification of this change is pending.

ActionGroup.uuid remains partial. Remaining work: persist collision-safe IDs
when action saves create only implicit groups; unify scripting, workspace and
UI identity consumers; cover deletion, rollback, import and restore collisions.
Do not infer complete group identity acceptance from these save tests.


### Implicit group identity persistence — 20 October 2026

Collision groups created by action saves now receive stored IDs in the same
transaction. Existing implicit IDs take priority. Ordinary noncolliding groups
stay implicit. Deleted records are excluded from pending decoding. Scripting,
workspace resolution, settings and group management use the shared allocator.

The full regression passed 454 app methods and 496 core methods. A later
focused run also passed the legacy backup and group removal case. Unsigned
Xcode compilation passed. Structural matrix validation passed before the
evidence update. Tests cover both creation orders, stored identity, deletion,
restore, reopen, failed batch, both scripting runners and workspace UUID
lookup. No automatic test opens a window.

Native collision creation and import acceptance with the new binary remain
pending. ActionGroup.uuid stays partial. Next: verify neutral colliding groups
in QA, check imported identities against existing groups, and record the
native result. The earlier commit push failed DNS resolution; retry when
GitHub is reachable. No global or core parity closure is claimed.


### Native collision identity acceptance — 20 October 2026

Updated Visual QA from the successful unsigned build. Executable SHA256:
8393885e47da2ef0ef568a85da491c3c3f4f32d7ac1f67e7dc15d2df805d79dc.
Imported action-group-collision-actions.json through File > Import. The fixture
contains one action in B plus 16 As and another in question mark plus 15 As.
The verification action checked distinct UUIDs, separate membership and one
getAll entry per UUID. History showed Success. The neutral editor marker showed
C95E49A1-6E4A-8EB1-B316-F1199A92BB18 and
3F414141-4141-4141-4141-414141414141.

Quit and reopened the exact QA bundle. Selected the existing neutral note and
ran the same action again. It completed and returned the same two UUIDs.
QA retains one neutral note, update-qa and its flag. No permission changed.
No screenshot or raw log is tracked. The reproducible fixture is tracked.

Added single-file and multi-file import cases against an existing collision
owner. Both preserve its UUID and action membership, allocate a different UUID
for the imported group, keep IDs on repeated import, and roll back injected
write failures. The focused import regression passed 16 methods in two suites.
This closes ActionGroup.uuid only. Broader group methods, installation formats
and remaining included contracts still require their own acceptance.

Commits 41d038a and 13bfeba reached origin/main after DNS recovered. Continue
with the remaining ActionGroup contracts and the engine/native acceptance
items. The complete Mac roadmap remains open.


### ActionGroup query contracts — 21 October 2026

Read the frozen ActionGroup reference. Added three member-specific tests,
each on legacy and worker runners. find uses an exact Unicode name and
returns undefined for missing, case, prefix and whitespace variants. getAll
covers an empty catalog, empty and implicit groups, typed results, unique IDs
and local array mutation. actions covers empty groups, stored order, hidden
entries, separators, disabled steps, foreign-group exclusion and readonly
collection replacement. All three methods passed with six runner cases.

Earlier native catalog fixtures asserted installed and missing lookup,
getAll identity and separate membership. The specific new automatic cases
complete actions, find and getAll. This does not accept installation formats.

Found a concrete installation gap: groupInstallURL serializes only member
actions. Empty groups lose their name and group record in the link. The
installURL member stays partial. Next: add a group installation envelope,
preserve its record and options, keep older action links readable, and test
empty groups, populated groups and atomic import. Continue other engine and
Mac roadmap requirements after that work.


### Group installation envelope — 21 October 2026

The new contract test failed on both runners because the old link contained
only an action array. groupInstallURL now uses the existing backup envelope
with only its group record and ordered actions. This preserves empty groups,
name, ID, symbol and order. Sorted JSON keys keep repeated links stable.

installationData reads new envelopes and old JSON/base64 action links. It
limits an installation envelope to actions and groups; unrelated notes and
workspaces are not installed. The legacy installationActions adapter remains.
The URL router imports the data atomically. The review dialog shows group
names, permits an empty group, and saves through atomic library operations.
It no longer saves downloaded actions one at a time.

The full regression passed 455 app methods and 502 core methods. Unsigned
Xcode compilation passed. Specific tests cover both runners, empty/populated
Unicode group links, record and action preservation, stable readonly links,
rollback, base64 URL routing, repeated installation, unrelated-data exclusion
and legacy action decoding. No automatic test opens a window.

Native URL installation and the empty-group review dialog remain pending.
ActionGroup.installURL stays partial until those checks pass with the new
binary. Visual QA still uses the earlier collision-verification build. Next:
update that isolated bundle, import a neutral empty group, obtain its link,
and verify URL installation and the review dialog. The complete Mac roadmap
remains active.


### Native empty-group installation — 21 October 2026

Updated the isolated Visual QA bundle from the successful build. Executable
SHA256: 421225aab7bac23d331dada17f03f26047ec1cf8b1b46253f04105d7ef7c0c15.
The QA helper targeted the exact Visual QA bundle. Opened a neutral action URL
with the tracked action-group-installation-envelope.json payload. This created
QA Empty café 🐼 with ID BBBF0003-0000-4000-8000-000000000011, symbol
folder.fill and order 7. No actions were included in that group.

Imported action-group-installation-actions.json through File > Import. Ran
QA Empty group link against the existing neutral note. It checked the installed
group, empty membership, exported record, exact fields and stable link. The
editor displayed Empty group link passed café 🐼 and the generated URL.

Loaded that observed URL through Actions > Import from Directory. The review
displayed Group: QA Empty café 🐼 with an empty list and an enabled save
button. Saved it, ran the checker again, and verified two Success records in
History. Closed History. No permission changed. QA retains one neutral note,
its update-qa tag and flag. No screenshot or raw log is tracked.

This completes ActionGroup.installURL with the existing automatic populated
group, rollback and legacy-link cases. The fixture envelope is neutral input,
not a user backup. Replay it as URL data, import the checker, and run the action.
All ActionGroup members now have recorded acceptance; this does not close
Actions, the engine, other APIs, inspector, sync or the Mac roadmap. Next:
review Action.installURL and find with specific boundary cases, then resume
the remaining configuredValues/recent and engine acceptance work.


### Refactoring baseline and pure catalog — 21 October 2026

Stable tag pre-refactor-2026-10-21 points to a415883. Functional duplicate-name
lookup work is saved separately at `35a790c` on agent/wip-action-lookup-2026-10-21.
Cloning is paused. The stable base passed 455 app and 502 core methods. The
system Python lacked Pillow; the bundled Python passed all 38 script tests.
Matrix structure passed; strict engine acceptance had 18 existing diagnostics.

The pure ActionCatalog extraction passed 455 app and 504 core methods and the
unsigned Xcode build. The two new characterization methods run without I/O.
The API matrix is unchanged and strict engine output matches the baseline.
No test was removed. No native UI session was needed for this extraction.
See refactoring-2026-10-21.md for the diagnosis and next stage.


### Refactoring bookmark preference boundary — 21 October 2026

NativeActionHost now forwards one file-preference dependency to all native
file adapter paths. Production still uses standard preferences. The existing
bookmark test uses an isolated suite and temporary files, with sync and async
host variants. It retains bookmark resolution, read/write, forget and retained
file coverage, and checks export and unrelated preferences.

All 455 app and 504 core methods passed. The unsigned Xcode build and matrix
structure passed. No public API, stored format or classification changed.
No visible UI, permission or sound check ran. See the refactoring record.


### Refactoring test execution support — 21 October 2026

A success-only test helper replaced 17 repeated legacy/worker dispatch sites.
All 25 named tests in the four changed suites remain, with 79 expectations
and 19 requirements. All 455 app and 504 core methods passed. Matrix structure
passed; the 18 strict engine diagnostics match the baseline exactly. Original
action fixtures and production code are unchanged in this stage.


### Refactoring Workspace sort writers — 21 October 2026

Four characterization methods with 15 cases passed on the original writers
(19 methods across four workspace suites). After extracting the common
dictionary mutation, all 459 app and 504 core methods passed. Unsigned Xcode
compilation and all 38 bundled-Python script tests passed. Matrix structure
passed and strict engine output matched the same 18 baseline diagnostics.

Window invalid-data no-op behavior, editor recovery, unknown fields, flagged
values, other views, encoding policies and observer order remain unchanged.
No public API, Note, record schema, bridge, original fixture or matrix changed.
No test was removed and no visible UI, permission or sound check ran. Signed
installation and client sync were not repeated. The cloning plan stays paused.


### Refactoring configuration defaults — 21 October 2026

Four new methods characterize default precedence at import, runtime and prompt
boundaries. All 19 focused methods passed before extraction. The shared field
descriptor retains caller-specific coercion, validation and confirmation.
All 459 app and 508 core methods passed after extraction. Unsigned Xcode build
and matrix structure passed. Strict engine output matches the 18 baseline
diagnostics. No test or original fixture was removed. No native UI check ran.


### Refactoring auditor reference index — 21 October 2026

The source-reference index is separate from evidence policy and CLI handling.
All 41 bundled-Python tests passed. Three new cases cover per-validation reuse,
changed source between validations and isolated roots. The repeated-reference
fixture reads one source once, compared with 154 reads before extraction.
Direct CLI and importlib loading work from another directory. Matrix structure
passed. Strict engine and global output and exit codes match the baselines
byte for byte: exit 1, 18 engine and 4,841 global diagnostics. No reference,
classification or policy changed. No existing test was removed. Swift production
is unchanged from the stage 5 build: 459 app and 508 core methods passed.
No UI or permission check ran. Cloning remains paused.


### Refactoring editing-bar calculations — 21 October 2026

Four methods with 40 cases passed before and after extraction. They retain
Unicode selection, line boundaries, marker wrapping, focus and save effects.
The line-up text no-op remains a separately recorded functional defect.
All 466 app and 508 core methods passed, including three native-routing
characterizations against the original host. Unsigned Xcode compilation and
matrix structure passed. No visible UI, permission or sound check ran.


### Refactoring native asynchronous routing — 21 October 2026

The shared classifier retains the original 28 operation names and handler
families. Three characterization methods passed before extraction. Afterward,
the focused routing/bookmark/prompt run passed 10 methods. All 467 app and
508 core methods passed, including original-code window-submission cases.
Unsigned Xcode compilation and matrix structure passed. Payload rejection
occurs before native effects; fallback, model envelope and prompt inventory
remain unchanged. No capability, permission or visible-window check ran.


### Refactoring window submission — 21 October 2026

Three methods with eight cases passed before extraction, covering mixed single
and batch launches, prestart cancellation, weak-owner release and task cleanup.
The focused after-run passed eight methods, including editor-interruption
coverage. All 467 app and 508 core methods passed. Unsigned Xcode compilation
and all 41 bundled-Python tests passed. Matrix structure passed. Strict engine
and global output and exit codes match the original 18/4,841 diagnostics byte
for byte. Independent review found no concrete regression in stages 7–9.
No visible window, permission, sound or native acceptance check ran.


### Isolated line-up regression — 21 October 2026

Local branch agent/wip-editor-line-up-2026-10-21 at 3af40f2 contains only
EditorActionBarEditingTests.lineUpMovesTheSelectedUnicodeBlock. Its build
passed and its text expectation failed once, as expected. No functional fix
was added. The red reproducer is not in main and was not pushed. After return
to main, all four editing-bar methods/40 cases passed. Main retains the full
467 app/508 core pass, 41 Python tests and unsigned build from stage 9.
No production source, fixture, format or matrix changed during branch
preservation. The final checkout audit confirmed that main has no red reproducer
and both WIP branches remain local. Main and the reference tag match origin.


### Native deterministic Action.find — 21 October 2026

Resumed the cloning roadmap after the nine refactoring stages. Selected only
the lookup code, specific test and neutral fixture from local WIP 35a790c.
Reload now breaks equal-name ties by UUID. No saved note or record format changed.
The lookup test uses shared execution support instead of restoring its old helper.

Automatic checks passed: 11 focused methods across four suites; the full run
passed 467 app and 509 core methods. Unsigned Xcode compilation passed. Drafts
installed reference remains 54.1.1 (943). No archived reference was refreshed.

Refreshed the existing signed Engine QA bundle with refresh-engine-qa.py.
Its identity and isolated library ID remained unchanged. Signed executable
SHA256: 4664fdb9d438b13acb7b2f70256c19ff74e66e7f276be5608319f62d7a0d3188.
Imported scripts/fixtures/action-lookup-installation-actions.json through File
Import. Created one neutral draft. Ran QA Action lookup link from its group.
The editor showed Action lookup link passed café 🐼 and History showed Success.

Quit through the native app menu. The process was absent before relaunch.
Reopened the same QA bundle, selected the persisted draft and ran the checker
again. History displayed two Success rows (01:47 and 01:48 local). The fixture
checks the first duplicate UUID, exact missing names and stable action identity.
It also checks generated link structure and readonly behavior; it does not
install that URL, so Action.installURL remains separately pending.

This accepts Action.find only. The six partial engine contracts and other API
members remain open. No screenshot is tracked. AX state supplied functional
observations; screenshot capture was unavailable and no visual parity is claimed.
No permission changed, message was sent or personal note was edited.


### Native duplicate-window App Intent owner selection — 21 October 2026

Used the signed Engine QA executable from the preceding lookup check:
4664fdb9d438b13acb7b2f70256c19ff74e66e7f276be5608319f62d7a0d3188.
Imported engine-window-owner-actions.json. Created a neutral draft with text
Alpha 🐼 Beta Gamma café and opened it in a second window. Both windows used
UUID 79798870-16AE-49B0-A039-7FB0BDAE89D4. AX identifiers confirmed
library-AppWindow-1 and library-AppWindow-2.

Configured the existing Draftly QA Engine — disposable Shortcut to run
QA Same draft window selection on that UUID. Selected Gamma in window 2,
then ran the actual Run Draft Action Intent in Shortcuts. The result was
Alpha 🐼 Beta Owner:Gamma café. Activated confirmed window 1, selected Alpha,
and ran the Intent again. The result was Owner:Alpha 🐼 Beta Owner:Gamma café.
Shortcuts changed from Stop to Run after each invocation. History displayed
two Success rows at 01:52 local time.

Restored the Shortcut to QA Caught rejection and its original draft UUID
A386D93F-D3D8-49EB-8F7F-205612F74D93. Confirmed both fields and closed History.
No action remains pending. No permission changed or personal note was edited.
This accepts same-draft native App Intent owner selection in both activation
orders. It does not close the remaining capability-specific entry variants.
Production code did not change. The preceding full tests and build still apply.


### Native Action.installURL roundtrip — 21 October 2026

Reviewed the archived readonly installURL getter. It has no arguments, defaults
or documented getter-specific errors. The implementation resolves the stored
action by UUID and encodes its current fields. Draftly retains its own URL scheme.
Recovered only the specific installation test from WIP 35a790c. It now uses the
shared ActionTestExecution helper. No production behavior changed in this step.

Automatic checks passed: five atomic URL installation methods, five catalog
methods and the new getter method with both runner cases. The getter test checks
Unicode and reserved characters, stable readonly values, no source mutation,
complete action fields, disabled unknown steps, raw payload and unknown fields.
Installation into another library and backup recovery retain the complete value.
The preceding full suite and unsigned build apply to unchanged production code.

Used the existing Engine QA executable with SHA256
4664fdb9d438b13acb7b2f70256c19ff74e66e7f276be5608319f62d7a0d3188.
Read the generated URL from the neutral lookup-result note. Pasted that exact
observed URL into Actions > Import from Directory. Load showed QA Action lookup
link with one script step. Save returned to the action list with one entry.

Changed only that QA action's name to QA Temporary reinstall café 🐼 and its
description to Neutral temporary replacement. Saved the changes. Loaded and
saved the original generated URL again. The list showed one QA Action lookup
link and no temporary entry. Its inspector showed the original name, empty
description, Native installation QA group, bolt symbol and original options.
Cancelled the inspector without further edits.

Quit through the native app menu and confirmed that the QA process was absent.
Relaunched the same bundle, selected the saved neutral note and ran the installed
action. Its checker asserted UUID BBBF0003-0000-4000-8000-000000000015 and wrote
Action lookup link passed café 🐼. History showed Success at 01:58 local time.
Closed History. QA retains two neutral notes and no pending execution or dialog.
No permissions changed. No personal data or screenshot is part of this check.

This accepts Action.installURL only. It does not accept every imported option,
external directory format, engine capability or full Mac delivery.


### Current Apple model readiness and unavailable responses — 21 October 2026

The host runs macOS 27.0.1, build 26A434, arm64. Imported the neutral fixture
engine-apple-model-availability-actions.json into the same signed Engine QA
image 4664fdb9d438b13acb7b2f70256c19ff74e66e7f276be5608319f62d7a0d3188.
The action compared availableModes with static and instance availability for
onDevice and pcc. The reported list was empty. Each unavailable respond call
returned undefined and lastError contained the explicit unavailable message.
The neutral editor showed both results. History showed Success at 02:01 local.
Closed History. No action or dialog remains pending.

A separate read-only FoundationModels probe reported:
onDevice unavailable(modelNotReady); pcc unavailable(systemNotReady).
System Settings > Siri also reported that Apple Intelligence requires the same
Mac and Siri language. The Mac used Spanish (Argentina); Siri used Spanish
(Mexico). No language, permission or system setting changed. Returned Settings
to its original page. Do not infer that this notice is the only readiness cause.

Expanded NativeModelAsyncTests.unavailableModesReturnNoFabricatedSuccess to
cover both included modes. All seven methods passed, including cancellation,
timeout, session cleanup and tool lifetime with the injected backend. Automatic
checks did not request real models or open a window. No production code changed.

This records current system readiness and both actual unavailable responses.
It does not accept generation, generation cancellation, or the full task
cancellation contract. Those native checks stay blocked until the system makes
the relevant model available. Existing positive and other cancellation evidence
remains separate. No screenshot or raw probe output is tracked.


### Action.recent saved-history boundaries — 21 October 2026

Reviewed the frozen reference. recent() returns recently used actions in reverse
chronological order. It has no arguments and defines no error or count limit.
Added a specific both-runner case with six fixed-date records inserted out of
order. It checks an empty list, order, unique identities, current renamed names,
deleted actions, unknown UUIDs without name fallback, legacy name-only records,
repeat reads and unchanged backup data. Observer actions disable logging so the
query does not add its own records. Eight focused methods in four suites passed.
The existing broad catalog cases remain because they cover other contracts.
No automatic test opens a window or uses a real library.

Action.recent remains partial. ActionRunner.logExecution omits every run at
logLevel 0 and non-error runs at level 1. recentActions reads only saved runs.
That coupling means an unlogged use cannot enter the current recent list.
The saved-history test does not approve this limitation. Compare actual Drafts
behavior with omitted logs before deciding the separate persistence change.
No production or public API change was made for this test.


### Typed configuration of another action — 21 October 2026

A specific test failed on both legacy and worker runners: Action.find returned
a string for a stored field declared as Boolean. The same action's execution
configuration already converted that field to a Boolean. Catalog snapshots used
raw persisted strings instead of the shared execution conversion.

ActionRunner.actionValue now calls the existing configurationValues function
with only that action's enabled steps. No inclusion expansion, prompt or write
occurs during lookup. Bootstrap still replaces its snapshot field with the
shared context.configuredValues object. The persisted string format is unchanged.
This is a functional correction. Scripts that relied on strings for declared
Boolean or number fields will now receive their declared types.

The test checks Action.find, ActionGroup.actions and Action.recent in both
runners. Stored false, 3.5 and Unicode text override different defaults. Disabled
fields do not alter conversion. Unknown stored keys remain strings. Readonly
replacement is rejected. An empty configuration returns an empty object. The
observer keeps its own typed shared context. Stored actions, groups and history
remain unchanged. The test does not require all execution metadata to stay fixed.

All 24 focused methods passed after the correction. The full run passed
467 app methods and 512 core methods. No automatic test opens a window.
Unsigned Xcode compilation passed. All 41 Python tooling tests passed. Matrix
structure has zero errors; strict engine/global gates still report 18/4,823
diagnostics. These gates remain open and do not imply compatibility percentages.
The Mac locked before QA could be refreshed. The native check remains pending;
the earlier binary cannot accept this correction. Included-action collision
precedence is a separate engine contract and remains pending.


### Native callback adapter absolute deadline — 21 October 2026

ActionCallbackRouter.openAsync previously started its timeout after openURL
returned. Pending tokens did not carry an absolute deadline. A callback could
be accepted after the requested deadline if opening consumed that time or if
delivery ran before the timeout task resumed. The worker already enforced its
own reply deadline; this test does not claim that an expired result could bypass
that separate worker guard.

Added an injected per-request clock. The test failed with success instead of
timeout in both controlled cases: delivery during opening and delivery before
the timer task resumed. No URL or app was opened. No real sleep or system clock
change creates the boundary. The default production clock remains Date.

Pending callbacks now retain the deadline before opening. Delivery at or after
that deadline finishes with timeout and reports the token as rejected. The timer
waits only for the remaining budget. Completion also checks the deadline.
A duplicate expired response is rejected, and a new independent request succeeds.
Cancellation retains its existing error path. The legacy synchronous adapter and
public scripting contract are unchanged.

The focused app suite passed seven methods, including both new cases. Three core
callback response methods also passed. Full regression passed 468 app and512
core methods, including the independent Context test extension. Unsigned Xcode
compilation passed. Matrix structure has zero errors.
Native OS delivery for this new boundary is pending while the Mac is locked.
Previously recorded native callbacks remain evidence only for their exact cases.
The host request lifetime contract remains partial for its other native checks.


### Context success parameter member acceptance — 21 October 2026

Expanded the existing contextSuccessParametersAreExportedOnlyForSuccessfulRuns
method rather than adding a duplicate suite. Both legacy and worker routes now
check undefined return, raw Unicode and reserved characters, empty names and
values, repeated-key replacement and names __proto__, constructor and toString
in the final report. A new execution starts empty. Cancel, fail and a thrown
error export no success parameters. Numeric names and numeric values each fail
with the explicit strings-required error. No production code changed for this
member. The focused run passed and the full468app/512core regression includes
both cases. Unsigned Xcode compilation passed after the callback adapter change.

The existing Native final callback merge and late response record supplies
actual external URL delivery: one matching success callback, parameter replacement
and Unicode, with separate non-success and late-response checks. Return and
argument boundaries are automatic evidence; they do not claim another native
run while the Mac is locked. The archived method signature has required string
name and value and no optional defaults. Context.addSuccessParameter is complete
for that contract. Context.fail notification behavior and other Context members
remain separate and partial.


### HTTP query value preservation — 21 October 2026

A real loopback server decoded an added literal plus as a space on both transport
routes. Request construction also changed an existing encoded plus in the source
URL into a raw plus. The specific builder test failed before the correction.

ScriptHTTP.makeRequest now appends separately encoded new parameters to the
existing encoded query. New literal plus signs use %2B. The original query is not
decoded and rebuilt. Existing raw plus and %2B therefore retain distinct server
meanings. The correction does not change body encoding, authentication or the
stored action format. The focused builder and loopback checks passed. Full
regression passed 468 app and522 core methods. The server uses only a temporary
loopback port and neutral values; no app window or permission prompt opens.
The broader HTTP contract tests and their remaining limits are recorded below.


### HTTP timeout range correction — 21 October 2026

The archived HTTP.timeout contract defines seconds and a 60-second default.
It defines no 600-second maximum. The previous builder silently clamped valid
values to 0.01...600. Changed the existing 900-second assertion to retain900 and
added cases for 0.001, 2.5 and 3600 seconds. The regression failed before the fix.

The builder now preserves positive finite durations. Zero, negative, NaN and
infinite values fail explicitly instead of being silently replaced. The default
remains 60 seconds. This removes only the HTTP-specific clamp; action execution
and host request deadlines remain unchanged. The new unit case and the focused
17-method HTTP run passed. The real loopback timeout test also confirms that an
expired request closes its connection. No 900-second wait is needed to verify
that a 900-second request setting is preserved. Full regression follows below.


### HTTP loopback and worker contracts — 21 October 2026

Read the frozen HTTP reference, including the nested request-setting descriptions.
Added a neutral Python standard-library server fixture on an ephemeral 127.0.0.1
port. It is a real HTTP server, not URLProtocol. Each test stops its child process
and closes its pipe. No personal data, remote endpoint, permission or visible
window is used. The server source is retained; raw traffic and logs are not.

The loopback cases check both legacy and async transports. Actual 301 and 302
redirects are followed or stopped according to the option; server events prove
the destination. JSON/form POST bodies preserve Unicode, quotes, newlines and
reserved characters. Query checks distinguish an original raw plus, an original
encoded plus and an added literal plus. Empty values, custom headers and neutral
Basic Authentication survive. A 503 response, invalid JSON and abrupt disconnect have their
correct response/error shape. Cancellation and timeout close the actual waiting
connection. The server observes that disconnect.

A separate scripting case runs both engines against that server. It checks HTTP
constructor/factory types and defaults, mutable redirect and timeout options,
HTTPResponse type, status, Unicode JSON/text, returned headers and undefined
optional fields when absent. A positive 900-second setting is used for an immediate
response; zero produces an explicit HTTP failure. This is not a 900-second wait.

Four injected worker cases isolate factory/default/option forwarding, a network
failure that the script can handle, an infrastructure error that stops execution,
and cancellation after a transport returns a failure value. Cancellation retains
its typed report; subsequent script and steps, Archive and success parameters
are suppressed. The library is released after transport cleanup. No timer sleep
coordinates that cancellation case.

These cases accept the five HTTP object members for the frozen signatures.
The API needs no platform dialog, so manual Computer Use is not required for
these network and object contracts. This is automatic integration evidence,
not a new manual UI check. HTTPResponse still needs its own complete per-member
review. In particular, the reference does not explain when otherData is filled;
the tests do not invent such a condition. The raw body encoding option remains
a Draftly extension; the included reference options are JSON and form.

The focused HTTP run passed 17 methods. The final full regression passed
468 app and 523 core methods. All 41 Python tooling tests passed. The final
unsigned Xcode build passed. Matrix structure has zero errors. The strict
engine gate still reports 18 diagnostics; the full gate reports 4,757. No HTTP
member has a strict diagnostic. These counts do not measure compatibility.
The Mac remains locked; configuredValues and callback-boundary native checks
remain separately pending. No full engine or Mac delivery is closed here.


### Native typed other-action configuration — 21 October 2026

The user unlocked the Mac. Quit Engine QA through its native menu and confirmed
the process was absent. Refreshed every runtime image and resource from the
validated unsigned build with refresh-engine-qa.py, then development-signed it.
The QA bundle and isolated library identities stayed unchanged. Signed hashes:
launcher 1119f1dab32b157510b34f67380f61c175889fdbcab72478358aa57933c1e00e;
Debug image 1b2c4be2bfdc696e100349a4dc21ae022c0ec040459eb71605758f6bdf8655d4.
This image includes the configuredValues, callback-deadline and HTTP fixes.
It predates the new HTTP response charset correction.

Confirmed that the neutral configuration fixture uses an actual LF in its text
value and the matching JavaScript string escape. Imported it through File > Import.
Selected an existing neutral QA draft. Ran QA Typed configuration source and
then QA Typed configuration lookup. The lookup checked the same source through
Action.find, ActionGroup.actions and Action.recent. Each returned Boolean false,
number 3.5 and café 🐼 followed by LF and Text. Readonly replacement was rejected.
The running action retained its own typed shared context and no source count key.

The editor displayed Typed other-action configuration passed café 🐼. History
showed source Success at 02:29 and lookup Success at 02:30 local. Closed History.
QA retains two neutral notes and no pending action or dialog. No permission,
personal note or system setting changed. No screenshot or raw log is tracked.

Together with the specific both-runner stored-override, disabled-field and
nonmutation tests, this accepts Action.configuredValues. Shared included-action
collision precedence remains a separate pending engine contract. No full engine
or Mac delivery is closed by this member acceptance.


### Native callback regression after deadline correction — 21 October 2026

Used the refreshed Engine QA image from the typed configuration check above.
Its launcher and Debug hashes are recorded there. Imported the unchanged
engine-native-actions.json fixture. The local callback helper targeted only
that isolated QA bundle. No permission or system setting changed.

QA Native success wrote Callback: Native café 🐼. QA Native cancelled preserved
that text. QA Native error returned the expected callback error and preserved
that text. Started QA Native late, then used Actions > Cancel Running Action
while it waited. Ran QA Typed configuration lookup afterwards. The editor
showed Typed other-action configuration passed café 🐼.

The helper reported four replies opened, a successful last open, an eight-second
delay and the neutral callback value. After that actual delayed URL open, the
editor retained the typed marker. History showed Success, Cancelled, Error and
Cancelled for the four callback cases, then Success for the typed lookup, all
at 02:34 local. Closed History and quit the helper. Its process was absent.
QA retains one window, two neutral notes and no pending action or dialog.

This checks ordinary native delivery and cancellation with the corrected image.
It does not establish that the next action completed before the delayed reply.
It does not reproduce an OS delivery at the exact deadline before the timeout
task runs. The controlled-clock tests retain that boundary evidence. Permission
and capability lifetime variants remain pending. No screenshot or raw log is
tracked, and no complete engine or Mac acceptance is claimed.


### Bounded loopback server cleanup — 21 October 2026

The first full run after the response tests did not finish. A process sample
showed one test in LoopbackHTTPServer.stop at Process.waitUntilExit. The server
child was already absent. The app tests had passed; the unfinished core run
is not accepted as a full pass. Terminated only that owned test helper.

The fixture now installs its termination handler before launch. The handler
signals a semaphore. Cleanup waits at most two seconds and records a test issue
if the signal does not arrive. It no longer waits indefinitely for Foundation
process bookkeeping. Requests still run on their existing executors. No window,
permission or personal data is used. No production code changed in this fix.

The focused response and loopback run passed 12 methods. A fresh full run
passed 468 app and 530 core methods, including the response work recorded
separately. The counts describe executed tests, not API parity.


### HTTP response charset and member review — 21 October 2026

Reviewed all eight HTTPResponse members against the archived 19 October
reference. Kept its hash and signatures. The responseText regression first
failed for ISO-8859-1, UTF-16LE and UTF-16BE: the old UTF-8-only decoder returned
empty text. ScriptHTTP now converts the declared IANA charset with CoreFoundation.
A missing, unknown or undecodable charset retains the prior UTF-8-or-empty
fallback. It does not invent a binary or otherData representation.

Specific automatic cases cover those three charsets, fallback behavior,
explicit JSON array and scalar types, absent bodies and initial constructor
fields on both scripting runners. The frozen constructor does not document
those initial values; the test records Draftly behavior without inventing a
reference default. The real loopback fixture also returns Latin-1 text,
UTF-16 JSON, GET 204 and HEAD 200. Both transports preserve text, parsed Unicode,
status, custom headers and Set-Cookie values. No remote endpoint, permission,
visible window or personal data is used.

The member review accepts constructor, headers, statusCode and responseText
for their frozen contracts. Network and object checks require no native dialog;
actual URLSession and JavaScriptCore run in automatic integration tests.
This is not a new Computer Use or updated QA image claim.

Four members remain partial. responseData needs the non-JSON representation
checked in Drafts. error needs the HTTP-status failure policy compared; Draftly
currently leaves error absent for 503. success needs unfollowed 3xx behavior
compared; Draftly currently returns false. otherData has no documented trigger
and is not populated by this transport. No guessed behavior or broad test count
accepts those boundaries. Each member has its own matrix record.

The focused response and loopback run passed 12 methods. After the separate
fixture cleanup correction, the full regression passed 468 app and 530 core
methods. Unsigned Xcode compilation passed. The previous unfinished full run
remains recorded as unfinished. The QA image used above predates this charset
change. No complete integration, engine or Mac acceptance is claimed.

The final tooling run passed all 41 Python tests. Matrix structure has zero
errors. The strict engine gate still reports 18 diagnostics. The global gate
reports 4,670. Its HTTPResponse diagnostics refer only to the four explicitly
partial members. These diagnostic totals do not measure compatibility.


### XML-RPC decoded HTTP charset boundary — 21 October 2026

The new serialized-transport regression failed before the fix. Latin-1 text
café became cafÃ©. A UTF-16 declaration caused a parse failure. HTTP had already
decoded the response, but XMLRPC re-encoded that text as UTF-8 and retained the
old XML byte-encoding declaration. XMLParser then interpreted the new bytes
using the old encoding.

XMLRPC now changes only the leading XML declaration encoding to UTF-8 when
it converts decoded HTTP text to UTF-8 data. The public raw-byte parser keeps
its existing encoding behavior. The malformed closing-tag controls still fail
explicitly. No public API, library format or action script changed.

Both scripting runners also passed actual loopback requests for Latin-1 and
UTF-16 XML with matching HTTP charsets. The responses retain typed status,
exact café & mañana text and no parse error. The server and data are neutral.
No app window, permission, external service or personal data is used.

The focused XML-RPC, loopback and Context run passed 23 methods. The full run
passed 468 app and 535 core methods. Unsigned Xcode compilation passed. Context
acceptance is recorded separately. This fixes the decoded-text boundary; it
does not close date/binary mapping, complete grammar, XML encoding detection
without an HTTP charset, invalid inputs or the full XML-RPC contract.


### Context response contracts and native acceptance — 21 October 2026

Read the frozen Context reference. Added three specific methods on both engines.
previewValues starts empty, preserves three keys and nested typed fields through
script and step paths, and resets in a later execution. appleScriptResponses
starts empty, preserves mixed step/script order and record/list/null types, and
resets later. The failure case checks that a failed host call publishes no
invented values. A failed AppleScript.execute returns false and retains lastError.
The tests use a narrow fake host; no real native capability or window opens.

Manual verification used the existing Engine QA image. Its launcher hash is
1119f1dab32b157510b34f67380f61c175889fdbcab72478358aa57933c1e00e and Debug hash is
1b2c4be2bfdc696e100349a4dc21ae022c0ec040459eb71605758f6bdf8655d4. This image
predates the HTTP charset changes. Context production code did not change.
Imported context-response-actions.json through File > Import into the isolated
library. Kept the existing neutral note selected.

QA Context preview script and QA Context preview step each opened actual HTML.
Clicked Send typed context values. Drafts.send replaced one key and returned
Unicode text, null and a nested list containing Boolean false and number 3.5.
Each checker wrote its expected editor marker. History showed Success at 02:47.
The first AppleScript fixture failed to compile because a record key used a
reserved identifier. Quoted the fixture keys, reimported the same identities,
and repeated it. That fixture error remains in History; it is not a product fix.

QA Context AppleScript values then ran actual neutral AppleScript handlers.
The step record, script list and step missing value reached context in order.
The checker also caught an intentional AppleScript error and verified that it
added no response. The editor showed Context AppleScript values passed café 🐼.
QA Context fresh execution then checked empty preview and AppleScript collections
and wrote its fresh marker. Both History rows showed Success at 02:49. Closed
History. QA retains one window, two neutral notes and no pending action or dialog.
No Automation permission, third-party app, message, private data or system setting
was used. No screenshot or raw log is tracked.

This accepts Context.previewValues and Context.appleScriptResponses with their
specific automatic and native checks. Context.configuredValues also receives
its own record: the existing runtime default assertions read that exact accessor
on both engines, and the earlier typed native fixture checked the running
context and action object identity. Included-action key collision precedence
remains a separate partial engine contract. Context.callbackResponses and fail
still need their remaining specific acceptance. No whole Context, engine or Mac
closure is claimed.

The focused run passed 23 methods across five suites. The full run passed
468 app and 535 core methods. Unsigned Xcode compilation passed. The tests and
manual results have different scopes; the totals do not establish parity.

The final full rerun, including the explicit empty configuredValues assertion,
passed 468 app and 535 core methods. All 41 Python tooling tests passed.
Matrix structure has zero errors. The strict engine gate retains 18 diagnostics;
the global gate retains 4,652. None refers to the three Context members accepted
above. The remaining diagnostics retain their original contract scope.


### XML-RPC original response bytes — 21 October 2026

Extended the actual loopback regression before changing production. Latin-1,
UTF-16 with BOM, UTF-16LE without BOM and UTF-16BE without BOM all failed when
HTTP omitted charset. The eight failures covered both engines. The HTTP text
fallback could not preserve the original XML bytes. Separate envelope tests
also failed on Latin-1/UTF-16 bytes and malformed base64.

XML-RPC now requests original bytes through its internal HTTP envelope. A
response without HTTP charset can carry responseBodyBase64 beside value. The
XML-RPC parser consumes those bytes directly. HTTPResponse and XMLRPCResponse
keep their existing public fields. Ordinary HTTP requests omit the byte payload.
The legacy XML-RPC adapter uses the same envelope rule. A declared HTTP charset
keeps the previously tested decoded-text path. Older injected text-only
transports still work.

Added guards for invalid base64, an empty body and a failed HTTP response whose
body contains otherwise valid XML. The first fails explicitly; an empty body
remains a parse failure; valid XML cannot erase an HTTP failure. Actual metadata
checks prove opt-in behavior and charset priority on both transports. A public
HTTP script cannot see the transport byte field even when the internal flag is
present in its settings. No additional data is stored in a library or backup.

The focused run passed 41 methods in seven suites. The full run passed 468 app
and 539 core methods. Tests use neutral data on ephemeral loopback ports and
injected envelopes. No app window, permission, personal data or external service
is used. No manual native check or refreshed QA image is claimed. XML-RPC stays
partial for JavaScript date/binary mapping, complete grammar, unknown HTTP
charsets, invalid inputs and native automation. This fixes the encoding boundary
without treating those separate contracts as accepted.

Unsigned Xcode compilation and all 41 Python tooling tests passed after the byte
preservation change. Matrix structure has zero errors. Strict engine and global
acceptance remain open; this change does not reclassify XMLRPC.request.


### Context.fail specific boundaries — 21 October 2026

Extended the existing current-script termination test instead of adding a
second suite. Both engines now check cancel as a control and fail with omitted,
empty and Unicode message values. A clipboard write after the call verifies
undefined and proves that the current script continues. The sentinel next step
never runs. The report retains error or cancellation, and one stored run has
the exact expected message and status.

Enabled notifyOnError for the fake host. Failure requests exactly one action
notification with the action name and message. Cancellation stays silent.
Existing notification-policy and log tests retain their broader responsibilities;
the new case does not repeat those combinations. No visible notification,
window, sound, permission or personal data is used.

The focused run passed 30 methods across three suites. Omitted and empty fail
text currently use Action failed. Those exact default words are not required
by the frozen reference. Context.fail remains partial until its native visible
notification and presentation-policy behavior are checked. A fake request is
not proof of OS delivery. No production behavior changed in this test update.

The final full rerun passed 468 app and 539 core methods. Production code was
unchanged after the successful unsigned build and 41-test tooling run above.
Matrix structure has zero errors. Strict engine/global gates retain 18/4,649
diagnostics. The remaining Context.fail diagnostics refer to incomplete native
acceptance and its recorded limit. These counts do not measure compatibility.


### XML-RPC value structure correction — 21 October 2026

Consulted the supplemental [XML-RPC protocol specification](https://xmlrpc.com/spec.md)
on 21 October. The archived Drafts reference and hashes stay unchanged. The
protocol requires one data element in an array, one name and one value in a
member, and scalar content without nested elements. Fault records have only
faultCode and faultString. These rules identify malformed data independently
of undocumented JavaScript date or binary mappings.

New tests failed before the correction. The parser had accepted malformed arrays
and records, nested scalar elements and extra text, then discarded part of the
response. It now validates those structures before returning values. Nonempty
nil text and extra fault fields also fail explicitly. Errors retain HTTP status
and empty success parameters. Untyped string whitespace, empty arrays with data,
empty records, Unicode, Boolean false and the existing nil extension remain valid.

Kept existing i8, nil and multiple-response-parameter support. Duplicate record
names retain their previous behavior; the reference does not settle that policy.
A candidate duplicate-name rejection was removed from the new tests before
implementation. No new Date, binary or duplicate-name representation is invented.
No public API, stored format, action script or backup changes.

The first focused grammar checks reproduced discarded content; the corrected
family then passed. The later focused XML-RPC and loopback run passed 28 methods,
including separately recorded metadata cases. The full regression and unsigned
build results follow with that acceptance record. Automatic tests use neutral
data and no app windows, permissions, sound or personal information.


### XML-RPC response member acceptance — 21 October 2026

Reviewed the frozen XMLRPC and XMLRPCResponse member signatures. Extended the
neutral loopback server and the existing actual JavaScript test on both engines.
The constructor checks create XMLRPC and XMLRPCResponse instances, inspect
initial fields and prove that separate response instances have separate params
arrays. Initial values are recorded as Draftly behavior; the archived
constructors do not define those defaults.

Actual success responses have status 200, true success, the exact Unicode
parameter and no error or faultCode. Actual XML faults preserve codes -42, 0
and 42 as numbers and the exact Denied café 🐼 text. Every fault has false
success, empty params and HTTP 200. Code zero is not mistaken for success.

Separate actual requests return malformed arrays, records and fault fields,
an HTTP 503 with a valid XML body, an empty HTTP 204 and an abrupt disconnect.
Both engines preserve their respective 200, 503, 204 and 0 status values.
All have false success, a nonempty error, no fabricated faultCode and empty
success params. This tests field conversion through real URLSession requests
and the public JavaScript objects, not only an injected Swift parser result.
No exact undocumented parser error wording is assigned to Drafts.

These specific cases accept XMLRPC.constructor and XMLRPCResponse.constructor,
error, faultCode, statusCode and success. They need no native dialog or hardware.
This is automatic integration evidence, not a new Computer Use check. It does
not accept date/binary mappings, full XML tolerance or native cancellation.
XMLRPCResponse.params and XMLRPC.request remain partial. The frozen descriptions
do not define JavaScript Date, typed-array, ArrayBuffer or binary-wrapper
conversions. The normal JSON bridge currently converts Date to a string and
typed arrays to objects; response date/base64 values remain strings. A complete
mapping requires comparison rather than a newly invented representation.

The focused family passed 28 methods. Full regression passed 468 app and
543 core methods. All 41 Python tooling tests and unsigned Xcode compilation
passed. No test opens a window, asks for permission, plays sound or reads
personal data. No raw log or screenshot is tracked. The source correction and
this wider member acceptance have separate commits.

Matrix structure has zero errors. Strict engine/global gates retain 18/4,595
diagnostics. XMLRPC.request and XMLRPCResponse.params retain incomplete status,
comparison and limitation diagnostics. Their known normal/default/error cases
are now recorded explicitly. No accepted metadata member has a strict diagnostic.
These counts are not a compatibility percentage.


### Context callback collection acceptance — 21 October 2026

Read the frozen Context.callbackResponses contract. Added two member-specific
methods to the existing suite. Both engines mix callback and Shortcut responses
through step and script paths, verify four distinct ordered entries, and verify
an empty collection in a second execution. Error and cancelled script replies
publish no success entry; the handling script continues. Existing no-wait and
prototype-key tests keep their separate assertions.

The first automatic fixture compared a full callback URL against a base without
its empty query suffix. It now identifies the source by URL host; URL formatting
was not the contract under test. No product code changed. The focused family
passed 29 methods. Full regression passed 468 app and 545 core methods.

For manual verification, quit Engine QA and confirmed its process was absent.
Refreshed the complete runtime from the validated build with the existing helper
script and development signature. Kept its bundle, library and signing identities.
Signed launcher SHA256:
34cc6a16a64ce79f408765abfcf4bea43375fa47cfaab80e6b50132907b07bed.
Signed Debug image SHA256:
47eb6869273c66efb69cc836e19de186aaa1c73ef98c19f04c44d2a52e4cae63.
This image includes the HTTP/XML-RPC corrections. This session checks callbacks.

Inspected the existing Draftly QA Output — disposable Shortcut. It still has
Wait 5 seconds, neutral Unicode Text and Stop and Output with no further action.
No Shortcut was edited, created or deleted. Imported context-callback-actions.json
through File > Import and selected the existing neutral QA draft. The local
callback helper targeted Engine QA with its inventory monitor off.

The first mixed run failed its fixture assertion at 03:13. The fixture encoded
spaces as plus signs; URLComponents preserved those literal plus signs. Changed
only those fixture URL values to percent-encoded spaces and reimported the same
identities. The corrected mixed run wrote Context mixed callbacks passed café 🐼
and History showed Success at 03:14. It verified callback step, Shortcut step,
script callback and script Shortcut values in that exact order.

QA Context unsuccessful callbacks then handled actual error and cancelled
responses, checked an empty success collection and wrote its marker. QA Context
callbacks fresh checked the empty collection in another execution. Both History
rows showed Success at 03:15. The helper reported six replies opened and a
successful last open. This includes the two replies from the initial fixture
run. The first Error row stays in History; it is not a production regression.

Closed History, quit the helper and confirmed its process was absent. Closed
only the neutral Shortcut editor opened for inspection. QA retains one window,
two neutral drafts and the final Context callbacks fresh passed café 🐼 marker.
No permission, system setting, personal data or remote message changed. No raw
log or screenshot is tracked. These native cases accept this collection member;
engine task cancellation and remaining capability variants retain their own
acceptance. Context.fail still needs its visible native notification check.

The unsigned Xcode build and all 41 Python tooling tests passed. The automatic
tests use fake hosts and stay headless. Real URLs and Shortcuts ran only in the
separate manual session. No whole engine or Mac closure is claimed.

Matrix structure has zero errors. Strict engine/global gates retain 18/4,589
diagnostics. Context.callbackResponses has no strict diagnostic. Its completion
does not accept other native capabilities or the remaining Mac deliveries.


### Context.fail native result checks — 21 October 2026

Imported context-fail-actions.json into isolated Engine QA. The two actions
use the same Unicode failure and a later insertion sentinel. Only the imported
notification policy differs: muted or errors enabled. History recorded Error
at 03:20 and 03:29 with Neutral context.fail café 🐼. The muted run showed the
in-app error. Both runs kept the existing source text and two-note library.
The later insertion did not run. Closed History after reading the records.

No permission or system setting changed. Visible OS notification delivery was
not established. Context.fail stays partial for that presentation acceptance.
A request sent by the host is not evidence of a visible system notification.
This record accepts native result and text preservation only.


### App message banners — 21 October 2026

The four App display methods returned true and only logged their message.
The new member-specific test first failed with 16 return-value issues across
both runners. Each method now returns undefined and routes its exact message
and severity to the owning window. A separate command preserves Context.cancel
logging. The native host uses the existing window; it does not open a new one.
A host without a presenter returns an explicit error.

The window shows an info, success, warning or error banner. New messages replace
the current banner. Close dismisses it. Expiry removes only the same banner
identity. History keeps the existing message. The first native check exposed
a duplicate bottom status notice. Successful matching status now stays empty.
Unrelated status and later errors remain visible. Headless tests cover these
boundaries without windows, permission requests, sound or personal data.

The final Swift run passed 472 app methods and 546 core methods. All five
original action scripts passed on both runners without changes. The unsigned
Xcode build passed. These totals do not prove unrelated API contracts.

Refreshed and development-signed Engine QA only after quit and process absence.
The bundle and library identities stayed unchanged. Imported the neutral
app-message-actions.json fixture. The final image showed all four messages
with the matching symbols. Info was blue, success green, warning orange and
error red. No duplicate bottom notice remained. History showed Success for
all four at 03:57/03:58. Error severity did not fail its action. Verified expiry
and manual close. Closed History. The two neutral notes and selected source
text stayed unchanged. No permission or system setting changed.

Final signed runtime hashes:

```text
Draftly: daf54d3f07079657d1d71039c1e7b8b48df0a21d31f4cdcc0d926176a07a985b
Draftly.debug.dylib: 303d2d93531f1714f5afdc3759e680c85459635a15052e4a6ccdde2feb48c575
```

This accepts the four message contracts. Exact banner geometry and styling
against Drafts remain part of the separate visual matrix. Context.fail OS
notification delivery remains pending. No raw log or screenshot is tracked.


### Native sharing file cancellation — 21 October 2026

Imported engine-sharing-actions.json into Engine QA. The openIn step prepared
Draftly-neutral-sharing.txt and opened the native sharing picker at 04:08.
The picker showed a 26-byte text document. A read-only check of the generated
temporary file found exactly Neutral sharing plus the neutral Unicode text
from the fixture. No Draftly-Share folder existed before the run.

Pressed Escape without choosing a service. The picker closed. History recorded
Cancelled. The source text stayed Context callbacks fresh passed followed by
its existing Unicode suffix. No tail sentinel appeared. No Draftly-Share folder
remained afterward. No content was sent and no permission changed.

This accepts native file preparation and cleanup before service handoff on
user cancellation. It does not accept service completion, transferred-file
cleanup, task cancellation, owner-window close or every automation entry.
The existing headless NativeSharingRequestTests cover controlled driver
completion, cancellation and late callbacks separately. No production code
changed for this check. The full 7047474 Swift run already passed those tests.


### Supplemental Share inventory — 21 October 2026

The approved utility scope includes Share, but the required object list and
frozen archive omitted it. The old global gate could not detect that omission.
Share is now required. Its public reference was captured as a dated supplement
with its URL and SHA256. The original 19 October baseline date, archived pages,
member evidence and Drafts version stay unchanged.

The new --supplement OBJECT path fetches only the selected object. It keeps
other objects, steps, engine records and unknown metadata. Changed reference
contracts retain their evidence but require review. Four auditor regression
cases cover required inventory, preservation, invalidation and invalid input.
The Share page adds a constructor and three static methods. They start without
compatibility acceptance. A larger inventory does not reduce the remaining
work. This supplement does not establish Theme or other omitted utility scope.


### Share argument and result contracts — 21 October 2026

The new official Share supplement exposed a reversed argument order.
shareAsFile now takes filename first and text second. The new tests first
failed with 12 filename/content issues on both engines. Text, LF, Unicode,
URLs and Boolean results now pass. Non-string arguments return false before
a host request. Ordinary host sharing failures return false; that policy is
an interpretation of the completion Boolean, not an explicit thrown-error
clause in the reference. Native cancellation and timeout stay latched.
The existing interruption test now covers all three Share routes in addition
to Bookmark. Later writes, steps and archive effects stay blocked.

The constructor has specific identity and no-host-effect checks on both
engines. Its contract is complete. All three sharing methods remain partial:
legacy native sharing returns immediately, and actual completed-service and
post-handoff file lifecycle acceptance remain open. Fake host success does
not close those native cases. No original action script changed.

Updated Engine QA and imported QA Share file API cancel. Its picker displayed
Draftly-neutral-api as a 39-byte text file. Read only the generated temporary
file: its name, neutral Unicode contents and line break matched the fixture.
Escape returned false to the script, which completed and reported Share API
cancellation passed. History recorded Success at04:22. The earlier openIn
step cancellation recorded Cancelled; these are different caller behaviors.
The source note stayed unchanged. No service was chosen or content sent.

The complete automatic run passed 476 app and 553 core methods, including
the five unchanged original actions. The unsigned Xcode build passed. These
results also include the independent draft-selector changes recorded below.


### Interrupted sharing success parameters — 21 October 2026

Strengthened the existing caught-host interruption test. After the native
interruption, the script now adds an explicit late success parameter. The
final timeout or cancellation report still publishes no success parameters.
The same test checks blocked editor/clipboard writes, later steps and archive
effects. All four routes pass with cancellation and timeout: Bookmark, text
sharing, file sharing and URL sharing. No duplicate test suite was added.
The complete run passed 477 app and 556 core methods. This is controlled host
evidence. It does not replace native service-completion acceptance.


### Workspace draft selection — 21 October 2026

app.selectDraft previously ignored its optional Workspace. It now uses a copy
for structural filters, dates, folder and sort. The initial query stays visible
and editable. Replacing it searches the same structural result set. The source
Workspace does not change. The selector shares DraftTableRow drawing and
DraftRowPresentation measurements with the real list. It carries preview, tags,
date, last-action and search options. Parsed row data is cached once.

Specific both-engine tests cover archive/date/tag exclusions, order, typed
result and cache identity, last-action metadata, optional defaults, Trash
exclusion, user cancellation, unmatched queries, invalid types and invalid
dates. They preserve source selection and decoded library collections. Native
headless cases cover shared dimensions, options, content search with previews
hidden, case/title settings, original row identity, selection emphasis, keyboard
bounds and query replacement. The ordinary SelectPrompt path stays unchanged.

The first native pass found two keyboard defects. Down from search did nothing.
Escape with a nonempty initial query hid the alert but left the action waiting.
That run ended with Error at04:32: the action operation timed out. It is not an
accepted cancellation. The native Cancel button control completed at04:33.
Draft-mode search now routes arrows to the table and Escape to the actual
Cancel button. The existing presenter owns finalization. A headless test
replaces the button target and proves Escape uses its current action.

Imported app-select-draft-notes.json and app-select-draft-actions.json into
isolated Engine QA. The library now has five neutral drafts. The picker shows
Alpha and Zulu in name order and excludes Excluded. Compact mode hides preview,
tags and dates. Full mode shows them with its normal-preview option. The
initial Picker QA: query is visible. Replaced it with Neutral body, which found
both rows with previews hidden; an absent term found none; Zulu found its
original row. Return yielded the typed Zulu result without loading it. Up/Down
changed selection from the search field. Main Inbox, filters and source text
stayed unchanged. History records the successful compact result at04:30.

After refreshing all QA runtime images, Escape from the full picker with its
nonempty initial query completed at04:36. The script reported Selection
cancelled. History recorded Success because the script handled undefined.
Cancel Running Action was disabled afterward. History is closed. No dialog or
action remains. No permission or system setting changed. The source remains
the prior Context callbacks fresh marker with its Unicode suffix.

The final full regression passed 477 app and 556 core methods, including the
five unchanged original scripts. Later focused runs passed all five selection
contract methods and all six presentation methods, including the added actual
Cancel-button target check and last-action assertions. All 45 Python tests and
the unsigned Xcode build passed. Automatic tests opened no visible windows.
This accepts the scripting contract; exact Drafts pixel parity remains separate.

Final signed QA runtime hashes:

```text
Draftly: cc128c3bb217ed1490c495317fcd25336d29999e7f1ca67a152f0b843d77a0bf
Draftly.debug.dylib: a444ecab3aa9532d60dc7bcada549f3233237a71a45ae6c341aba1f54451bc14
```

Matrix structure has zero errors after this update. Strict engine/global
controls still report 18/4538 diagnostics. The newly required Share inventory
adds real open contracts. These diagnostics are not a compatibility score.

### Configured App themes — 21 October 2026

Implemented: app.darkTheme and app.lightTheme no longer validate and discard
assignments. They return typed Theme values and save a device-local reference
for each appearance. Custom references resolve UUID before name. Renames follow
the saved identity. A missing custom definition falls back to its built-in
slot without erasing the reference. Reinstalling that identity restores it.
Workspace themes override the window presentation without changing this pair.
The shared resolver rejects missing identities before changing the window.

Settings now uses the same pair, with Light Theme and Dark Theme selectors.
The previous editor.theme choice remains readable. The first explicit pair
write keeps the matching legacy slot. Themes stay in the library; selections
stay local. Selecting a theme does not change app.themeMode. File themes are
not implemented and fail explicitly. Their absence is not an accepted macOS
platform exclusion.

The catalog now includes saved custom themes without requiring a UI host.
Built-in names have one source. The Theme reference was missing from the
required inventory. A dated 21 October supplement adds its six members and
archived URL/hash. It does not replace the frozen 19 October baseline.
Theme.installURL remains partial: its name-only URL cannot transfer a definition
and has no receiving route. File-theme discovery also remains open.

Automatically tested: both runners assign and read typed Themes through the
real WindowModel adapter. Tests preserve text, selection, persisted content,
and native Undo/Redo without opening windows. Separate models share the local
pair. Custom renames follow UUID. Workspace overrides do not change the pair;
a built-in reference with an unrelated UUID cannot select a custom theme.
Preference tests cover legacy slots, separate device domains, missing and
restored identities, unknown fields, and atomic rejection of invalid values.
Catalog tests cover exact Unicode/type lookup, detached writable values,
constructor identity, independent arrays and library isolation.

The first preference test exposed an Objective-C exception when serializing a
non-JSON field. Validation now rejects it before serialization or any write.
The first combined Undo test also counted a separate selection edit as a text
edit. The final test edits the selected text and records the selection before
the theme assignment. Existing editor Undo tests pass unchanged.

Final full regression: 484 app methods and 558 core methods passed, including
the five unchanged original action scripts. All 46 Python tests and the
unsigned Xcode build passed. Automatic tests presented no windows or prompts.

Verified in use: refreshed and signed isolated Engine QA. Imported the neutral
app-theme-backup.json definitions and app-theme-actions.json actions. The first
fixture used external action fields inside a native backup; import rejected
it with a missing-data error. The fixtures now keep those formats separate.
Both final imports completed. QA Configure theme pair returned typed configured
slots, preserved source text/selection and showed Configured theme pair passed.
The editor visibly changed to the custom dark blue background #162839.

Pending native acceptance: opening Settings with Command-comma caused Computer
Use to report a closed native pipe. QA remained running. Rebinding and resetting
the tool did not recover its AX state; Finder remained readable. Settings
selection, light rendering, restart and cross-window refresh are not accepted.
A user request to close the QA Settings window is pending. No system permission
or personal preference changed. QA still has five neutral drafts. No action
was waiting when Settings was opened.

Signed QA runtime hashes:

```text
Draftly: e5b0928db77cbfb34d5cff7a5bd160c77805386701db9f32586c818ff0705281
Draftly.debug.dylib: f20f029a8985540ecc453f07fb02189866290c45c2d7252c9ee5df52b3e8ea03
```

Matrix structure has zero errors. Strict engine/global acceptance retains
18/4534 diagnostics. These counts do not measure compatibility. Theme value
members have specific tests; catalog/install and App selection native gaps
remain classified as partial.

### Theme installation links — 21 October 2026

Implemented: Theme.installURL now calls a host operation. A custom link carries
the complete EditorThemeDefinition, including UUID, colors, unknown fields and
original Drafts source. UUID lookup takes precedence over a detached name.
Name-only custom references remain valid when no UUID is supplied. Built-in
links use the shared catalog and do not create a library definition. Legacy
built-in name-only links remain readable. File links fail explicitly.

A shared codec validates both sides. It rejects malformed identities, invalid
colors/names, unsupported addresses, duplicate parameters and conflicting
payloads. The application receiver uses this codec before storage. Identical
imports require no write. Replacing a name match requires confirmation and
keeps its destination UUID. An incoming UUID/name that identifies two distinct
destination themes fails before confirmation. Cancel leaves storage unchanged.
The receiver checks the captured theme collection after confirmation; a change
during the alert cannot be overwritten by the stale incoming definition.

Automatically tested: seven core methods and five headless app methods passed.
Both scripting engines produce stable readonly URL strings. Tests cover Unicode,
quotes, query characters, unknown/source fields, exact built-ins, legacy names,
missing definitions, strict UUID resolution, invalid/file types, persistence,
backup recovery, cancellation, confirmed replacement, identity collision,
commit rollback and a library change during confirmation. No test opens an
alert, requests a permission or accesses personal data.

Full regression passed 489 app methods and 565 core methods, including the five
unchanged original action scripts. All 46 Python tests and the unsigned Xcode
build passed. Matrix structure has zero errors. Strict engine acceptance still
has 18 diagnostics. Global acceptance remains open; its current output is
recorded below. Test totals are not a compatibility score.

Native verification remains pending. QA still returns a closed-native-pipe
error when Computer Use binds to it. The previous request to close its Settings
window has no response yet. The QA binary still contains the preceding theme
selection change; the new installation build has not been installed in QA.
Do not treat the headless receiver tests as acceptance of the native alert or
external dispatch. QA registers only draftly-engine-qa; ApplicationURLRouter
currently accepts only draftly. Resolve that isolated transport boundary before
opening an external theme link in QA. Do not dispatch a test link to the
habitual app by accident.

File themes remain a real implementation gap. The dated guide check confirms
that developer mode uses external JSON files in the Themes library folder.
See [developer mode](https://docs.getdrafts.com/extending/development) and the
[theme format](https://docs.getdrafts.com/docs/extending/development/theme-format).
These are 21 October follow-up references, not replacements for the archived
19 October scripting baseline. Do not classify file support as unavailable on
macOS merely because Draftly has not implemented it.

Current global result: Matrix check: 4529 errors.

### Configured application URL scheme — 21 October 2026

Implemented: the application router now accepts its configured scheme as well
as the canonical draftly scheme. It normalizes that outer scheme at the
application boundary. The domain codecs still receive canonical links.
Recognized callbacks are consumed before normalization. The production default
is unchanged. Engine QA can now dispatch to draftly-engine-qa without opening
the habitual app. Other unconfigured schemes are rejected.

Automatically tested: 17 focused methods passed. The new cases preserve the
encoded query, path, Unicode and nested callback destinations. They reject
unconfigured schemes and pass an isolated theme URL through the real codec
and receiver. Existing ordered delivery and callback-consumption tests remain
unchanged. Full regression passed 491 app and 565 core methods. The unsigned
Xcode build passed. Python remains at the preceding 46-test passing run;
this change does not edit scripts. Matrix structure has zero errors.

Prepared, not executed: theme-installation-actions.json contains neutral
Engine QA-only dispatch and verification actions. Import app-theme-backup.json
first. Run Install, then Verify. Run Replace and choose Cancel; Verify must
still report D0EEDD. Run Replace and confirm; Verify must report EED0DD. Repeat
Identical must not show a replacement alert. The verification checks the saved
UUID and unknown payload fields. A dispatch action message does not prove that
the receiver finished. Check the receiver and source text separately.

Native QA is still running its preceding build. Computer Use cannot bind to
its Settings window. The request to close that window remains pending. Refresh
all QA runtime images after a clean quit before testing this transport change.
The new source resolves the transport issue recorded in Theme installation
links above; it does not supply missing native acceptance.

### Selected file themes — 21 October 2026

Implemented: stored theme definitions now distinguish custom and file types.
Older definitions default to custom. Custom encoding omits the new field to
keep the previous shape. UUID and unknown fields remain intact. Names are
unique within each type. A custom and file theme can share a name. Stable
name/type/UUID ordering prevents catalog changes after unrelated draft saves.

ThemeFileAccess prepares validated native JSON or Drafts theme JSON and a
security-scoped bookmark. It saves the definition before storing that local
bookmark. A failed new save or replacement leaves prior records and access
unchanged. Reading a file resolves without UI, preserves its registered UUID,
requires its registered name, and validates the current colors and source.
Missing permissions, deleted files, invalid JSON and renamed themes fail
explicitly. Backups retain definitions, not bookmarks or local paths. Restored
file themes require local reselection.

Settings now has Use Theme File, Reload and Reselect controls. Selectors carry
the exact type and UUID. File choices are distinct from custom choices with
the same name. App and Workspace references use those same identities. File
access is checked before changing App preferences or applying a Workspace.
A local revision triggers reapply in other windows. Window presentation caches
its validated theme until configuration, library definitions, appearance or
Workspace changes. It does not reread the file for each keystroke. Failed
reload keeps the last valid presentation and reports the failure. Opening a
new window with an unreadable selected file reports the read error.

Theme.getAll and Theme.find include registered file metadata. They do not read
or save file contents. Theme.installURL reads the current file and emits a
portable custom snapshot, including preserved source fields but no local
access. Direct file-reference URLs are rejected. A custom installation cannot
replace an existing file record with the same UUID. Same-library import-as-
custom identity behavior still needs comparison with Drafts.

Automatically tested: file-access cases cover old decoding, unknown fields,
native and official input, latest source, missing/corrupt/deleted/renamed files,
rollback and backup/local-access separation. Both engines cover exact typed
catalog lookup, portable current links, source preservation and failure before
later steps or success effects. App/Workspace cases cover reload, local revision,
last valid rendering, explicit reopen errors and atomic application failure.
The existing native Undo test now runs with custom and file themes in both
engines. Text, selection, persisted content and Undo/Redo remain coherent.

The first shared-name test exposed unstable ordering after library reload.
The catalog now has a deterministic tie-break, and the same test passes without
sorting its assertion. Full regression passed 493 app and 573 core methods,
including the five unchanged original scripts. All 46 Python tests and the
unsigned Xcode build passed. Automatic tests opened no windows or prompts.
Matrix structure has zero errors; strict engine/global retains 18/4529
unresolved diagnostics. These counts do not establish parity.

Native acceptance is pending. A fresh QA bind still reported a closed native
pipe after Settings. QA has not been refreshed with this build. File selection,
reload, reselection, moved-file behavior, sandbox permission lifetime and
cross-window refresh require a separate manual session. Stale-bookmark renewal
exists but has not been forced deterministically in tests. Automatic discovery
from the developer-mode Themes folder is not implemented. The selected-file
workflow does not replace that remaining contract. Do not declare file-theme
parity complete from these tests.


### Development-folder themes and native acceptance — 21 October 2026

Implemented: Settings can select a local development folder. Refresh runs at
launch, app activation or Reload Folder. It reads direct `.json` and
`.draftsTheme` files. Hidden items, directories, symlinks and aliases are skipped.
All files are parsed before one library save. Local bookmarks and the enabled
preference change only after that save succeeds. Refresh preserves registered
source identities, including when two source names exchange. Missing sources
remain registered. Disabling refresh keeps registered file themes usable.
This is a selected-folder workflow, not automatic standard-folder discovery or
a filesystem watcher. Validation covers each read, not later external edits.

Automatically tested: ThemeDevelopmentFolderTests covers direct discovery,
stable identity, name exchange, invalid later input, storage failure, conflicting
sources, duplicate names, disabled/missing/corrupt access, and backup exclusion.
ThemeDevelopmentRefreshTests checks controller refresh with pending editor
text, selection, focus, stored content and last valid rendering. The first
focused run found that a missing source bookmark stopped an empty refresh.
The scanner now skips only missing-file errors when matching prior sources.
The unchanged regression passes; other bookmark errors remain explicit.
Full regression passed 494 app and 580 core methods, including the five
unchanged original scripts. All 46 Python tests and the unsigned Xcode build
passed. Automatic tests opened no windows or permission prompts.

Verified in use with Computer Use: a fresh development-signed isolated app was
installed at `/Users/andrestobelem/Applications/Draftly Theme QA.app`.
Bundle: `com.andrestobelem.draftly.theme-qa`. Scheme: `draftly-theme-qa`.
Library: `12934D88-007D-404E-B05F-BFAC257A5EB2`. CloudKit was off.
Team: NM92LU2KKV. Executable SHA-256:
`42172c0ec0d388e0ac09c58502181f611d1a01bc7c363cf5f5a42f535144ebf6`.
Debug image SHA-256:
`efd5032cc9ddc180a9474b9e28f96366ca99fcfc12caef792b1cae2fcef8b6cb`.
The previous Engine QA app was left intact. Its native-pipe failure was not
counted as acceptance. The fresh app first ran in `/tmp`; OS URL opening failed
there. Clean quit, relocation to Applications and Launch Services registration
resolved that packaging issue. Only the later receiver results count below.

| Manual case | Observed result |
| --- | --- |
| Configure custom pair | Typed getters passed; dark editor rendered 162839 |
| Select custom light | Editor rendered FFF3D6 |
| Quit and restart | Configured custom slots survived; light/dark selection passed |
| External installation | Receiver stored D0EEDD with expected UUID and unknown fields |
| Replacement Cancel | Existing D0EEDD, UUID and unknown fields remained |
| Replacement Replace | EED0DD replaced colors and kept UUID and unknown fields |
| Identical reimport | No replacement alert; main editor remained open |
| Choose development folder | Native picker selected two sources; Settings reported Loaded 2 theme files |
| Select discovered light file | Typed file option appeared; action resolved its name; editor rendered DAF0E6 |
| Edit source and Reload Folder | Editor rendered E8D9F2; text and selected café remained |
| Add invalid JSON and reload | Settings showed filename and invalid-JSON error; last valid rendering, text and selection remained |
| Remove invalid input from scan | Renamed neutral input to an unsupported extension; Reload Folder reported 2 loaded files |
| Undo/Redo after Settings | Redo restored prior t edit; Undo restored café; subsequent theme reload kept café selected |

Reproduce with the neutral `app-select-draft-notes.json`, `app-theme-backup.json`
and `app-theme-actions.json` fixtures. For external links, use
`theme-installation-actions.json` with its QA scheme changed to the isolated
app scheme. Verify receiver state with the fixture action after each alert.
Copy `scripts/fixtures/theme-development-folder` outside the repo, select that
copy in Settings, and choose its file theme. Change day.json background from
DAF0E6 to E8D9F2 and reload. Add an invalid JSON file for the failure case.
These two source fixtures use native JSON; they do not establish native
acceptance of the official Drafts source format. Automated format tests cover
that parser separately. CUA accented typing produced t rather than the intended
replacement; only the actual observed t/café Undo sequence is recorded.

Still pending: native cross-window refresh, file-specific Reload/Reselect,
moved/stale bookmark and sandbox permission lifetime, folder refresh after
restart, portable file snapshot transfer and comparison with Drafts. Registered
metadata can remain after source loss. Same-library custom snapshot import
cannot overwrite an existing file UUID. Theme contracts and full Mac acceptance
remain open. The Settings maximum-width placeholder wraps awkwardly; retain it
for the visual pass. Raw screenshots and logs remain outside Git.

Matrix structure passed with zero errors. Strict engine/global checks retain
18/4529 unresolved diagnostics. These checks remain open; the theme work does
not close the motor or the full Mac roadmap.


### Native file-theme lifecycle — 21 October 2026

Verified in use on the same signed Theme QA build and isolated library recorded
above. This session changed neutral source copies only. Production source and
runtime images did not change. Full regression and build results above remain
the latest code validation; they were not rerun for this manual record.

| Case | Observed result |
| --- | --- |
| File Reload with folder refresh off | Changing day.json to D6E5F5 and clicking the slot Reload changed the editor; café selection remained |
| Move source, then File Reload | Moved the original to `/tmp/Draftly Theme Moved/day.json`, changed it to F4E2C5, and Reload followed the bookmark and rendered the new color |
| Inspect configured/catalog identity | Neutral action found the same file Theme by name and UUID, and checked the portable payload UUID; UUID EE96C215-E109-4001-B12A-89C4D620855B, source F4E2C5 |
| Reselect a different source | Selected `/tmp/Draftly Theme Reselected/day.json` with the same theme name and E1F0D5; rendered color changed and the inspection action returned the same UUID |
| Cross-window refresh | Opened Zulu in an independent window, set both windows to light, changed the reselected source to CCDDEE and clicked File Reload; Zulu and the original Alpha window both rendered the new color |
| Editor preservation across windows | Alpha retained its text and selected café after returning through Window menu; Zulu retained its own draft |
| Launch discovery | Enabled refresh, quit, confirmed process absence, then added a new QA Launch discovered source to the chosen folder; after relaunch the file theme appeared in Settings without a manual reload |
| Local access after restart | Configured file slot survived; inspection action read CCDDEE with the same UUID after relaunch |

Reproduction action: `scripts/fixtures/file-theme-actions.json`. Import it in
isolated QA and select a neutral light file theme. The action checks typed file
lookup and portable source identity without editing the draft. Keep before and
after UUID results when testing Reselect. It does not compare with Drafts.

A native Reselect cancellation check was interrupted by Computer Use focus-change
errors. Its last observed window was Settings. It is not accepted. The older
user response about closing Engine QA Settings arrived after the fresh Theme
QA app was already working; it did not establish any additional result.

The moved bookmark worked, but its stale flag was not observed. A forced stale
bookmark check remains pending. `codesign -d --entitlements -` shows no
entitlements on this QA signature; the production entitlement file also has no
app-sandbox key. Successful local access after restart therefore does not prove
sandbox permission lifetime. Native portable file-snapshot transfer, official
source-format UI acceptance, full Theme catalog comparison and same-library
snapshot identity comparison remain pending. Do not mark full theme parity
from these local lifecycle checks. No screenshots or raw logs were added.

The system Python tooling run could not import Pillow and did not count as a
complete run. Repeating with the bundled runtime passed all 46 Python tests.
The matrix structure check passed. Production code was unchanged in this session.

Read-only engine review retained the 18 strict diagnostics across six partial
contracts. The finite acceptance checklist is now
`docs/research/engine-native-checklist.md`; the matrix points to it. It separates
current async-route evidence from older voice checks and theme-file access.
The review did not accept new motor behavior or change production rules.


### Native shell process lifetime — 21 October 2026

Manual session used the same signed Theme QA build, isolated library and hashes
recorded in Development-folder themes and native acceptance. No runtime code or
production deadline changed. Fixture:
`scripts/fixtures/engine-shell-lifetime-actions.json`. The cancellation action
saves a completed editor write, starts a shell with a child sleep, ignores TERM,
and has sentinel steps plus Archive on success. The recovery action validates
literal Unicode output without editing the draft.

UI Cancel Running Action: observed shell PID53915 and child53916 in isolated
PGID53915 while pending. The native cancel control returned Cancelled. Both PIDs
were absent and the exact temporary directory was removed on the following
process check. The draft stayed in Inbox with its completed write and no
sentinel. Recovery returned Shell recovery café 🐼; history showed Cancelled
followed by Success.

Owner close: repeated with live shell53926, child53927 and PGID53926. The native
window close control replaced the editor with Untitled. Both PIDs disappeared
and the exact temporary directory was removed. Inbox still listed the original
neutral draft and its second completed write. A following recovery action
completed before the next timeout run. This tests UI owner close, not a URL or
Intent shell operation.

Focused NativeProcessExecutorTests passed 15 methods in two suites. They cover
literal arguments, output/status, task cancellation, timeout, TERM escalation,
descendants, launch errors and waited/detached Shortcut lifetime. They opened
no windows, requested no permissions and produced no audio. Production code
was unchanged; the earlier full build remains the current build evidence.


Production timeout: the fixture used a 180-second child, longer than the unchanged
120-second limits. Observed shell53974 and child53975 in PGID53974. Both were
still live at ps elapsed01:46. The next monitor observation, 20 seconds later,
found both PIDs absent and the exact temporary directory removed. These are
observation bounds, not a precise timeout timestamp. Execution History showed
Error with “The action operation timed out before it completed.” at05:54.
The completed write stayed in Inbox, with no sentinel or Archive. Recovery then
returned the exact Unicode result and history Success. History also confirmed
the owner-close run as Cancelled and its following recovery as Success.

The action/host deadlines can race at the same production limit. This session
accepts final timeout, interruption cleanup and recovery through the UI; it does
not isolate which deadline won. It does not accept shell operation variants
through URLs or App Intents. All fixture processes and the process monitor are
terminal. Theme QA remains open on the retained neutral Alpha draft, history
closed. No private data, permissions, external service or screenshots were used.

Post-session tooling passed all46 Python tests with the bundled runtime. Matrix
structure passed. Strict engine/global checks remain open at18/4529 diagnostics;
new native shell evidence does not close the other capability obligations.


### Completed PDF printing and actor isolation — 21 October 2026

Native QA found a real crash when Save as PDF completed. The process was absent
and no output existed. The local crash report identified a dispatch isolation
trap in NativePrintTextView.knowsPageRange, called from AppKit's printing thread.
SheetPrintDriver had enabled canSpawnSeparateThread for a MainActor text view
and delegate. The failed run is not accepted.

Implemented: NativePrintLayout now creates the shared operation configuration.
It disables the separate printing thread. SheetPrintDriver uses that operation.
Pagination and delegate delivery stay on MainActor. The panel still uses its
asynchronous completion callback and the existing cancellable request boundary.
AppKit renders on the current thread after panel completion; long-document print
latency remains unmeasured. Apple documents this behavior in
[canSpawnSeparateThread](https://developer.apple.com/documentation/appkit/nsprintoperation/canspawnseparatethread).
This AppKit lookup does not change the frozen Drafts reference.

Automatically tested: the new regression first rejected the unsafe thread flag.
After correction, it generated an actual one-page PDF with print/progress panels
disabled. PDFKit found the heading, café, emoji and final line. The first text
assertion assumed font runs had one extraction order; PDFKit extracts the emoji
run later. The test now checks all source segments on the single page. Existing
layout tests still check wrapping and final glyph bounds. All 15 focused print
methods passed. No automatic test opened or moved a window or printer panel.

Verified in use: refreshed all 13 QA runtime files after confirming the process
was stopped, retained its identity/library and verified development signing.
The first corrected image saved `/tmp/Draftly Print QA.pdf`, one page, 45514 bytes.
The success banner confirmed the following action step ran. The final image
repeated the complete print to a distinct PDF: one page, 45506 bytes, all neutral
text verified through PDFKit. That second panel used its fixtures location; the
neutral output was moved to `/tmp/Draftly Print QA current.pdf`. Neither PDF is
tracked. The original draft stayed unchanged; history recorded Print Success.
No physical printer, network service or permission was used.

Fixture: `scripts/fixtures/engine-print-completion-actions.json`.
The first corrected executable/debug image SHA-256 values were
`0a49f7f3cb4319c2fb26cd189d5a4853671f1f954f90f3bc69415a30b21b022a` /
`501517692b67f7a2e79702f068437f605602f078bd9e9be845de2a4f3536ddb1`.
The final image, including the independent shell fixes, was
`e9671565e875cdba2498ccbfabd106159e6834478dc9091b57d0532ab9ad6b10` /
`f582263651117d2e5523775e4a66b47e8e4ee68e1f0607b7adf6d14fed4952a4`.
Bundle/library/scheme remain the isolated Theme QA values recorded above.
Full final regression passed 496 app and 586 core methods and the unsigned Xcode
build. Five original action scripts remain unchanged. These counts do not close
print format/margin variants, native task cancellation, timeout or owner close.


### Literal shell arguments and Unicode composition — 21 October 2026

Native QA found that an NFC café argument returned as decomposed cafe plus
combining accent. JavaScript strict equality caught the difference. Swift String
canonical equality in the old adapter test had hidden it. The installed SDK's
NSTask.h documents that Process converts argument strings with
fileSystemRepresentation. Source-file stderr kept NFC, so normalizing output
would have hidden the argument defect and changed intentionally decomposed text.

Implemented: both shell adapters now launch a private UTF-8 shell file that
executes the original script with individually single-quoted literal arguments.
Embedded apostrophes are escaped. The exec replaces the launcher, preserving the
process identity and isolated group. The original script retains its shebang.
NUL arguments fail explicitly instead of being truncated. The temporary folder
contains the launcher and is removed through the existing cleanup boundary.
This does not change general Process or Shortcut argument behavior.

Automatically tested: the existing literal-argument test now runs both adapters
and compares UTF-8 bytes. It includes NFC and NFD strings, quotes, whitespace,
newlines, empty arguments and shell substitution syntax. It failed in both
adapters before the fix and passed afterward. A second test rejects NUL before
execution. Tests validate status and both streams; they do not normalize results.
The full final regression/build recorded above includes these cases.

Verified in use on the final signed QA image recorded above: QA Shell nonzero
streams passed exact JavaScript stdout/stderr equality with exit7 returning
false. The first fixture attempt had an escaped newline instead of a real
shebang newline; it failed and is not acceptance. Fixing that fixture then
exposed the actual NFC/NFD defect. The final fixture and implementation passed.
QA Shell launch failure handled returned false and preserved the editor.
Re-ran task cancellation after the exec change: parent58697 and sleep58698 shared
PGID58697, then both disappeared and the exact temporary folder was removed.
History showed Cancelled, followed by the Unicode recovery action Success.
No tail or Archive occurred; only the completed neutral write remained in Inbox.

Fixture: `scripts/fixtures/shell-member-actions.json`. No production permission,
private content or external service was used. The earlier120-second native
timeout/owner-close evidence predates this launcher change. Group behavior has
headless regression coverage and the repeated native task-cancel case; native
timeout/owner-close were not repeated on the final launcher image.


### ShellScript member contracts and failure results — 21 October 2026

Audited all five ShellScript members against their archived 19 October reference.
No reference hash or signature changed. Constructor/create are independent typed
values and do not execute source. Optional stream properties hold the latest
text, preserve Unicode/newlines, accept assignment, replace old output with empty
output and remain independent across instances. No undocumented default script,
invalid-input coercion or post-launch-failure stream result was invented.

Implemented: execute returns false for ordinary host errors, matching its Boolean
contract. It still returns false for nonzero process status and true for zero.
Typed interruption metadata now crosses both host transports. ShellScript
rethrows marked interruption errors. The async transport also preserves raw
CancellationError as cancelled. Without this last change, the new regression
showed a cancelled worker continuing to edit text and Archive. The corrected
regression stops all later effects and success parameters. Legacy native shell
timeout now retains typed interruption through the bridge rather than becoming
an ordinary false. Legacy final reports keep their prior generic error reason.
No message-string matching determines interruption type.

Automatically tested: six methods cover both runners with source/argument
forwarding, independent construction, writable streams, repeated/empty/status7
output, ordinary host failure, uncaught typed/raw cancellation and timeout, and
caught interruption with blocked later effects. The ordinary-host-error test
failed before correction. The raw worker CancellationError case also failed
before its transport fix. Both now pass without weakening their assertions.
The final full run passed 496 app and 586 core methods; five original scripts were
unchanged. The unsigned Xcode build passed. The added writable-stream assertions
also passed the focused member suite afterward.

Verified in use: the final signed image recorded in the print entry ran
shell-member-actions.json. Status7 returned false with exact Unicode stdout and
stderr. The missing-interpreter action returned false and continued to its
explicit handled-result message. Both kept the editor text. A real task cancel
then removed the shell and child, retained the completed write without Archive
or tail, and a following shell action returned Success. The earlier fixture and
Unicode failures remain recorded in the preceding entry; they are not accepted.

Constructor/create and the two stream members now have member-specific complete
records. Execute stays partial: the reference uses the Drafts Application Scripts
directory and first-use access. Draftly uses private temporary scripts and the QA
build is not sandboxed. Real permission-denied acceptance remains pending.
Omitted arguments and automatic /bin/sh remain compatible Draftly extensions.
Successful UTF-8 text tests do not define a contract for binary output decoding.
No unrelated native route is accepted by these ShellScript checks.

Final tooling passed all 46 Python tests. Matrix structure passed with zero
errors. Strict engine/global acceptance remains open with 18/4470 diagnostics.
Member-specific evidence, not these totals, determines compatibility status.


### Native print cancellation — 21 October 2026

Implemented: no production change in this check. The neutral fixture
`scripts/fixtures/engine-print-lifetime-actions.json` writes text before printing,
has a visible tail sentinel, and uses Archive only after success. It permits
reproduction of cancellation without a physical printer or private data.

Verified in use: the current signed Theme QA image recorded in the preceding
print entry opened the native one-page panel. Actions > Cancel Running Action
closed it and recorded Cancelled at 06:19. A second run used the native panel
Cancel button and recorded Cancelled at 06:21. Both retained the completed
write in Inbox, without ERROR: print continued or Archive. A following
QA Shell lifetime recovery run recorded Success at 06:22. History is closed.
No print job or PDF was submitted during these cancellation checks.

Automatically tested: no new production calculation or contract changed, so
the previous headless print regression and full suite remain the code baseline.
This manual check does not replace timeout, owner-close, format/margin or large
rendering acceptance. Those checks remain pending. No raw capture is tracked.


### Native print production timeout — 21 October 2026

Verified in use: ran QA Print pending operation on the same signed Theme QA
image as the cancellation checks. The native panel remained open at79 and110
seconds after observation. At128 seconds it had closed. History recorded Error
at06:25 with The action operation timed out before it completed. The production
120-second limit was not changed. The completed write remained in Inbox without
the tail sentinel or Archive. This does not isolate which equal host/print
deadline won. A following shell recovery recorded Success at06:27.

The owner-close attempt is not accepted. File > Close was disabled during the
print sheet. Close All did not produce a confirmed owner closure; the Window
menu still listed Alpha. The second run later recorded Cancelled at06:26 after
menu/Escape interaction. Its exact cause was not isolated. Do not label this an
owner-close success. QA is back on Alpha with history closed and no print panel.

Automatically tested: the15 NativePrintRequestTests passed headlessly on this
source. No production implementation changed for the native timeout check.
Owner-close and long-rendering acceptance remain pending.


### AppleScript interruption integrity — 21 October 2026

Implemented: AppleScript.execute now rethrows marked control errors before
handling ordinary host failures as false. The new member suite first showed
three legacy regressions: timeout, typed cancellation and CancellationError
continued to edit text, publish a success parameter and Archive. The worker
already rejected those effects. The same assertions now pass on both runners.
Ordinary failures still return false and set lastError; later success clears it.

Automatically tested: four specific methods cover12 runner/argument cases.
They check independent constructors without host execution, optional writable
properties, exact source/subroutine/structured arguments, independent results,
ordinary failure/recovery and control errors. The focused suite passed. The
full sequential run passed496 app and590 core methods. The unsigned Xcode
build passed. Matrix structure validation passed. No automatic window, native
permission or external message was used. The original five scripts are unchanged.

The first full concurrent run did not finish. Its helper remained alive with
no CPU or log changes. A process sample showed idle executors; outstanding
async tests remained. After recording the diagnostic, that exact helper and
parent were terminated. AsyncHostDrainTests then passed both cases alone, and
the full sequential run passed. The concurrent-suite stall remains unresolved;
the sequential result does not establish its cause or erase the failed attempt.

Verified in use: none for this code change. QA still uses the earlier signed
image. The five-member AppleScript audit is not closed. Native date conversion
and nested dates are missing; permission and Date argument contracts need review.
Only execute receives a partial classification in this stage. Constructor and
property evidence is available in the new suite for the next member review.


### QA Services isolation — 21 October 2026

The user found ten duplicate capture entries from five QA copies. Implemented:
refresh-engine-qa.py now removes NSServices before signing. It preserves the
other isolated plist values and keeps its process and identity checks. The
production Configuration/Info.plist still declares both capture Services.
Manual preparation now requires removal for all ordinary QA copies. A dedicated
Services acceptance session must remove its temporary registration afterward.

Automatically tested: a new packaging regression first failed because codesign
received a QA bundle that still declared Services. The corrected case verifies
removal before both signing calls and preservation of all other plist values.
All47 Python methods passed. No Swift source changed; no Swift rebuild was needed.

Verified in use: quit Engine QA and Theme QA with native Quit. Process inspection
confirmed all five QA copies stopped. Removed only NSServices from Visual,
Engine, Restore, Scale and Theme QA plists. Kept their identities, library IDs,
URL schemes and other values. Signed each with the existing development identity
and retained signature metadata. All five deep/strict signature checks passed.
Updated only those Launch Services records and refreshed the Services cache.
Finder > Services, with a neutral /tmp text file selected, then listed exactly
Capture to Draftly, Capture to Draftly with Options, Capture to Drafts and
Capture to Drafts with Options. No QA capture variant remained. No service was
invoked, library changed or app removed. All QA apps remain stopped.


### AppleScript date and member contracts — 21 October 2026

Implemented: native typeLongDateTime descriptors now use dateValue and return
Foundation Date. A shared AppleScriptValueTransport codec stores milliseconds
and escaped JSON Pointer paths outside the returned value. JSON records keep
their own keys without marker collisions. The helper, native host, legacy bridge,
worker bridge and first-party step path preserve this metadata. JavaScript
reconstructs Date values only for AppleScript responses. Date-like strings remain
strings. No JavaScript object crosses executors. Library formats did not change.

The initial native regression returned String instead of Date. The core Date
fixture also exposed a Foundation JSONSerialization NSException before the
transport correction. The first integration attempt then failed the worker root
Date assertion: ActionScriptWorker unwrapped the reply and dropped its metadata.
It now decodes typed values before the runtime serializes the response. Original
assertions were retained. No crash or failed attempt counts as acceptance.

Automatically tested: six codec methods cover root/nested/negative/fractional
dates, escaped and numeric keys, normal JSON, marker-like records and invalid
metadata/values. Both-runner member tests cover root/nested Date, own __proto__
keys without prototype changes, normal records and date-like text. Both first-
party step paths preserve dates in context.appleScriptResponses. Actual neutral
NSAppleScript tests check descriptor types and the helper JSON round trip. They
use no UI, permissions or target applications. Full sequential regression passed
498 app and598 core methods. Unsigned Xcode passed. Original five scripts did not
change. The earlier concurrent-suite stall remains unresolved; this run does not
claim to repair it.

Verified in use: refreshed the stopped Engine QA with all runtime files through
the guarded script. Copied hashes and development signature verified. Its
identity, library and isolated callback scheme were retained; NSServices remains
absent. Final executable/debug SHA256:
50012515f21522bca0ca21be40ef16e2d13c3c39ac2894d99991a8be10b9fad4 /
c0b6343fab2e087f33d81d4234f190ae71560cb11f7d31cfa6661e6d6daf57d0.

Imported scripts/fixtures/apple-script-member-actions.json through File > Import.
QA AppleScript dates and recovery returned actual root/nested Date objects,
retained ordinary records/text, checked independent objects, handled an intentional
error and recovered with cleared lastError. QA AppleScript step dates verified
the native step response collection. History recorded both Success at06:39.
The selected neutral Alpha content stayed unchanged. History is closed and no
action remains pending. No external message or permission was involved.

Current Apple dateValue documentation and the installed Foundation header confirm
its date/coercion contract. This implementation lookup does not change the frozen
Drafts reference: https://developer.apple.com/documentation/foundation/nsappleeventdescriptor/datevalue.
Constructor, create, lastError and lastResult now have specific complete records.
Execute stays partial: Date argument behavior, native permission-denied and
corrected-image interruption acceptance remain open. No binary or undocumented
post-failure result contract is claimed. Structure validation passed0; strict
engine/global still reports18/4412 diagnostics, not a compatibility percentage.


### Host cleanup fixture completion — 21 October 2026

A new full concurrent reproduction passed498 app/598 core before any change.
The historical stall therefore remains intermittent. Source review found two
definite fixture gaps in AsyncHostDrainTests: start and cleanup streams never
finished when the action returned before their expected signal. A terminal
action could leave the test waiting forever. The cleanup release could also
arrive before its continuation was installed and be lost.

Implemented in tests only: the action task finishes both streams on return.
Required signals now fail with the runner message when absent. Deferred cleanup
cancels the task and releases a latched gate. The original busy-library and
cleanup-drain assertions remain unchanged. Production still waits for native
cleanup; no runtime deadline or exclusion contract was weakened.

Automatically tested: a new regression throws Before host, observes both absent
signals without waiting for a deadline, checks the error and retained content,
and runs a following action on the same library. Both focused methods passed,
including the existing cancellation and timeout cases. A full concurrent run
then passed498 app/599 core. This proves the fixture correction, not the exact
cause of every earlier suspended test. No production source or visible UI changed.
The preceding successful Xcode build remains the production code baseline.


### Native AppleScript helper lifetime — 21 October 2026

Verified in use on the signed Engine QA image recorded in the Date entry.
Imported engine-applescript-lifetime-actions.json through File > Import. The
action writes neutral text, starts a45-second AppleScript delay, catches a
possible script error and attempts later edits plus Archive. It never targets
another application or requests Automation access.

Task Cancel: observed helper65858 with the exact private request directory
BAEF84AE-27D9-432C-B3D3-D5AE8AE25996. Actions > Cancel Running Action ended
the pending action. Process inspection confirmed that PID and directory absent.
History recorded Cancelled06:44. Alpha stayed in Inbox with the completed write,
without ERROR: AppleScript continued, the tail sentinel or Archive.

Owner close: ran the action again and observed helper65912 with directory
F1A2A8D6-B875-4FCC-9B71-DE104C74621B. Clicked the owner window close button
while the helper was alive. The source window disappeared; the next observed
window was Untitled. The exact helper and directory were absent. Selected Alpha
again and verified both completed writes, no tail and no Archive. History
recorded Cancelled06:45. A following QA AppleScript dates and recovery action
recorded Success06:45. History is closed and no helper/action remains pending.

Implemented: no new production change in this native check. Automatically
tested: the preceding full concurrent498 app/599 core run covers this image's
contracts and the test-only stream fix. No UI runs inside automatic tests.
Production120s native timeout, Automation permission paths, and Date argument
comparison remain pending. This acceptance does not close AppleScript.execute
or any other native route.


### Native AppleScript production timeout — 21 October 2026

Extended engine-applescript-lifetime-actions.json with QA AppleScript production
timeout. It uses a180-second neutral delay and the unchanged120-second production
limit. No executable or runtime setting changed. The source writes text before
waiting and tries a caught-error tail and Archive afterward.

Verified in use on the current signed Engine QA Date image. Observed helper67146
and its exact request directory83461698-C3EC-4BB2-BB03-27A0E93255FC. A process
monitor watched that PID, then confirmed it absent and the directory removed.
The later monitor origin was not the execution start, so its111.4-second duration
is not a precise execution latency. At129.6 seconds after the first UI
observation, History recorded Error06:49: The action operation timed out before
it completed. The completed write stayed in Inbox without tail or Archive.
Equal host/helper deadlines were not isolated.

A following QA AppleScript dates and recovery action recorded Success06:50.
The neutral editor text remained intact. History is closed and no helper or
action remains pending. No Automation permission was requested and no external
application was targeted. Permission request/denied/cancel and pending-permission
cleanup remain open. Date argument semantics still need comparison. This result
accepts only the native UI helper timeout; URL/Intent and other routes keep their
own pending checks.

Automatically tested: the concurrent suite with the accompanying utility tests
passed498 app/601 core methods. No production code changed after the preceding
successful unsigned build. No automatic test opens a visible window.


### Base64 member contracts — 21 October 2026

Reviewed the archived19 October Base64 page and retained its URL/hash. It defines
only static encode(data:string):string and decode(data:string):string. No default
argument, malformed data policy, padding/whitespace rule or invalid UTF-8 result
is specified. No guessed error policy was added to production or acceptance.

Implemented: existing Foundation UTF-8/Base64 commands already satisfy the
documented valid-string contracts. No production source changed. Automatically
tested: two member-specific methods each run on both engines. Independent known
vectors cover f through foobar, empty strings, café/emoji, CRLF/LF and embedded
NUL. Assertions check exact values and string returns, unchanged source and
editor/storage, and no native-host call. The focused suite passed. Full
concurrent regression passed498 app/601 core. The preceding successful Xcode
build remains the production code baseline. No automatic test opens a window.

Verified in use: imported scripts/fixtures/base64-member-actions.json through
File > Import in current signed Engine QA. QA Base64 member contracts checked
standard/Unicode/empty encode and decode results without changing the editor.
History recorded Success06:50. No permission, clipboard or external service was
used. Both members now have specific complete records for their documented
contracts. This does not define behavior for undocumented malformed data.

Final tooling: Python47 and matrix structure0 passed. Strict engine/global
remain open with18/4388 diagnostics. Totals are not a parity percentage.


### HTML literal text and member contracts — 21 October 2026

Reviewed the frozen HTML reference. It declares a constructor and static escape
and unescape methods. It specifies no defaults, error outcomes or malformed-
entity policy. Its escape illustration uses hexadecimal spelling; Draftly uses
equivalent named/numeric forms. Exact spelling comparison remains pending.

Implemented: HTML unescape no longer parses the whole input as an HTML document.
That parser normalized literal CRLF/CR and changed NUL text. Three byte-level
cases failed before correction. The function now finds entity tokens, decodes
them once with the existing native entity parser, and replaces them in reverse
UTF-16 order. A per-call cache avoids reparsing repeated entity tokens. Literal
text is copied unchanged. Tokens contain no markup or resource URLs. Native
entity-parser behavior remains in use; no guessed malformed-entity rule was added.

Automatically tested: the original three byte assertions now pass. New specific
HTML member methods cover construction, escape output and unescape forwarding
on both engines. Their fake-host unescape results accept the bridge only. Actual
NativeActionHost tests check literal markup, Unicode, whitespace and entity text.
Core concurrent604 methods passed. The full concurrent command and a separate
app-only concurrent command exited0 without an app final summary;499 methods
started but nine lacked completion lines in the latter. Those app runs are not
accepted as a full pass. A separate sequential app run reported all499 methods
passed in86 suites. This output anomaly remains open and is distinct from the
previous stream-wait fixture. Unsigned Xcode passed. Original scripts unchanged.

Verified in use: refreshed stopped Engine QA through the guarded script; runtime
hashes and development signature verified. Final executable/debug SHA256:
73b16024c8d44debf0ce788011e09674dd4c724c590bf01f76bbb80b23c12e50 /
7233791c50afe6f70646c1f0f0377e5b16b7eb8bc6ee028f46fd1dc3e5a45e30.
NSServices stays absent; identity and library unchanged. Imported
html-member-actions.json. The action checked literal CRLF/tab/NUL and entity
text, escape/unescape roundtrip, decoded markup, one pass and empty strings.
History recorded Success06:56; the editor was unchanged. Constructor is complete;
escape/unescape remain partial for exact spelling/catalog comparison. No binary,
malformed or complete native catalog result is inferred from the bridge tests.


### Native HTML preview lifetime — 21 October 2026

Verified in use on the signed Engine QA image recorded in the HTML literal
entry. Imported engine-html-lifetime-actions.json. Pending actions save neutral
text before presentation and have an ERROR tail plus Archive after success.
The fresh-response action checks typed Unicode/null and absence of an old key.

Task cancel: clicked Arm delayed result and observed Late result armed. The old
page scheduled Drafts.send/continue after15 seconds. Actions > Cancel Running
Action removed the preview. A fresh preview remained open42.9 seconds after the
old timer was armed. Send fresh result returned only its own typed values;
History showed pending Cancelled and fresh Success06:57. This demonstrates
observable isolation. It does not prove that the old WebKit timer actually ran
or delivered a message after its handler was detached. Direct late receive
rejection is covered separately by the existing headless request tests.

Owner close: opened another pending preview and clicked its owner close button.
The source window disappeared; the next observed window was Untitled. Selected
Alpha again. History recorded Cancelled06:57. Completed text remained Inbox
without the tail or Archive. No preview remained from the closed owner.

Production timeout: started the dedicated pending preview without changing the
120-second limit. It was still visible at77.9 seconds after first observation,
and absent at154.9 seconds. History recorded Error07:00 with The action operation
timed out before it completed. This does not measure exact teardown latency or
isolate equal host/request deadlines. Completed text remained Inbox without tail
or Archive. A following fresh preview recorded Success07:01 and only its own
values. History is closed; no preview or action remains pending.

Implemented: no production preview change. Automatically tested: all six existing
NativeHTMLPreviewRequestTests passed headlessly, including explicit late receive
after timeout, cancellation, cleanup once, subframes and errors. The current
production build also passed the499 app sequential and604 core concurrent runs
recorded above. Capability-specific URL/Intent variants and actual stale WebKit
message delivery remain separate. No remote content, permission or personal data
was used. The HTML unescape correction is in its own commit.

Final tooling passed47 Python tests and matrix structure0. Strict engine/global
remain18/4356 diagnostics. These counts do not establish compatibility.


### Complete Swift result verification — 21 October 2026

Investigated the concurrent app output anomaly without changing production. Two
app-only concurrent repetitions with xUnit each produced499 complete identities
and a final summary. Later full and app-only report attempts failed with
Line2: Extra content at the end of the document and produced no XML. Core still
reported604 passed in the full attempt. Excluding HTMLPreferencesTests did not
resolve the report failure. No explicit test exit or application termination
route was found. These observations do not prove a production or HTML-importer
cause. The historical incomplete concurrent app runs remain unaccepted.

Implemented: scripts/run-swift-tests.py discovers methods, runs each target with
a fresh report, and verifies exact classname/method identities. A zero process
exit is insufficient. Missing, duplicate, unexpected, failed, skipped, truncated
and count-inconsistent reports fail. Root summary errors also fail. Old report
files are removed before execution. New discovered targets are included.
Default app execution is serial because AppKit fixtures share process-wide
state. Core stays concurrent, and tests retain their explicit concurrent tasks.
The script never retries. --concurrent-app exposes the unresolved diagnostic
mode; it does not silently fall back. Parameter cases still rely on Swift
Testing's report and do not have an independent discovery inventory.

Automatically tested: nine Python methods exercise complete and incomplete
reports, identity substitution with equal counts, duplicates, hidden failure/
error/skip nodes, root errors, truncated XML, stale reports after a zero exit,
new targets, explicit app mode and no retries. All56 Python methods passed.
The real final runner compared all discovered identities against the fresh
reports and printed Verified complete Swift results: DraftlyCoreTests604,
DraftlyTests499. The app summary passed499 in86 suites; core passed604 in115.
Both process handles terminated normally. The first guard attempts correctly
failed rather than accepting the report errors. No production code changed;
the preceding successful unsigned Xcode build remains its baseline.

Verified in use: no Computer Use was needed for this test-tool change. QA apps
and libraries were not changed. Matrix structure passed0; compatibility status
is unchanged. README and testing instructions now use the checked runner.
Reports/logs stay outside Git. Temporary success files are removed by default;
failure files remain for diagnosis. This is a validation guard and an explicit
execution workaround, not a claim that concurrent app-reporting is repaired.


### Native arrangement lifetime — 21 October 2026

Verified in use on the Engine QA HTML image recorded above, before the URL
component update. Imported engine-arrangement-lifetime-actions.json. The pending
action saves neutral text, calls editor.arrange with explicit text, catches a
possible error and attempts later text plus Archive. No source production code
changed for this route check.

Task Cancel: observed Arrange lines with First, Second café 🐼 and Third.
Actions > Cancel Running Action closed the native dialog. History recorded
Cancelled07:13. The completed write remained Inbox without the sentinel or
Archive. Production timeout: the same arrangement dialog stayed open at92.4
seconds and was closed at134.9 seconds after initial observation. History
recorded Error07:15 with The action operation timed out before it completed.
The120-second limit was unchanged; these observations do not measure exact
teardown latency. Completed text stayed Inbox without tail/Archive.

A following QA Arrange recovery opened a new dialog. Done returned the exact
neutral text and History recorded Success07:16. The editor retained only its
completed writes. History is closed and no arrangement remains pending.
Owner-close, stale navigation and entry-specific URL/Intent checks remain open.
No permission, external target or personal content was used.

Automatically tested: the checked499-method app report includes all three
NativeArrangementRequestTests: accepted Unicode text, exact original text on
user Cancel, and rejection of an accepted result after task cancellation. The
UI acceptance above does not infer these cases from a global test total.


### URL component coherence — 21 October 2026

Reviewed the frozen URL page. Its four headings match the inventory. It says
the implementation closely mirrors Web URL; host/searchParams also occur in
its parsing example. No invalid-input return or exception policy is documented.
No reference URL/hash changed.

Implemented: hostname and hash now retain one private component snapshot and
update the native URL before replacing the snapshot. fragment uses hash. The
new internal updateURL route changes only hostname or hash through the existing
URLComponents parser/serializer. It returns a fresh component snapshot so href,
host and String(url) stay coherent. Source/base strings and independent objects
remain unchanged. The empty constructor and existing URL/base overload remain
compatible. Enumerable hostname/hash values remain serializable. No library
format, Note identity, public method name or original script changed.

Automatically tested: the new five-method both-runner suite first found stale
href after fragment mutation and stale host/href after hostname mutation. The
same assertions now pass. Construction, prefix handling and absolute/base-
relative parsing also pass. The checked runner verified499 app and609 core
method identities against fresh reports. Unsigned Xcode passed. The Foundation
URLComponents documentation lookup confirms component setter/encoding behavior;
it does not replace the frozen Drafts reference or prove Web URL equivalence.

Verified in use: safely quit and refreshed Engine QA after the native Arrange
check. Copied runtime hashes and development signature verified; identity/library
and callback scheme unchanged, NSServices absent. Final executable/debug SHA256:
7c47e9dd2014c4fc88c5512e10be61141def3d2697ef0d7c0f190a0471cf30a5 /
92bb1adc94ef4f9361f16070051e329b5c04137e5d8f12ba9dd6c10a52e0d66e.
Imported url-member-actions.json. QA URL member contracts checked href/host/
String coherence, port/query retention, separate instances, enumerable hostname
and relative resolution without opening a URL or changing the editor. History
recorded Success07:18. History is closed; QA stays open on Alpha.

Constructor is complete. The other members remain partial: percent-encoded
component values, Unicode/IDN/IPv6 normalization and further Web URL edge cases
need dedicated comparison. Existing non-heading fields/searchParams mutations
are not accepted by these tests. Basic coherence is not full URL compatibility.
No malformed-input policy was invented. Native Arrange acceptance is a separate
commit and refers to its preceding executable.

Final tooling passed56 Python tests and matrix structure0. Strict engine/global
remain18/4314 diagnostics. Those totals are not a compatibility percentage.


### HTMLPreview member contracts — 21 October 2026

Implemented: no production change. Reviewed all four members against the frozen
HTMLPreview reference. Added HTMLPreviewContractTests with four identified tests,
each run through both runner paths. Constructor and create return independent
typed instances with no host presentation. The writable hideInterface value is
per instance and is forwarded on every show call. Exact HTML includes empty and
Unicode strings. Continue returns true, Cancel returns false, and empty returned
values remove previous context values. A presentation error stops the script
before its following editor mutation. Source text stays unchanged.

Automatically tested: the targeted four-method suite passed. The checked full
runner then verified all 613 core and 499 app method identities, with no missing
or duplicate reports. Swift compiled the added test source. Matrix structure
passed with zero errors. Strict engine/global gates remain 18/4274 diagnostics.
No production build or QA refresh was needed because production did not change.

Verified in use: no new native session. Preserve the earlier Native HTML preview
lifetime record, including its stated limits. The new fake-host member tests do
not prove WebKit presentation. Constructor and factory are complete for their
construction contracts. hideInterface and show remain partial for hidden-toolbar
comparison, actual stale WebKit delivery and capability-specific URL/Intent
acceptance. No reference content, original scripts or personal data changed.


### Window bridge contracts — 21 October 2026

Implemented: getter-only Window properties now match the archived readonly
signatures. floatOnTop remains writable. Void panel, Info, search and palette
commands discard the native host result. Group and tab commands retain their
Boolean return path. No storage format, identity or original script changed.

Automatically tested: WindowContractTests adds four methods, each run on both
runners. Readonly, panel void results and query/Info void results failed before
the correction. The first red run also exposed an unsafe test array index after
an earlier failed assertion. Added a count requirement, then repeated the red
run without that test crash. The corrected bridge passed the same assertions.
The floatOnTop test passed before and after. Exact query text, Info target UUID,
omitted Info argument and source-content preservation are checked. The controlled
host is not a real window. No default native window layout is inferred.

The checked runner verified 617 core and 499 app method identities. Unsigned
Xcode build passed. Matrix structure passed. Strict engine/global gates remain
18/4154 diagnostics, not a compatibility percentage. Fifteen Window member
records now cite their specific test and preserve remaining limitations.

Verified in use: none added in this review. QA remains on the preceding URL
image; no refresh or new native acceptance is claimed. Dedicated host-error
cases, native Window behavior and remaining group/tab/Workspace contracts stay
pending. Source inspection found that WindowActionAdapter ignores initialQuery
for showQuickSearch and showCommandPalette. The forwarding tests cannot close
that functional gap. Correct it separately with native-model regression coverage.


### Window search initial query correction — 21 October 2026

Implemented: the Quick Search dependency carries a String to AppController and
QuickSearchController. A fresh QuickSearchView starts with that exact query.
CommandPalette binds to window-local paletteQuery. The common palette opener
sets its query on every invocation. Menu and toolbar paths use an empty query.
The list query and action-list query remain independent. No format or public
scripting signature changed.

Automatically tested: WindowSearchQueryTests has two headless model tests.
After adding query-capable state and dependency transport, both failed with the
old adapter behavior: Quick Search received two empty strings, and the palette
query stayed empty. The adapter correction passed the same tests. Cases cover
Unicode and a newline, omitted arguments after a nonempty query, unchanged list
and action filters, unchanged source identity, unsaved text and selection.
Existing injected-route tests use the new String parameter. No test opens UI.
Checked runner verified 617 core and 501 app method identities. Unsigned Xcode
build and matrix structure passed. No new Python source changed.

Verified in use: quit Engine QA through its native shortcut. The final AX read
timed out because the process exited. The refresh guard verified its absence,
then copied and checked the runtime files, signed and verified the bundle.
NSServices remains absent. Signed executable SHA256:
60d30be1b1c7fa47965f14e00a2fa5d3b6cdd3e1998759d2f488b3b9d07abc6b.
Debug dylib SHA256:
f60ed97b774b3dc3eb4095ffc15a02dbf7ac8c6de85eab845f5e620c6f2872a4.

Imported window-search-query-actions.json in the isolated library. Quick Search
showed Picker QA: Zulu in its field with one matching result. Cancel kept Alpha
open with its existing text. The palette showed QA URL member contracts with
one matching action. Done did not run that action. Reopening both through the
no-argument fixtures showed empty fields and the full result lists. History
recorded four Success results at 07:31–07:32. Closed all dialogs. QA remains on
Alpha with five neutral drafts. No data was sent and no permission requested.

This closes the ignored-initialQuery defect. It does not close every contract of
Window.showQuickSearch or Window.showCommandPalette. Dedicated host-error and
cross-window checks remain pending. The native state confirms fields and results;
it is not a new comparison with Drafts. Full Mac parity remains open.


### Native file save lifetime — 21 October 2026

Implemented: no production change. Added engine-file-lifetime-actions.json with
pending, production-timeout and recovery actions. Pending actions save neutral
text before export, then have an ERROR insertion and Archive on success. The
fixture does not change production timeout settings.

Automatically tested: all 14 NativeFileSelectionTests passed headlessly. They
include simulated late selection after cancellation, duplicate completion,
absolute deadline rejection, timeout closure and exact Unicode export. No new
automatic test opens a panel. The previous checked 617-core/501-app run and
unsigned build are unchanged. Matrix structure passed. Strict engine remains18.

Verified in use on the signed Engine QA image from the initial-query correction
(executable60d30be1b1c7fa47965f14e00a2fa5d3b6cdd3e1998759d2f488b3b9d07abc6b).
Imported the fixture. Opened pending Save and selected /tmp without saving.
Actions > Cancel Running Action closed the panel. History recorded Cancelled
07:34. Earlier File completed write remained in Alpha in Inbox. No ERROR tail
or Archive occurred. The target did not exist.

Opened the timeout fixture. Save showed /tmp and its distinct target name.
The panel was still visible85.4seconds after first observation and absent133.6s.
The120-second production limit was unchanged. This observation does not measure
exact teardown latency or distinguish host and selector deadline winners.
History recorded Error07:37: The action operation timed out before it completed.
Earlier File timeout completed write remained in Alpha; no tail or Archive.

The recovery fixture then opened Save with a third target in /tmp. Save completed
and History recorded Success07:37. Its bytes exactly matched Neutral file café 🐼,
a newline and Second line (35 UTF-8 bytes). Both interrupted targets remained
absent after recovery. This proves no observed late write in these native paths;
it does not prove an actual late AppKit completion was delivered. The headless
late-completion tests remain separate evidence. History is closed, Alpha is open
with five neutral drafts, and no action or Save panel remains pending.

Bookmark restart/access loss, owner close and capability-specific URL/Intent
variants remain pending. No personal data, permission or external destination
was used. The temporary output stays outside Git.

A parallel read-only Window review found independent defects. Group loading
resolves the serialized name rather than stable UUID. Reusing an old name after
rename can select another group. WorkspacePresentationResolver already has a
UUID-first rule. Tab opening uses a Void dependency and returns true before a
scene exists; AppController uses a0.2-second delayed attachment. Fixing only the
no-window return cannot prove tab completion. Add focused identity regressions
and correlate scene completion before closing these contracts. No production
fix for either issue is included in this acceptance change.


### Stable Window action group references — 21 October 2026

Implemented: ActionGroupReferenceResolver shares UUID-first lookup between
WindowActionAdapter and WorkspacePresentationResolver. It returns the current
name while retaining unknown reference fields. A supplied invalid or absent
identity throws before mutations. References without UUID keep name lookup.
No persisted format or identity changed. List-opening behavior is unchanged.

Automatically tested: WindowGroupReferenceTests has three methods, each with
both list and bar operations. Actual LibraryStore rename followed by reuse of
the old name exposed both methods selecting the wrong group. Missing identity
also exposed an incorrect name fallback and changed presentation. Name-only
compatibility passed before and after. The first test draft did not compile
because an editor helper accepts String values only; it now builds Workspace
metadata through JSON to preserve the unknown Boolean field. The compiled red
run reproduced the functional failures before the resolver edit. Corrected
methods pass, including malformed identity rejection and Workspace equivalence.
Checked runner verified 617 core and 504 app methods. Initial unsigned Xcode
build missed the new source. Regenerated the project and repeated successfully.
Matrix structure0 and strict global4136. No compatibility percentage inferred.

Verified in use: quit and refreshed Engine QA, signed and verified; NSServices0.
Executable SHA256 a1b4d6967fcf3d68a788215ca3ec54067f96036cadaacfffdd08adf9bd36446d.
Debug dylib SHA256 920a3ee79d330503ecf5d14686728f9a0ff582f34a74327aa258c3ea6c366608.
Imported window-group-reference-library.json into isolated QA. It adds two
neutral groups and an action, preserving the five existing drafts. The fixture
represents the renamed-state snapshot; it does not rename through UI. Its stale
ActionGroup name refers to another current group while its UUID identifies QA
Identity renamed. The action returned true from both loaders and kept source
text. Native list header showed QA Identity renamed. The bar menu screenshot
showed its check beside that same group. History recorded Success07:43. Closed
the menu and history. Alpha remains open; action panel is visible and both group
selections are the neutral renamed group. No external data or permission used.

This closes the internal stable-identity defect. Frozen Window prose does not
define stale references, missing-group error behavior or whether list loading
must reveal the panel. Preserve the existing behavior and keep those comparison
limits explicit. Tab scene completion remains a separate defect and next task.


### Correlated native tab opening — 21 October 2026

Implemented: WindowOpenRequestRegistry gives every opening request a UUID,
deadline and one final result. The existing library WindowGroup now accepts an
optional UUID scene value. AppController routes the request to its exact model
and native window. It loads the target draft and checks membership in the origin
tab group before returning true. Missing target, missing origin or unavailable
opener returns false. Removed the0.2-second window scan. Completed scene records
cannot reapply a draft on later key events. Failed requests retire their IDs;
late scene registration closes that target. Prior-process IDs take the normal
restored-scene path. Origin/target closure cancels pending owned requests.

The worker has an optional async UI hook for opening operations. JavaScript
remains synchronous from the script's perspective while MainActor suspends.
Replies revalidate execution and step, preserve typed timeout/cancellation and
drain cleanup. Existing sync UI access remains available. The legacy runner
uses a separate event-servicing adapter; the new worker path does not poll.
WindowAccessor now observes viewDidMoveToWindow instead of checking window
attachment only once. An event schedules registration after actual attachment.

Automatically tested: eight registry methods check actual-result return, inline
and duplicate completion, independent requests, timeout, absolute deadline,
cancellation, invalid limits and pre-cancelled tasks. Four adapter/controller
methods check unavailable dependencies/origins/targets, exact argument forwarding,
rejection, pending target close and rejected late registration. Three worker
methods check awaited true/false results, legacy fallback, MainActor availability,
cancellation/timeout cleanup, no later text edits and no Archive after failure.
All tests are headless and use neutral in-memory data.

Registry test drafts first had local variable redeclarations; fixed before the
eight-method targeted pass. Initial full run rejected a new worker timeout case
because its0.05-second fixture budget expired before the host hook started under
concurrent load. Increased that test budget to5seconds, matching the existing
cleanup-test approach. Production120-second limits did not change. Repeated the
checked full run: all620 core and516 app method identities verified. Unsigned
Xcode build passed after project generation. Matrix structure0; strict18/4127.
The failed run is not counted as acceptance and the runner did not retry it.

Verified in use: refreshed signed Engine QA only after native Quit and process
absence guard. NSServices remains absent. Executable SHA256:
ff4b3ac82766e5011dd575edfe64f193f0eeb99da08a7e8693593992693dcb19.
Debug dylib SHA256:
1fa20a0d47054c03548dfe6f7e514a82e428db4a76044285279bef6265412a77.
Imported window-tab-opening-actions.json. From Alpha, the action requested Zulu
and then Excluded. Native AX showed one tab group with Alpha, Excluded and Zulu;
Excluded editor held its exact neutral content. Switched to Zulu and confirmed
its editor. The script checked Boolean true after each opening and unchanged
source content. Alpha still held its original text. History recorded Success
07:54 and the expected confirmation message. Clicks on AX close-tab controls did
not remove tabs; native Command-W closed each test tab. Final state: Alpha,
one tab, five drafts, no pending action or dialog. No screenshots were saved.

This accepts sequential target success on the worker route. It does not accept
deliberately slow native creation, cancellation/timeout during scene creation,
source closure before creation, concurrent native opens, native restoration,
legacy-runner native opening or capability-specific URL/Intent variants. Those
remain explicit in the Window member record. No complete Window parity claim.


### Window list selection connection — 21 October 2026

Implemented: Window.selectedDrafts previously had no WindowModel selection hook.
The runner fell back to its current draft. Native list selection lived only in
LibraryView state. WindowModel now owns the IDs used by the native table binding
and the runner callback. The callback filters the current visible rows in list
order. Empty selection does not synthesize the editor draft. An editor identity
subscription updates IDs immediately; duplicate identity emissions do not
collapse multiple selection. Existing UI navigation behavior remains.

Automatically tested: WindowSelectedDraftsTests adds three both-runner contracts
for visible order, typed/shared Draft identity, independent returned arrays,
current editor preservation, empty selection, stale IDs and filtered-out rows.
The initial test draft referenced a helper in the other test target and did not
compile. Replaced it with a small suite-local builder. The compiled red run then
failed all three contracts on both runners. The selection connection passed the
same assertions. A fourth test covers immediate editor identity updates and
same-draft loads. Full working-tree run verified 623 core and 520 app identities;
it also includes the separate new WindowWorkspaceAccessTests suite. Unsigned
Xcode build passed. No new production file or format was added.

Verified in use: signed Engine QA refreshed after native Quit and absence guard;
NSServices0. Executable SHA256:
b17f3470cd6e853bf07160ee8d48cebc3700a40845cc47369ef3fb903c075c28.
Debug dylib SHA256:
869286ee3568fb807a28117c3301fd50e8810c8374b2a91aa11a2bbac12b0a65.
Imported window-selection-actions.json. Command-click selected Zulu and Excluded
while Alpha remained in the editor. The fixture checked both titles in visible
order, Draft instances, shared Draft.find identity and array independence.
History Success08:03. Selected Alpha, then Command-click removed its selection.
No rows remained selected. The empty-selection fixture passed with Alpha still
open; History Success08:04. No text or organization data changed. The fixture
also checked a detached current Workspace snapshot, recorded separately.

Repeated the tab success fixture and observed three tabs. Quit and relaunched
QA. The observed window was Untitled with one tab; all five stored drafts were
present. No prior scene request ID was observed being restored. This does not
accept native restoration and does not establish whether the cause is system
reopening policy, scene restoration or app selection persistence. Do not claim
it passed or attribute a regression without a baseline comparison. Selected
Alpha again. Final state: one Alpha tab, five drafts, no pending action/dialog.
Selection comparison with Drafts and external selected-reference updates remain
pending. Raw screenshots and logs stay outside Git.


### Window Workspace access contracts — 21 October 2026

Implemented: no additional production change. A separate test-only commit adds
WindowWorkspaceAccessTests instead of crediting the global app alias for every
Window member. Three methods run on both the legacy and worker paths.

The getter returns typed detached snapshots with exact identity, folder, query,
tags, exclusions, presentation and matching mode. Changing the first snapshot's
query and public archive-sort configuration does not change the next snapshot's
query result order. Tests use stored neutral notes and query results rather than
inspecting private JavaScript sort fields. Reads neither save nor apply.

The apply method forwards configured defaults when omitted, and exact explicit
folder/query/tags/exclusions/display options when supplied. Both calls return
true. An injected application failure stops the later editor write and does not
save a Workspace. This is access coverage, not acceptance of every evaluator,
group, theme, storage or native-window effect. Getter serialization failure is
still pending. No generic application failure is credited as a getter test.

Automatically tested: all three methods were included in the checked623core/
520app run recorded above. Unsigned Xcode build passed. Matrix structure0 and
strict global4107. These counts do not measure compatibility.
Verified in use: window-selection-actions.json also read an Inbox Workspace
with empty query, changed the detached query and read the unchanged real query.
History Success08:03 on the same signed selection image. No native apply was
added by this review. Native application and full Workspace closure stay open.

Final gate recheck:4107 diagnostics after the getter record explicitly retained
its missing serialization-error case. The preliminary4106 count preceded that
record correction. Structure remains valid; strict closure remains pending.


### Local scene draft references — 21 October 2026

Source review found a gap distinct from system window reopening policy. Unknown
prior-process scene request IDs were accepted, but LibraryView did not retain a
per-scene editor identity. It would create an empty draft in a restored model.
Added a String SceneStorage value for the current draft UUID, with no text or
shared library data. On appearance, explicit pending targets and existing editor
state take precedence. A fresh model restores the stored ID only if it exists.
An invalid or missing ID falls through to the existing startup flow.

Implementation reference: Apple's [SwiftUI state restoration guidance](https://developer.apple.com/documentation/swiftui/restoring-your-app-s-state-with-swiftui)
describes scene-local storage and leaves persistence timing to the system.
The [scene restoration modifier](https://developer.apple.com/documentation/swiftui/scene/restorationbehavior(_:))
controls scene behavior. These are implementation references, not changes to the
frozen Drafts reference. The app does not promise immediate SceneStorage writes,
change the system reopening policy or synchronize local scene references.

Automatically tested: four WindowDraftRestorationTests pass headlessly. A saved
Unicode draft restores with its UTF-16 selection, current selection IDs and an
access timestamp, without changing modifiedAt, content or revision history.
Invalid/missing IDs create no draft. Injected access-write failure leaves the
editor unloaded and permits retry. An existing target with pending text and
selection is not replaced or saved by a stale restored ID. Checked full runner
verified623 core and524 app method identities. Unsigned Xcode build passed before
the fourth test-only addition; production did not change after that build.

Verified in use: refreshed and signed Engine QA after native Quit/absence guard.
NSServices0. Executable SHA256:
3316ba606c910e41fbde27da07deee780c4a79562530f320df7890a88d1cb241.
Debug dylib SHA256:
c26e3a59aa9942570ee70e2bb8545d57641c0ee20fa12fdffd7c545a767af19c.
Repeated the existing neutral tab fixture. Three correct titles appeared in one
group. This is opening regression evidence, not restored-scene evidence.

A native app-menu snapshot exposed Quit and Keep Windows. Later fresh snapshots
did not expose that alternate. A modifier-only key request was rejected; an
Option-click menu request failed as offscreen. Option-Command-Q returned without
terminating the app; exact executable PID inspection and fresh AX confirmed it
was still running with three tabs. The alternate quit was not completed, so no
relaunch from that path was attempted or accepted. No system setting was changed,
no force quit was used and no normal Quit is credited as keep-windows acceptance.
Closed both target tabs with Command-W. QA ends on Alpha with one tab/five drafts,
no pending action or dialog. Native full scene restoration remains pending.


### Native HTTP and XML-RPC responses — 21 October 2026

Implemented: added transport-response-actions.json as a repeatable neutral QA
fixture. Its initial configuration requires an ephemeral loopback URL. It rejects
other hosts. No production source, reference or contract classification changed.
Start Tests/DraftlyCoreTests/Fixtures/http-server.py and enter its printed port.
Stop that server after the action completes. Use a new port on each repetition.

Verified in use: imported and ran the fixture in the signed Engine QA image
recorded in the previous scene restoration check. The local server used port
63016. Execution History showed Success at 08:23. HTTP checks covered typed
responses, Unicode JSON and text, returned headers, absent optional fields,
Latin-1 text, HTTP 503 and a recoverable disconnect. XML-RPC checks covered
Latin-1, UTF-16, and UTF-16 LE/BE without an HTTP charset. Fault codes -42, 0
and 42 kept their exact numeric value and Unicode error text. Malformed arrays,
HTTP 503, empty HTTP 204 and disconnect returned failure without invented fault
codes or success parameters. The server observed the corresponding requests.
URLSession retried the disconnected HTTP GET; this is not an extra action run.
The action checked that editor text remained unchanged. Alpha retained its five
neutral drafts and existing text. Closed History. Stopped the exact server
session after completion; no server or action remains pending.

This is native installed-app acceptance, not a comparison with Drafts. It does
not define the missing Date/binary mapping, otherData triggers, unfollowed 3xx
success policy, or exact Drafts error wording. Those partial contracts remain
partial. Constructor acceptance remains the existing automatic evidence; this
fixture does not exercise constructors directly. No permission, personal data,
remote destination, screenshot or raw log is required.

Automatically tested: all 11 methods in ScriptHTTPLocalServerTests passed with
their parameterized legacy and worker cases. Matrix structure has zero errors.
No production code changed, so this stage did not require a new app build. The
previous successful build identifies the installed binary used above.


### XML-RPC parameter transport acceptance — 21 October 2026

Implemented: added a neutral XML echo endpoint to the existing loopback fixture.
It parses the actual methodCall and returns its params in a methodResponse.
No production behavior or frozen reference changed. The specific JavaScript
case runs on both engines. Empty parameters return a typed successful response,
HTTP 200, an empty array, and no error or faultCode. A second request preserves
Unicode, XML metacharacters, Boolean values, a negative integer, a fractional
number, nested arrays and records, null, empty containers and string whitespace.
Mutating the reply does not change the input or the earlier empty response.
Both real POST requests are observed by the fixture.

Automatically tested: all 12 ScriptHTTPLocalServerTests methods passed, including
both runner cases for the new contract. This extends the parser-only composite
tests with actual request serialization, HTTP transport and JavaScript reply
conversion. Matrix structure passed. No production code changed; no new app
build was required.

Verified in use: imported the added QA XMLRPC parameter round trip action.
Configured the neutral server at ephemeral port 63900. Execution History showed
Success at 08:26. The server observed two POST requests to /xml-echo. The action
verified editor text unchanged. Closed History and stopped the exact server.
The installed binary is the same signed image recorded in the preceding check.
No permission, remote destination or personal data was used.

XMLRPC.request and XMLRPCResponse.params remain partial. This does not establish
Date/binary mapping, duplicate struct-name policy or undocumented invalid-input
behavior in Drafts. No compatibility classification was promoted.


### Manual fixture identity correction — 21 October 2026

Found a fixture defect before continuing native route acceptance. The new HTTP
response action reused BBBF0043-0000-4000-8000-000000000001 from the existing
Window tab action. Import replaced that QA action. The earlier transport checks
did run, but the imported catalog did not preserve both fixtures. Production
lookup and import behavior did not cause the defect.

Corrected both transport fixture IDs to the unused BBBF0045 namespace. Added a
headless check of explicit UUIDs in manual *actions.json array fixtures. It fails
with the original collision and passes after correction. It does not assert
uniqueness for backup or installation envelopes, which can intentionally reuse
identities. No application source or library format changed.

Verified in use: imported the original Window tab fixture again. Renamed the
old second transport action to QA XMLRPC parameter round trip — previous identity
through its inspector, then imported both corrected transport actions. The list
showed the two current transport names and the retained previous-identity action.
The command palette separately showed QA Window confirmed target tabs in Window
contract QA. No action was executed in this catalog repair. No action history,
note or preference was deleted. Closed the palette. The earlier successful
transport runs remain scoped to their observed scripts, not catalog isolation.

All 57 Python tooling methods passed. Matrix structure has zero errors and
git diff --check passed. No Swift source changed; no new app build was needed.


### Arrangement attempt and priority change — 21 October 2026

Attempted native navigation while QA Arrange pending operation was waiting.
The footer Arrange control opens a direct line-operation menu, not the awaited
Arrange dialog. Closed that menu, then ran the existing pending-operation action.
The real Arrange dialog displayed First, Second café 🐼 and Third. Window-menu
selection failed with elementHasNoFrame. Later AX reads showed a stale Window
menu and screenshots were unavailable. Finder still responded. A process sample
showed the main thread waiting for events; it did not prove an application hang.
The user reported closing the menu. Resetting the CUA connection did not recover
it. Normal Command-Q and reopening QA restored access. No force quit was used.

The neutral Alpha draft had then moved to Archive with the fixture's continuation
and tail text. A user cancellation returns the original text by contract and can
continue this fixture; task cancellation is different. The attempted interaction
therefore does not accept navigation or owner-close behavior. Restored Alpha's
observed 325-character content and returned it to Inbox through the native UI.
All five neutral drafts are again visible. Its modification date and revisions
reflect this test and restoration; no historical metadata rollback is claimed.
The full checked baseline passed 624 core and 524 app methods. The user then
prioritized inspector, Workspaces, Settings and personalization, followed by
visual comparison, capture and search. Arrangement acceptance stays pending.


### Action inspector step enablement — 21 October 2026

Implemented: expose Enabled in ActionStepInspector. An omitted isEnabled displays
as enabled, as both engines already require. The toggle writes the typed field
on the temporary action copy. Disabled step rows show Disabled. No execution,
serialization or backup rule changed. Imported platform settings remain preserved
but currently have no execution filter. Do not expose a working platform editor
until that rule is defined and implemented.

Added inspector-step-options-actions.json with a disabled neutral logging script,
an explicit unique identity and retained extra fields. The existing manual UUID
check passes. Existing disabled-step and imported-field tests cover execution
and storage; no test that only mirrors the binding was added.

Unsigned Xcode compilation passed. Quit QA normally, refreshed all code and
resources with the guarded updater, then signed and verified. QA Services remain
absent. Signed executable SHA256:
20019fe43794f3ac81644ddcfbac0e74d9df07cac48bd4d617fb80152699581b.
Signed debug dylib SHA256:
4939b63cbab8dcbbeea7de418af0c616c0d27ba4a15321d703810b586d979454.

Native import and Inspector QA action-list presence were observed. Context menus
opened but CUA lost them before Edit could be invoked. Native toggle, Save,
Cancel, reopen and execution differences are pending. No successful run is
credited to that unconfirmed click. Alpha retains its restored text. No full
inspector, Workspace, Settings or visual parity closure is claimed.

Final checked regression after the inspector change passed all 624 core and
524 app methods. Matrix structure has zero errors. The test runner verified
complete method identities; these totals do not establish contract parity.


### Action list options — 21 October 2026

Compared the installed Drafts action-list options menu. It contains Action Log,
Search, Action Group Bar, Show Keyboard Shortcuts and three action filters. All
were disabled because that reset Drafts library has no action groups. The group
manager independently confirmed an empty catalog. No reference groups were
installed, and no Drafts preference was changed. This inspection establishes
menu labels, not enabled behavior or a full visual comparison.

Implemented: Draftly now exposes Action Log, Search, Action Group Bar and Show
Keyboard Shortcuts in its action-list options. Search shares its button handler
and clears the query when hidden. The group-bar preference hides the footer and
its divider. The shortcut preference shows valid action bindings in each list
row. Both preferences are local AppStorage values. Group symbols, selection,
order, library formats and backups remain unchanged. Import and group management
remain available. The three reference action-filter modes remain pending.

Shortcut labels share the normalizer and supported modifier set with conflict
validation. Labels use control, option, shift and command glyphs in that order.
Missing modifier metadata retains the existing Option-Command default. Invalid
imported bindings produce no misleading label. Existing imported values and
conflicts are retained. A valid but conflicting shortcut still has its label.

Automatically tested: two specific cases cover normalized/default modifiers,
fixed glyph order, duplicate modifiers, Unicode keys, no modifiers and invalid
imported values. All four CommandShortcutTests methods passed. The final checked
regression passed all 626 core and 524 app methods. Unsigned Xcode compilation,
matrix structure and git diff --check passed. No automatic test opened a window.

Updated and signed the isolated QA app after normal Quit. Executable SHA256:
2d8ce425c576b8d5fe9666d783bc664273c91ccb092ae9e5fe775a1cda01bed9.
Debug dylib SHA256:
a24f1403da3440340266359fc30a7345183e240eaf2890cc61d06911269ad7d2.
The guarded updater verified signatures and retained Services isolation. QA
opened and its action panel appeared. CUA lost the options menu with a user-change
guard before a selection. Native toggle, persistence after restart, shortcut
row layout and enabled comparison with Drafts remain pending. Existing Enabled
inspector Save/Cancel acceptance is also pending. No parity closure is claimed.

Independent Workspace review found three source-level gaps: effective per-folder
sort differs from sort labels, absent list options use different editor/window
fallbacks, and unsaved Workspace display options are bypassed by list getters.
Reproduce them with focused tests before correcting production code. Keep those
functional corrections separate from this action-list preference change.

## Native Arrange Close All — 22 October 2026

Build: local Debug at 2af31c8. Isolated QA executable SHA256:
7cd18d48966da357583ed1a7517b4279dbb5b19db0c7e17ce9727cb1e8f89107.
QA had a unique app identity, a copied closed neutral library, no Services,
no normal URL registration and no CloudKit container. The habitual app stayed
unchanged. Reproduction: scripts/fixtures/engine-owner-close-arrangement-actions.json.

Computer Use imported the neutral actions and ran QA Owner Close Arrange Valid.
The Arrange dialog displayed First and Second café 🐼. Command-W did not close
it. File → Close was disabled; File → Close All was available. Close All removed
the dialog and cleared the source selection. Execution History showed Cancelled.
The source remained in Inbox with exactly Retained owner-close café 🐼. Neither
ERROR tail nor Archive occurred. A following action completed and appended only
Following action passed. Closed storage confirmed Cancelled and Success records
for the same note, retained text and isArchived false.

An initial manually constructed fixture had a literal newline inside a JavaScript
string and failed with Unexpected EOF. It did not reach Arrange and does not count
as lifetime acceptance. The corrected fixture above reached the panel before the
close operation. No production fix was needed. Direct individual-window closure,
stale navigation and URL/Intent variants remain separate checks.

QA quit normally. Process inspection confirmed absence. Its exact LaunchServices
path was unregistered. Runtime, exported preferences and closed library moved
recoverably to ~/.Trash/DraftlyEngineLifetimeQA-5f9007e3. No screenshots or raw
logs were added to Git. This observation does not close the engine strict gate.

## URL Prompt final callbacks — 22 October 2026

A fresh isolated Engine QA and the existing callback helper ran under Computer
Use. Both bundles had only their QA URL schemes. QA used a copied closed neutral
library, no Services and no CloudKit. The habitual app stayed unchanged.
Reproduction: scripts/fixtures/engine-url-prompt-result-actions.json. Open its
run URL with separate x-success, x-cancel and x-error destinations at the helper's
received endpoint. The target note in this session was already archived.

Observed native results:
- While Prompt was open, the helper showed zero callbacks.
- Prompt Cancel called context.cancel. The helper received exactly one callback
  with outcome=cancel. The prior persisted edit remained.
- A second run left Prompt pending at unchanged production deadlines. The panel
  closed and QA displayed The action operation timed out before it completed.
  The helper received exactly one outcome=error callback with that errorMessage.
- A following run accepted Prompt and received exactly one outcome=success
  callback with value=Accepted café 🐼. It ran the insertion step and completed.

Closed storage confirmed Cancelled, Error with the timeout message, and Success
for the same action and note. The final insertion used the retained selection;
it produced Retained UR AcceptedL prompt café 🐼. This session does not accept
Archive suppression after interruption because the note was archived before the
Prompt cases. Headless runner/Intent tests cover that separate assertion.

An earlier Arrange run in this session used the dialog's Cancel button. It
continued and sent success, as the archived Editor.arrange contract requires:
Cancel returns the original string. This is distinct from task cancellation or
source closure and is not a defect. The neutral tail sentinel from that action
was overwritten by the subsequent Prompt fixture. Do not classify this as a
cancelled action or reuse that sentinel as a failed lifetime check.

Automatic: 21 focused methods passed across NativeAsyncPromptTests,
ActionCallbackRouterTests and RunDraftActionIntentTests. Fixture identity checks
passed. The strict engine audit still reported 18 errors across six partial
contracts. No production source, deadlines or installed app changed.

QA executable SHA256:
da540b1e5ab358fc4fc1cac706bac770b8b18a902091a6a54e281d072a3b8e92.
Helper executable SHA256:
17a76bfcb8e05c9740c0dbc3ef4bce4c7cf5c1e8741c22dacc0341070afeae59.
Both apps quit normally. Process inspection confirmed absence. Exact paths were
unregistered. Apps, exported QA preferences and closed library were preserved
recoverably in ~/.Trash/DraftlyURLLifetimeQA-cxpjl39e. No screenshots or raw logs
were committed. Other native routes, SelectPrompt timeout and actual late panel
callbacks remain open; this is not full engine acceptance.

## URL SelectPrompt timeout and recovery — 22 October 2026

Current-image QA at cf956d6 used the callback cancellation correction. Isolated
library, app identity and URL schemes stayed separate from the habitual app.
Reproduction: scripts/fixtures/engine-url-selection-result-actions.json. The
source was selected in a visible window and started in Inbox.

Computer Use ran the action through the helper's explicit URL delivery. The
native SelectPrompt showed both title/subtitle rows. Filtering Other selected
the second row. The helper showed zero callbacks while the list remained open.
At unchanged production deadlines the list closed, QA displayed the timeout
message, and the helper received exactly one outcome=error callback with
errorMessage=The action operation timed out before it completed. The editor and
selected Inbox row retained exactly Retained selection café 🐼. Archive remained
available; the success-only final text and Archive did not run.

A following URL run opened a new list with empty search and the first row
selected. Filtering Other and accepting returned one outcome=success callback
with selected=two. Closed storage confirmed timeout Error then Success for the
same action/note, final text Selection accepted café 🐼 and isArchived true.
This accepts URL SelectPrompt timeout, current-selection result and recovery;
it does not prove actual late panel-callback delivery or all native routes.

Automatic: 36 focused Core methods across seven execution suites passed. Fixture
identity validation and matrix structural validation passed. Previous full app709
and local build belong to the same unchanged production source at cf956d6. No
new code or deadline change was needed for this session.

QA executable SHA256:
941d5911b0c0a4030e9e94a4b2394c90ff0ac1a83b112a6cf46ad218541bbfe7.
Helper SHA256 remains
17a76bfcb8e05c9740c0dbc3ef4bce4c7cf5c1e8741c22dacc0341070afeae59.
Both apps quit normally and process absence was confirmed. Exact paths were
unregistered. Apps, exported QA preferences and closed library were preserved
recoverably in ~/.Trash/DraftlySelectionLifetimeQA-37p7wtu_. Habitual app unchanged.
The strict engine gate stays open. No screenshots or raw logs were committed.

## Native URL shell lifetime — 22 October 2026

Current-image QA at b1584f9 ran shell through actual URL delivery and the callback
helper. The source was a new neutral Inbox draft, selected in its visible window.
QA had a separate library, identity and callback scheme, no Services and no
CloudKit. Reproduction: scripts/fixtures/engine-url-shell-lifetime-actions.json.

The pending action saved Retained shell URL café 🐼 before launching a shell
that ignored TERM and waited for a sleep180 child. Read-only process inspection
identified the exact parent, child, separate group and native temporary folder.
No process was controlled outside the action's normal UI cancellation path.

Observed outcomes:
- Actions → Cancel Running Action produced one x-cancel callback. Parent87342,
  child87343 and their temporary folder were absent after cleanup.
- Repeating and waiting for unchanged production deadlines produced one x-error
  with the timeout message. Parent87398, child87399 and their folder were absent.
  The editor retained the completed write and selected Inbox row; no tail or
  Archive ran. The helper showed zero callbacks while waiting.
- A following recovery action returned exactly Shell recovery café 🐼 from shell,
  saved it and sent one success callback with that exact value.
- Repeating pending work then closing its source with Command-W produced one
  x-cancel. Parent87755, child87756 and their folder were absent. Another recovery
  URL worked without the original window and displayed the saved draft again.

Closed storage confirmed Cancelled, timeout Error, Success, Cancelled and Success
for these runs on the same note. Final content was Shell recovery café 🐼 with
isArchived false. A transient Computer Use invalid-capture error occurred while
starting the owner-close case. Fresh observation recovered the existing run
confirmation; the action was not restarted or duplicated.

Automatic: focused15 app methods and2 Core cleanup methods passed, as did fixture
identity and matrix structural checks. No production source/deadline changed.
Previous local build at the same source passed. App Intent shell-specific native
acceptance and exact deadline-race ordering remain separate. This does not close
the six partial engine contracts.

QA executable SHA256:
585a4940752235c310c1c01d003241e571c3fc8ce65a3342cc742a41abe2f34b.
Helper SHA256:
17a76bfcb8e05c9740c0dbc3ef4bce4c7cf5c1e8741c22dacc0341070afeae59.
Both apps quit normally; exact process absence was confirmed. Exact app paths
were unregistered. Apps, exported preferences and the closed library were moved
recoverably to ~/.Trash/DraftlyShellURLQA-53c2nx7a. Habitual app unchanged.

## Mail handoff is not delivery — 22 October 2026

A real URL action with no recipients opened a neutral Mail composer. Before any
send, the helper received one success callback with mailStatus=sent. Closing the
composer showed Mail's explicit not-sent/save-draft warning. The neutral content
was discarded without sending. Closed QA history recorded Success and the tail.
This contradicted archived Mail.send(): true requires a successfully sent message.

The current NSSharingService composeEmail adapter cannot observe actual delivery.
It now rejects Mail.send before creating the service on both legacy and async
routes, with an explicit delivery-confirmation-unavailable error. Sharing remains
separate. This removes false success; it does not implement confirmed Mail delivery
or classify macOS Mail itself as unavailable. Mail.send remains partial. A future
confirmed-delivery adapter and authorized send/cancel acceptance are still needed.
Messages was not tested or changed by this finding.

The regression uses injected service factories, so a removed guard fails without
opening a real composer. Removing only the guards made both parameter cases fail;
restoring them passed. Full app713 methods passed with matching XML inventory.
Local Debug build, fixture identity and matrix structural checks passed. Core
source stayed unchanged; its prior integrated674 result remains separate.

Computer Use repeated the same URL on the corrected QA: one x-error contained the
explicit diagnostic, no neutral composer appeared and the tail did not run.
A following shell recovery URL returned one correct Unicode success. Closed
storage confirmed the old false Success and the corrected Error on the same
neutral action/note. No mail was sent. No personal message was edited.

Before QA executable SHA256:
11abf1ff703a1a48a706e2db4b78e183859aec02a8682142f96c237b9245d373.
After QA executable SHA256:
aeba9e2372ea10fe3f22782a1d277d65eb5c6d7c7f0e0752b5750e95db23c7e6.
Both QA/helper quit normally; process absence and exact path unregistration were
confirmed. Old/new runtimes, QA preferences and closed library were retained
recoverably in ~/.Trash/DraftlyMailLifetimeQA-7pj02op2. Habitual app unchanged.
Reproduction: scripts/fixtures/engine-mail-confirmation-actions.json.

Official AppKit docs reviewed through find-docs/Context7 on 22 October:
https://developer.apple.com/documentation/appkit/nssharingservicedelegate/sharingservice(_:didshareitems:)
and
https://developer.apple.com/documentation/appkit/nssharingservicedelegate/sharingservice(_:didfailtoshareitems:error:).
They describe sharing completion and user-cancel errors. The observed Mail
handoff does not prove send completion. Frozen Drafts reference stayed unchanged.

## Native file write permission loss — 22 October 2026

Isolated QA at 8257008 ran the tracked engine-file-permission-actions.json through
actual URLs. The source was selected in an Inbox window. A native folder picker
selected only the newly created neutral QA destination. Grant saved its bookmark
and wrote exactly Original neutral file café 🐼, then delivered one success.

Only that QA folder's owner write permission was removed (mode0500). The next
URL action saved Retained before file failure café 🐼 before attempting replace.
It delivered one error callback: You don’t have permission to save the file
“neutral.txt” in the folder “destination”. The file stayed exactly original; the
draft stayed in Inbox with its completed write and no tail or Archive. The folder
mode was restored to its exact prior value. Recovery reused the same bookmark
without another picker, wrote Recovered neutral file café 🐼 and returned one
success with saved=yes. Closed history confirmed Success, Error and Success.

This proves actual filesystem write denial and recovery. It does not prove TCC
privacy denial, revoked security scope, sandbox permission loss or stale-bookmark
recovery. Those outcomes remain separate; do not merge them into this acceptance.

Automatic: new lostDirectoryWritePermissionPreservesFileAndBookmarkThenRecovers
uses a real neutral temporary folder with restored permissions. It requires the
specific Cocoa fileWriteNoPermission error, original bytes and retained bookmark,
then successful replacement without another selection. All16 file-selection
methods passed. Local Debug build, fixture identity and matrix structure passed.
Production unchanged; no complete-suite rerun is claimed for this new test.

QA executable SHA256:
7c7c14ea2b6b69500fc69cc7249341e3e1171d22671a7c9fbf5e576fbbe47817.
QA/helper quit normally. Exact process absence and unregistration were confirmed.
Apps, closed library, preferences and neutral files were preserved recoverably in
~/.Trash/DraftlyFilePermissionQA-jr2q1ee9. Folder permissions were restored before
retirement. Habitual app and personal folders stayed unchanged.

## Native file Close All during export — 22 October 2026

QA at 1cbeda7 imported the existing engine-file-lifetime-actions.json through
File → Import. No fixture script changed. The neutral Inbox source was selected
before starting QA File pending operation through the helper's explicit URL.
The action saved its completed write and displayed NSSavePanel. Go to Folder
selected the new QA exports directory, with draftly-file-lifetime-1.txt pending.

File → Close was disabled by the panel. File → Close All was available. It
removed the panel and source selection, leaving an Untitled editor. The helper
received exactly one cancel callback. The intended file and all export directory
entries remained absent. The completed note stayed in Inbox without the tail or
Archive. This accepts the exposed Close All path; it does not claim an enabled
individual-window close control or an actual late OS panel callback.

The following QA File recovery URL displayed a fresh selector in the same neutral
exports folder. Save created exactly the expected35 UTF-8 bytes, Neutral file
café 🐼 followed by a newline and Second line. The helper received one success.
The cancelled target still did not exist. Closed history confirmed Cancelled and
Success on the same note; its completed text remained and isArchived was false.

Focused app25 and Core6 methods passed. Local Debug build and matrix structural
check passed. No production source or deadline changed. QA executable SHA256:
36f4f06829b5f1241f760883828d9213239a5b6ecc474fb79e27da53ec8468cb.
Both QA/helper quit normally; exact process absence and path unregistration were
confirmed. Apps, exported preferences, closed library and neutral export were
preserved recoverably in ~/.Trash/DraftlyFileCloseQA-c2vl4t8y. Habitual app unchanged.
TCC/revoked-scope and actual late panel completion remain separate obligations.

## Native Notes sharing service lifetime — 22 October 2026

Isolated QA at 4f3aea3 ran the tracked sharing-service-lifetime fixture through
actual URLs. The source was a neutral Inbox draft. The system picker displayed
the38-byte text file. Read-only inspection confirmed the exact prepared file.
Selecting Notes opened its real share extension with the attachment.

Cancel in the Notes extension delivered one cancel callback, removed the shared
folder, kept Retained sharing café 🐼 in Inbox and stopped tail/Archive. A first
coordinate click did not close the extension; fresh AX state exposed its Cancel
button and that explicit control completed cancellation.

The next run selected Notes again. While its Save dialog waited, the original
shared file still existed with exact content. Neutral identifying text was added
to a new test note. Save delivered one success with shared=yes; the temporary
folder was removed. The action saved Sharing completed café 🐼 and archived its
source. Closed history matched Cancelled then Success.

In Notes, a scoped search located only the created test note and its38-byte
attachment. After the original Draftly file was gone, opening the attachment in
TextEdit showed exactly Neutral sharing café 🐼, newline, Second line. This proves
the Notes service retained its own copy. The created note UUID was
5383C50D-1790-4FB1-BBA4-991C245C6074. Only that test note was moved to Notes'
Recently Deleted through its normal trash action. No permanent deletion occurred.
TextEdit and Notes opened for this check were closed. No personal note was edited.

Focused app17/Core6 methods, local Debug build, fixture identity and matrix
structure passed. No production code or deadline changed. This accepts Notes
service cancellation, completion and file handoff/copy lifetime. It does not
accept task cancel, timeout/owner close after handoff, other services or legacy
sharing. Supplemental archived Share contract remains unchanged.

QA executable SHA256:
c42ea8f7c42fc7027954bd6925f737d4dec3f48c0802d42b62ccd41896185f40.
QA/helper quit normally; exact process absence and path unregistration were
confirmed. Apps, exported preferences and closed library were retained recoverably
in ~/.Trash/DraftlySharingServiceQA-c2btg1qg. Both temporary share folders were
absent. Transient invalid-capture/frontmost errors were resolved by observing the
same sessions; no action was restarted because of an observation error.
Habitual app unchanged; no screenshots or raw logs committed.

## Native sharing timeout after handoff — 22 October 2026

QA at 827f54f used the existing sharing-service-lifetime fixture. The source was
moved back to Inbox before execution. Its URL opened Notes with the38-byte file.
The helper showed zero callbacks and the file remained exactly readable while
Notes waited. At unchanged production deadlines, the action delivered one error
callback with the timeout message. The completed draft text stayed in Inbox;
tail and Archive did not run. The handed-off file remained readable after timeout.

A shell recovery URL completed BEFORE the old Notes dialog was closed. It returned
one success with exact Unicode output while the old file remained retained. The
read-only QA inventory showed two visible windows. Notes was behind the source
and absent from its Window menu. Accessible menu Cancel closed that menu; minimizing
only the QA source exposed the old Notes dialog. No process restart was needed.

Cancel in that old dialog then removed the old temporary folder. The helper stayed
at one success for the recovery request: no extra cancel/error/success arrived.
Closed storage confirmed only timeout Error then recovery Success for this session,
with unchanged recovery content and isArchived false. No Notes item was saved.
This is actual late provider cancellation, not a simulated callback. It accepts
Notes handoff retention, production timeout, cleanup and isolation from a later
execution; task cancel/owner close and other services remain separate.

Focused app17/Core2 methods, local Debug build and matrix structural check passed.
No production code/deadline changed. QA executable SHA256:
3026d63f7bb9da6e616848b9848c764f31462b00b763087ec5994220f78360d4.
QA/helper quit normally; exact process absence and unregistration were confirmed.
Apps, exported preferences and closed library were retained recoverably in
~/.Trash/DraftlySharingTimeoutQA-19mcp3wz. The shared folder was absent before
retirement. Habitual app unchanged. No screenshots or raw logs were committed.


## Integrated engine regression — 22 October 2026

At 709821e, the complete headless runner passed 674 Core methods and 716 app
methods. The runner compared both XML reports with test discovery. No methods
were missing, duplicated or skipped. App tests ran serially. All 68 Python tests
passed. Local Debug compilation passed after the tests. No retry or deadline
change was used. Logs and XML remain outside the repository in
`/tmp/draftly-engine-current-2026-10-22`.

This run includes the Mail final-report cases and the file permission regression
added after the previous complete run. It adds no native acceptance. The strict
engine gate still reports 18 diagnostics across six partial contracts. Continue
from `research/engine-native-checklist.md`, including sharing task cancellation
and owner closure after service handoff. Confirmed Mail delivery still requires
an implementation and an authorized recipient. The habitual app was unchanged.


## Native sharing task cancellation after handoff — 22 October 2026

At 94aa77f, an isolated QA copied the closed neutral library. A cold URL run
used a headless execution owner while the visible window remained Untitled.
Its Cancel Running Action item was disabled. Notes Cancel returned one cancel
callback. This does not accept task cancellation from that unrelated window.

The draft was then loaded through its open URL. A second sharing URL selected
Notes and displayed the actual extension dialog. Window selected the source
draft; Actions now enabled Cancel Running Action. That command returned exactly
one cancel callback. The prepared 38-byte Unicode file remained readable while
the Notes provider was pending. The completed script text stayed in Inbox; the
success tail and Archive did not run.

A following shell recovery URL succeeded before the old provider closed. It
returned one success callback with `value=Shell recovery café 🐼`. Minimizing the
source exposed the old Notes dialog. Its actual Cancel removed the old file.
The receiver remained at one recovery success with no extra callback. Closed
storage recorded Cancelled, Cancelled and Success for these three runs. The
final draft held the recovery text in Inbox. No Notes item was saved.

QA executable SHA256:
6c87f6ee73dff21712187281f8ea4df70b0787414e14a0299084b019cabb440d.
No production code or tests changed. The preceding complete regression applies
to this production source. QA and helper quit normally. Process absence and
exact LaunchServices unregistration passed. Apps, preferences and the closed
library remain recoverable in `~/.Trash/DraftlySharingCancelQA-r3c4x1dx`.
The habitual app was unchanged. Owner closure after handoff remains pending.


## Native sharing owner closure after handoff — 22 October 2026

At bb9a10f, a loaded neutral draft ran the sharing fixture through URL. Notes
opened its actual extension dialog. Window selected the source. Its enabled
close button closed that window and returned exactly one cancel callback. The
prepared file still contained all 38 UTF-8 bytes. Read-only QA storage confirmed
the completed script text in Inbox, without the success tail or Archive.

A following shell recovery URL succeeded before the old Notes dialog closed.
The receiver reported one success with `value=Shell recovery café 🐼`. The new
source window was minimized to expose Notes. Actual provider Cancel removed
the retained file without another callback. Closed storage recorded Cancelled
then Success, with final recovery text in Inbox. No Notes item was saved.

QA executable SHA256:
3f76c853c19b34de0bdf3584cd3e31562c1da2a8cc13d40bd33471b2b46ab45a.
No production code or tests changed. The complete regression recorded above
continues to apply. QA and helper quit normally; exact processes were absent,
and exact LaunchServices paths were unregistered. Apps, preferences and closed
library remain recoverable in `~/.Trash/DraftlySharingCloseQA-abbi4wsp`.
The shared file was absent. The habitual app was unchanged. This accepts Notes
owner closure after file handoff on this URL path, not every sharing provider.


## Location authorization cancellation race — 22 October 2026

A deterministic headless test cancelled the location task while authorization
was pending. It delivered authorization and a location before the queued
MainActor cleanup. Before the correction, the driver started updates and the
request returned success. The new regression failed on both observations.

NativeLocationRequest now records cancellation synchronously in a locked
per-request state. Authorization checks that state before starting updates.
Final delivery rejects cancellation, and the public async return also checks
the task. Cleanup still stops updates and invalidates the driver once. The
regression passes with zero starts and CancellationError. It uses no location
service, privacy prompt, window or personal coordinates.

All 51 focused location/sharing/file/callback methods passed. Complete Swift
verification passed 674 Core and 717 app methods, matched against discovery.
Local Debug compilation and matrix structure validation passed. No retry or
deadline change was used. Python source was unchanged; the preceding 68-test
result is separate. This controlled race test does not accept native macOS
authorization outcomes. No QA app was launched or habitual app replaced.


## Speech completion cancellation race — 22 October 2026

At 24fb4a5, a headless speech driver waited for completion. The test cancelled
the task and delivered completion before MainActor cancellation cleanup ran.
Before the correction, playback returned success, showed the completion notice
and did not stop the driver. The new regression failed on all three effects.

SpeechPlayback now checks cancellation after its continuation resumes. A
cancelled return stops the driver through one guarded cleanup operation and
throws CancellationError before the completion notice. The existing queued
cancellation path uses that same stop operation. The new test passes without
creating a synthesizer, window, permission prompt or sound.

All 31 speech, transcription and location methods passed. Local Debug compilation
passed. No retry or deadline changed. The previous complete 674 Core / 717 app
run predates this change; it is not a complete run for the new regression.
Native audio and permission acceptance remains separate. No QA was launched
and the habitual app was unchanged.


## Native location URL timeout and cancellation — 22 October 2026

At 8d60429, isolated QA imported the neutral location fixture and loaded its
source draft before URL execution. The script saved retained text, then called
Location.currentLatitude without recording its value. No authorization dialog
was observed in the QA window or app inventory. No privacy setting changed
and no permission was granted. The real request reached its unchanged timeout
and returned exactly one error callback with the timeout message. This does
not establish denied authorization or unavailable services.

A second URL run was cancelled through Actions > Cancel Running Action while
location was pending. It returned exactly one cancel callback. Read-only QA
storage confirmed retained text in Inbox with no success tail or Archive. A
following shell recovery URL returned one success with the exact Unicode value.
Closed storage confirmed Error, Cancelled, Success and final recovery text in
Inbox. Actual driver stop/delegate state and late OS callbacks were not directly
observed; those assertions still have separate injected coverage only.

The reproducible import is `scripts/fixtures/engine-location-lifetime-actions.json`.
QA executable SHA256:
fb1d02b3b050e237e60993291f309faf14fa61612afeea12f72a88e614a08d40.
Production code and tests were unchanged. QA/helper quit normally. Exact process
absence and LaunchServices unregistration passed. Apps, preferences and closed
library remain recoverable in `~/.Trash/DraftlyLocationQA-pamo_0rl`. The habitual
app was unchanged. Native permission outcomes remain pending.


## App Intent shell process interruption — 22 October 2026

The new RunDraftActionIntentTests case calls actual perform() with the native
action host, an in-memory library and a real neutral shell with one child.
Separate cases cancel the Intent task or reach the configurable host timeout.
Both require typed final reasons before checking that parent and child process
groups no longer exist and the shell temporary folder is gone. The test checks
retained Unicode text in Inbox, empty success parameters, no later step or
Archive, released library ownership and a following successful Intent. History
is checked by action identity.

The first fixture assumed history insertion order and failed; it now resolves
entries by action ID. The next run exposed a partial readiness-file read. The
shell now writes a pending file and renames it before the test consumes it.
No production code, retry or deadline was changed for those fixture defects.
The final 27 Intent/process methods passed. Local Debug compilation and matrix
structure passed. No windows, permissions, sound or personal data were used.

This proves real process cleanup through perform() in the test environment.
It does not accept system delivery from Shortcuts or every native capability.
The previous complete Swift run predates this new method. The habitual app
was unchanged.


## Dictation permission cancellation race — 22 October 2026

At 52f2e60, a new headless regression cancelled while speech or microphone
authorization was pending. It delivered the grant before queued MainActor
cleanup. Before the correction, the speech grant configured recognition and
requested microphone access; the microphone grant started capture. Both cases
failed their no-effects assertions.

DictationSession now records cancellation synchronously in locked per-session
state. Phase transitions and capture/display work check that state. Final
delivery also rejects cancellation. The two regression cases pass with no
next permission request, recording start or recorder presentation after cancel,
and exactly one cleanup. No actual microphone, window or permission is used.

The 30 focused dictation/transcription methods passed. Complete Swift reports
matched discovery: 674 Core and 720 app methods. All 68 Python tests, local
Debug compilation and matrix structure passed. No retry or deadline changed.
This complete run includes the earlier speech race and actual Intent shell
cleanup tests. Native dictation permission acceptance remains separate. The
habitual app was unchanged.


## Composition callback deadline — 22 October 2026

At 02cf08f, a controlled clock advanced to the composition deadline or beyond
it during driver startup, before the queued timeout task ran. Both new cases
incorrectly returned sent. MessageCompositionWait now retains its absolute
deadline and checks it when a service callback arrives. The exact boundary and
the later completion return timeout, detach once and ignore a repeated callback.
The injected clock defaults to Date; production limits did not change.

All 21 composition/Intent methods passed, as did local Debug compilation and
matrix structure. Tests used only injected composition drivers and neutral
process fixtures. No Mail message, composer, permission or QA app was opened.
The previous complete 674/720 run predates this new regression. Native Messages
acceptance and confirmed Mail sending remain pending.

Mail investigation: the archived Mail.send contract opens the Mail window and
returns true for a successful send. Apple documents didShareItems as a sharing
completion, but the earlier native Mail observation showed it before send. See
[the delegate reference](https://developer.apple.com/documentation/appkit/nssharingservicedelegate/sharingservice(_:didshareitems:)).
The installed Mail scripting dictionary offers a send command with a Boolean
result. Calling it directly would not preserve the documented user composition
flow. No such replacement was implemented. The user authorized one neutral
message to a named recipient in chat. No message has been sent; the recipient
is not stored in repository fixtures. Authorization is no longer the blocker
for that one message. A reliable send/cancel implementation is still required.


## Print owner-close observation limit — 22 October 2026

At 4f66e62, isolated QA imported the unchanged print-lifetime fixture. Two URL
runs reached the native one-page print panel. Both ended with one cancel
callback. The source retained the completed write in Inbox without the error
tail or Archive. The first panel disappeared during an observation that reported
user interaction. During the second run, File Close was disabled. File Close
All left the print panel visible in the immediate observation. Window source
selection also reported user interaction; the next observation showed the panel
gone and one cancel callback. The user reported that it worked.

Do not infer which close operation ended either run. Owner-close acceptance
remains pending because the input sequence was not isolated. A following shell
recovery URL returned one success with the exact Unicode value. Closed storage
confirmed Cancelled, Cancelled, Success and recovery text in Inbox. No physical
printing or PDF save was requested. No production code or tests changed.

QA executable SHA256:
b68ccd1dd9bf9d8c207b9968cf7c8cb0cc1323ae8bcfa19b11141723da62dace.
QA/helper quit normally; exact process absence and LaunchServices unregistration
passed. Apps, preferences and closed library remain recoverable in
`~/.Trash/DraftlyPrintCloseQA-p1sumtoi`. The habitual app was unchanged.


## Messages handoff is not delivery — 22 October 2026

At 1522028, isolated QA ran the neutral Messages fixture through URL. Its
recipient list was empty. Before any send, the action returned success, ran its
error-marked tail and archived the draft. Messages displayed an unsent new
composition with the exact neutral body and an empty To field. Only that body
was cleared; the window and app were closed. No message was sent. No private
conversation content was copied to repository artifacts.

The legacy and async adapters now reject this unverifiable service before
composition. They return an explicit Message.send delivery-confirmation error.
This prevents false success effects but does not implement confirmed sending;
Message.send is partial, not unavailable on macOS and not accepted as parity.
Safe factories prove neither route opens a service. Both runners and actual
Intent.perform preserve prior writes, stop tails/Archive and return error.
The runner tests also prove following recovery. The first integrated attempt
failed because the new fixture did not retain the weak host. Retaining it fixed
the fixture; no production lifetime rule or test deadline changed.

The first native repeat mistakenly copied only the Debug executable, leaving
the old Draftly.debug.dylib. It repeated the old false-success behavior and is
not corrected-build evidence. Its neutral unsent body was also cleared. The
complete current app package was then copied and signed. Debug QA updates must
copy the complete package, including code libraries, rather than the launcher.

On that corrected package, the same fixture returned one explicit error callback
and Messages remained stopped. No new composer or tail appeared. Following shell
recovery returned one success with the exact Unicode value. Closed history
confirmed two old Success records, corrected Error, then recovery Success.
The draft was already archived by the old defect and remained archived; native
non-archiving is not claimed from this state. Headless tests start in Inbox.

Complete Swift reports matched discovery: 674 Core and 724 app methods. All 68
Python tests, local Debug compilation and matrix structure passed. The new
factory regression failed before the correction and passed after it. No retry
or deadline inflation was used. Native acceptance here covers explicit failure
and recovery, not successful delivery or user-cancel parity. The fixture is
`scripts/fixtures/engine-messages-lifetime-actions.json`.

Corrected QA SHA256, launcher:
bb9e86b1eea32153dcf5534339a6a440fdb977b2456b9bea313221fb01514b51.
Corrected QA SHA256, Draftly.debug.dylib:
cc8ec7c33a7f1e2d4ec9c5fa209dc1946ebbdb84f86f9cabca65586476f96d55.
QA/helper quit normally; exact process absence and LaunchServices unregistration
passed. Before/after packages and closed libraries remain recoverable in
`~/.Trash/DraftlyMessagesQA-dw_456s4`. The habitual app was unchanged.


## Dictation phase deadline enforcement — 22 October 2026

At b601442, controlled-clock tests advanced to or beyond the active deadline
inside a speech grant, microphone grant or recording update. All six cases
incorrectly advanced or returned success before the queued timeout task ran.
The regression does not wait for a physical microphone or an OS permission.

DictationSession now retains each phase deadline. Its transition checks reject
expired authorization before the next permission or capture starts. Recording
updates cannot display expired text. Final delivery checks the deadline too,
so Done cannot return earlier partial text at expiry. Cancellation keeps its
priority over timeout. Each timely phase still receives its own full timeout;
this is not a single deadline for all three phases. Production limits are
unchanged, and the injected clock defaults to Date.

All 33 dictation/transcription methods passed. This includes the six red/green
cases, a timely three-phase run and an expired Done case. Local Debug compilation
and matrix structure passed. No retry or deadline inflation was used. The prior
complete 674 Core / 724 app run predates this change. Native dictation permission
and recording acceptance remains separate. No QA or habitual app was opened.


## Location callback deadline enforcement — 22 October 2026

At 022c3bb, four controlled-clock cases delivered authorization or coordinates
at or after the deadline before the queued timeout task ran. The request
returned coordinates, and an expired authorization also started updates. All
four cases failed before the correction.

NativeLocationRequest now retains an absolute deadline from request startup.
Authorization checks it before starting updates. Final delivery converts an
expired callback to timeout, with cancellation retaining priority. Cleanup
stops and invalidates the driver once. The clock is injectable and defaults
to Date. The production 30-second limit did not change.

All 46 focused location/dictation/composition methods passed. Complete Swift
reports matched discovery: 674 Core and 728 app methods. Local Debug compilation
passed. The strict engine gate still reports 18 diagnostics across six partial
contracts; this is not a parity pass. No retry or deadline inflation was used.
The previous 68 Python result is separate; Python source was unchanged.
No permission, location capture, QA window or habitual app was used. Native
location outcomes remain limited to the earlier recorded URL cases.


## Transcription phase deadline enforcement — 22 October 2026

At ba0d315, controlled-clock callbacks completed authorization, file selection
or recognition at or after expiry. Before queued timers ran, all six cases
advanced or returned success. The regression failed before the correction.

Each TranscriptionPhase now owns its absolute deadline and injected clock.
Completion checks expiry before delivering a result; the existing cleanup runs
first. An expired grant cannot configure or open a picker, an expired selection
cannot start recognition, and expired recognition cannot return text. The timer
uses the remaining phase time after startup. The default clock is Date and
production limits remain unchanged. A cancellation result keeps its own reason.

All 36 dictation/transcription methods passed. Besides the six red/green cases,
tests verify independent timely phase budgets and picker cancellation at expiry.
Local Debug compilation and matrix structure passed. No retry, deadline increase,
window, audio or privacy permission was used. The prior complete 674 Core /
728 app result predates these new methods. Native recognition and permission
acceptance remains separate. The habitual app was unchanged.


## EventKit callback cancellation and deadline boundaries — 22 October 2026

At 82cc2a2, controlled-clock EventKit waits returned success at and after expiry
and skipped underlying request cancellation. A second deterministic test queued
a completion before cancelling the task in the same MainActor turn. That wait
also returned success and skipped cleanup. Both regressions failed before the
correction. A callback before expiry remained valid.

EventKitCallbackWait now records cancellation synchronously, retains an absolute
deadline, and checks both when it delivers a callback. Cancelled or expired waits
invoke their cancellation token once. Timely success releases the token without
calling it. The timer uses remaining time after startup. Final return checks
task cancellation. Default production timeouts did not change.

All 20 EventKit wait/dialog methods passed. Complete Swift reports matched
discovery: 674 Core and 733 app methods. Local Debug compilation passed. The
strict engine gate still reports 18 diagnostics across six partial contracts.
No retry or deadline increase was used. Previous Python68 evidence is separate;
Python source was unchanged. These tests use injected authorization/fetch
callbacks, no EventKit permissions or personal records. Native Calendar and
Reminders acceptance remains pending. The habitual app was unchanged.


## Native Calendar default query and authorization — 22 October 2026

At 89fde30, isolated QA imported the read-only Calendar fixture. The first URL
run saved its neutral prior text, then returned exactly one access-denied error
callback. It did not run the completion text or calendarAvailable parameter.
The source retained its prior archived state; no new Archive effect was tested.
A following shell recovery returned one success with the exact Unicode value.

Computer Use could not inspect UserNotificationCenter because that app is
blocked by its safety policy. No alternate automation was used. The user
confirmed the Calendar access prompt and explicitly authorized full Calendar
access for QA. QA was reopened and the same query returned one success with
calendarAvailable=yes and stored the neutral completion text. It did not export
calendar names, identifiers or event contents. The Calendar API requires full
access, but this fixture reads only the default calendar and creates no records.

After a normal Quit, exact process absence was checked. A new process ran the
same query successfully with the same parameter. Closed QA history confirmed
access-denied Error, recovery Success, query Success and reopened query Success.
The user handled the permission UI; no agent privacy-setting change occurred.
This accepts native default-calendar lookup, its access-denied result, final URL
reports and successful lookup after restart. It does not accept event fetching,
Calendar writes, Reminders, pending-authorization cancellation or late OS replies.

The reproducible import is `scripts/fixtures/engine-eventkit-query-actions.json`.
Its manual-fixture test and matrix structure passed. Production code was
unchanged; the preceding complete 674 Core / 733 app result and local build
apply to this source. Corrected QA SHA256, launcher:
4b8ee99ae4e49670fdb48881fbaa84afe09377dabc506a805cd24e64de94536d.
QA SHA256, Draftly.debug.dylib:
a401d7c00a25dce8dc43a4d1af7980854ba33e6222bd050a00dd89788b420a05.
QA/helper quit normally; exact process absence and LaunchServices unregistration
passed. Apps, preferences and closed library remain recoverable in
`~/.Trash/DraftlyEventQueryQA-q58vi1ol`. The habitual app was unchanged.

## Authorized Mail composition investigation — 22 October 2026

The isolated Engine QA app used the production code from `89fde30`. Its full
Debug bundle included the debug library. The main app was not replaced.

Native AppleScript actions queried the Mail version and the outgoing-message
count. Both returned one success callback. No new Automation prompt appeared.
The version query alone does not prove Automation authorization.

The user authorized one neutral message to a specific test recipient in chat.
One action created one visible outgoing message. Computer Use checked the
composer and clicked Send once. A read-only query of the exact test subject
returned no Sent records before Send and one record after Send. A second
read-only query checked only that record. Subject and recipient matched. The
record had an RFC Message-ID. The outgoing object no longer existed. The exact
body comparison failed after paragraph normalization. Its cause is unresolved.
No recipient address or message content is stored in this record.

Mail used different object IDs for the outgoing and Sent records. Disappearance
of an outgoing object cannot distinguish Send from Cancel. This experiment
does not accept `Mail.send()`: the current adapter still rejects unconfirmed
delivery, and no replacement correlation rule was implemented. A Sent record
also does not prove delivery to the recipient. No second message was sent.

QA and its callback helper quit normally. Their exact LaunchServices entries
were removed. The closed QA library, preferences and packages remain recoverable
in the Trash. The user's Mail app and the sent test message were retained.
Production code did not change. The earlier Core674/app733 build and tests apply
to the unchanged production code; this session did not rerun them.

## Speech notice cancellation boundaries — 22 October 2026

At `8ef988d`, silent presenter tests cancelled the current task immediately
before returning a notice response. Both completion responses returned normal
results. A rejected initial confirmation also returned false instead of task
cancellation. All three cases failed before the fix.

NativeSpeechRequest now checks cancellation after each notice response, before
returning or deciding whether to create a driver. The regression cases pass.
They use injected drivers and presenters: no windows, permissions or audio.
Existing rate, voice, playback cancellation and cleanup cases still pass.

Complete Swift runs passed: Core674 and application735. Machine-readable
results matched the discovered test inventory. The local Debug app compiled.
The structural matrix check passed. Strict engine acceptance still reports
18 diagnostics for six partial contracts. No timeouts or retries were changed.
Python was not rerun; no Python code changed. Native synthesis and notice-panel
cancellation still require a separate manual session. The usual app was not
replaced. This fix does not accept those native cases or complete the engine.

## Native process exit deadline — 22 October 2026

At `8d35651`, controlled-clock process tests returned exit status zero at and
after the configured deadline. The before-deadline case passed. The executor
relied on the timeout task instead of checking expiry at termination delivery.
A second real process fixture exited its parent while a child ignored SIGTERM.
Before the fix, it returned success and left that child running. The fixture
cleanup killed the child after the failed assertions.

The executor now records the deadline before launch and checks it before
accepting termination. Expiry enters the existing interruption and process-group
cleanup path. The parent-exit fixture now returns timeout and removes the child.
The clock remains injectable for tests; production uses Date. Explicit launch
errors and the production timeout values remain unchanged.

All19 process/Shortcut test methods passed, including the three clock cases and
the remaining-child case. Complete Swift runs passed Core674/application737;
XML results matched the discovered inventory. All68 Python tests passed. The
local Debug app compiled and the structural matrix check passed. No retries or
longer deadlines were added. Tests used temporary files and local processes.

No manual UI session was needed for this executor correction. It does not accept
system-delivered Shortcuts or additional App Intent routes. The usual app was
not replaced. Strict engine acceptance remains pending for six partial records.

## Native speech cancellation blocks the main thread — 22 October 2026

The isolated Engine QA app used the full local Debug bundle from `2c8a456`.
Its debug library SHA256 was
`4c101b389816a8cc76b07e3b547280c3e1b3e477a0316fd68ac4d07490ed2bf8`.
The main app was not replaced. The new library started with zero drafts.

Three reproducible neutral actions are in
`scripts/fixtures/engine-speech-actions.json`. Only QA Speech completion ran.
A URL requested it on a neutral draft. Computer Use accepted the action
confirmation and clicked Read in the native confirmation panel. The receiver
remained at zero callbacks. The expected completion panel did not appear.
The Actions menu still opened and exposed Cancel Running Action.

Computer Use selected Cancel Running Action. QA then stopped answering UI
requests. The receiver remained responsive with zero callbacks. A process
sample showed the main thread in SpeechPlayback.finish -> stopPlayback ->
SystemSpeechDriver.stop -> NSSpeechSynthesizer.stopSpeaking -> semaphore wait.
An audio worker was waiting inside CoreAudio output-device initialization.
This is a failed native check, not accepted synthesis or cancellation. The
underlying audio condition does not justify blocking MainActor during cleanup.

The exact QA executable and PID were checked before SIGTERM. Only the blocked
QA process was terminated. Its helper quit normally. Both processes were
confirmed absent and their exact LaunchServices registrations were removed.
The closed QA library, preferences, packages and process sample remain
recoverable in the Trash. The retained source text remained in Inbox. No
completed run record was found; termination is not a final engine response.

The long playback and confirmation-timeout fixtures were not run. No audio
completion, stopped output, timeout, recovery or late callback is accepted by
this session. No system speech service was killed and no audio settings or
permissions changed. No production code changed. The fixture identity test and
structural matrix check passed. Existing Core674/app737/Python68/build results
apply to unchanged production code; they do not cover this observed OS block.

Next fix: isolate native synthesis and its blocking cleanup from MainActor.
Cancellation and timeout must finish cleanup without waiting on an unbounded
speech-system call. Preserve voice identity, rate, panels and final results.
Repeat this native case and a successful following action after that fix.

## Speech helper isolation and native recovery — 22 October 2026

The failure recorded above was corrected in the asynchronous speech route.
NSSpeechSynthesizer now runs in a private mode of the Draftly executable.
The parent awaits an owned process with cancellation and deadline cleanup.
The launcher enters helper mode before preferences or SwiftUI initialize.
Text, voice identity and rate pass through a private request file.

Tests preserve the existing notice and driver contracts. New tests check exact
Unicode and voice/rate transport, Boolean results, helper errors, malformed
responses and helper-mode validation. Real silent helper fixtures ignore TERM.
Cancel and timeout must reap them before request-file removal and return the
correct typed reason. A held cleanup fixture proves the playback result cannot
return before driver cleanup. A timeout cannot show the completion notice.
All33 speech/AppleScript test methods passed. Full Swift runs passed Core674 and
application745; XML results matched discovery. All68 Python tests passed.
The local Debug build passed after regenerating the project to include the new
source file. Structural matrix validation passed. Strict engine acceptance
still reports six partial contracts and 18 diagnostics.

A separate manual session used the complete corrected Debug bundle in Engine QA.
The debug library SHA256 was
`7bfe58e99f7ccd5ebe375bcc8f09c7dc6775272c495ddb2d6996b340f58ca02c`.
The session started with an empty isolated library. Computer Use imported
engine-speech-actions.json and ran QA Speech completion through a URL. After
Read, the actual helper process and its private request folder were observed.
The Actions menu remained available. Cancel Running Action returned exactly one
x-cancel callback. The helper and folder were absent before the final callback
was inspected. The retained source text stayed in Inbox with no completion
text. A following real shell action returned one success callback with exact
Unicode output.

A second run of the same short-phrase action exercised the unchanged production
timeout. Its actual helper remained live and the receiver had zero callbacks
through approximately97 seconds after the live-process observation. After the
configured120-second limit, the receiver showed one x-error callback: The action
operation timed out before it completed. The helper and private folder were
absent when inspected at approximately134.5 seconds. No precise timer latency
is inferred from that observation interval. The retained source text remained
in Inbox. A following real shell action again returned exactly one success.
Closed history records were Cancelled, Success, Error and Success in that order.

QA and the callback helper quit normally. Exact process absence, private-folder
cleanup and LaunchServices unregistration were checked. Their packages, closed
library and preferences remain recoverable in the Trash. The usual app was
not replaced. No shared speech service was terminated and no audio setting or
permission changed.

This accepts URL speech task cancellation, production timeout, cleanup and
following recovery for this implementation. Audible successful completion,
output-stop confirmation, individual owner close and capability-specific
Intent delivery remain pending. The audio subsystem did not complete the short
phrase on this Mac. The new isolation fixes the parent-app hang; it does not
claim to repair the operating system audio condition. The legacy synchronous
speech path is unchanged and is not accepted by this session.

## Process cancellation before queued cleanup — 22 October 2026

At `e312a3e`, controlled-clock tests cancelled the owner during process exit
delivery, before its MainActor interruption task ran. A completed process
returned status zero. A parent-exit fixture also returned status zero and left
a TERM-ignoring child running. Both tests failed. A third test cancelled before
spawn and showed that the process still launched. Its cancellation result was
correct, but the unwanted process launch was a side effect.

NativeProcessExecutor now records cancellation synchronously in a locked flag.
Termination checks that flag before accepting a status and uses the existing
process-group cleanup before returning cancellation. A check immediately before
spawn rejects cancellation that arrived after the initial check. A post-await
check also prevents a cancelled caller from receiving a normal status.

All three regressions passed after the change. The parent-exit expiry and
cancellation tests share a fixture, with separate test identities and assertions.
Focused process, Shortcut and speech-process suites passed28 methods before the
fixture extraction. The complete run after extraction passed Core674/app748.
XML results matched discovery. Local Debug compilation and the structural
matrix check passed. No retries or timeout increases were added. Python code
did not change; the previous68-test result is separate, not a new run.

These tests use real local processes and temporary files. They do not open
windows, play audio or request permissions. No manual UI session was needed for
this executor boundary. They do not accept new system-delivered App Intent or
Shortcuts cases. The usual app was not replaced. Native route acceptance still
has six partial engine records.

## Speech process cleanup through actual Intent.perform — 22 October 2026

At `0898a34`, a headless integration test calls RunDraftActionIntent.perform.
It executes JavaScript through the worker, then NativeSpeechRequest, the real
SystemSpeechDriver and NativeSpeechProcess. An injected executable waits as a
real local process and ignores TERM. It does not use an audio device. The test
host substitutes only that executable and the notice presenter. It does not
accept the operating system delivery of an App Intent.

Both task cancellation and helper timeout throw AutomationActionError with the
matching final reason. Before the Intent returns, the helper is reaped and its
request directory is removed. Retained text stays in Inbox. The later script,
next step, completion notice and success Archive effect do not run. Library
execution exclusion is released. A following Intent succeeds, saves distinct
text and records Success. The interrupted run records Cancelled or Error.
The process-level and Intent-level cases share the neutral blocked executable
fixture; each keeps its own contract assertions.

The focused speech-process suite passed7 methods, including the two new Intent
cases. Complete Swift results passed Core674/app749 and matched discovery.
Local Debug compilation, structural matrix validation and the manual-fixture
identity test passed. Production code did not change in this session. Python
fixture validation is not a new full Python run.

A separate manual owner-close fixture is now prepared as QA Speech owner close
in engine-speech-actions.json. It includes a later step and Archive after
success, so both must remain absent after closing the source window. This
fixture was not executed: Computer Use reported that the Mac was locked.
No synthesis, UI action confirmation or final callback was observed for it.

An isolated full QA bundle was prepared from `0898a34`, with debug-library hash
`a8b51a41294099ed3c44b7b5faddd80a20c14a6756701006afc78fd829efc7e5`.
Its process was confirmed live but idle, with zero stored notes and runs and no
speech helper or request directory. The QA app and callback helper bundle stay
prepared for the unlocked manual session. They do not publish Services entries.
The usual app remains unchanged. Owner-close acceptance is still pending.

## Native speech owner close and complete result — 22 October 2026

The prepared QA session resumed after the Mac was unlocked. During its first
portion, closing the source window while Reading complete was open returned
one x-cancel. The retained source stayed in Inbox with no later script, tail
or Archive. A following shell action returned one success. A normal short
phrase also returned one speech=complete success callback. The later attempt
to close during playback was interrupted before a final result was observed.
Its process and temporary database were absent at continuation. That attempt
is not accepted. Missing observation was not treated as a live process.

The playback case was repeated only after confirming the earlier process was
absent. The same isolated QA bundle retained the production code from
`0898a34`; no production source changed through `7428733`. Its debug library
SHA256 was
`a8b51a41294099ed3c44b7b5faddd80a20c14a6756701006afc78fd829efc7e5`.
The temporary library was recreated empty.

Computer Use imported QA Speech playback owner close from
engine-speech-actions.json and created a neutral source. The action reads a
neutral phrase repeated40 times, then has a later script, another step and
Archive after success. After external-link confirmation, the real helper and
its private request folder were confirmed live. Computer Use clicked the
source window's close button. Exactly one x-cancel callback arrived. The
helper and folder were absent after cancellation. The database retained the
prior text in Inbox, with no sentinel and a Cancelled run. A following real
shell action returned one success with exact Unicode output.

The same completed session then ran QA Speech completion. Computer Use
clicked Read. The actual native helper completed and Reading complete appeared
while the callback count remained zero. Computer Use clicked OK. One x-success
arrived with speech=complete. The saved source was Speech completed in Inbox.
This proves the native synthesis result and final notice ordering; it is not
a microphone recording or an independent confirmation of audible output.

Both apps quit normally. Exact process absence, private-folder cleanup and
LaunchServices unregistration passed. The closed repeat-library history was
Cancelled, Success, Success. Packages, closed library and preferences remain
recoverable in the Trash. Earlier interrupted temporary data were unavailable
and were not claimed as recovered. No shared speech services, audio settings,
permissions or usual-app files were changed.

The fixture identity test and structural matrix check passed. Production code
did not change. The preceding Core674/app749/local-build evidence applies;
those suites were not rerun for this fixture and native-evidence update.
Speech system-delivered Intent variants, selected-voice variants and direct
output-stop confirmation remain separate. The six global partial contracts
are not closed by this route-specific acceptance.

## Print callback cancellation race — 22 October 2026

At `58dea8c`, two headless driver cases cancelled the task immediately before
delivering true or false from the print callback. Both returned normal results
and skipped cancelOwnedPresentation. The before-fix run failed both cases.

PrintRequestWait now records cancellation synchronously in a locked flag.
The queued MainActor handler still performs cleanup, but a callback also checks
the flag. It detaches callbacks, cancels the owned presentation once and throws
CancellationError. NativePrintRequest checks cancellation after a normal resume.
The same tests now pass; a later captured callback cannot repeat cleanup.

The focused print suite passed16 methods, including both regression cases.
The existing PDF output test still runs without a print or progress panel.
Complete Swift runs passed Core674/app750; XML reports matched discovery.
Local Debug compilation, structural matrix validation and diff checks passed.
No test retries or longer deadlines were added. Python code did not change;
its earlier68-test result is separate, not a new run.

No native print panel was opened in this session. Native source-window closure
remains separate and unaccepted: the earlier manual attempt did not establish
owner closure. This fix also does not recall an already delivered print job
or undo completed external effects. The usual app was not replaced.

## Native print source closure restriction and recovery — 22 October 2026

A fresh isolated QA bundle used the full Debug build from `6e85978`. Its debug
library SHA256 was
`04594b83dfe372e2f9feabef6a6cca6dd6768025d6eb73cec96c9f0894e1c918`.
The library started empty. The imported print fixture data were compared with
engine-print-lifetime-actions.json after normalizing the stored step structure.
The data matched exactly before execution. An initial import had the wrong
template line break; it was corrected before any action ran.

The URL requested QA Print pending operation on a neutral source. The one-page
print sheet opened. No printer was selected and Print was disabled. File Close
was disabled. File Close All remained available, but selecting it left the
print sheet visible and the callback count at zero. The Window menu still
listed the source window. This establishes that Close All did not close the
owner in this state. It does not accept native owner-close cleanup.

Computer Use cancelled the Window menu and clicked Cancel on the print sheet.
Exactly one x-cancel callback arrived. A following real shell action returned
one x-success with exact Unicode output. No print or PDF-save command was used.

Both apps quit normally. The closed database had a Cancelled print run and a
Success recovery run. Revisions retained the completed pre-print write and
contained no later-step sentinel. The final source stayed in Inbox. Exact
process absence and LaunchServices unregistration passed. Packages, closed
library and preferences remain recoverable in the Trash. The usual app was
not replaced.

Production code and fixtures did not change in this session. The structural
matrix and diff checks passed. The preceding Core674/app750/local-build results
apply to unchanged code; those suites were not rerun for this evidence update.

Native owner-close acceptance remains pending. File Close All must not be
repeated as an owner-close test unless application or system behavior changes.
Any later test must establish an actual source-window close through a supported
lifetime operation. Process termination is not a substitute for a final engine
result. Large-document print rendering latency is also still pending.

## Apple model deadline and cancellation guards — 22 October 2026

Injected tests reproduced three delivery defects before the fix: a response at
or after its deadline returned success; a tool ran after owner cancellation
before queued cleanup; and an expired request started generation. Deadline and
cancellation checks now reject these paths. Failed requests still discard their
session and await operation cleanup. Recovery reuses the session identity.

Four new test methods cover before, at and after deadline delivery, cancelled
tool authorization, expired tool authorization and expired generation start.
The focused model suite passed 11 methods. Complete Swift runs passed 674 Core
and 754 app methods. XML reports matched discovery. All 68 Python tests and the
local Debug build passed. Structural matrix and diff checks passed. The strict
engine check still reports six partial contracts and 18 diagnostics. No retry
or longer timeout was added.

The backend, clock and tools were neutral test doubles. No native model ran,
no library write occurred, and no visible window or permission prompt opened.
Native generation, cancellation and tool cleanup remain pending system readiness.
The usual app was not replaced. No QA app is running or prepared.

## Native transcription completion and recovery — 22 October 2026

The complete isolated QA package used production commit c21dac9. Its debug
library SHA256 was 4c269dbc0200bbc5c0a46c9696a2b9e93523767c89776c51d3f28ef4d73c241d.
A fresh temporary library had no drafts before the neutral test source.
The usual app was not opened or replaced. The QA bundle had no iCloud container,
Services or document-type entries.

A URL model readiness action returned one success callback with available=false
and readiness=unavailable. No generation ran and no Apple Intelligence settings
changed. The local action remains with the recoverable QA data; this result does
not accept native model generation, cancellation or timeout.

The transcription fixture is engine-transcription-completion-actions.json.
The user authorized and granted speech recognition access in the protected macOS
prompt. Computer Use then selected only the synthetic neutral audio file. The
file was generated with Samantha, without playback or microphone recording:
"This is a neutral test. The blue notebook is on the table."

The current async adapter returned one success callback with transcript:
"This is a neutral test the blue notebook is on the table".
The visible editor had that same text. A read-only check confirmed the imported
script matched the fixture. The following existing URL shell recovery returned
one success with exact Unicode output. No extra callback was observed.

Both apps quit normally. Exact process absence and exact LaunchServices
unregistration passed. Closed history had three Success records: model readiness,
transcription and shell recovery. The final draft had the recovery text.
QA packages, closed library, exported preferences, local readiness action and
synthetic audio remain recoverable at:
~/.Trash/DraftlyModelTranscriptionQA-r0n_9o_o.

Only a manual fixture and evidence changed. The fixture test and structural
matrix check passed. Previous Core674/app754/Python68/local-build results apply
to unchanged production code; they were not repeated for this evidence update.
Native transcription denial, pending-authorization cancellation, production
recognition timeout and late recognition remain pending. This session accepts
URL transcription completion after an actual grant, not the full route-by-entry
matrix. Six engine contracts remain partial.

## Native Shortcuts interruption and timeout — 22 October 2026

QA used the complete isolated c21dac9 package. Its debug-library SHA256 was
4c269dbc0200bbc5c0a46c9696a2b9e93523767c89776c51d3f28ef4d73c241d.
The prior neutral QA library was restored from its closed recoverable copy.
The usual app was not opened or replaced. No iCloud container was enabled.

Computer Use changed only Draftly QA Output — disposable from a five-second
Wait to 180 seconds. Reopening the editor confirmed the saved value. Its Text
and Stop and Output actions stayed unchanged. The new action fixture is
engine-shortcut-lifetime-actions.json. Its imported script and Archive-on-success
value matched the source before execution.

An initial preparation run completed before an active wait was established.
Its source had success effects, as expected for success. This run does not
accept interruption. A later request was cancelled at external confirmation
and did not run the action. The accepted tests used a new neutral source loaded
in the visible QA window, after the saved 180-second Wait was confirmed.

For cancellation, /usr/bin/shortcuts PID32034 was confirmed live with its exact
private input/output paths. Actions > Cancel Running Action returned one x-cancel.
That PID and its owned input directory were absent afterward. History recorded
Cancelled. The retained pre-wait text stayed in Inbox without the later script
or tail. A following real shell recovery returned one Unicode success.

The next request used the unchanged production 60-second Shortcut deadline.
PID35323 and its separate input directory were still present at 37 seconds.
After the deadline, one x-error reported that the operation timed out. The PID
and directory were absent. Following shell recovery returned one Unicode success.
Closed source history was Cancelled, Success, Error, Success. Its five revisions
had no later-step sentinel, and its final draft stayed in Inbox.

These observations accept the actual CLI process and owned-file cleanup, final
callbacks, stopped later steps and recovery. They do not prove that every job
inside the system Shortcuts service stopped, or recall effects already completed
there. No service job identifier, spawned child or internal stop signal was
observed. Those cases and system-delivered Intent variants remain pending.

Computer Use restored Wait to five seconds, closed and reopened the editor, and
confirmed five seconds plus the original output text. No new Shortcut was created
or deleted. Shortcuts and both QA apps quit normally. Exact QA process absence
and exact LaunchServices unregistration passed. Packages, closed library and
exported preferences remain recoverable at:
~/.Trash/DraftlyShortcutLifetimeQA-pufuzq3z.

Production code did not change. Fixture identity, structural matrix and diff
checks passed. Earlier Core674/app754/Python68/local-build results apply to
unchanged production code, not a new execution of those checks. Six engine
contracts remain partial.

## System-delivered App Intent shell lifetime — 22 October 2026

A complete isolated QA package from c21dac9 was development-signed with team
NM92LU2KKV. Signature verification passed. Its signed debug-library SHA256 was
554a03b3cb136f7e491cd26350c5c5eb88c9ba2ae4a26c9c8eb3715fa983c932.
A fresh temporary library had one neutral source. QA had no iCloud container,
Services or document-type entries. The usual app was not opened or replaced.

Computer Use configured the existing Draftly QA Engine — disposable Shortcut,
editor ID D11EC900-D6B4-48DD-AE0D-7CD51353D655. Its Run Draft Action used
QA URL Shell pending and the neutral draft UUID. The imported pending/recovery
scripts matched engine-url-shell-lifetime-actions.json before execution.
The pending root retains an initial write, then runs a shell with a sleeping
child. Later script and tail sentinels plus Archive apply only on success.

This session used actual system delivery from Shortcuts, not an injected
RunDraftActionIntent.perform call. Three interruption cases passed:

- Stop in Shortcuts cancelled the request. Parent38543 and child38544 were
  confirmed live before Stop. Both and their exact private folder were absent
  afterward. History recorded Cancelled.
- The unchanged production120s deadline expired. Parent38585 and child38586
  stayed live at64s and117s. Both and their private folder were absent after
  expiry. Shortcuts showed the operation-timeout alert and the same inline error.
  History recorded Error with the timeout message.
- Direct close of library-AppWindow-1 cancelled a later request while parent38644
  and child38645 were confirmed live. Shortcuts showed the action-cancelled
  alert. Both processes and their private folder were absent afterward.

Each case was followed by a new shell recovery through the same App Intent.
Shortcuts displayed completion, and the draft held exact Unicode recovery text.
The last recovery ran after the source window closed. The closed history was
Cancelled, Success, Error, Success, Cancelled, Success. All seven revisions had
no sentinel. The final draft stayed in Inbox. No callback-helper action run
substituted for an Intent in these six executions.

Computer Use restored the Shortcut's original QA Caught rejection action name
and original neutral UUID. No Shortcut was created or deleted. Shortcuts and
both QA apps quit normally. Exact QA/helper process absence and exact
LaunchServices unregistration passed. Packages, closed library and exported
preferences remain recoverable at:
~/.Trash/DraftlyIntentShellQA-tp1i9uui.

Production code and fixtures did not change. Matrix and diff checks passed.
The previous Core674/app754/Python68/local-build results apply to unchanged
production code; this evidence session did not rerun those suites. The strict
engine gate still has six partial contracts and18 diagnostics. Other native
capabilities, entry variants and reference comparisons remain separate.

## Native Reminders access outcomes — 22 October 2026

The complete c21dac9 QA package was development-signed with team NM92LU2KKV.
Signature verification passed. Signed debug-library SHA256:
b77772ece411c7a9f79f3485a7d31e8b8322c3823e780387b2f1d771c532c7b3.
The library was fresh and temporary. No iCloud container, Services or document
handlers were enabled. The usual app was not opened or replaced.

The new engine-reminders-authorization-actions.json fixture matched its imported
script and Archive-on-success option before execution. It writes neutral text,
requests only ReminderList.default(), validates the returned shape, then adds a
success parameter and tail. It does not enumerate lists or tasks, export a list
name or identifier, or create a reminder or list.

The existing Shortcuts fixture delivered Run Draft Action through the system.
The first request returned Error: Access was denied. Enable access in System
Settings. This was visible inline in Shortcuts and in Execution History. A
read-only check before recovery confirmed the pre-request write stayed in Inbox
without the success text or tail. No active wait remained to cancel. A following
shell recovery through the same App Intent completed with exact Unicode text.

A later URL request returned one x-success with listAvailable=yes.
History recorded Success. The script reached its success text and tail, and its
configured Archive effect applied. A second App Intent shell recovery completed.
The closed history was Error, Success, Success, Success. The final source held
recovery text in Archive, which was the prior successful root's deliberate effect.

The permission gesture was not visible to Computer Use. Questions to the user
were pending at recording time. Do not infer that the first response was an
observed button-level denial, that the grant gesture was observed, or that
pending-authorization cancellation or a late grant was tested. The accepted
results are the native access-denied outcome from App Intents and a subsequent
successful URL default-list lookup. No privacy setting was changed by the agent.

Computer Use restored the Shortcut's original action name and neutral UUID.
Shortcuts and both QA apps quit normally. Exact QA/helper process absence and
exact LaunchServices unregistration passed. Packages, closed library and exported
preferences remain recoverable at:
~/.Trash/DraftlyReminderAuthorizationQA-viiam2ln.

Only the manual fixture and evidence changed. Fixture identity, matrix and diff
checks passed. Previous Core674/app754/Python68/local-build results apply to
unchanged production code; these suites were not rerun. Reminder queries and
persistence, pending authorization, timeout and late results remain open.
Six engine contracts remain partial.

### Reminders permission clarification — 22 October 2026

The user later confirmed that the Reminders request appeared and that they
pressed Allow. Computer Use did not operate that protected prompt. This adds
human confirmation of the grant behind the later successful lookup. It does
not establish pending-authorization cancellation or late-grant isolation.

## Large PDF regression and native owner-selection failure — 22 October 2026

The headless print suite now saves 4,000 numbered Unicode lines to a local PDF.
The input has126,925 UTF-16 units. It verifies every line in order plus the first
and final markers. Letter geometry produced126 pages in0.224800667s for one run.
No print or progress panel appeared. Timing is an observation, not a threshold.
The existing short-PDF test shares the same export setup and keeps its name.
Complete Swift results passed Core674/app755 and matched discovery.

The neutral engine-print-large-document-actions.json fixture generates that text
as a template tag while retaining a short draft write. The imported script matched
before execution. Native QA used unchanged c21dac9 production code, signed debug
library81f11b36359b811826e4747421c455c13d81ed82b0d1bdd9aa89fa6457ea8cb1.

The first real print panel showed118 pages with its system paper configuration.
Panel Cancel returned one x-cancel without the pre-print success parameters.
The click-to-observed-callback bound was881ms, including Computer Use overhead.
The draft retained its initial write in Inbox without completion text or Archive.
A later URL repeat failed with Open a Draftly window before printing, despite
the source window remaining open. It returned one x-error. No PDF was saved and
no print command was sent. The failed repeat does not accept native completion.

Inspection found that SheetPrintDriver resolves NSApp.keyWindow after the external
confirmation closes. This can be nil even when the action's source window exists.
The fix must carry the owned window, without borrowing another window if that
owner disappears. Keep this defect separate from the large-PDF test change.
Both QA apps quit normally and exact process absence passed. Their packages and
closed temporary library remain in place for a validated refresh and repeat.
The usual app is unchanged. No screenshot or raw log is tracked.

## Owned print window and large native PDF — 22 October 2026

The prior URL repeat failed after external confirmation because SheetPrintDriver
read the global key window. The source window was still visible. Async native
hosts now use the WindowModel owner through a weak closure. A missing or invisible
owner fails before a panel opens. An ownerless host cannot borrow an unrelated
window. Direct request calls keep the old fallback only if no owner provider is
supplied. Legacy synchronous printing is unchanged.

Four headless tests cover an owned window with no global key window or an unrelated
key window, explicit missing-owner rejection, WindowModel binding removal and
ownerless-host failure before presentation. Restoring the old global selection
rule made the two selection tests fail with four assertions. Restoring the fix
passed the complete run: Core674/app759, with XML results matched to discovery.
All 68 Python tests and the local Debug build passed. No retry or longer limit
was added. Structural matrix and diff checks passed. The strict engine gate still
reports six partial contracts and 18 diagnostics.

The closed baseline QA package and library were preserved before refresh. The
complete current runtime was copied and development-signed. Signed debug-library
SHA256: 97662ac2353d331f696f5af1f8ea91e832298f9a6592bb95e98ef91ece68792c.
The usual app stayed unchanged. QA used the same neutral library and fixture.

The same externally confirmed URL now opened the real 118-page panel. The
run-button-to-panel observation was 1,521ms, including Computer Use overhead.
Save as PDF wrote only large-neutral.pdf in the temporary QA directory. No printer
was selected and no printer job was submitted. The first callback observation
at 797ms after Save had zero replies; the next at 6,111ms had one success with
printed=yes and utf16Length=126925. These are observation bounds, not isolated
rendering times or proof of UI responsiveness during drawing.

The saved PDF has 118 A4 pages, 595 x 842 points, and 218,182 bytes. Text extraction
verified all 4,000 numbered lines in order, both markers and 4,000 cafe accents.
Poppler extracted only 3 panda characters and PDFKit 34. Rendered pages 1, 59 and 118
showed the repeated panda glyphs, correct line numbers and clean margins. This
supports a text-extraction limitation, not a demonstrated rendering defect. Do
not claim a full-page visual review or 4,000 extractable emoji characters.
The automatic Letter export has 126 pages; its different geometry is explicit.
Hardware: Mac14,6, Apple M2 Max, 64 GiB; macOS 27.0.1; local Debug build and temporary
local storage. Timings are single observations without acceptance thresholds.

A following real shell recovery returned one Unicode success. Both apps quit
normally. Closed history preserved baseline Cancelled/Error and corrected
Success/Success. The final source had recovery text in Archive, from the completed
print root's explicit success effect. Exact process absence and exact
LaunchServices unregistration passed. Both runtime versions, both closed library
states, PDF and exported preferences remain recoverable at:
~/.Trash/DraftlyLargePrintQA-x623szvb.

Native print owner-close remains pending because the system sheet disables Close
and Close All did not close its owner in the earlier check. The large-document
case here does not remove that restriction or accept other capability routes.

## Sharing discovery cancellation and deadline — 22 October 2026

Two controlled regression methods reproduced the prior defects before the fix.
Cancelling from service discovery still showed the picker when services existed;
without services it returned the availability error instead of cancellation.
Advancing the clock to or past the original deadline still showed the picker
because the request started a fresh budget after discovery. The five expanded
cases included a timely nine-second control; four cases failed with six issues.

The request now captures one deadline before file preparation. The sharing
session checks cancellation and expiry before and after discovery, then starts
a timer for the remaining budget. Cancellation wins over an unavailable-service
answer from that cancelled discovery. No service is handed the prepared file
on these paths, so existing disposal removes it. Handed-off service leases and
late provider callbacks keep their existing behavior.

The two regressions passed after the fix. A third case expires during preparation
and confirms that discovery and presentation never start. The focused sharing
suite passed 20 methods. Complete Swift results passed 674 Core and 762 app
methods, with XML reports matched to discovery. Local Debug compilation,
structural matrix and diff checks passed. No retries or longer limits were added.
Python code did not change; the earlier 68-test result remains separate.
The strict engine check still reports six partial contracts and 18 diagnostics.

The driver, clock and files were neutral temporary fixtures. No native sharing
service, visible window, permission or personal data was used. No QA package was
prepared or launched, and the usual app stayed unchanged. These tests do not
accept a live service interruption or complete native ownership.

Next: SystemSharingDriver.show still takes NSApp.keyWindow. Review its owner
binding separately, using the confirmed print-window failure as the risk model.
Do not count that pending correction as part of this discovery-boundary fix.

## Owned sharing windows — 22 October 2026

The native host now supplies its action window to sharing and printing through
one weak owner closure. Sharing stores that window weakly and checks visibility
before discovery and presentation. An ownerless host cannot borrow another
window. Direct helper calls keep their previous current-window default. Owner
failure removes any prepared file. Service handoff leases stay unchanged.

Three new headless tests cover a missing owner with file cleanup, an invisible
owner and an ownerless host. Existing print test names stay unchanged. The final
complete Swift run passed 674 Core and 765 app methods. XML results matched the
discovered inventory. The local Debug build passed. An earlier complete run used
a test name that changed during execution; it is not the final evidence. The
final run used frozen source files. No retry or longer timeout hid a failure.
Python code did not change; its earlier 68-test result remains separate.

A separate manual session used a fresh, isolated, development-signed QA library.
Signed debug-library SHA256:
385dc946749c2991f8723c6ec398f8039a729e6681149835ba3429b6427fe6c0.
The unchanged engine-sharing-service-lifetime-actions.json fixture opened the
real picker on its source window after URL confirmation. The neutral attachment
had 38 bytes. There were zero callbacks while the picker was open. Picker Cancel
returned one cancel and removed the file. The pre-request write remained in
Inbox; later steps and Archive did not run.

A second neutral window stayed open after the source window closed. Repeating
the confirmed URL returned one error: Open a Draftly window before sharing.
No picker appeared on the unrelated window. Its editor stayed empty. No new
sharing folder remained. Following shell recovery returned one success with
Shell recovery café 🐼. The closed library records Cancelled, Error and Success.
No revision contains the sharing completion marker.

QA and the callback helper quit normally. Their exact LaunchServices entries
were removed. Packages, exported preferences and the closed library remain
recoverable in ~/.Trash/DraftlySharingOwnerQA-pefkodl5. The usual app stayed
unchanged. No service was selected and no message was sent. Native service
completion, other services and legacy sharing remain separate checks. Structural
matrix checks pass; the strict engine gate retains six partial contracts and
18 diagnostics. This check does not close the engine.


## Included configuration reference block — 22 October 2026

Manual Computer Use observed Drafts About: Version54.1.1 (943). Manage Action
Groups allowed the neutral empty group QA Included Configuration 20261022.
Add Action opened Drafts Pro with action creation/customization listed among
paid features. The dialog was closed without purchase, trial, restore or account
change. No action was created or executed. About and group management were
closed. The empty neutral group remains for the next reference session.
No personal draft or existing filter was changed. No screenshot or raw log is
versioned. This is evidence of the reference block, not configuration parity.

CFG-01 through CFG-05 remain blocked. The packaged neutral observer and five
Draftly-only characterization methods are described in
research/included-configuration-comparison-2026-10-22.md. The remaining engine
case inventory is research/engine-acceptance-cases-2026-10-22.md. The matrix stays
partial and retains the six contracts. No production rule changed.


## Controlled speech permission and cancellation — 22 October 2026

The focused baseline passed 41 methods. A new fake-clock transcription test
queued an expired reply before task-cancellation cleanup. Authorization, picker
and recognition each incorrectly reported timeout. The correction records
cancellation synchronously before actor cleanup and returns CancellationError.
All 42 focused methods then passed; local Debug compilation passed.

Additional injected-driver cases cover requested denial/restriction, stale
speech/microphone grants, stale recognition/file replies, same-turn recording
cancel and recovery. The real worker/runner with a speech-host fixture retains
completed text, skips tail/Archive, drops success parameters and permits a fresh
action after cancellation. This is not system-delivered UI/URL/Intent evidence.

Final Core 679 / app 792 matched the full XML inventory. Focused 53, Python 80,
local Debug build, structural matrix 0 and diff checks passed. Six partial engine
contracts and 18 strict diagnostics remain. No retry or deadline changed.
See research/speech-permission-lifetime-2026-10-22.md for the exact cases.
No native permission request, speech session or microphone capture ran. Two
neutral manual probes are prepared but not accepted as executed. The user was
asked for a quiet-session availability; protected OS permissions remain gated.
No habitual app, privacy setting, original script or native acceptance changed.


## Native dictation callback correction — 22 October 2026

A manual Engine QA run exited after audio engine startup. The system log reports
a block that expected the main queue. The installed SDK permits audio tap calls
outside that queue. The driver now uses an explicit Sendable callback constructed
outside MainActor. Its new test supplies synthetic silent audio on a detached
task without starting a microphone or recognition task.

Full Core679/app793 matched XML/discovery; Python80, local Debug build and
structural matrix0 pass. Strict engine remains six partial contracts/18 diagnostics.
The signed isolated QA then displayed Dictation with Listening, Cancel and Done.
No phrase result arrived during the wait. Computer Use selected Cancel. The
panel closed, Inbox retained the marker without a completion tail or Archive,
and History showed Cancelled: Neutral user cancellation. The process log shows
engine/input stop at 19:52:13. QA quit normally; its exact process is absent.
This accepts user-Cancel from the action palette, not task cancellation or a
permission outcome. Recognition/Done and other native speech cases stay open.
The usual app is unchanged.
See research/speech-permission-lifetime-2026-10-22.md for package hashes and limits.


## Native neutral phrase follow-up — 22 October 2026

The user completed a new neutral dictation attempt. Computer Use observed
`Prueba neutral de Daf Fitly` in the editor with the panel closed and QA responsive.
The process log confirms engine/input stop at20:17:18. This accepts recognition,
insertion and capture stop with the corrected QA package, not exact spelling.
The latest capture entry was not observed. Older Success history rows do not
prove the current fixture tail/Archive path. Full action completion, Undo/Redo
and remaining speech negative cases stay open. QA is idle with neutral text.
No production code, tests, habitual app or acceptance status changed.


## Controlled speech interruption follow-up — 22 October 2026

Baseline44 and final focused47 passed in four suites. The real worker with an
injected dictation driver now covers cancellation during both permission stages
and recording, plus requested denials. Assertions cover retained text, no later
steps/Archive, no success parameters, one cleanup/log and successful recovery.
The existing transcription runner test now includes file selection cancellation.
Two pre-cancelled request cases start no driver work. No production code changed.

Full Core679/app796 match XML/discovery. Python80, local Debug build and
structural matrix0 pass. Strict engine retains six partial/18 diagnostics.
No automatic test opened a visible window, used a microphone or requested access.
Builds and tests did not overlap. The initial new fixture expression triggered
a Swift compiler assertion; binding the require result before invocation fixed
the compile. No timing threshold or retry policy changed. Native permission
outcomes remain distinct obligations. See the speech record for exact cases.


## Native transcription cancellation, wait timeout and recovery — 22 October 2026

Computer Use ran the neutral transcription fixture through the action palette
in the existing signed Engine QA. Cancel in Open closed the picker, retained the
Inbox marker, omitted tail/Archive and added one Cancelled result. The next run
transcribed a locally generated Spanish synthetic AIFF, ran the tail, archived
the draft and added one Success. No microphone or playback was used.

A separate selection wait used the unchanged production deadline. Open closed
without input. The marker stayed in Inbox without a tail. One Error reported
The action operation timed out before it completed. A following transcription
succeeded and archived its neutral draft. This accepts selection-wait cleanup
and recovery, not recognition timeout or an independent phase-deadline winner.

QA quit normally. Read-only inspection of its closed library confirmed four
corresponding run IDs, one per attempt, and both recovered archived transcripts.
The speech lifetime record gives IDs, package hashes and exact limits. Its
LaunchServices entry was removed; neutral data and package remain recoverable.
No personal data, clipboard, habitual app, permission or privacy database changed.
Existing speech access cannot prove denial or a pending grant. Those native
cases, live task cancellation, late recognition and URL/Intent speech paths stay
pending. Strict engine remains six partial contracts and18 diagnostics.


## Native transcription task cancellation — 22 October 2026

A synthetic long-file transcription reached recognition. Computer Use observed
Cancel Running Action enabled and selected it. The main window retained the
Inbox marker without tail/Archive; History recorded one Cancelled. A fresh
short-file transcription succeeded. Read-only closed-library inspection confirms
run EF837AA5-F2C7-493B-8D61-3E6DDE0A6662 then0D515DBC-3B5A-47C3-A383-F1005C683D5A
on neutral note26F53FFE-C943-4F25-A017-A859210E20C1. QA quit normally. No microphone,
permission change or personal data was needed. No native late callback or SDK
resource-deallocation acknowledgement was observed. URL/Intent and recognition
timeout remain separate. Source/tests are unchanged from their validated state.

The user-reported dictation panel Cancel/close was not observed directly.
Its latest durable log instead shows Success with tail/Archive. Do not accept
that attempt as cancellation or diagnose the cause without a controlled repeat.
The speech record preserves this discrepancy without a private transcript.


## Dictation final-result cancellation boundary — 22 October 2026

One new headless method covers user Cancel and task cancellation after final
recognition has already stopped audio but the panel still awaits Done. Final
text is discarded, cleanup runs once, and stale final/Done callbacks cannot
affect a fresh request. Baseline27 and focused48 passed. Full Core679/app797
match XML/discovery; Python80, local build and structural matrix0 pass. Strict
engine remains six partial/18. No production rule or deadline changed.

The user noted that native sessions had already run. No new microphone session
was started. Accepted prior cases remain accepted; live dictation task cancel
and the recorded close/Success discrepancy remain unresolved, not repeated or
promoted. See the speech record's consolidation for the bounded next checks.


## Recovered dictation acceptance — 22 October 2026

The user confirms an earlier successful microphone cancellation check and says
its detailed evidence was lost. The existing Core closure pass of19 October
already records native dictation insertion, Undo and cancellation in Core QA.
That entry does not identify its cancellation control or the current package.
Preserve both the dated native record and the present user verification. Do not
require a repeat of the user's check. No new CUA observation, permission outcome
or cross-entry contract acceptance is claimed. The later20:33 Success record
remains separate. See the speech lifetime record for this reconciliation.

### Editor insertion line — 29 October 2026

Implemented a local Highlight Insertion Point preference. It is off by default.
The editor draws the current visual line below the text and selection. The
change does not write background attributes to the document. It uses the
existing text layout manager and keeps the text system intact.

The focused tests cover UTF-16 positions, invalid positions, document end,
empty and trailing lines, state preservation, and background drawing for an
empty document. The local Xcode build passed. The serial Swift run verified
682 Core and 851 app tests. Python ran 80 tests. The matrix structure check
reported no errors. A direct concurrent ThemeRenderingTests run failed in the hanging-indent case
with an earlier prototype that replaced the layout manager. The final version
keeps that manager. The concurrent suite passed on the unchanged base and on
the final version. The full serial app run also passed. This does not establish
the cause of the earlier failure.

In isolated Engine QA, the setting enabled the indicator. It followed the
cursor from the third line to the second. Editing, Undo, and Redo preserved
the neutral Unicode text. This check used dark appearance. Drafts comparison,
light appearance, wrapped lines, and a restart check remain pending. No
screenshots are stored in Git. QA was closed and its bundle was archived.

After a normal restart, Engine QA retained the enabled preference. A neutral
long paragraph wrapped across five visual lines. Moving the insertion point
changed the highlighted visual line without changing the text. The light-mode
check remains pending: the QA appearance picker remained on System after the
attempt. The Drafts visual comparison also remains pending.

A focused regression test found that a final carriage return or Unicode line
separator placed the indicator on the preceding line. The editor now uses the
extra line fragment reported by AppKit at the end of the document. The test
covers carriage return, CRLF, Unicode line and paragraph separators, and an
end position without a terminator. The focused suite and local build passed.
This fix has not been checked in a visible QA session.

An offscreen drawing test found that the default line color could be resolved
under the wrong appearance before drawing. In light appearance this could
leave the indicator without contrast. The default color now resolves when the
background is drawn. The focused tests check both Aqua and Dark Aqua, and the
local build passed. Visual verification in a light QA window is still pending.
The QA theme selector stopped responding during that check.

The full serial Swift regression also passed after the draw-time color fix.
The inventory check verified 682 Core and 853 app tests. This automated run
does not replace the pending visible light-mode check.

A focused offscreen test now checks wrapped visual-line geometry with Unicode.
It confirms that the indicator follows the selected visual fragment rather
than the paragraph start. The focused suite and local build passed.

### Editor paragraph numbers — 29 October 2026

Drafts 54.1.1 showed Paragraph numbers and Highlight insertion point as
syntax-specific settings. Enabling them for Markdown did not enable them for
Plain Text. A neutral sample showed one number per paragraph, including an
empty paragraph, without numbers on wrapped visual lines. The original Drafts
settings were restored after the comparison.

Draftly now stores both display options by syntax. Existing global highlight
settings remain the fallback when a syntax has no override. A native ruler
numbers paragraphs without modifying the document. It uses UTF-16 offsets and
handles CRLF, Unicode paragraph separators, and a trailing empty paragraph.
The ruler draws within its bounds and keeps the editor text visible.

Focused tests cover index boundaries, drawing, Unicode, separate syntax values,
unknown fields, legacy fallback, and invalid preference data. The local Xcode
build passed. The complete serial Swift inventory verified 682 Core and 860 app
tests. Python ran 80 tests. The matrix structure check reported no errors.

In Engine QA, Markdown retained paragraph numbers after restart, while Plain
Text remained off. The same neutral sample showed four numbers, including the
empty paragraph. A drawing regression in an intermediate build covered the
editor; clipping the ruler fixed the observed issue in the next build. The QA
bundle was archived and unregistered. Light appearance, long-document scroll,
full selection/Undo coverage, and measured visual comparison remain pending.
No screenshots are tracked.

Engine QA scrolled a neutral 120-paragraph note from the end to the beginning.
The visible labels matched the paragraph numbers, including 120 at the end.
Selecting paragraph 3, editing it, and using Undo restored its text and
selection. Redo restored the edit but visibly clipped the left edge of every
line while the ruler was enabled. Repeating Undo and Redo reproduced the
change. With paragraph numbers disabled, the same Undo/Redo sequence showed
the full left edge. The cause is not established. A first offscreen attempt
did not reproduce the clipping and is not evidence of a fix. Keep this as an
open regression; do not install this build as the usual app. The QA bundle was
closed, archived, and unregistered. The test note remains in QA storage.

A temporary geometry probe identified the ruler clipping cause: typewriter
scrolling reset the clip view's horizontal origin to zero. With the ruler, the
normal origin was -38 points. The editor now preserves that origin while it
centers the selected line. A focused calculation test covers negative and zero
origins. In Engine QA, the same 120-paragraph edit, Undo, and Redo kept the
full text and ruler labels visible. The temporary probe is not in the source.
The local build and complete serial Swift inventory passed (682 Core, 861 app).
Python ran 80 tests and the matrix structure check had no errors. QA was
closed, archived, and unregistered. Light-mode comparison remains pending.

### Ordered-list reference — 29 October 2026

In Drafts 54.1.1 with Markdown Auto-renumber lists enabled, pressing Return
at the end of `1. Uno` in `1. Uno / 2. Dos / 3. Tres` inserted `2. ` and
changed the following numbers to `3.` and `4.`. Starting from `7. siete /
8. ocho / 9. nueve` produced `7., 8., 9., 10.` in the same operation. Pressing
Return on the empty inserted item removed its marker; the following `3.` and
`4.` remained unchanged. With Auto-renumber lists disabled, insertion still
created `2. `, but the following items remained `2.` and `3.`. Restored the
original enabled setting. These are observed examples, not a complete grammar
or an implementation acceptance.

The QA Light Theme selector timed out during another attempt to select Light.
After the selector recovered, its value was still Dark. QA was closed, archived,
and unregistered. The light-mode check remains pending.

### Ordered-list calculation — 29 October 2026

Drafts normalized irregular Markdown numbering on paste and after a manual
number edit. In the observed nested example, a new parent item changed later
parent numbers and retained the nested sequence. A new child item changed the
next child and retained the parent sequence. The two syntax preferences were
independent in the tested Markdown and Plain Text settings. Their original
values were restored.

An internal calculation now finds ordered-list number edits using enabled
list-completion rules from the assigned syntax. Focused tests cover start
numbers, separate lists, nested levels, UTF-16, a custom padded rule, disabled
rules and integer overflow. The local build and complete serial Swift
inventory passed (687 Core, 861 app). This calculation is not connected to
the editor. Paste, typing, selection, Undo/Redo and native parity are not yet
implemented or accepted. More boundaries need comparison before applying edits.

Drafts also retained the parent sequence when an unordered child followed the
new item. The internal calculation now handles that case and treats an
unordered item at the same level as a new group. A focused test covers both
cases and a nested sequence. The calculation remains disconnected from the
editor; this observation does not establish full mixed-list parity.
The focused renumbering suite and local build passed. A complete Swift run
failed in the previously recorded XML-RPC interruption timeout; its focused
suite passed separately. This does not turn the complete run into a pass.
Before connecting the calculation, address excessive custom sequence padding,
edit scope, composition, selection, and Undo/Redo.

With renumbering enabled, typing in an irregular first list corrected that list
but left a separate irregular list unchanged. The internal calculation now
accepts an affected UTF-16 range and limits edits to intersecting list groups.
Focused tests cover a caret, multiple groups, invalid ranges, CRLF, and Unicode.
Scope for other edits and native editor behavior still require validation.
Editing an unordered item immediately before an irregular ordered list also
renumbered that contiguous list in Drafts. The focused test covers that case.
After the scope change, the complete serial inventory passed (690 Core, 861
app); the focused suite and local build also passed. A final extra assertion
was checked by the focused suite after the complete run.

The internal calculation now reports `sequenceOutputLimit` if selected list
edits would generate more than 1 MiB of sequence digits. It checks the affected
groups before allocating padding and returns no partial edits on error. Tests
cover an extreme custom padding value, an unrelated edit, and the cumulative
limit. This is a Draftly resource limit, not a documented Drafts grammar rule.
The editor does not yet call this calculation. Its error presentation and the
separate existing list-continuation path still need review before integration.
In the contiguous bullet and ordered-list example, one Undo restored both the
typed character and the prior irregular number. Redo restored both changes.
The focused suite, complete serial Swift inventory (692 Core, 861 app), and
local Debug build passed after the resource limit change.
The focused suite also passed after extending the unrelated-list test to
confirm that a normal list can still be renumbered beside an oversized rule.

The existing list-continuation path now checks the same output limit before
allocating padding. Its internal checked form reports the limit error. The
existing public optional interface returns no continuation in that case, so
the editor inserts a normal newline. A headless editor test checks that the
original Unicode text remains. The focused syntax and editor tests, complete
serial Swift inventory (692 Core, 861 app before the new editor test), and
local Debug build passed. User-facing error presentation remains pending.

### Ordered-list editor integration — 29 October 2026

Text insertion can plan a single replacement that includes sequence edits and
the resulting UTF-16 cursor. The per-syntax Auto-renumber lists preference is
enabled by default. Headless tests cover insertion, Return, the disabled
option, Unicode and one Undo/Redo operation. The planner keeps a separate list
unchanged and preserves distinct Unicode representations. This is not full
native acceptance: paste, deletion, input methods, error reporting and real
editor interaction still need checks. Pressing Return on an empty list item
before another line currently leaves an extra newline; this is a separate
existing continuation defect and is not covered by the new acceptance.

The complete serial Swift inventory passed (696 Core, 865 app), and the local
Debug build passed. In an isolated Engine QA app, typing in an irregular list
renumbered it; one Undo and one Redo restored each state. Return inserted and
renumbered the next item. Pasting the irregular list did not renumber it, so
paste remains a confirmed difference from Drafts. QA quit, its specific
LaunchServices entry was removed, and the temporary app was moved to Trash.
The normal app was not updated.
Python ran 80 tests, and the action API matrix structure check had no errors.

### Leaving an empty list item — 29 October 2026

Drafts 54.1.1 left the insertion point on the empty line when Return removed
an empty list marker, both before another item and at the end. Draftly now
keeps the existing line ending before another item and places the caret on the
empty line. Headless tests cover LF, CRLF, Unicode, Undo and Redo with
renumbering on and off. The complete serial Swift inventory passed (696 Core,
868 app). A final guard for an existing selection passed the focused suite,
and the local Debug build passed after it.

In isolated Engine QA, two Return presses followed by typing matched the
observed Drafts text before later list items. QA quit, its exact LaunchServices
entry was removed, and the temporary app was moved to Trash. The usual app
was not updated. Other list input paths remain pending.

### Ordered-list plain paste — 29 October 2026

Plain text paste now uses the same atomic list edit when renumbering is on.
HTML conversion still runs first. A headless test checks Unicode, replacement
of a selection, the pasteboard, the disabled option, Undo and Redo. Existing
HTML preference tests passed. The complete serial Swift inventory passed (696
Core, 866 app), and the local Debug build passed.

In isolated Engine QA, pasting an irregular neutral list produced `1., 2.,
3.`. One Undo removed the paste and one Redo restored the numbered list. QA
quit, its specific LaunchServices entry was removed, and its temporary app
was moved to Trash. This does not verify file or rich-text paste variants,
deletion, input methods, or the rest of list parity. The usual app was not
updated.

### Ordered-list deletion — 29 October 2026

In Drafts 54.1.1, deleting a list item's text left the following numbers as
they were while a blank line separated them. Deleting that line ending joined
the lists and renumbered the following items. Draftly now plans the deletion
and renumbering as one edit when the affected list needs new numbers. It keeps
the native deletion path when no renumbering is needed. Headless tests cover
backward and forward deletion, Unicode, LF, CRLF, Undo and Redo. The complete
serial Swift inventory passed (696 Core, 870 app), and the local build passed.

In isolated Engine QA, Backspace joined the lists and produced the observed
Drafts numbers. One Undo and one Redo restored each state. QA quit, its exact
LaunchServices entry was removed, and the temporary app moved to Trash. This
does not verify every deletion command, input method or list grammar. The usual
app was not updated.

### File paste routing — 29 October 2026

When a pasteboard contains a file URL as well as plain text, the list
renumbering paste handler now leaves it to the native paste path. A headless
test verifies that this handler does not change the editor selection, text, or
pasteboard in that case. The complete serial Swift inventory passed (696 Core,
871 app), and the local Debug build passed. This checks routing only; an actual
file paste and rich-text variants still need native verification. The usual app
was not updated.

### Ordered-list planning cost — 29 October 2026

The planner now checks the affected lines before it scans the document for
list groups. If none uses a list rule, it returns without scanning all lines.
The same matcher handles this check and the full calculation. Tests cover
plain text, multiple selected list groups, Unicode and the document end.

On an Apple M2 Max with macOS 27.2 and Xcode 27.1, a temporary Debug probe
planned ten insertions in a 102,500 UTF-16 unit document of ordinary text.
One run took 61.7 ms before and 2.2 ms after the change. These are single
calculation measurements, not end-to-end editor latency or acceptance limits.
Editing within a list can still scan the document. The complete serial Swift
inventory passed (697 Core, 871 app), and the local Debug build passed. Real
editor performance and large-list performance remain pending.

### List edits in long documents — 29 October 2026

The calculation now scans the affected list groups instead of surrounding
unrelated paragraphs. The editor plan maps changed UTF-16 ranges back to the
original edit instead of comparing the whole document character by character.
Tests cover replacement across a sequence marker, changes before the caret,
Unicode representations and unrelated text.

On the same M2 Max, a temporary Debug probe planned ten insertions in a short
list surrounded by a 102,514 UTF-16 unit document. One run took 315.5 ms
before and 2.5 ms after. These are individual calculation measurements, not
end-to-end editor latency or acceptance thresholds. A single long contiguous
list can still require a full scan of that list.

The complete serial Swift inventory passed (698 Core, 871 app), and the local
Debug build passed. In isolated Engine QA, a neutral 102,514-character draft
was pasted, its central list was edited, and Undo and Redo restored the text.
This is a functional check, not a timed measurement. QA quit, its specific
LaunchServices entry was removed, and the temporary app was moved to Trash.
The usual app was not updated.

### Action link replacement native check — 29 October 2026

Isolated Engine QA imported neutral actions with a fixed target UUID. An action
sent a changed installation link to the QA URL scheme. Cancel kept the original
name and UUID. A second request selected Replace; the changed name kept the UUID.
A verification action passed again after QA quit and reopened. This checks one
action, not group replacement or every import format. QA quit normally, its
exact registration was removed, and its temporary app and fixture moved to
Trash. Neutral records remain in the isolated library.

After the complete run, an additional focused test checked planned replacement
against direct sequence edits across many insertion and deletion ranges. It
passed; the complete inventory count above predates that added test.

### List editing resource errors — 29 October 2026

If sequence output exceeds the internal limit, typing and deletion now keep
the user's edit and report the error through the existing library alert. Return
falls back to a normal newline and reports the same error. The existing public
optional continuation method remains compatible; an internal editor interface
exposes the error. Headless tests cover the three operations, error delivery,
Undo/Redo and the editor callback. The complete serial Swift inventory passed
(699 Core, 873 app), and the local Debug build passed.

In isolated Engine QA, a neutral custom syntax with excessive padding showed
the alert after paste and preserved the text. Undo and Redo worked without
repeating the alert. Typing showed the alert and kept the added character.
QA quit, its exact LaunchServices entry was removed, and its temporary app and
syntax file moved to Trash. The imported syntax and neutral draft remain in the
separate QA library. The usual app was not updated.

### Marked text and list numbering — 29 October 2026

A headless test simulates marked text in an irregular list. It checks that
composition stays intact and the committed text remains in the editor. In
this simulation, the list number did not change after composition. This does
not establish Drafts parity or validate a real input method. On the current
keyboard layout, the attempted Option-E input produced a direct euro symbol,
so it did not provide a valid marked-text comparison. The Drafts Markdown
renumbering preference was restored after preparing the comparison.

One complete Swift run stopped in `URLActionInstallationTests` without a
complete report. That suite passed separately. A subsequent complete serial
run passed (699 Core, 874 app), as did the focused composition test and local
Debug build. The reason for the interrupted run is not established. No test
timeout or retry policy changed. Native input-method behavior remains pending.

### Workspace link replacement — 29 October 2026

A workspace installation link now requests confirmation before it replaces a
different workspace with the same identity. An identical link does not ask.
Cancel leaves the library unchanged. A change to that workspace during the
confirmation prevents replacement. A missing library is an error. Tests cover
new and identical links, cancellation, replacement, unknown fields, reload,
backup, a concurrent edit and an injected storage failure.

In isolated Engine QA, a neutral action delivered a link with the QA scheme.
The replacement dialog appeared. Cancel kept the original workspace in the
workspace menu. The native Replace path was not confirmed: the second attempt
lost the expected dialog in Computer Use, and the user closed QA. Its exact
LaunchServices entry was removed. The temporary app and action fixture moved to
Trash; the neutral action, draft and workspace remain in the QA library. The
usual app and the `drafts://` scheme were not changed.

The focused workspace tests and local Debug build passed. The complete serial
app inventory passed (877 methods) before the final missing-library alert
change; the focused suite and build passed after it. Two normal full runs
failed in separate timing-sensitive Core tests: XML-RPC transport in the first,
and asynchronous runner waits in the second. Both focused suites passed. A
separate complete serial Core run passed (699 methods). These diagnostics do
not turn the normal parallel Core runs into passes. No timeout was changed.

On 29 October, isolated Engine QA showed the workspace replacement alert again.
Replace closed the alert and the workspace menu showed the incoming name.
The menu and management sheet showed two records with that name. Their identities
were not inspected, so this does not prove which record changed or accept the
replacement contract. QA quit normally; its exact LaunchServices registration was
removed and its temporary app moved to Trash. Its isolated data was retained.

A separate unique-name QA case created a workspace, saved its UUID in a neutral
draft, and dispatched a changed link through the QA URL scheme. Replace was
selected. A second action found exactly one workspace with the new name and
checked its UUID against the draft. The check passed again after QA quit and
reopened. One earlier restart check ran on an empty draft and failed; selecting
the draft that contained the UUID produced the passing result. QA quit normally,
its exact registration was removed, and its temporary app and fixture moved to
Trash. The neutral QA records remain in the isolated library.

### Action link replacement — 29 October 2026

The focused action installation suite passed nine tests. It covers cancel,
replacement, identical groups, duplicate identities, concurrent edits, unknown
fields, and storage failure. Full serial Swift runs passed 699 Core and 881 app
tests. The local Debug build, 80 Python tests, and matrix structure check passed.
The normal parallel Core run failed in asynchronous window, XML-RPC, and host
cleanup timing tests. No timeout changed. Native confirmation and replacement
are pending. The usual app was not updated.

### Syntax and theme link errors — 29 October 2026

Five syntax import choice tests passed, including link installation and save
failure. The serial app suite passed 882 tests. The local Debug build passed.
Native error presentation and syntax link replacement remain pending. The
prior parallel Core timing failures remain recorded above.

### Action group link name conflicts — 29 October 2026

Ten focused action URL installation tests passed. They include a Unicode group
name collision and verify that the action batch is unchanged after reload. The
serial app suite passed 883 tests. The local Debug build passed. Native error
presentation and a conflict merge policy remain pending.

### Action group link rename — 29 October 2026

The new regression first failed because existing actions stayed in the old
group. It passed after the atomic rename. Eleven focused action link tests and
the serial app suite (884 tests) passed. The local Debug build passed. Native
confirmation was pending at that point; implicit group conflicts remain open.

### Drafts action group file import — 29 October 2026

Five focused tests passed for the real empty export, corrupt input, output size
limit, conflict, rollback, retry and backup. The serial Core run passed 702 tests
before the last two focused cases; the serial app run passed 886 tests. Local
Debug build, 80 Python tests and matrix structure check passed. Native QA used
File > Import on the real fixture and showed its group in Library Organization.
QA quit normally, its exact registration was removed, and its temporary app
moved to Trash. Imported QA data remains isolated. No real populated group or
separator was tested. Metadata is retained but its visual options are not applied.

### Imported group visibility — 29 October 2026

Core tests cover the observed Mac flags, independent surfaces, invalid values,
full catalog, identity and backup. The serial runs passed 706 Core and 886 app
tests before the final internal module-access adjustment. The local Debug build
and seven focused tests passed after that adjustment. The first Xcode build found
that package-only access did not work for the app target; internal SPI fixed the
build. In isolated QA, a synthetic empty group using the real List-off value was
absent from the list group bar, present in the editor bar selector and present
in Library Organization. QA quit, was unregistered and its temporary app and
fixture moved to Trash. Action-level precedence, search and native restart remain
unverified. The usual app was not updated.

Native Engine QA imported a neutral group and one action. Its installation link
renamed the group. The confirmation named the group and action. Cancel retained
the original group UUID and membership. Replace retained the UUID and moved the
action to the new name. A verification action passed again after QA restarted.
This does not cover implicit group conflicts or all import formats. QA quit
normally, its exact registration was removed, and its app and fixtures moved
to Trash. The isolated QA records remain.

An implicit-group regression first showed that importing the same name with a
different UUID changed the existing identity. The link now rejects that case
and a different name with the same UUID. A matching name and UUID still installs.
Thirteen focused action URL tests, the serial app suite (886 tests), and the
local Debug build passed. Native error presentation is pending.

An additional action link test checks an imported action edit, unknown fields,
an unrelated group, and backup restoration after the group rename. All twelve
focused action link tests and the local Debug build passed. This test does not
replace the pending native confirmation.

### Published main integration — 29 October 2026

Merged published main commit 536eb82 into the editor work branch without
conflicts. The serial Swift suites passed 699 Core and 885 app tests. The local
Debug build, 80 Python tests, and matrix structure check passed. The separate
main checkout had uncommitted website and fixture work; it was not changed.
The prior parallel Core timing failures and native checks remain open.

### Integrated branch verification — 29 October 2026

At commit 4474d96, the normal inventory runner failed in parallel Core tests:
`libraryExclusionCoversLegacyAndAsyncRunnersWithoutBlockingOtherLibraries` and
`cancellationReleasesAnIdleScriptAndPreservesCompletedEffects` missed their wait
conditions. These failures are not accepted as product regressions or dismissed
as noise. Parallel timing fragility was recorded before this run. Both serial
suites passed, and their XML reports matched the discovered inventory: 712 Core
and 890 app cases. This does not explain the parallel failures.

The system Python lacked Pillow and could not import the visual capture tests.
The bundled Python with Pillow passed all 80 script tests. The matrix structural
check passed. The most recent local Debug build passed before this integration
run. These results do not accept native behavior or the strict parity gates.

The two affected tests now cancel their owned tasks if an assertion exits early.
The focused async runner suite passed. A further parallel Core run still failed
at the same two wait conditions. The cleanup change does not resolve or explain
the parallel failures; keep them open.

Additional diagnostics distinguish early completion from an active runner. In a
later parallel Core run, both runners were active with no final report when the
clipboard wait expired. Two promise-lifetime tests also reported timeouts in
that run. The focused async runner suite passed. This narrows the observation;
it does not identify whether scheduling or execution caused the delays.

A further parallel Core run passed those two tests but failed the timeout case
of `cancellationAndTimeoutDrainTheOpeningWaitBeforeReturning`. The focused
async runner and window opening suites passed together. The failures vary with
the full concurrent workload. The cause and product impact remain unproven.

One subsequent parallel Core run passed. A focused stress test also completed
24 independent workers and their host calls. Its host only yields and returns;
the original run did not exercise MainActor or the full test workload. The
updated test sends all 24 clipboard calls through MainActor and confirms that
they run on the main thread. It passed in isolation. Neither result proves the
intermittent failures under the full test workload are resolved.

### Directory group import in isolated QA — 29 October 2026

A local ad-hoc QA bundle used a separate testing library and no Services entries.
The import screen loaded the official Basic Directory page over the network. It
showed the group and 31 entries, including the Services and Apps separators.
Save installed the group. After a normal quit and restart, Basic retained the
same order and separators. No imported action was executed.

The first build showed a generic group header while the group bar showed the
imported symbol. After the header fix, QA showed `arrow.up.forward.app` in both
places. Searching for Copy changed the header to `magnifyingglass`. The focused
presentation suite and local Debug build passed. The QA app quit, its individual
LaunchServices registration was removed, and the app moved to Trash. Its isolated
library remains. This does not verify group replacement review, unsupported step
execution, or a group exported from Drafts itself.

### Group editing and replacement review — 29 October 2026

An isolated local QA app used a separate test library. Editing the imported Basic
folder and saving a different symbol initially failed with a duplicate-name error.
The group editor now presents the group and its previous name as one request.
The same edit then saved and retained the symbol after reopening the editor.

The official Basic Directory group was loaded again. Cancel in the replacement
alert retained the edited symbol. Replace restored the imported symbol. These
checks did not execute the imported actions or verify their external services.
The QA app was quit, unregistered, and moved to Trash. Its test library remains.

The focused library management and action-group persistence suites passed. The
local Debug build passed. These tests do not exercise the SwiftUI sheet binding;
the manual QA check covers the observed regression.

### XML-RPC response depth — 29 October 2026

The response parser already limits XML element depth to 64. A focused test
confirms that a response with 19 nested arrays succeeds and one with 20 nested
arrays fails with an error and no parameters. Array wrappers add XML elements,
so this limit differs from the request encoder's value-depth limit. The XML-RPC
contract suite passed. No product behavior changed.

### Inline HTML code conversion — 29 October 2026

Inline code with backticks previously produced ambiguous Markdown delimiters.
A regression test failed before the change. The converter now protects inline
code during conversion and selects a longer delimiter when needed. The test
covers backticks, entities and Markdown emphasis characters. The HTML preference
suite and local Debug build passed. A native comparison with Drafts and broader
HTML grammar coverage remain pending.

### XML-RPC duplicate response members — 29 October 2026

A response struct with duplicate member names previously reported success and
silently discarded a value. A regression test failed before the correction.
The decoder now returns an error for duplicate names, including inside arrays.
The focused XML-RPC, async transport and loopback suites passed. The local Debug
build passed. Drafts behavior for this malformed response remains unverified.

### HTML ordered list values — 29 October 2026

A regression showed that conversion ignored the value attribute of ordered list
items. The converter now updates that list's counter and keeps nested counters
separate. It reads start and value as attributes, not text inside quoted values.
The HTML preference suite and local Debug build passed. Drafts comparison and
other HTML list variants remain pending.

### Reversed HTML lists — 29 October 2026

The converter now writes descending source markers for reversed ordered lists.
An explicit start and item value update the correct list counter. Without a
start, only direct items determine the initial number. The regression failed
before the change. The HTML preference suite and local Debug build passed.
Markdown renderers can renumber ordered items; this test checks source text,
not rendered parity. Drafts comparison remains pending.

### File operation root containment — 29 October 2026

Legacy readFile, writeFile and fileExists used a lexical path check. A test
showed that a symbolic link could reach a file outside the library root. These
operations now use the existing resolved-path containment check. The shared
check also rejects dangling symbolic links instead of treating them as missing
path components. The regression covers read, write, existence, a dangling link,
and normal Unicode file access. Native file and bookmark suites and the local
Debug build passed. Concurrent filesystem changes, system permission outcomes,
and iCloud Drive access need separate checks.

### Integrated regression after file and conversion changes — 29 October 2026

At 721f716, the full Swift runner passed and its results matched discovery: 725
Core and 901 app tests. The 80 Python script tests passed with the bundled Python.
The matrix structural check reported zero errors. The strict engine parity check
still reported 18 diagnostics across six partial contracts. This run does not
replace their native checks or prove compatibility with Drafts. The local Debug
build passed separately after the file containment change. Previous concurrent
Core timing failures remain recorded; one passing run does not resolve them.

### Subscription compatibility property — 29 October 2026

Draftly has no paid tier. Imported actions must remain available regardless of
Drafts subscription metadata. The compatibility property app.isPro always
returns true. A regression showed that scripts could overwrite it. It is now
read-only. Tests cover both runners, assignment in strict and non-strict code,
and imported metadata with both values. The focused suite, matrix structural
check and local Debug build passed. Native action execution remains separate.

### Subscription compatibility action in QA — 29 October 2026

An isolated ad-hoc QA app used a separate local test library and no Services
entries. A neutral action created in its inspector checked that app.isPro was
true, attempted to assign false, checked it again, and changed the editor text.
The action ran from the Actions menu. The editor showed the expected Unicode
text and the completion message. This confirms the observed UI execution path;
it does not check a Drafts subscription. QA quit normally. Its exact app
registration was removed and its bundle moved to Trash. The test library remains.

### FileManager factory and directory creation — 29 October 2026

The archived reference specifies create(isLocal) and createDirectory(name, path).
Draftly ignored the factory argument and the directory parent. Regressions failed
before the correction. False now selects cloud storage; true selects local. A
named directory is created under its parent. The earlier omitted factory argument
and single-path directory call remain supported. Invalid directory names fail.
Both script runners and the native adapter passed isolated local filesystem tests.
The focused file suites, matrix structural check and local Debug build passed.
Actual iCloud Drive access, native permission failures and Drafts comparison
remain pending.
