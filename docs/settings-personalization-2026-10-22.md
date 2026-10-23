# Settings and personalization — 22 October 2026

## Scope and baseline

Start: ca2d450. Preserve the installed app, library, local preferences and shared
theme identities. This stage excludes engine changes, Workspace fixes and iCloud
acceptance. Visual tolerance is three points. Do not repeat accepted mic checks.

The first complete Core run executed679 tests and reported three timeout issues
in two WorkerPromiseEpochTests methods. Both methods passed in a focused run.
The app suite passed810. Local Debug build and structural matrix0 passed.
System Python lacked Pillow and could not import test_visual_capture. The bundled
Python runtime passed all80 tests. No source, timeout or retry rule changed for
these results. Tag pre-settings-personalization-2026-10-22 retains this baseline
and states its known Core failure. Do not call the first full run green.

## Reference observations

Computer Use read General, Markdown, HTML and Editor Settings in Drafts without
changing values. General places Touch Bar above global shortcuts. Markdown has
an Escaped line breaks switch that Draftly does not expose. HTML uses text fields
for marks. Editor Settings has a syntax sidebar and Editing, Autocomplete,
Syntaxes and Themes pages. Draftly currently combines editor controls in one
scrolling page. These are real differences, not a completed visual comparison.

The native screenshots have a one-scale content region inside a larger white
canvas. They are invalid for point measurements. Keep qualitative observations;
do not declare the three-point gate passed from these images. No screenshots
enter Git. The reference remains Drafts54.1.1 and its dated archived contracts.
Escaped line breaks needs behavior comparison before adding a renderer rule:
the bundled MultiMarkdown extension flags have no equivalent switch.

## Control inventory

Each row lists the storage and its consumer. Existing tests establish only their
named behavior. Native acceptance remains pending unless a later entry says so.

| Controls | Storage and defaults | Consumer | Existing specific coverage / remaining acceptance |
| --- | --- | --- | --- |
| Appearance | application.appearance, System | NSApp appearance and window theme resolution | AppThemeContractTests; native light/dark and restart pending |
| Launch at login | SMAppService status; no simulated preference | LoginItemPreferences | LoginItemPreferencesTests; real service-capable install pending |
| Initial window / menu bar | application.showMainWindowAtLaunch / showInMenuBar, true | App launch and status item | startup and General preference tests; remaining restoration variants pending |
| Capture timeout | capture.newDraftAfter,300 seconds | Capture reuse policy | capture tests; native restart pending |
| After Success navigation | application.actionMoveNavigation, Create New Draft | completed action navigation | existing navigation tests; no engine change |
| Advanced Find / Touch Bar | editor.preferAdvancedFind false / showCustomTouchBar true | Find entry and Touch Bar delegate | existing Find/Touch Bar tests; physical Touch Bar requires hardware |
| Three global shortcuts | commands.bindings plus current command defaults | global shortcut registrar | GlobalShortcutTests, ShortcutRecordingInputTests; physical delivery pending |
| Local command shortcuts | commands.bindings | CommandShortcuts / command modifier | CommandShortcutTests; native record/cancel/reset pending |
| Font / size | editor.fontName System / fontSize17 | editor styles | EditorPreferenceTests; Nerd Fonts must remain available |
| Line height / paragraph | editor.lineHeightMultiple0 / paragraphSpacing0; legacy lineSpacing2 | EditorParagraphLayout | EditorPreferenceTests, EditorPreferenceDisplayTests; native restart pending |
| Margins / width / typewriter | horizontalMargin6, verticalMargin26, maximumWidth0, typewriter false | editor layout and scrolling | editor layout tests; selection and Undo acceptance pending |
| Syntax indentation and features | editor indentation / syntax-feature dictionaries | text input and syntax rendering | existing syntax and indentation tests; all selector routes pending |
| Theme selection and definitions | local theme references; generic shared theme records | InstalledThemeCommands and theme resolver | InstalledThemeCommandsTests, ThemePickerOptionsTests, LocalThemeMigrationTests; restored rendering pending |
| Theme files / Reload | local scoped bookmarks and source IDs | ThemeFileAccess and development refresh | ThemeDevelopmentRefreshTests, FileThemeApplicationTests; native file/restart pending |
| Bookmarks | bookmark.name scoped Data | file API and BookmarkPreferences | BookmarkPreferencesTests, BookmarkReopenContractTests; native cancel/Forget pending |
| Markdown processor | markdown.processor multi | MarkdownPreferences.render | MarkdownPreferencesTests; native switch/persistence pending |
| MultiMarkdown switches | markdown.options.multi, defaults from option catalog | ScriptMarkdown.multi | MarkdownOptionContractTests; omitted Escaped line breaks remains unresolved |
| GitHub switches | markdown.options.github, defaults from option catalog | ScriptMarkdown.github | MarkdownOptionContractTests; native live preview pending |
| HTML paste and marks | html.pasteAsMarkdown true; strong **, emphasis _, list - | DraftTextView HTML paste | HTMLPreferencesTests, EditorHTMLPreferenceContractTests; native checks pending |
| HTML links / images / emphasis | inlineLinks true; other flags false | HTML converter | EditorHTMLPreferenceContractTests; disabled values must survive edits |
| Reference help | documentation topics; no preference | SettingsReferenceHelp | native navigation pending |
| iCloud | existing tab and library status | existing sync status view | unchanged; no new synchronization acceptance |

## First functional correction

Markdown option editing currently writes all default values and decodes only
Boolean dictionaries. A future non-Boolean field can discard all stored options.
The correction must patch one stored key, preserve unknown JSON values and leave
absent defaults absent. Invalid JSON must remain intact and report an edit error.

