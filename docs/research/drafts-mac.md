# Drafts Mac interface reference

The installed Drafts app was inspected with Computer Use on 2026-10-18. The
inspection used the empty editor, the action list, and the Copy action inspector.
No draft content was imported into Draftly.

| Area | Observed control | Draftly implementation |
| --- | --- | --- |
| Main window | Separate filter, draft list, and action panel toggles | Independent toolbar buttons |
| Draft list | Workspace selector, add menu, search, and draft view icons | Compact header and capsule draft view selector |
| Draft list | Count and sort above the list | Count and sort menu |
| Editor | Blank draft with keyboard focus | Temporary draft that saves after typing |
| Editor footer | Undo, redo, navigation, tasks, date, indentation, and clipboard | Compact action bar |
| Actions | Group selector, add menu, search, and log | Compact action header |
| Action footer | Group shortcuts | Group tabs |
| Action editor | Action settings, step list, and step details | Three separate inspector panels |
| Toolbar | Previous and next draft, share, palette, and quick search | Native toolbar controls |

The interface keeps the Draftly name and supported feature set. Service-specific
actions, custom themes, and the AI console are not copied. Dictation uses the
native macOS command.

## Control measurements

The reference window is 1033 by 734 points. The main toolbar is 52 points high.
The panel utility rows are 48 points high. Action rows are 28 points high.
The bottom editing bar is 31 points high. The editor footer is 29 points high.

The editor uses a 17-point system monospace font. The reference line height is
1.1. Draftly uses a 2-point line gap and a 17-point text inset. Tags use an
NSTokenField. Search uses an NSSearchField. The main toolbar uses NSToolbar.

Panel widths can change when the user moves a divider. The default action
catalog differs from Drafts. It contains supported actions only.

## Visual polish checks

The toolbar uses fixed spaces between the filter, draft list, and last draft
buttons. A flexible space separates the draft organization controls from Share. Header
menus use native buttons with 20-point symbols. Their menus keep the same
actions as the previous controls. The sort menu shows the active sort order.

The draft view selector has a capsule background and a neutral selection fill.
Each draft view button has a label and exposes its selected state to accessibility.
The tag field uses a 12-point font. Panel titles use a regular 22-point font.

Computer Use checks confirmed that the workspace menu opens, the sort menu
changes the draft order, and the draft view selector updates the list and empty
state. The checks did not change draft content. The local Xcode build passed.

The window title stays available to the window menu and accessibility. It is
hidden in the toolbar. Opening a saved draft does not move the toolbar items.
This behavior was checked after the final local build.

## Action search and feedback

The reference action search includes all groups. A nonempty query changes the
heading to Search. The heading uses a blue search symbol. Both panels use the
same empty state with braces and a message. The search field has no outer focus
ring. Its header button has a filled circle while the field is visible.

Draftly uses these search states. A search for Rich from General found the
imported Copy as Rich Text action during the interface check. A query with no
matches showed No actions found. Clearing and hiding search restored the group.

Action rows have an inset rounded background on hover and press. Disabled rows
are dimmed and cannot run. The editor footer uses native menus for Arrange and
Syntax Highlighting. Both menus use the secondary label color.

## Review fixes and integrated preview

Capture first saves the current draft. A failed save leaves its content and
selection in place. The pending capture is cleared only after a successful
transition. Automated tests cover saved drafts and temporary drafts.

The footer reduces spacing and text size in a narrow editor. The interface
check used four panels and confirmed that the preview button and full count
remained visible. The editor action bar can select library groups. The Imported
group showed its Copy as Rich Text and Save in Obsidian Vault buttons.

Clear Filters removes workspace tag restrictions. The sidebar reports those
restrictions while they are active. Draft pinning and window floating have
separate controls and state. New Draft After is configurable in Settings.

List Options has persistent preview, tag, and date controls. Preview Lines has
one, two, and three line choices. Interface checks confirmed that options
survived an app restart. The original display options were restored after the
check.

The eye button switches the center panel between text and rendered Markdown.
The native editor stays mounted to keep its selection and undo history. The
preview uses a WKWebView with JavaScript disabled. Preview actions from the
current window use the same panel. New draft creation returns to text editing.
The interface check confirmed that the eye button and Option-Command-P switch
both ways within the main window.

## Parity audit — 2026-10-19

