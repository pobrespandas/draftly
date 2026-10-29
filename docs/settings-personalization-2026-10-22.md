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

## Native theme files and bookmarks follow-up

This batch starts at ff3e3f1. It changes no production code, test rule or stored
format. The isolated Engine QA package uses the same neutral library and local
preferences as the previous Settings session. It publishes no Services.

### Verified in use

CUA selected a neutral Drafts theme through Use Theme File. A first definition
without description produced an explicit validation error and kept the previous
selection. Adding the required string allowed installation as a file theme.
The dark slot showed QA External café 🐼 (File). Reload applied an external
background change from152535 to354525. After normal Quit and restart, the same
file theme remained selected. Replacing its JSON with invalid text made Reload
show an explicit error without changing selection. Restoring valid JSON and
pressing Reload cleared the error. The neutral editor then rendered the green
background and retained its original text. This is qualitative render evidence;
the screenshot still has invalid scale for point measurements.

Import Theme opened the review form with the expected source colors. Save
created QA Imported café 🐼. Editing its name and background, then Cancel and
reopen, retained the saved name and354525 background. A readonly check of the
closed QA database confirmed distinct file/custom UUIDs and the preserved
future object from the original Drafts source. No uncommitted theme record was
saved. The only note still contained its exact neutral text.

Choose Folder registered the neutral theme directory and enabled refresh. The
view reported one loaded file. Reload Folder completed without an error. Turning
refresh off disabled Reload Folder; both file and imported themes stayed in the
picker. This does not accept every automatic refresh or replacement scenario.

Add Bookmark selected a neutral folder with the name QA Folder café 🐼. The
row remained after normal Quit and restart. A second use of that name showed
an explicit duplicate message and kept Select Folder disabled. Cancel retained
the existing rows. Forget removed only that neutral bookmark. The old QA Local
Write Access bookmark stayed. A closed-preference check confirmed both results;
the neutral input file remained intact on disk. The screenshot has a coordinate
scale mismatch: one coordinate attempt selected General and changed no value.
The observed two-to-one mapping allowed the intended Forget button to work.
Do not treat that screenshot as a valid visual measurement.

### Automatic checks and limits

The existing six Core file-theme methods and14 app methods in six suites passed.
They cover commands, file application, folder refresh, bookmark names, native
file API routing and bookmark reopen/recovery. The existing cases already cover
unknown fields, storage failures, invalid/deleted files and retained selections.
No duplicate test was added. Local Debug build passed after the focused run.
The previous complete Core681/app820, Python80, signed Release and matrix0
results remain unchanged; they were not rerun as new results for this doc batch.

QA quit normally. The exact LaunchServices entry was removed. Its package ZIP
passed integrity verification before the temporary launch package was removed.
Neutral inputs were copied beside the archive in local
DraftlyRecovery/settings-files-20261022-233652. The original neutral inputs and
QA library/preferences remain. Reusing an archive at another path can require
reselecting external files; no cross-path bookmark transfer is claimed.

Remaining native work includes theme replacement/reselection, unavailable file
permissions, bookmark access failures, all Markdown/HTML option bindings, startup
and login variants, physical keys and valid-scale visual acceptance. Full
per-syntax font/layout options remain implementation work. Do not reopen the
known failing Markdown reader or repeat accepted microphone checks. The usual
app remains unchanged. This batch does not close Settings or synchronization.

## Device theme reference field preservation

Inspection before the next native batch found a separate persistence defect.
EditorThemePreferences cast the whole stored object to a dictionary of reference
objects. An unknown array or scalar discarded otherwise valid light/dark slots
on read. Editing then replaced those fields. Malformed JSON was also replaced
by a new pair instead of reporting an error.

The four existing preference methods passed before edits. Two added methods
failed with17 issues before the correction. Reading now decodes each reference
slot independently. Writing patches the chosen slot in the full JSON object.
Unknown arrays, objects, nulls and Unicode remain intact. Invalid JSON and wrong
storage types reject writes with an explicit error and retain the original data
and revision. Absent storage still accepts an initial selection. Reads do not
write missing defaults. Public APIs, preference keys and theme identities stay
unchanged. The focused25 app methods in six suites passed after the correction.
No existing case or test name was removed. Full and native results follow.

