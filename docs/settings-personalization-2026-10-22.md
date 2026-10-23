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

## Indentation field preservation follow-up

The complete validated source at a54f4f0 is the new stage base. The annotated
pre-settings-editor-2026-10-22 tag retains it. A failing regression confirmed that
one future nested JSON field caused valid syntax styles and unknown siblings to
be discarded on edit. Reading now resolves only the selected string. Writing
patches that key and retains other JSON values. Invalid JSON remains unchanged;
the control is disabled with an explicit message. Nine focused app methods and
local Debug passed. The source signature and preference key remain unchanged.

## Escaped-line-break reference comparison

Drafts54.1.1 was confirmed from its installed bundle. CUA created two neutral
notes and opened the Basic preview. With Escaped line breaks enabled, a trailing
backslash produced a visible line break. A multiline inline-code span retained
its slash and collapsed its newline; two trailing spaces also made a break.

CUA disabled the option and verified its checkbox was off. The same preview still
showed the break. A neutral text edit and reopening the preview did not clarify
the result. After normal Quit and restart, a new neutral document still rendered
the trailing backslash as a break with the saved checkbox off. This is a reference
discrepancy, not proof that a missing implementation should be a no-op toggle.
No new renderer rule or setting was added. Restore the original enabled state:
CUA confirmed the checkbox on before closing Settings. Both neutral notes were
moved individually to recoverable Trash. No other notes or filters changed.
No clipboard-copy command, microphone or external action ran.

Two official Settings pages consulted on22 October are archived in the separate
settings-reference directory with URLs, dates and SHA-256 hashes. They supplement
and do not replace the19 October baseline. The Markdown guide describes an
escaped trailing backslash as forcing a new line. Context7 resolved MultiMarkdown7;
its documentation cannot establish a version6 disable-option contract. The
bundled version6 source has no equivalent extension flag. The disabled-state
behavior remains unresolved and must not be presented as accepted parity.

## Editor Settings navigation batch

EditorSettingsView now owns the existing font, layout, syntax and theme controls.
Its Editing, Syntax Settings and Themes sections separate these controls.
EditorSettingsNavigation keeps built-in syntax order, adds sorted installed names
and removes exact duplicates. It preserves the selected syntax across sections
and returns to Markdown if an installed selection disappears. No stored format
or preference key changed. Fonts and layout remain global, as the caption states.
This batch does not add per-syntax fonts, autocomplete management or a separate
native Editor Settings window. Those reference differences remain pending.

Four headless navigation methods cover initial state, Unicode names, duplicate
names, catalog removal and independent state. The focused26 app methods in six
suites and local Debug build passed. Existing font tests retain their names.

In isolated QA, CUA selected TaskPaper and set Insert to2 Spaces. Markdown stayed
on Tab. Both values remained after normal Quit and restart. Theme navigation
showed the restored day and night identities. Opening Settings, switching to
Themes and closing retained the neutral note text and the café 🐼 selection.
This checks these bindings and selection only. The earlier Undo/Redo acceptance
remains separate. No microphone, external service or personal data was used.
The Markdown reader failure was not repeated. No scale measurement or visual
parity acceptance is claimed. Full regression results follow separately.

Complete Swift regression passed Core681/app820. The runner matched discovered
identities to fresh XML results. Python80 and structural matrix0 passed. Local
Debug passed. No deadline, retry rule, API matrix classification or contract test
name changed. QA quit normally. Its exact LaunchServices entry was removed;
its package passed ZIP integrity verification before removal from the temporary
launch path. Neutral library and preferences remain. The recoverable archive is
in local DraftlyRecovery/editor-settings-20261022-232859. The usual app was not
replaced. Full visual acceptance, per-syntax font/layout options and the native
checks listed above remain pending. This batch does not close Settings.

The updated signed Release build passed. Signature and profile verification
confirmed com.pobrespandas.draftly, team NM92LU2KKV and the unchanged
iCloud.com.andrestobelem.draftly container. The candidate stays in ignored
.build/settings-personal. It was not installed or used as synchronization proof.
