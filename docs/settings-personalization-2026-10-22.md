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