The first complete Core run failed one existing AsyncHostDrainTests case:
scriptRequestKeepsLibraryBusyUntilCancelledHostCleanupReturns(timeout: true)
ended before its host started. This exact failure is recorded before these
changes in the Cloud QA preparation and editor text mutation records. The
focused two methods passed, including both timeout variants. No deadline,
execution rule or runner retry changed. A separate complete confirmation run
is recorded below; it does not erase the initial failure.

The separate complete confirmation passed Core681/app822 with matching discovery
and XML results. Python80, structural matrix0 and local Debug passed. No test
window, permission, sound or personal data was used. The historical Core startup
fragility remains open. The first failed run remains recorded above.

In isolated QA, the native selectors showed the saved custom identities with
future array/scalar fields present. Changing only the light slot preserved the
dark reference and the unknown fields in a closed-preference check. With invalid
QA JSON, a light-slot change showed the explicit error and left the picker on
Light. After normal Quit, the invalid bytes and theme revision were unchanged.
The valid neutral reference data were then restored. These native checks finished
on23 October; the archived Drafts reference did not change. No file replacement
or unavailable-file acceptance is inferred from this preference check.

The QA refresh guard caught a missing DraftlyCallbackScheme in the old QA plist.
Only the temporary QA plist received its existing isolated scheme value before
refresh. Bundle identity, library ID, URL scheme and disabled Services stayed
unchanged. QA quit and its exact registration was removed. Its verified ZIP is
in local DraftlyRecovery/theme-references-20261023-000112. Neutral data remain.
No screenshots, logs or preference dumps were added to Git. The habitual app
was not replaced. Remaining native theme cases and the Settings stage stay open.

Signed Release and signature/profile checks passed with com.pobrespandas.draftly,
team NM92LU2KKV and the existing iCloud.com.andrestobelem.draftly container.
The candidate remains isolated in .build/settings-personal. This is not an
installation or synchronization result.

## Native theme replacement and reselection — 23 October 2026

This documentation batch uses the validated2903882 source. No production code
or test rule changed. In isolated Engine QA, Cancel in Reselect kept the file
theme selected. Selecting a definition with another name showed the explicit
Select the file for theme error and kept the original reference. Selecting a
new file with the expected name applied263749 and retained the existing UUID.

Only that newly created neutral replacement file was removed, with its bytes
retained for restoration. Reload reported The file doesn’t exist and kept the
selection. Restoring its bytes and using Reselect recovered without an error.
This accepts a missing-file path. It does not prove sandbox, OS permission
denial or iCloud Drive permission behavior. No personal file was used.

Importing a definition with the existing custom theme name offered Replace,
Import as New and Cancel. Replace opened the review. Cancel left the original
354525 background and UUID in a readonly QA snapshot. A second Replace followed
by Save applied263749 and kept the UUID. After normal Quit and restart, the
same theme was selected and Edit showed the saved color. Import as New was
observed as an option but was not executed or accepted by this session.

Use Theme File offered its separate duplicate-name Replace/Cancel alert. Cancel
kept the custom selection. Replace selected the file theme with its existing
UUID. Closed-library checks found exactly four themes, both stable replacement
identities, the replacement source’s unknown future field and the exact neutral
note text. Unknown array/scalar fields in device theme preferences also stayed.
No theme duplicate or wrong-name theme was saved.

The existing focused16 app methods and six Core methods passed. Local Debug
build and structural matrix results follow. Existing full Core681/app822 and
Python80 results are retained as prior evidence, not rerun totals. No duplicate
test or automatic UI test was added for these native sequences.

QA quit normally; its exact LaunchServices registration was removed. The ZIP
passed integrity verification before removing the temporary app package. Its
neutral input files are also copied to local
DraftlyRecovery/theme-reselection-20261023-003946. The original neutral inputs
and QA data remain. The usual installation was not changed. Screenshots and
logs remain outside Git.

