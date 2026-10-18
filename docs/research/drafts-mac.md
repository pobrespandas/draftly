# Drafts Mac interface reference

The installed Drafts app was inspected with Computer Use on 2026-10-18. The
inspection used the empty editor, the action list, and the Copy action inspector.
No note content was imported into Draftly.

| Area | Observed control | Draftly implementation |
| --- | --- | --- |
| Main window | Separate filter, draft list, and action panel toggles | Independent toolbar buttons |
| Draft list | Workspace selector, add menu, search, and folder icons | Compact header and capsule folder selector |
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
buttons. A flexible space separates the folder controls from Share. Header
menus use native buttons with 20-point symbols. Their menus keep the same
actions as the previous controls. The sort menu shows the active sort order.

The folder selector has a capsule background and a neutral selection fill.
Each folder button has a label and exposes its selected state to accessibility.
The tag field uses a 12-point font. Panel titles use a regular 22-point font.

Computer Use checks confirmed that the workspace menu opens, the sort menu
changes the note order, and the folder selector updates the list and empty
state. The checks did not change note content. The local Xcode build passed.

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