## Markdown field preservation correction

A new regression showed smartQuotesEnabled false becoming true when a future
object field was present. Markdown reads now select Boolean JSON fields without
invalidating their siblings. The form patches only the selected key, retaining
unknown objects, arrays, null and Unicode. Opening the form still writes nothing.
Invalid option JSON reports an error without replacing the original string.
Three new app methods and19 existing Core methods passed. Local Debug passed.
No renderer flag or public API changed. Native binding acceptance is pending.

Opening Settings in fresh Engine QA again closed the CUA native pipe. The QA
process stayed alive. Rebinding by exact path did not restore observation. This
is a reader failure, not evidence of an app exit. The user was asked to close
only QA Settings or quit QA. No preference or personal library was changed.

## Shortcut correction

Two new Core regressions failed before the correction. Empty local overrides
fell back to the default key. A malformed future entry also discarded valid
sibling overrides. Editable commands now accept an explicit empty binding;
fixed macOS commands remain fixed. Each stored command decodes independently.

Settings adds Clear Shortcut, distinct from Reset Command. Clear disables the
selected command. Reset restores its default. Local and global edits patch known
fields, retain future fields and siblings, and reject invalid JSON without a
replacement. Matching recorded physical key codes survive Save. Eight app
methods and ten Core methods passed. Local build results follow below.

## Native checks on the Markdown correction candidate

The user closed QA Settings and CUA recovered. General opened after the QA
fixture selected General as its initial page; no habitual preference changed.
Editor Settings showed persisted17 points and1.1 line height. CUA changed these
to19 and1.2, enabled typewriter, and reopened the pane to confirm the values.
The neutral text stayed intact. Undo removed the original insertion; Redo restored
it. These gestures prove text/Undo for this sequence, not every selection case.
Find opened Advanced Find after enabling that preference. A new Unicode bookmark
name followed by Cancel did not add a row or remove the existing QA bookmark.

Entering Markdown again closed the native reader pipe. The user closed that
window and CUA recovered. Do not repeat the failing observation in this session.
This does not establish Markdown bindings or a product crash. QA quit normally.

The shortcut correction local Debug build passed. No public signature, action
shortcut or persisted preference key changed. Native acceptance is separate.

## Presentation batch

General now places Touch Bar before global shortcuts, as observed in Drafts.
HTML mark options now use editable text fields, as observed in the reference.
Existing invalid or unknown stored strings remain visible; the converter retains
its existing safe fallback. This batch changes no consumer rule or preference
key. The26 related app methods in seven suites and local Debug build passed.
There is no claim of measured visual parity. Full Editor Settings structure and
all remaining native cases in the inventory are still pending.

## Restored-theme coverage and shortcut native acceptance

A new headless integration case restores a theme backup, resolves the selected
local identity through WindowModel, and checks background, unknown fields,
content, UTF-16 selection, focus and unchanged reference data. It adds coverage
between persistence and presentation; it does not replace existing tests.
Fifteen related app methods and five Core methods passed.

CUA verified local Clear shows no assigned key, Reset restores Command-N, and
Escape exits active recording without replacing the old binding. It recorded
Control-Option-Command-Y, saved, quit and reopened QA. The same assignment was
visible after restart; its stored keyCode was16. Reset restored the original
command. These checks used no global key delivery or private data.

CUA imported scripts/fixtures/app-theme-backup.json into the neutral library.
Editor Settings showed QA Theme day and QA Theme night café 🐼 in their slots.
Loading the retained neutral note rendered the dark-blue restored theme with
its text. The content stayed intact. Screenshot scale remains invalid for point
measurements. This is native recovery/render acceptance for that fixture only.


## Final regression and remaining acceptance

Complete Swift results match the discovered inventory and XML: Core681/app815.
Python80 passed with the bundled runtime. Structural matrix check returned0.
The first baseline Core timeout remains recorded; the final run passed without
changing a deadline or adding a runner retry. Local Debug builds passed after
the production batches. A signed Release candidate is prepared separately.

CUA also confirmed TaskPaper can be selected in Editor Settings and that both
MultiMarkdown and TaskPaper appear in that menu. This is not acceptance of every
syntax route. Drafts itself has no built-in HTML syntax in the observed sidebar;
HTML conversion settings are a separate category, not an invented built-in.

QA quit normally. Its exact registration was removed and its package was zipped
under local DraftlyRecovery. The archive passed its integrity check. Its neutral
library and preferences remain available. The habitual app was not replaced.

Outstanding implementation: the Escaped line breaks control and its validated
consumer behavior; the full syntax-oriented Editor Settings presentation and
controls seen in Drafts. Do not add a fake renderer switch or call these external
blocks. Remaining native checks include full theme file/import/reload paths,
bookmark selection/Forget/access failure, all Markdown/HTML option bindings,
startup variants, login registration and physical global keys. Reuse existing
accepted evidence; do not repeat mic checks. Restored-theme rendering has the
specific acceptance above, not blanket acceptance for all theme paths.

Visual acceptance is still pending. Native screenshots have invalid scale, and
Markdown repeatedly breaks the reader. Do not count these as a three-point
measurement pass or proof that Settings is complete. A physical Touch Bar also
needs supported hardware. No new iCloud or engine acceptance is claimed.

The isolated signed Release build passed. Signature and profile verification
confirmed com.pobrespandas.draftly, team NM92LU2KKV and the unchanged
iCloud.com.andrestobelem.draftly container in Development. The profile expires
21 October2027 and includes two devices. No habitual installation occurred:
mandatory Settings acceptance is not complete. The candidate remains in the
ignored .build/settings-personal output. Signing is not synchronization proof.