Remaining theme cases include Import as New, explicit OS permission denial,
other missing-reference paths and full visual acceptance. Other Settings work
remains: per-syntax controls, Markdown/HTML, startup/login and physical shortcuts.
The known Markdown reader failure and capture scale block remain distinct.
This batch does not close Settings, iCloud acceptance or Draftly.

Local Debug build passed after the focused tests. Structural matrix check
returned zero errors. No timeout, retry, classification or public API changed.

## Import as New and HTML reader failure — 23 October 2026

This batch starts at a98fe2b. Native QA imported the existing neutral custom
theme through Import as New. Save remained disabled while its name matched
the existing theme. A new Unicode name enabled Save. Saving selected
QA New theme café 🐼. A readonly library snapshot found five themes: the
original custom UUID stayed1200FC27-B2CA-422C-B956-C4B9C788E7DF; the new
UUID was87019CD7-53B2-4EEB-9FA0-2D8226716D8B. Both retained263749 and
the unknown source object. The neutral note text stayed exact. This snapshot
was read while QA was idle, not after a verified restart.

A specific headless command test now checks importing the same source twice
with a new identity and name. Preparing the candidate changes no library or
reference data. Save retains the original, patches the new source fields and
selects the new identity. Backup restore retains both exact theme records.
The focused16 app methods and10 Core import methods passed. Production code,
APIs, stored formats and existing test names did not change.

Entering HTML Settings closed the Computer Use native pipe before a response.
The QA process remained alive. Sending Command-Q through the old binding failed
because that binding was inactive. Binding Dock timed out. The user was asked
to quit only Engine QA normally. No HTML binding or app crash is accepted from
this result. Do not repeat the HTML or Markdown observation failure in this
session. The usual installation and personal data remain untouched.

The complete run passed Core681/app823 with matching discovery/XML inventory.
Python80 and structural matrix0 passed. The earlier concurrency risk remains
recorded; this run required no deadline or retry change. A local build result
follows. No new signature, installation or synchronization check is claimed.

Local Debug build passed. QA still runs with HTML Settings after the reader
failure. Its package has not been retired. Normal shutdown and exact-path
unregistration remain pending until the user closes QA. The current package
path is retained in /tmp/draftly-settings-import-qa-path.txt. Do not remove the
package while it runs or report this batch as complete Settings acceptance.

### Import QA cleanup completed — 23 October 2026

The user confirmed normal QA closure. The exact process was absent. A readonly
check of the closed library confirmed five themes, both original/new import
UUIDs and the exact neutral note text. The package ZIP passed integrity checks.
Only its exact LaunchServices registration and temporary app package were
removed. The archive and neutral input copy are in local
DraftlyRecovery/settings-import-20261023-011732. QA library/preferences remain.
This completes the pending cleanup, not native HTML or restart acceptance.
The habitual installation remains unchanged. No source or test changed.

## Syntax feature preference write protection — 23 October 2026

Baseline at b0777b7: focused app4/Core29 passed. The annotated
pre-settings-syntax-features-2026-10-23 tag retains that source. A new Core
regression failed seven invalid cases before the correction. The nonthrowing
setter had replaced malformed JSON, non-object roots and non-object syntax
slots with new dictionaries. That could discard retained preference data.

The Core setter now returns the original string for those invalid inputs. Its
public signature and preference key stay unchanged. SettingsOptionEditing
validates the form input and reports an explicit error before delegating the
actual patch to Core. The view retains its stored string when editing fails.
Syntax option errors have separate local state from theme errors.

Two new app methods cover unknown nested fields, other syntax slots, Unicode,
absent defaults, reopening local preferences and explicit invalid-data errors.
The existing syntax test still checks that the stored option changes the real
task grammar without changing shared definitions or backups. Focused app10 and
Core30 passed. No existing test or API signature was removed. Full regression
and native checks follow separately.