This audit compared the installed Drafts app with the local verification build
of Draftly. It used Computer Use and source inspection. No draft content was
changed, and no action was executed. Different libraries contain different
content and action catalogs. Their row counts are not a parity defect.

Drafts showed a Pro restriction in the action step inspector. Several list and
action menu items were disabled. Their controls were inspected, but their effects
were not tested. The disabled state must not be copied as a product requirement.

### Functional corrections first

| Priority | Finding | Evidence and scenario |
| --- | --- | --- |
| P1 | Batch archive changes each draft to the opposite state | `NativeDraftTable.Coordinator` uses `isArchived.toggle()`. In All, select one Inbox draft and one Archive draft. The Archive command would put the archived draft back in Inbox. Use the named destination for the full selection. This was found in code; it was not run on user data. |
| P1 | Batch flag has the same mixed-state problem | The context menu changes each flag independently. A selection with flagged and unflagged drafts cannot receive one common target state. |
| P1 | Duplicate loses metadata | The context menu creates a draft from content and tags only. It does not copy the source flag or syntax. Define the intended duplicate contract before adding the missing metadata. Drafts exposes Duplicate, but its metadata behavior was not tested in this audit. |
| P1 | The action editor accepts shortcuts that the command menu suppresses | Copy shows Command-Option-1 in the Draftly inspector. The command registration excludes Command-Option-1 and Command-Option-2 to protect panel toggles. The editor gives no conflict message. |

### Missing behavior and controls

| Area | Drafts reference | Draftly gap |
| --- | --- | --- |
| Draft context menu | New window/tab, explicit Inbox/Archive/Trash destinations, flag colors, tag add/remove, syntax, Run Action, Merge, Info, Versions, Copy, Share, Export, Empty Trash | The current menu has Archive, Flag, Trash/Restore, and Duplicate. Some other operations exist elsewhere, but are not available here. Merge was disabled for the single reference selection. |
| Draft list options | Workspace Bar, search preview, last action, separate Inbox/Archive flag inclusion and sorting, swipe default, Save as Default | Only preview lines, tags, and date are present. Save Workspace is not the same operation as Save as Default. |
| Flag choices | Orange, Red, Purple, Blue, Yellow, Green, Gray, and Clear Flag | The current menus expose six colors and no Gray choice. Their order also differs. Numeric color compatibility was not verified. |
| Workspaces | A management entry and Save Current in the Workspaces menu | Draftly offers selection and a Save Workspace form. It has no equivalent management interface for editing, ordering, and deleting saved workspaces. The reference management entry was disabled. |
| Action list options | Action Log, Search, group bar, keyboard shortcuts, Chat Console, and three visibility filters | Draftly offers Import from Directory and Execution History in this menu. Its search and group controls exist elsewhere. The visibility filters and console are missing. |
| Action organization | Reference groups contain section rows such as Services and Apps | Draftly builds groups from action names, sorts them alphabetically, and applies a fixed preferred action order. It has no equivalent section layout or group order editor. |
| Action properties | Description, icon picker, action bar label and icon visibility, special shortcut keys, after-success flag/tags, notifications, log level, confirmation, visibility by surface and platform, action versions and sharing | Draftly has name, group, an SF Symbol text field, shortcut modifiers, and a move-after-success picker. The other controls and several corresponding behaviors are absent. |
| Action steps | Named step controls, write type choices, template type choices, platform switches, and step summaries | Draftly edits a filtered set of raw value fields. It has no enable/disable control, platform switches, typed step forms, or full template editor. Import can preserve disabled steps without making them editable in the UI. |
| Settings | General, iCloud, Bookmarks, Notifications, Markdown, HTML, Mail Drop, Auto-Import, Credentials, Extensions | Draftly has one form for font, spacing, capture timeout, and data status. Native APIs for some resources do not provide an equivalent settings interface. |
| Global capture controls | Configurable main-window, quick-capture, and clipboard shortcuts; launch and menu-bar options | Draftly registers one fixed capture shortcut. Clipboard capture exists in its status menu, but has no equivalent shortcut control. |
| After-success navigation | A setting for what happens after an action moves its source draft | Draftly changes the source organization state. It has no equivalent global choice for the next editor draft. |
| Editor menus | A separate Editor menu, app appearance, editor theme choices, font size commands, and typewriter scrolling | Some operations exist as buttons or scripting APIs. Draftly has no matching Editor menu or full theme selector. |