Complete Core682/app825 passed with matching discovery/XML inventory. Python80,
structural matrix0 and local Debug passed. No deadline, retry rule or API matrix
classification changed. The previously recorded concurrency risk stays open;
this full run passed without a confirmation retry.

In isolated QA, CUA imported scripts/fixtures/editor-neutral-grammar.draftsSyntax
through the footer Import Syntax command. The native selector reported an
offscreen selection and disabled Open while its screenshot showed a blue Open
button. The observed coordinate mapping allowed the visible button to complete
the import. This is a reader discrepancy, not a confirmed file-type defect.
No valid-scale visual acceptance is inferred from that screenshot.

Editor Settings listed Neutral QA grammar and its Suggestions option. CUA
switched it off. After normal Quit and restart it remained off. Closed-device
preferences retained the unknown nested field and future sibling array.

A separate QA input made that syntax slot an array. Its option used the defined
fallback. Clicking it showed the explicit error and retained its visible value.
After normal Quit, the exact invalid string was still stored. The valid neutral
configuration was restored. A readonly library check confirmed the exact
original neutral note text. These checks accept the settings binding and
persistence, not all syntax behavior, editor selection or Undo combinations.
The existing automatic consumer cases retain their separate scope.

QA quit and its exact registration was removed. Its ZIP passed integrity
verification before the temporary launch package was removed. The archive is in
local DraftlyRecovery/syntax-features-20261023-012721. QA library/preferences
and the existing neutral fixture remain. No screenshot or raw log enters Git.
The usual app was not replaced. Do not repeat the known HTML/Markdown reader
failures or microphone checks. Per-syntax font/layout controls, other native
Settings paths and visual acceptance remain open. Signed results follow.

Signed Release and profile verification passed with com.pobrespandas.draftly,
team NM92LU2KKV and iCloud.com.andrestobelem.draftly. The isolated candidate
remains in .build/settings-personal. No habitual update or sync claim is made.

## Per-syntax font and size — 23 October 2026

The archived official Editor Settings supplement states that editor settings
can differ by syntax. Draftly previously used one global font and size. This
batch adds internal EditorSyntaxFontPreferences and an optional local
editor.fontBySyntax JSON preference. Missing fields inherit the existing global
font and size without a migration or a default write. Shared syntax definitions,
library records, identities and backups do not change. The annotated
pre-settings-syntax-fonts-2026-10-23 tag retains9b27dce; focused baseline app9
passed. The existing complete Core682/app825 record remains separate.

Syntax Settings now shows font and size for the selected syntax. Each edit
writes only its field. Reset Font Settings removes those two fields for that
syntax and preserves unknown fields and other syntaxes. The existing font
catalog is reused, including Nerd Fonts and exact unknown selected names.
Editing retains the defaults; layout controls remain global. Per-syntax
line/paragraph spacing, margins, monospace options and a complete system font
selector remain separate work. This is not full Editor Settings parity.

EditorBody resolves the active draft syntax before it passes font and size to
the existing NativeEditor. Invalid stored values read the current defaults;
invalid edits report an error and keep saved data. Four pure methods cover
field inheritance, reset, Unicode, unknown values, invalid edits and reopen.
The initial compile exposed JSONValue’s Decimal number representation; the
resolver now converts that value explicitly at the font boundary.

A headless EditorBody test uses injected temporary defaults and an offscreen
window. It verifies Menlo23 attributes, retained text/Unicode selection and
script Undo/Redo through a font change. Its first version used direct native
insertText and UndoManager.undo: native text reverted, but the offscreen session
did not receive that Undo callback. The test now uses the existing script-edit
route and makes its narrower contract explicit. Native typed Undo remains a
separate manual check; no editor mutation rule was changed to hide that result.
Focused17 app methods in four suites passed. Complete and native results follow.

Complete Core682/app830 passed with matching inventory/XML. Python80,
structural matrix0 and local Debug passed. No retry or deadline changed. The
earlier concurrency risk remains documented. The five new methods add contract
coverage; these totals do not express a compatibility percentage.

Native isolated QA loaded the retained neutral Markdown note and pasted a
neutral marker. CUA selected café 🐼, opened Syntax Settings, chose Menlo and
set23 points for Markdown. TaskPaper still showed inherited System19. The three
installed FiraCode Nerd Font variants remained in the picker. Closing Settings
retained the selection and exact edited text. Command-Z removed the marker;
Command-Shift-Z restored it. A final Undo restored the original neutral text.
This real native sequence passed and is distinct from the offscreen direct
UndoManager callback limitation recorded above.

After normal Quit and restart, Markdown still showed Menlo23. Reset Font
Settings restored inherited System19. A closed-preference check retained all
future fields and the unchanged global size. The absent global font-name key
stayed absent. The closed QA library retained the original note text exactly.
The form’s invalid-data error paths have automatic coverage; this session did
not exercise them natively or claim a complete visual comparison.

QA quit normally. Its exact registration was removed after its ZIP passed
integrity verification. Recoverable package:
DraftlyRecovery/syntax-fonts-20261023-021316. Neutral QA library/preferences
remain. No screenshot or raw log enters Git. The habitual installation remains
unchanged. The remaining per-syntax layout and font catalog work is listed
above. HTML/Markdown reader failures, startup/login, physical keys and valid
scale remain separate pending items. Signed candidate checks follow.

Signed Release and profile verification passed. The candidate retains
com.pobrespandas.draftly, team NM92LU2KKV and the existing
iCloud.com.andrestobelem.draftly container. It stays in .build/settings-personal.
It was not installed or accepted as synchronization evidence.

## 23 October — per-syntax layout

The clean base was 60bf56d. The annotated
pre-settings-syntax-layout-2026-10-23 tag retains it. Focused baseline font and
spacing tests passed 10 methods. This batch adds optional local
editor.layoutBySyntax fields for line height, paragraph spacing, horizontal and
vertical margins, and maximum width. Missing fields inherit current global
values independently. Reads do not write defaults. Width remains in points;
this does not establish parity with Drafts width in characters. Typewriter
scrolling remains global. No shared record, public API or backup format changes.

Syntax Settings exposes these values and Reset Layout Settings. Each edit
patches one field. Reset removes only known fields for the selected syntax.
Unknown data and other syntaxes remain intact. Invalid JSON or syntax slots
reject edits with an explicit error. EditorBody passes the resolved values to
the existing native editor. A zero line height preserves legacy line spacing.
Five new test methods cover inheritance, errors, reset, Unicode, local reopen
and the real offscreen EditorBody consumer. The consumer case checks paragraph
attributes, margins, width, text, selection, script Undo/Redo and reset to global
values. Focused 15 methods passed before its final reset assertions were added.
Full and manual acceptance results follow when performed.

Complete Core 682/app 835 passed with exact inventory/XML results. Python 80,
structural matrix 0 and local Debug passed. No deadline or retry changed. The
prior concurrency risks remain recorded. A final focused 15 run also passed
with the reset assertions. Manual review found a duplicate visible label in
the new width field. The field now hides that label while it keeps its
accessibility description. The final local build and a second QA inspection
confirmed the correction. No unrelated global layout control changed.

In isolated native QA, Markdown accepted 1.6 line height, 12-point paragraph
spacing, 24/30-point margins and 240-point maximum width. TaskPaper still showed
inherited 1.2/0/6/26/0 values. Closing Settings retained the Unicode selection.
Command-Z removed a neutral typed marker; Command-Shift-Z restored it. A final
Undo restored the exact original text. After normal Quit and restart, all five
Markdown values remained. Reset restored the inherited values and disabled its
button. A closed-data check retained unknown layout fields, global preferences
and the exact original neutral note. The initial numeric check used exact
Double equality for the prior 1.2 value; its stored representation is
1.2000000000000002. The check now uses a small numeric tolerance. No product
change was needed for that check.