### Visual differences still visible

- The action inspector is a fixed-size sheet in Draftly. Drafts uses a separate
  window. The column proportions, title area, form density, step summary, and
  bottom controls differ substantially.
- The toolbar lacks the Action List/Chat Console selector. Float on top has a
  different size and placement. Other item spacing and group boundaries differ.
- The editor action bar has a different button order, symbols, and colors. Its
  built-in group lacks the Mail and Message buttons seen in Drafts. The extra
  Markdown preview control is a requested Draftly feature and should remain.
- Draft list rows lack the dotted separators seen in Drafts. Long previews,
  multiple tags, and flag placement still need a controlled comparison with
  equivalent test content.
- Draftly uses generic footer group icons and a different action catalog. Drafts
  uses distinct group icons and section labels.
- The two apps initially had different search-field and panel visibility states.
  Those state differences must not be counted as missing layout. No exact pixel
  match is claimed: the reference windows had different overall dimensions.

### Existing behavior to preserve

Draftly already has in-app Markdown preview, native text and tag controls,
preview-line/tag/date options, multiple selection, basic workspace saving,
clipboard capture, action import, and revision history. The previous transition
check measured the filter toolbar motion without reversals. This audit did not
repeat that temporal measurement.

The scripting API remains partial. The limitations in `docs/compatibility.md`
include XML-RPC, Mustache template directories, some URL and mail options,
HTML conversion, and the chat console. This interface audit does not establish
end-to-end service compatibility or live iCloud sync.

### Recommended implementation order

1. Correct mixed-selection operations and report shortcut conflicts.
2. Complete the draft context menu and draft list display options.
3. Match the action list, group order, sections, and visibility rules.
4. Expand action properties and typed step controls, then match the inspector.
5. Complete workspace management, editor menus, and settings.
6. Use equivalent test content and window sizes for the final visual pass.

## Context menu delivery — 2026-10-19

The preceding audit tables describe the baseline before this delivery. The
mixed-selection archive and flag defects are corrected. Duplicate now retains
content, tags, flag, and syntax, with new identity and dates in Inbox. It does
not copy history or internal metadata. Shortcut conflicts use the same validator
in the action inspector and command registration. Existing conflicting shortcuts
remain stored, but are not registered; the inspector explains the conflict.

The draft context menu now includes window/tab opening, explicit destinations,
Restore, seven flag colors, tag changes, syntax changes, action selection,
Merge, Duplicate, independent Info and Versions targets, Copy variants, native
sharing services, TXT/CSV/JSON export, and confirmed Empty Trash. Single-draft
commands and Merge have selection limits. Actions run in captured list order and
stop on failure or cancellation. External effects from completed steps remain.

JSON exports contain a `drafts` array with UUID, title, content, tags, flag,
syntax, archive state, Trash date, and creation/modification dates. The importer
accepts these optional fields and still accepts legacy `isFlagged` data. CSV
uses the same columns and quotes every field. A full backup remains a separate
format. No stored schema migration is needed.

See `docs/validation.md` for tests and QA boundaries. The other audit gaps,
including list preferences, action organization and inspector parity, workspace
management, themes, and settings, remain outside this delivery.

## Main window presentation pass — 2026-10-19

The live reference showed an outline filter symbol and an italic empty-filter
label. Draftly now uses both. Tag rows start eight points higher. Draft and
action headers share their inset, spacing, and height. Draft rows have dotted
separators. The editing bar follows the relative order of the reference controls.
Toggle Tasks uses purple. Float on Top uses a smaller symbol. The Markdown
preview button sits beside the syntax menu.

Editor status messages now appear in a temporary overlay. They do not change
the editor height. Library errors still use the existing alert. The panel
minimum widths now allow all four panels to fit at 850 points. The footer uses
less spacing at narrow widths. The Filters heading stays on one line.

Shared dimensions are in `MainWindowStyle`. A Visual QA menu is available only
in a bundle with `DraftlyUITesting` enabled. It sets the three test window sizes
and the local window theme. It is absent from the normal app.

Visual parity is still partial. The sidebar material, exact toolbar grouping,
and footer spacing need an aligned comparison with the reference. The current
screenshots do not prove one-point accuracy. The action catalog is intentionally
different. See `docs/validation.md` for evidence and remaining checks.

### Tab-bar correction — 2026-10-19

The filter item now uses native sidebar behavior and full-height layout. Live
checks show the tab bar begins after filters, as in Drafts. The old generic item
made tabs span the entire window and moved filters down. Native sidebar sizing
initially reduced the width to 160 points. Explicit initial divider positions
restore 240-point filters and the 280-point list. Existing collapse tests pass.

The sidebar now shows its native material. Folder selection responds to active
window state. The list search uses a 30-point layout height. The narrow-window
check now reaches 850 by 600 including visible tabs, with native toolbar overflow.
Screenshots are in `screenshots/visual-parity-2026-10-19/`. These changes do not
establish full pixel parity for populated lists or every window state.

### Note typography correction — 2026-10-19

Compared the installed Drafts selected row and editor with Draftly. The list
uses a 14-point bold title, a 13-point preview, 10-point tags, and an 11-point date.
Rows use one presentation helper for both preview text and height. Paragraphs
have bullet separators. The title, tags, and date have fixed line heights. Preview
text keeps its measured height when selection changes. A full two-line preview
with tags and a date uses a 105-point row at the reference list width.

Native table emphasis now sets white title and tag text, lighter preview text,
and a dim date. Inactive selection keeps native neutral colors. Noninteractive
hosting cells pass mouse events to the table. This fixes row clicks that left
focus in the tag field. Dates use English relative day labels and 24-hour time,
with regional numeric dates for older notes.

The editor has a System font option and uses it by default for new preferences.
Existing font choices remain unchanged. This Mac still uses its chosen Fira Code
Nerd Font. Editor text therefore does not have the same glyph widths as the
reference system font while that choice remains active.

Live checks used neutral text in a temporary DraftlyRowsQA library. Long titles,
two preview lines, tags, short notes, active selection, inactive selection, and
dark appearance were checked. Screenshots are in
`screenshots/note-typography-2026-10-19/`. The reference was inspected without
editing its drafts. No private reference content was copied into test fixtures
or saved in the new screenshots. This pass does not certify every pixel or font
configuration.

### Main window comparison follow-up — 2026-10-19

Reference version: Drafts 54.1.1. The editor uses SYSTEM at 17 points, line height
1.1, and zero paragraph spacing. The user chose System for normal Draftly too.
The filter toolbar button now belongs to the native sidebar region. Its standard
tracking separator follows the real split view. Search previews use matching
lines and original line numbers. Action titles use 13 points. Footer symbols use
11 points, with distinct history symbols and horizontal scrolling.

See the Main window comparison section in `../validation.md` for test results,
capture sizes, and open acceptance checks. The capture-scale defect prevents a
one-point comparison. Status-menu icons and Reduce Motion remain unverified.
Do not mark the visual delivery complete from this pass.

## Main-window closure evidence — 2026-10-19

Drafts 54.1.1 remains the reference. The final local list comparison now matches
its 81-point row pitch. Four consecutive title bands align. See
`main-closure-2026-10-19` under `screenshots` for the crop and measurement data.
The status menu has a complete capture with visible icons and a recent-draft
submenu. Reduce Motion was checked through the real macOS setting and restored.
A quit/reopen check retained a new neutral draft in a temporary library.

Full visual parity remains open. The capture backend can place 1x content in a
2x canvas. The new capture checker rejects that defect for full-window metrics.
The reference also moves its history toolbar cluster as window width changes.
The seven native spaces in Draftly do not reproduce that responsive behavior.
Custom and fixed-width spacer prototypes failed visual inspection and were
removed. See the latest section in `../validation.md` for the acceptance limits.

## Responsive toolbar follow-up — 2026-10-19

The seven fixed toolbar spaces now use one native flexible space. The real
split separator remains connected. Draftly also keeps the one-tab bar visible,
as observed after restarting Drafts 54.1.1. Header offsets align search, folder
controls, count, and the Tags heading without changing row height.

Valid light captures at 1033 x 734 and 1200 x 800 points are stored in
`screenshots/visual-close-2026-10-19`. The reference capture is 1115 x 645 points.
Do not treat these as the complete equal-size acceptance matrix. Dark and narrow
captures from this pass failed the scale check. See `../validation.md` for the
separate implementation, automated test, and native use results.