The QA process quit normally. Its exact LaunchServices entry was removed only
after its ZIP passed integrity verification. Recoverable package:
DraftlyRecovery/syntax-layout-20261023-022901. Neutral QA data/preferences
remain. The corrected form was inspected in dark mode. This is not a 3-point
comparison against Drafts, a light/inactive acceptance, or acceptance of every
error binding. HTML/Markdown reader blocks, full font catalog, monospace
options, remaining controls, startup/login and physical keys remain pending.
The habitual app stays unchanged. Signed candidate verification follows.

Signed Release and profile checks passed. The candidate retains
com.pobrespandas.draftly, team NM92LU2KKV and the existing
iCloud.com.andrestobelem.draftly container. The profile covers two registered
devices and expires on 21 October 2027. The candidate remains in
.build/settings-personal. It is not installed and does not prove sync.

The final complete Swift run after the field-label change also passed:
Core 682/app 835, with exact inventory/XML results. No retry was needed.

## 26 October — installed font catalog

The branch starts at aa9452d. Existing local skill deletions remain separate.
The font picker now includes installed families and all their available faces.
The existing common choices keep their labels and stored names. Nerd Fonts
remain available. Each face uses its exact PostScript name. The catalog removes
repeated identities and keeps an unknown configured font selectable. Both the
global and syntax font pickers use the same catalog. Reading it does not write
preferences. No text mutation, theme, library or backup format changes.

One new pure test covers all faces, deterministic ordering, Unicode family
labels, duplicate families, empty identities and unknown selection. Existing
font tests keep their names and coverage. The first attempted baseline was
contaminated: editing started before discovery/build finished. Its missing
member error is not a pre-existing product failure or baseline evidence. The
subsequent isolated focused run passed nine methods. Full checks and native
acceptance are recorded separately below.

Complete Core 682/app 836 passed with exact inventory/XML results. Python 80,
structural matrix zero errors and local Debug passed. No timeout or retry
changed. Native isolated QA showed the expanded catalog and FiraCode Nerd Font
faces. Courier New Italic could be selected and remained selected after normal
Quit and restart. System was selected again before cleanup. This verifies the
picker and persistence path, not every installed font's rendering or visual
parity. The older temporary QA library was absent in this session. No prior
neutral-note retention check is claimed for this session.

QA quit normally. Its exact LaunchServices entry was removed after ZIP integrity
verification. The recoverable package is in
DraftlyRecovery/font-catalog-20261026-044518. QA preferences remain. The habitual
app was not replaced. Monospace-specific options, remaining editor controls,
startup/login, physical keys, HTML/Markdown native acceptance and the valid
visual comparison remain pending. This does not close Settings.

Signed Release and profile checks passed. Bundle com.pobrespandas.draftly,
team NM92LU2KKV and container iCloud.com.andrestobelem.draftly remain unchanged.
The candidate stays uninstalled in .build/settings-personal. Signature is not
sync evidence.

## 26 October — syntax text input options

The clean production base is931ca9b. Existing local skill deletions remain
untouched. Focused baseline font/layout10 passed before editing. The annotated
pre-settings-text-input-2026-10-26 tag retains that source.

The archived Mac Editor Settings reference includes continuous spelling,
grammar, smart quotes and smart dashes. NativeEditor previously fixed these
values at true/false/false/false. The new optional local
editor.textInputBySyntax preference keeps those defaults for absent or invalid
fields. Syntax Settings exposes all four switches and a reset action. Each
write patches one field; reset removes only known fields. Unknown fields and
other syntaxes remain. Invalid JSON or non-object syntax slots reject edits
with an explicit error. This does not change shared syntax definitions or
library/backup formats.

EditorBody resolves the active syntax. NativeEditor applies the four values
when creating or updating its NSTextView. It does not mutate text or change
Undo rules. Automatic correction, text replacement and Writing Tools remain
separate; this batch does not claim those contracts. Four new test methods
cover defaults, invalid fields, Unicode, unknown data, independent syntax slots,
reset, reopen and the actual offscreen EditorBody consumer. The consumer checks
all four native flags plus text, selection and script Undo/Redo. Focused14
methods passed. Complete and native checks follow below.

Complete Core 682/app 840 passed with exact inventory/XML results. Python 80,
structural matrix zero errors, local Debug and signed Release checks passed.
The bundle, team and existing container remain unchanged. The candidate stays
uninstalled. No retry or deadline changed. Signature does not prove sync.

Native isolated QA created a new neutral note. After changing all four Markdown
switches, TaskPaper still showed its original values. Closing Settings retained
the Unicode selection and text. Command-Z removed the initial paste; Redo
restored it. All four Markdown values remained after normal Quit and restart.
Reset restored the defaults. Closed preferences retained the prepared unknown
fields. A readonly check of the closed QA library confirmed the exact original
neutral text after restart and reset.

This verifies bindings, per-syntax independence, persistence, reset and editing
preservation. Automatic tests verify native NSTextView flags. This session does
not claim the system's linguistic correction quality, smart substitution typing
or complete reference visual acceptance. Those checks remain distinct.

QA quit normally. Its exact LaunchServices entry was removed after ZIP integrity
verification. Recoverable package:
DraftlyRecovery/text-input-20261026-045342. Neutral QA data/preferences remain.
The habitual app is unchanged. Autocorrection, Writing Tools, monospace, other
editor controls and the previously listed native/visual checks remain pending.

## 26 October — system text input overrides

The base is007b5ff. Focused text-input baseline4 passed before editing. The
annotated pre-settings-system-input-2026-10-26 tag retains that source. Local
skill deletions remain separate.

Syntax Settings now exposes System Default, Enabled and Disabled for automatic
spelling correction and Writing Tools. Missing or invalid fields inherit the
native state. The coordinator captures that state before applying overrides.
Reset and a syntax without overrides restore it. This avoids inventing a fixed
system preference or leaving the previous syntax's explicit value active.
Both fields use the existing local text input JSON preference. Unknown fields
and other syntaxes remain. No public API, shared record or backup format changes.

The implementation checked the installed AppKit headers and current Apple API
documentation through find-docs/Context7. References:
https://developer.apple.com/documentation/appkit/nstextview/writingtoolsbehavior
https://developer.apple.com/documentation/appkit/customizing-writing-tools-behavior-for-system-views
The October19 Drafts behavior reference remains unchanged. Explicit enablement
requests NSWritingToolsBehavior.default; disablement requests none. The system
still controls availability. No model is installed or run by changing the option.

One new pure test covers optional values, invalid fields and edits, Unicode,
unknown fields, persistence, individual inheritance and reset. The existing
EditorBody test keeps its name and now checks correction override, Writing Tools
disablement and restoration of initial values with text and script Undo retained.
Focused5 passed. A later assertion checks explicit enablement against the same
system request on a separate offscreen view. Complete results follow below.

## 28 October — native selector verification

The local Debug build succeeded. In isolated QA, both Markdown selectors started
at System Default. Disabled values persisted after normal Quit and restart.
Writing Tools also accepted Enabled. Reset restored both selectors to System
Default. This checks the UI bindings and persistence. It does not verify a real
Writing Tools session, model availability or correction quality. The existing
headless editor test covers the NSTextView flags and restoration of its initial
values. No model was invoked during this check.

QA quit normally. Its exact LaunchServices entry was removed after ZIP integrity
verification. The recoverable package is
DraftlyRecovery/system-input-20261028-234102. QA preferences remain. The usual
application was not replaced. Existing local skill deletions remain separate.

The first complete verification on 28 October failed with three timeouts in the
previously recorded WorkerPromiseEpochTests. The focused suite then passed two
tests. A separate complete confirmation passed Core 682 and app 841 with exact
inventory/XML results. Python 80 and the structural matrix check passed. No
retry policy or timeout was changed. The initial failure remains an open
intermittent risk and is not counted as a passing run.

Signed Release and profile verification passed with the existing bundle, team
and CloudKit container. The candidate remains uninstalled. The signature check
does not verify synchronization.

## 28 October — monospace font

The baseline is b775ddd, retained by the annotated
pre-settings-monospace-2026-10-28 tag. The focused baseline passed 19 methods.
Existing local skill deletions remain separate. Editor Settings now exposes a
local default monospace font and a per-syntax override. The existing font
catalog supplies installed fonts, including Nerd Fonts. A missing font falls
back to system monospace. Reset Font Settings removes the selected syntax's
known font fields and preserves unknown fields and other syntaxes.

EditorBody resolves the active syntax. NativeEditor includes the selected name
in its style identity. Syntax scopes, theme scopes and indentation metrics use
the same font resolver. The System Monospace choice retains the prior behavior
for a base font that is already fixed-pitch. No shared record, public API or
backup format changed. Focused 21 methods passed, including new checks for
inheritance, invalid data, reset, themed code and syntax scopes with Unicode
selection. Full and native checks follow below.

Complete Core 682/app 843 passed with exact inventory/XML results. Python 80,
the structural matrix check and local Debug passed. In isolated QA, Markdown
accepted Menlo while TaskPaper inherited System Monospace. The Markdown choice
persisted after normal restart; Reset restored the inherited choice. After the
full run, a duplicate System choice was removed from the monospace picker.
Focused 25 and a fresh local Debug build passed after that small UI change.
Native QA was performed before the duplicate choice was removed; that final
picker change has not been checked in use real.

QA quit normally. Its exact LaunchServices entry was removed after ZIP integrity
verification. The recoverable package is
DraftlyRecovery/monospace-20261028-234803. QA preferences remain. The usual app
was not updated. Full visual parity and other editor options remain pending.

Signed Release and profile verification passed with the existing bundle, team
and CloudKit container. The candidate remains uninstalled. This does not prove
synchronization.

## 29 October — auto-match in progress

The archived editor reference describes matching parentheses, brackets, braces
and quotes, including wrapping selected text. The implementation adds a local
per-syntax Auto-match switch. Its absent value is off, which preserves the
existing editor behavior. Key events pair supported characters and retain the
UTF-16 selection inside the pair. Marked text, Command or Control key events, and direct insertions keep their
existing path. Option-modified character input can create pairs. The setting uses the existing text input
preference, including unknown field preservation and reset.

Focused tests cover all five pairs, empty and Unicode selections, and direct
insertion. Complete checks and native acceptance are recorded separately.

Complete Core 682/app 845 passed with inventory/XML. Python 80, the structural
matrix check, local Debug and signed Release/profile verification passed. Native
QA showed the Auto-match option and enabled it for Markdown. Computer Use sent
parenleft but the editor received a closing parenthesis under the current
keyboard mapping. A real keyboard check of insertion, wrapping, Undo and Redo
remains pending. No native behavior acceptance is claimed. QA quit normally;
its exact LaunchServices entry was removed after ZIP integrity verification.
Recovery: DraftlyRecovery/auto-match-20261029-005424. The usual app remains
unchanged. The implementation is uncommitted pending the native check.

A follow-up fixed Option-modified opening characters, which some keyboard
layouts require. The focused eight methods passed. In isolated native QA,
Computer Use sent Shift-8 for the current keyboard layout. Markdown wrapped
selected `café 🐼` in parentheses and retained the UTF-16 selection. Command-Z
restored the original text and Command-Shift-Z restored the pair. This is a
simulated keyboard event; other physical keyboards and input methods remain
unverified. The QA app quit normally and its exact LaunchServices entry was
removed after ZIP verification. Recovery:
DraftlyRecovery/auto-match-option-20261029-005610. The usual app is unchanged.

The final full run after the Option correction passed Core 682/app 846 with
inventory/XML, Python 80 and the structural matrix check. No timeout or retry
policy changed. Local Debug passed. Other keyboard layouts, composed input and
physical keyboard delivery remain unverified. This check does not close the
other Editor Settings work.

Final signed Release/profile verification passed with the existing bundle, team
and CloudKit container. The candidate remains uninstalled. Signature is not
sync evidence.
