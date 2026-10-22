# Editor and scripting continuation — 22 October 2026

## Scope

Complete syntax-defined tasks, navigation markers, links, custom syntax support,
and Advanced Find parity. Keep draft identities, UTF-16 ranges, library and backup
formats, imported scripts, native Undo and the integrated preview. Use Drafts
54.1.1 and the archived reference from 19 October 2026. This scope is not closed.

## Implemented and tested

- Custom link templates resolve captured keys and encoded or raw values. The
  editor uses the link capture as the active range only when link mode is on.
  Script snapshots retain their format. Commit `7c6e468`.
- Previous Marker and Next Marker use the assigned syntax. They retain circular
  navigation and synchronize selection without saving content. Missing syntax
  reports an error. Commit `4dbdc34`.
- Toggle Tasks advances shared task snapshots. Reverse order protects UTF-16
  offsets when states have different lengths. The selected state ranges limit
  edits; an empty selection targets all tasks. The final selection accounts for
  the length change. Imported action scripts are unchanged. Commit `bd8d1f5`.
- Advanced Find now offers Replace for each result. Replacement uses the match
  in the full source, so lookbehind and capture expansion retain their context.
  Invalid queries and unmatched ranges do not edit text. A failed save retains
  the new text and reports the existing error. Tests cover these paths, literal
  templates, zero-length regex results, persistence and native Undo.

The focused marker/find run passed 16 app methods and ten Core methods. The
broader task run passed four app methods and 27 Core methods. Three final task
methods passed after strengthening the variable-length assertion. The focused
individual-replacement run passed 12 app methods and six Core methods. Local
Xcode builds passed after each production change. These counts describe runs;
they do not establish compatibility for untested contracts.

## Native checks

Computer Use inspected Advanced Find in Drafts on the neutral existing draft
“Visual QA 49 — Tasks and lines”. Query “First” produced one result with a line
number and Replace button. The dialog also provides Reverse Values, history,
Regular expressions, Ignore case, Find, Previous, Next and Replace All. No source
edit was made. Native-find mode was restored and its panel was closed.

An isolated local QA app used a new identity and temporary library. It published
no Services, URL handlers or document types. CloudKit and global shortcuts were
disabled. The test source was neutral Unicode text with two matches and two
headings. Per-result Replace changed only the second match, selected the inserted
text, and updated the result list. Done exposed the exact expected native text.
Undo restored the source; Redo restored the replacement. Next Marker selected
the first heading, then the second heading. The source text stayed unchanged.

QA quit normally. Its process was absent before cleanup. Only its LaunchServices
registration was retired. The app, exported preferences and closed library were
moved together to recoverable Trash. The usual app was not changed. No raw logs
or screenshots were added to Git.

## Remaining acceptance

- Tasks: complete remaining grammar and presentation contracts; verify custom
  multi-state clicks, selected bulk edits, Undo and failure paths in native use.
- Markers: verify custom syntax and TaskPaper navigation in native use, including
  the Navigate interface and consistency with script snapshots.
- Links: complete built-in URL templates and supported destinations; check custom
  link activation and scopes in native use. Current native checks do not prove
  these paths.
- Custom syntax: audit all included format features, validation, installation,
  replacement, file reload, URLs, name conflicts and unknown-field preservation.
- Advanced Find: compare the remaining Reverse Values edge cases. Compare query
  initialization, multiline input, line labels, keyboard actions, navigation,
  cancellation, persistence and remaining independent-window edge cases. Keep native
  find and `preferAdvancedFind` checks. Individual replacement alone does not
  establish parity.
- Run complete regressions and the applicable contract gates. Update member
  evidence only when a named test or native check proves that member's contract.
- Keep Drafts Pro restrictions separate from defects and unverified behavior.
  Do not promote a blocked comparison to acceptance.

The dictation permission crash fix is a separate change. It still needs native
permission acceptance and rollout. It is not part of this scope's acceptance.

## Integrated automatic run

The final serial runs passed 666 app methods in 120 suites, 654 Core methods in
124 suites, and 68 Python tests. The matrix structural check reported zero
errors. The local build passed. These runs do not replace the open native and
reference comparisons above. Tests did not use the QA app or personal data.

## Find request history and reversal

The view now provides Reverse Values, Find with Command-Return, and History.
A request contains query text, replacement text, case sensitivity and regex mode.
Reverse Values swaps only the two texts. Find and replacement commands record
valid requests in local preferences. Exact duplicates move to the front. History
labels include nonempty replacement text. Restoring a request restores all four
values. Clear History removes only its own preference key. This change does not
add history to library backups or change public scripting APIs.

Three headless tests cover exact Unicode and multiline values, reversal,
complete persistence, duplicate order, option differences, invalid regex,
corrupt stored data, clearing and isolation between preference domains.

Computer Use confirmed that Drafts 54.1.1 restores replacement and matching
options from history. Its history labels include replacement text. The automated
Reverse Values observation was inconsistent: the replacement field changed to
the query text but the query field did not show the prior replacement. This is
an unresolved reference observation, not proof that Draftly matches every edge
case. No reference draft content was changed. The prior request and native-find
mode were restored. Neutral comparison requests remain in Drafts history.

Isolated QA verified both swapped texts with options retained. It restored the
saved request after changing both options. After a normal process exit and
relaunch, History still contained the request and restored both texts, options
and results. Clear History then left only its disabled menu item. It retained
the current fields and exact draft text. No replacement was performed in this
session. One transient Computer Use context warning occurred after relaunch.
Fresh state and a click on the row text recovered the session; that warning is
not counted as a product failure or acceptance evidence.

QA published no Services, normal URLs or document types. It used isolated
preferences and storage with CloudKit and global shortcuts disabled. It quit
normally. Process absence was checked before retiring only its registration.
Its app, exported preferences and closed library remain together in recoverable
Trash. The usual app was not replaced.

The final history run passed 669 app methods/121 suites and 654 Core methods/124
suites. Separate XML reports match the discovered method inventory. All 68 Python
tests passed. The matrix structural check reported zero errors. The local build
passed. No timeouts or retries were changed. This accepts the checked history
and reversal behavior, not the remaining Editor/scripting scope above.

## Independent Find window and multiline input

Advanced Find now opens in an independent resizable window for its source editor.
LibraryView owns the presentation bridge. WindowModel requests presentation;
headless model calls do not construct windows. A presentation identity separates
an explicit open request from ordinary query and editor updates. Returning to
Find raises the existing window and focuses the query. Typing and source changes
do not raise it. Closing the source closes its Find window. Done and plain Escape
close Find without closing the source editor.

Both fields accept multiple lines. Command-Return runs Find. Results show the
source line number. The preview calculation handles UTF-16 positions, CRLF, CR,
LF and Unicode line separators. Tests cover empty final lines and invalid ranges.
Other tests check repeated requests, multiline initial queries and isolation
between window models. Existing tests remain.

Native QA found two defects during this implementation: the initial query lacked
focus, and TextEditor absorbed Escape. The focus bridge and Find-specific Escape
handling correct these cases. A second focus adjustment makes returning to an
existing Find window focus the query instead of the prior replacement field.
The final native checks confirmed those corrections.

QA searched the literal two-line query “café” followed by “Tail”. It found two
matches with labels L1 and L3. It replaced only the second with two-line text
“té” followed by “End”. The source editor remained accessible while Find stayed
open. Undo restored the exact source without raising Find. Returning to Find
reused it and focused the query. Escape closed it with the draft retained. Closing
the source also left no available windows in the earlier lifetime check.

The same session found that native Find does not reach the source text view
when the draft list retains focus. That routing defect is a separate correction;
this presentation work does not claim full native-find coexistence yet. The
usual app was not replaced. Source content is neutral and QA data remains isolated.

Final presentation checks passed 671 app methods/121 suites, 654 Core methods/124
suites and 68 Python tests. Separate reports match discovery. Matrix structure0
and the local Xcode build passed. QA quit normally. Its exact registration was
retired after process absence was checked. The bundle, exported preferences,
closed library and prior QA runtimes are together in recoverable Trash. No
screenshots or raw logs were added to Git. Native-find focus routing remains a
separate next correction. This does not close the full Editor/scripting goal.

## Native Find source focus correction

A separate regression test failed before the correction: the source focus hook
was not called and a bound renderer that rejected focus did not report an error.
The native route now focuses the source editor before sending its find command.
It targets the source text view when available. A bound renderer that rejects
focus reports an explicit error. Legacy headless routing remains available when
no renderer hook is bound. Public void return behavior is unchanged.

The focused run passed 57 app methods. A separate isolated QA session placed focus
in the draft list, then invoked the editing-bar Find command. The native bar
opened, found two “café” matches and selected a source match. Done closed the bar.
Advanced Find then opened and Escape returned to the source with selection
retained. Native Find opened again and still found two matches. Source text stayed
exact. QA quit normally; its exact registration was retired and its closed data
was retained with the bundle and exported preferences in recoverable Trash.

The final app run passed 672 methods/121 suites. The unchanged Core sources had
passed 654 methods/124 suites in this stage. Reports for both targets match the
current inventory. The local build passed. Remaining native acceptance includes
two independent source windows, background routing, request defaults and the
remaining reference comparisons. This specific focus failure is resolved; it is
not a claim of complete native-find or Editor parity.

The final Python run passed 68 tests. The matrix structural check reported zero
errors. These checks do not promote showFind from partial compatibility.

## Task and link capture styles

Task interactive scopes and link key, value, prefix and suffix scopes now use
the shared syntax definition. Disabled rules produce no style ranges. The editor
applies font and decoration styles to task controls without applying their scope
foreground color, as required by the archived format. Markdown tasks declare the
monospace bold scope. Link styles do not enable link activation when link mode
is off. Imported scope fields remain intact.

Specific headless tests cover UTF-16 capture ranges, disabled definitions,
unknown fields, default and imported theme styles, task foreground protection,
and unchanged text and selection. The focused run passed 13 Core methods and
five app methods. The initial rendering fixture omitted required theme colors
and used an invalid style separator. The corrected fixture passed without weaker
assertions. The local Xcode build passed. Native rendering acceptance remains pending.

## Additional syntax consumers to complete

Navigate used a separate Markdown parser with a 100-entry limit. The correction
below replaces that parser. The list continuation change below connects
listCompletionDefinitions, sequence, padding and replacement rules.
Also complete featureKeys, autocompleteDefinitions, rangeExtensionType and
indentationPatterns. These fields are not excluded from the objective.

The file syntax bookmark ordering defect is corrected below.
The editor also suppresses file definition errors with try?, while scripting
reports them. Required captures and malformed rule values need validation.
Built-in name conflicts and import-as-new behavior need explicit resolution.
The full Editor and scripting goal remains open.

## Navigate uses assigned syntax

Navigate now builds its entries from the shared syntax markers in current editor
text. It retains all entries, labels, prefixes and indentation levels. TaskPaper
projects and custom markers use the same definitions as scripting and the marker
commands. Selection uses the shared synchronization and focus path. It does not
save or modify content. A menu captured before a text change cannot apply an old
range. Missing syntax offers an explicit error action instead of Markdown fallback.
Native menu indentation uses the AppKit limit of 15; the definition keeps its level.

Eight headless editing-bar methods passed, including existing parameterized cases.
New cases cover 105 custom markers, Unicode, unsaved text, prefix and level,
synchronization, stale entries, TaskPaper, Plain Text and missing syntax. Initial
fixture errors omitted required definition arrays; valid fixtures passed without
changing validation. The local Xcode build passed. Native menu presentation and
selection remain pending.

## File syntax installation and storage failure

File syntax installation now prepares bookmark data before saving the definition.
It writes the new local bookmark only after the library save succeeds. The import
command uses this operation. Custom definitions retain their existing save path.
Bookmark creation errors cannot save a definition. Storage errors cannot change
the previous bookmark. This does not change backup formats or copy permissions.

A temporary-file test installs an original definition, injects a storage error,
and replaces it with another file under the same identity. It checks the stored
definition, exact previous bookmark and content read from the original file.
A new definition with a unique name also fails without a local bookmark. A retry
then replaces both stored content and file access. Unknown fields survive. The
operation rejects non-file definitions. All 14 shared syntax methods and the
local Xcode build passed.
Native file permission and import-dialog acceptance remain pending.

## Grammar-defined list continuation

Enter now asks the assigned definition for a list continuation edit. Plain Text
and definitions without list rules use native newline behavior. Markdown variants
and Simple List define unordered and ordered rules. TaskPaper defines its task
prefix. Custom definitions retain their raw rules and unknown fields.

The shared calculation uses UTF-16 captures for indent, prefix, line and optional
sequence. It increments integer sequences, applies leading padding and prefix
replacements, and retains the indentation. An empty item removes its prefix.
Invalid selections and positions before the prefix do not create a list edit.
Disabled rules do not run. Optional list rules now validate expression captures,
replacement values and nonnegative integer padding before installation.

The padding calculation follows the archived example: padding 2 produces 001.
Its wording is ambiguous about total width. Native reference comparison remains
required. Sequence overflow does not increment the number. Empty item behavior,
selection across lines and built-in variants also need native comparison.

The focused run passed 15 Core methods and four app methods. Native text insertion
was tested in an offscreen window, including selection, Undo, Redo and Plain Text
fallback. No window was shown. The first Undo fixture failed because its second
edit lacked an explicit group with groupsByEvent disabled. Adding that group
fixed the fixture; production Undo behavior was not changed to hide the failure.
The final focused rerun and local Xcode build passed. Native interactive list
acceptance remains pending. Feature keys, autocomplete,
hanging indentation and broader validation are still incomplete.

## Native syntax check and prefix spacing

Computer Use used a new isolated Syntax QA bundle with CloudKit and global
shortcuts disabled. It published no Services, document types or URL handlers.
Markdown Enter changed `9. [x] task` to a next line `10. [ ] `. Undo removed that
line and Redo restored it. Navigate listed both Markdown headings and selected
`## Second`. TaskPaper listed two projects, selected `Last:`, and continued an
indented task with its tab and dash retained.

The session installed editor-neutral-grammar.draftsSyntax with Add File Syntax.
It selected the installed definition, then entered neutral Unicode text. Enter
continued `009) {done} item` as `010) {todo} ` with the leading spaces retained.
The custom task marker was bold and monospace; link key and value showed bold
and italic styles. Navigate displayed `→ Café 🐼` and selected exactly `Café 🐼`.
Toggle Tasks cycled `[ ]`, `[~]`, `[x]`, `[ ]`. After normal quit and relaunch,
opening the saved note restored its source and assigned file syntax with styles.
This checks same-machine file access, not sandbox permissions on another Mac.
The request used no microphone, private text or external link activation.

A separate neutral note in Drafts 54.1.1 confirmed ordered task continuation and
removing the empty next item. Its Navigate menu showed `H1 Syntax QA neutral`
and `H2 Café 🐼`. QA had joined the prefix and label. The correction inserts a
space only when the nonempty prefix does not already end in whitespace. Custom
prefix spacing remains intact. Nine editing-bar methods passed. The correction
still needs a native check in the rebuilt binary.

The toggle session showed a full-document selection after an action. The cursor
placement before the action was not observed independently. Do not count this as
selection acceptance or a confirmed product defect; reproduce it with explicit
before/after state. Custom padding still lacks a Drafts custom-grammar comparison.
Imported-theme native rendering, external link activation, empty/missing-file
errors, replacement dialogs and file permission denial remain pending.

QA quit normally. Process absence was checked, its exact LaunchServices record
was retired, and its bundle, exported preferences, fixture and closed library
were moved together to recoverable Trash. The usual Draftly app was untouched.
No screenshots or raw logs are tracked. The neutral source fixture is retained
under scripts/fixtures for replay. Full Editor/scripting acceptance is still open.

Final serial regression passed 677 app methods in 121 suites and 657 Core methods
in 124 suites. Both XML reports match current discovery. All 68 Python tests
passed. The matrix structural check reported zero errors. The local Xcode build
passed after the prefix correction. No test timeout or retry policy changed.
These results do not close the native checks and grammar features listed above.

## Syntax feature options

Definitions expose their named feature keys, descriptions and default values.
Shared rules require all feature IDs in their comma-separated featureKeys value.
The same filter governs highlighting, tasks, links, markers and list continuation.
Editor Settings lists the selected syntax features as toggles with descriptions.
Changing a toggle invalidates editor styling even when the source is unchanged.
The original syntaxDefinition(named:) access remains available; a separate
preferences-injected access supports isolated tests.

Overrides use a local preferences key, grouped by syntax name. Syntax source,
identity and coding keys remain unchanged. Runtime overrides are not encoded in
syntax records or backups. Unknown preference values survive edits. The glossary
distinguishes a syntax feature from its local override.

The focused run passed 17 Core methods and 15 app methods. Specific new cases
cover defaults, multiple requirements, disabled rules, persisted local overrides,
unchanged source and backup data, decode without overrides, unknown preferences
and malformed feature metadata. An offscreen renderer test changes a feature
on/off/on and checks color updates, exact text/selection and unchanged Undo state.
No window was shown. The local Xcode build passed.

Native Settings toggles and scripting with a changed local preference still need
acceptance in QA. Built-in feature declarations and their styling need reference
comparison. Feature keys do not close autocomplete, hanging indentation, grammar
validation, import conflicts, or the remaining Advanced Find checks.

## Autocomplete query foundation

Shared syntax analysis now builds a completion request from the latest trigger
on the current line and the UTF-16 insertion point. A request retains its source
range, display labels, insertion values and draft identities. It does not change
editor text. Static definitions support optional template processing against
current unsaved text. Draft definitions use the target draft for templates,
query title or full text, require each listed tag, exclude Trash and the current
draft, and order results by modification date with an identity tie break.
Disabled rules and feature requirements use the same syntax rule filter.

Tests cover Unicode triggers/ranges, query filtering, template processing on/off,
unsaved current content, prefix/suffix, equal labels with different values or
draft identities, title/full-text queries, tags, Trash, current draft exclusion,
closed delimiters, invalid selection, feature disablement and invalid triggers.
All 19 shared syntax methods and the local Xcode build passed. The original raw
grammar is unchanged.

This is the query foundation, not completed editor autocomplete. No dropdown is
connected yet. Complete keyboard selection, acceptance, cancellation, stale
requests, Undo and native comparison before accepting the feature. Built-in
trigger definitions also remain pending. Keep unknown imported fields intact.

AppKit completion documentation was checked through the official Apple source.
Its completion insertion callback receives a word, while this domain can have
equal labels with different values. The UI must retain result identity and must
not choose a draft by display label alone. Reference:
https://developer.apple.com/documentation/appkit/nstextview/insertcompletion(_:forpartialwordrange:movement:isfinal:)

## Editor autocomplete connection

The native editor now binds completion queries to current editor text and library
notes. Markdown variants declare the archived title and full-draft triggers.
A nonactivating child panel displays the results without taking editor focus.
Up/Down select an index; Return/Tab accept; Escape dismisses. Each row retains its
index and draft identity. Equal labels do not collapse into one result. The panel
uses the visible screen bounds and a scrollable list. Closing or detaching the
editor removes its panel. Headless editors cannot show it.

Acceptance requires the original source, selection and draft identity. Changed
syntax rules or feature values invalidate the request. Equivalent built-in reads
do not invalidate it merely because they have different transient IDs. Built-in
JSON output now has sorted keys so unchanged rules also have stable source text.
Acceptance replaces only the trigger/query range. It breaks native typing
coalescing before and after insertion. An accepted value does not open another
request. The existing native completion fallback remains available.

Six new app methods cover duplicate labels, navigation bounds, cancellation,
source/selection/draft staleness, native insertion and Undo/Redo, input refresh,
acceptance without another request, equivalent definition updates, built-in
triggers and Plain Text. All tests use no window or an offscreen window.
The focused run passed ten app methods and 19 Core methods. The local build
passed. No automatic test showed a panel or requested a permission.

Computer Use used isolated Completion QA with neutral notes. Two source drafts
had the same title and different bodies. Typing after the trigger displayed both
rows. Down/Return selected the second identity and inserted Body one. The title
trigger inserted the bracketed title. Escape kept the query, and a subsequent
Return inserted a newline rather than a suggestion. A screenshot confirmed the
active list, both equal labels and selection highlight. No screenshot is tracked.

The session found input-path and false-invalidation defects before acceptance
worked. A temporary count/focus trace confirmed the final request and panel state.
The trace code was removed. Native Undo/Redo then exposed a coalescing defect:
Redo repeated the last typed character. Breaking coalescing fixed the native case;
the final binary restored the query and redid the exact full-draft insertion.
The offscreen explicit-group case already passed before that correction. It is
not a red/green reproduction of the native event grouping defect.

Mouse acceptance did not complete through Computer Use. One click used the wrong
Retina coordinates and dismissed the list; a later click on the secondary panel
did not insert text. Keep mouse acceptance pending. Do not infer a product bug or
approval from those attempts. Static custom suggestions, feature-toggle QA,
query refresh after deletion, IME, long lists and multiple source windows need
further checks. Drafts dropdown comparison remains pending. Built-in link
activation, hanging indentation and the other grammar/Find work remain open.

QA quit normally. Its process was absent before unregistering its exact app path.
Its closed library, exported preferences, neutral inputs and earlier runtimes are
together in recoverable Trash. CloudKit, global shortcuts and Services were off.
The habitual app was not opened or replaced.

Final serial runs passed 684 app methods/122 suites and 661 Core methods/124
suites. Both reports match the discovered inventory. Python68, matrix structure0
and the local Xcode build passed. No retry or timeout was changed. The full scope
is not accepted; the interaction and reference checks above remain pending.

## Autocomplete refresh after deletion

Two new headless cases failed before the correction. Backward and forward deletion
changed the text without requesting updated suggestions. DraftTextView now uses
didChangeText for edits that do not pass through insertText. It waits for the next
main-queue turn, then checks source, selection, draft identity and refresh revision.
An explicit refresh supersedes the queued one. Cancellation, focus loss, detachment
and acceptance invalidate pending refreshes. Undo and Redo do not request them.

Nine focused app methods passed. New cases cover deleting a nonmatching suffix,
removing a trigger, forward deletion, the final UTF-16 insertion point, and pending
work after cancellation or a source/selection/draft change. The insertion test
now drains pending work and confirms that acceptance does not open another request.
The fixture separates an optional query from a required request. Expected absence
does not record an asynchronous assertion outside the test case.

Apple's didChangeText contract was checked: it notifies the delegate when a series
of changes completes. Reference:
https://developer.apple.com/documentation/appkit/nstextview/didchangetext()

Isolated Delete QA had one neutral target draft. Query cafex had no result.
Backward deletion produced cafe and displayed its matching bracketed title.
Return inserted the title. Undo restored the query and Redo restored exactly the
accepted result. A second deletion/Escape/Return sequence kept the query and
inserted only a newline. The local Xcode build passed. Forward deletion and stale
contexts have automatic evidence; their separate native checks remain pending.

QA quit normally. Process absence was checked, its exact registration was removed,
and the bundle, exported preferences and closed library are in recoverable Trash.
No screenshots or raw logs are tracked. The habitual app is unchanged. Mouse/static
suggestions, feature-toggle acceptance, IME, long lists, multiple windows and the
remaining grammar/link/Find scope remain open.

The final serial app run passed 687 methods in 122 suites. Its report matches
current discovery. Core sources did not change; the prior661/124 report also
matches the current Core inventory. The matrix structural check has zero errors.
No timeout or retry changed. These results do not accept the remaining scope.

## Mouse acceptance and custom static suggestions

The suggestion hosting view rejected first mouse events in its nonactivating
panel. A headless test failed on the actual content view's acceptsFirstMouse
result. The panel now uses a hosting view that accepts that event. Its window
still cannot become key or main. The content builder is shared by presentation
and the test; the test does not construct or show a panel.

Native Mouse QA confirmed the first click on a draft suggestion inserted its
bracketed title. Typing then continued in the editor. Undo removed that typing
and the accepted suggestion in separate operations; Redo restored the suggestion.
This completes the earlier unverified single-click path for the checked case.

The session imported the neutral grammar fixture with static autocomplete and a
default-enabled feature key. Two rows had the same label and different values.
Clicking the second label inserted Second 🐼. Clicking empty space in that row
initially did nothing. The row now defines a rectangular hit area. The rebuilt
binary accepted the first click in the same empty region and inserted Second 🐼.
A separate static template rendered [[title]] from the current draft and kept its
parenthesis prefix/suffix. The editor displayed (Current café 🐼).

The fixture is retained under scripts/fixtures for replay. Ten focused app methods
and the local Xcode build passed. The first-mouse policy has automatic red/green
evidence. Full-row hit testing has native before/after evidence, not an automatic
mouse simulation. No automated test opened a window or sent a mouse event.
Apple reference: https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse(for:)

QA quit normally. Process absence was checked before exact unregistration. Its
bundle, prior runtime, fixture, exported preferences and closed library are in
recoverable Trash. The habitual app was untouched. No screenshot is tracked.
Feature-toggle persistence, IME, long lists, multiple windows and Drafts dropdown
comparison remain pending. Other grammar, links and Find acceptance remain open.

The final serial app run passed 688 methods/122 suites. Its XML matches discovery.
Core sources are unchanged; the prior661/124 report still matches current Core
inventory. Local Xcode build and matrix structure0 passed. No retry or deadline
changed. These results accept the checked mouse paths, not complete parity.

## Native syntax feature persistence and retained Undo

Isolated Feature QA used the neutral custom grammar. Suggestions appeared for
!!sam. Editor Settings disabled Suggestions without changing the source. A new
input event produced no suggestion. After a normal quit and restart, the switch
remained off. Enabling it restored both equal-label suggestions without another
restart. Return inserted First café. This checks autocomplete gating and local
persistence, not all feature-gated scripting contracts.

The existing feature rendering test now also creates a real content edit through
NativeEditor, changes feature values with a populated Undo stack, then checks
exact Undo and Redo in both the session and text view. Its prior empty-stack
checks remain. All six ThemeRenderingTests passed. Production code did not change.
The current binary already passed the local build in the preceding stage.

QA quit normally. Its exact registration was removed. The runtime, exported
preferences and closed neutral library are recoverable in Trash. The habitual
app was unchanged. No screenshot or raw log is tracked.

Next: add built-in wiki templates together with working title, quick-search and
named-workspace destinations. Preserve imported templates and installation URLs.
Matching, duplicate-title, Trash and creation defaults need explicit contract
checks. Hanging indentation, grammar validation/import conflicts, IME, long
suggestion lists, multiple windows and remaining Find parity stay open.

## Built-in wiki destinations

The archived syntax-format example supplies empty, d, u, s, w, google, wikipedia
and bear template keys. The three built-in Markdown definitions now supply these
keys and capture scopes. First-party links use draftly://. Imported definitions
are unchanged. Unknown keys remain link snapshots without an active URL.

The application router now opens an exact title, creates only with
allowCreate=true, opens Quick Search with the decoded query, and applies an
installed Workspace by name. Named Workspace navigation does not install records.
A link with name and data fails before either effect. Installation decoding stays
on its existing path. Workspace application uses the existing pending window
command and flushes the editor before applying resolved presentation.

Title lookup excludes Trash and chooses the latest modified match, then UUID
for a stable tie. UUID takes precedence and cannot fall through to creation when
invalid. These rules are explicit implementation choices pending Drafts behavior
comparison. Creation must persist before navigation. A storage failure leaves no
new note or revision; retry is covered.

Focused tests passed: twenty shared syntax methods and eleven URL methods.
They cover all eight destinations in three syntaxes, Unicode/reserved characters,
UTF-16 ranges, unknown keys, title defaults, repeat creation, invalid UUID,
duplicate titles, Trash, storage failure/retry and exact Workspace lookup.
The local Xcode build passed. Native activation, Quick Search delivery, queued
Workspace application and Drafts matching/default comparisons remain pending.
External browser/Bear execution has not been checked. No app was installed.

Full serial regression passed 692 app methods/122 suites and 662 Core methods/124
suites. Matrix structural check passed with zero errors. No retry or deadline
changed. Native acceptance above remains pending.

## Title-link confirmation correction and native delivery limits

The current official URL scheme guide was consulted on 22 October 2026:
https://docs.getdrafts.com/docs/automation/urlschemes
This is a supplemental reference. The frozen 19 October archive is unchanged.
The guide requires a prompt before creating a missing title. Multiple title
matches produce a warning and search. It contradicts the direct creation and
latest-match choice in the preceding implementation. Those choices are replaced.

The router now asks before creation. Cancel makes no note or revision. Multiple
matches cannot select an arbitrary note or create another one; the router warns
and opens Quick Search. Twelve focused URL methods passed, including refusal,
ambiguity, Trash exclusion, confirmed creation and storage failure/retry. Native
confirmation, warning/search UI and exact Drafts search destination need checks.
Title/Marker navigation and other open parameters remain outside this acceptance.

Isolated Links QA installed a neutral file syntax with its own registered scheme.
Link Mode showed the expected encoded URLs and active ranges, including Unicode
and reserved characters. Click, Command-click and Open Link did not navigate.
Safari rejected both the encoded title URL and a plain neutral title URL as an
invalid address. Exact-path LaunchServices registration did not change this.
This does not prove a router defect or successful native delivery. Native URL
activation, query delivery and Workspace application remain pending.

File > Import treated the .draftsSyntax file as a text note. Add File Syntax from
the syntax selector installed it correctly. Record this separate import-path gap;
no fix is included in this title-link correction. The neutral note is retained
only in the recoverable QA data.

QA quit normally. Process absence was checked. Its exact registration was removed,
and its bundle, grammar, preferences and closed neutral library are in Trash.
The temporary Safari tab was closed. The habitual app was not opened or replaced.
No screenshot or raw log is tracked.

## Syntax files through File Import

LibraryFileImport recognizes .draftsSyntax before generic JSON and text routes.
It validates with SyntaxDefinition and saves a custom definition. Invalid syntax
cannot fall through to a text note. Reimporting identical custom source keeps the
installed identity. A different definition with the same name fails explicitly;
Import Syntax remains the route to review replacement. Existing file definitions
are not silently converted to stored custom definitions. Built-in name rules stay
in LibraryStore. No public API or library format changed.

The regression failed before the change because import created text notes.
Thirty-two focused import and syntax methods passed after the change. New cases
cover source/unknown-field preservation, extension case, repeat identity, backup,
malformed and conflicting input, storage failure/retry and atomic mixed-file import.
The local Xcode build passed.

Native Import QA used a coherent copy of the closed neutral library. File > Import
reported Import complete for ImportQA.draftsSyntax. The list retained four drafts;
File Import café 🐼 appeared in the syntax selector. This verifies installation,
not all syntax replacement/import-as-new behavior. QA quit normally. Process
absence was checked before exact unregistration. Its bundle, grammar, preferences
and closed library are recoverable in Trash. The habitual app was unchanged.
No screenshot or raw log is tracked. Native URL delivery remains pending.

Full serial Core regression passed 665 methods/124 suites. Matrix structure passed
with zero errors. No timeout or retry changed. App code is unchanged in this fix.

## Grammar-defined hanging indentation

The frozen syntax-format reference defines indentationPatterns as wrapped-line
presentation. It measures indentCapture with indentScope font metrics. This is
separate from Enter list continuation and source indentation.

SyntaxDefinition now returns enabled prefix and paragraph ranges in UTF-16.
It ignores empty/unmatched captures and non-line-start matches. The first matching
rule supplies the indentation for a paragraph. Missing or out-of-range captures
fail validation. Runtime values honor the shared feature rules. The archived
Markdown list/quote pattern is included in the three built-in Markdown variants.

The editor measures the prefix with default scope font traits and theme scope
metrics. It applies headIndent to the paragraph while retaining the first-line
position, line height and paragraph spacing. Source content is not changed.
Twenty-one shared syntax methods and seven offscreen rendering methods passed.
New cases cover Unicode, CRLF, disabled rules, invalid captures, built-in prefixes,
feature changes, unchanged text/selection and an empty Undo stack. The local
Xcode build passed. Native wrapping, tab metrics, themed metrics and Drafts
comparison still require separate acceptance. This does not close grammar parity.

Full serial regression passed 694 app methods/122 suites and 666 Core methods/124
suites. Matrix structural check passed with zero errors. No deadline or retry
changed. Native indentation acceptance remains pending. Usual app unchanged.

## Hanging indentation glyph metrics and native wrapping

A new parameterized headless test compares actual NSLayoutManager glyph positions.
The first content glyph and the first wrapped glyph align within one point for
space and tab prefixes, each with text.normal and themed text.heading metrics.
It checks the rendered layout rather than repeating the prefix-width calculation.
All eight rendering methods passed, including these four parameter cases. No
production code changed. The current binary is the successful ebf52e4 local build.
Matrix structural check passed with zero errors.

Isolated Wrap QA displayed long Markdown list and quote paragraphs. Wrapped lines
aligned with the content after the prefix for two spaces, a tab and a quotation.
Undo removed the pasted source. Redo restored the exact 782-character source.
Drafts54.1.1 received a separate neutral note with the same source. Its built-in
Markdown showed the same hanging alignment for these cases. This is functional
wrapping evidence, not a full one-point visual comparison with normalized setup.
Native custom theme metrics remain unverified; automatic themed metrics passed.

The comparison exposed separate differences: Drafts italicizes quotation text,
while QA leaves it upright; Drafts reports130 words and QA131 for this source.
Do not treat either as accepted parity. Keep syntax styling in the remaining
scope and record word counting separately. Existing reference notes were retained;
the new neutral Wrap QA note remains in Drafts for reproduction.

QA quit normally. Process absence was checked, its exact registration was removed,
and its bundle, preferences and closed library are recoverable in Trash. The
habitual Draftly app was unchanged. No screenshot or raw log is tracked.

## Markdown quotation style correction

The official grammar example linked by the frozen syntax guide was fetched on
22 October 2026: https://config.agiletortoise.com/examples/grammar-markdown.json
SHA256:6148637b698407b96b64d6a8a88560fa1f9dac32d4c801e5eb8d759d3f6b060e.
This is a supplemental reference; the frozen archive remains unchanged. Its
quotation rule captures markup.quotation and text.quotation separately.

The three built-in Markdown definitions now include that shared rule. Default
scope rendering gives quotation text italic font traits and attenuates its markup.
Theme scope rendering still runs afterward and can override defaults. Plain Text
and custom grammars without this rule do not gain quotation matches. No separate
quotation regex was added to the view.

The offscreen rendering regression failed before this correction. It now checks
italic body, plain following text and style reset across syntax changes, with
content, selection and Undo unchanged. A Core case checks nested prefix and body
captures with Unicode and CRLF. Twenty-two syntax methods and nine rendering
methods passed. Local Xcode build and matrix structure0 passed. No deadline or
retry changed.

Native Quote QA loaded the saved782-character wrapping note. The quotation now
renders in italics with attenuated markup, while lists and hanging alignment stay
intact. This resolves the specific before/after difference observed against
Drafts54.1.1. It does not accept all Markdown styling or native custom-theme
behavior. Word count130/131 remains a separate recorded difference.

QA quit normally. Process absence was checked before exact unregistration. The
runtime, preferences and closed library are recoverable in Trash. The habitual
app was unchanged. No screenshot or raw log is tracked.

## Known grammar field validation

The frozen syntax-format reference specifies object-valued style captures,
string capture indices, string scopes/templates and boolean enabled/exclusive
options. Previously several wrong types passed initialization and were ignored
at runtime. The new regression failed before this correction.

SyntaxDefinition now rejects malformed style capture objects and scopes, wrong
index container types, missing required link captures, non-string scope/template
maps and non-boolean rule flags. JSON numbers are not accepted as boolean flags.
Shared option checks also cover autocomplete and list rules. Feature defaults
require JSON booleans. Validation runs before File Import can persist records.

The positive regression preserves unknown root, rule and capture fields through
installation and backup. Legacy definitions without optional metadata retain their
existing defaults. Missing metadata was not made mandatory. Unknown platform
fields remain in rangeExtensionType. Full-text evaluation still ignores the range
optimization hint; incremental evaluation is not claimed by this change.

Thirty-eight focused methods passed before the additional preservation case.
The complete Core regression and local build results follow below. No native QA
session was required for this parsing-only change. Existing native syntax import
checks remain separate; these tests do not accept native replacement dialogs.

Full serial Core regression passed669 methods/124 suites. Local Xcode build and
matrix structure0 passed. No retry or timeout changed. Usual app unchanged.

## Exclusive capture boundaries and deterministic capture order

The frozen syntax-format reference describes exclusivity as protection of the
matched pattern or capture range from subsequent patterns. Previously a later
match was discarded in full when any part overlapped a protected capture. This
also removed valid styling outside the protected text. Capture dictionaries were
iterated without numeric ordering, so overlapping capture precedence varied.
Both new Core regressions failed before the correction.

styledRanges now masks protected text from later style ranges and retains the
unprotected fragments in source order. It applies capture indices in numeric
order, with a stable string tie. Exclusions take effect after the current rule,
so sibling captures can still style a parent match. Pattern exclusivity protects
the full match. The tests cover capture-only protection with Unicode, whole-match
protection and indices beyond9.

A direct offscreen renderer case checks actual fonts: protected code stays
monospaced and upright while text on both sides receives later italic styling.
Content and selection remain unchanged. Twenty-six syntax methods and ten
rendering methods passed. Local Xcode build passed. This is automatic acceptance;
custom-grammar comparison in Drafts remains pending. No native session was needed
for the headless range/attribute correction. Full grammar parity stays open.

Full serial regression passed697 app methods/122 suites and671 Core methods/124
suites. Matrix structure0 passed. No retry or deadline changed. Usual app unchanged.

## Syntax conflict review and import as new

Stored syntax import now offers Replace, Import as New and Cancel when a name
conflicts. Import Syntax file selection and syntax installation URLs share this
review. General File > Import still refuses conflicting definitions and directs
the user to this reviewed route. Identical
stored-source URL installation retains its existing no-dialog behavior. Built-in
names cannot be replaced; a stored copy can use a different name. File syntaxes
retain their external-file semantics and require renaming in the source file
before adding another file definition. No file bookmark is silently reassigned to
a stored copy.

SyntaxImportPreparation resolves the choice without persistence. Replace keeps
the installed identity. A new stored copy changes name and identity while retaining
all other JSON fields. It rejects empty, installed and built-in copy names. Cancel
returns no value. The review checks its installed-definition snapshot again after
modal interaction, before persistence, to avoid overwriting a changed catalog.

Four headless choice methods cover identity, no save before commit, cancellation,
unknown fields, backup, built-in/name conflicts, file-copy rejection and storage
failure/retry. Nine focused choice/URL methods and the local Xcode build passed.
The first test compilation lacked inner try expressions in require macros; those
were corrected before acceptance. No retry or deadline changed.

Native isolated QA exercised Cancel, named Copy QA café 🐼 and Replace using a
neutral conflict. The selector retained the original and listed the copy. The
five-note count stayed unchanged. After normal quit, read-only inspection of the
closed neutral SQLite library confirmed the original UUID, distinct copy UUID,
replacement source description and preserved unknown field. This is native QA
plus stored-data evidence, not a Drafts Pro dialog comparison. Built-in-name
copy dialogs, file conflicts and URL delivery still need native checks.

QA process absence was checked before exact unregistration. The bundle, fixture,
preferences and closed library are recoverable in Trash. The habitual app was
unchanged. No screenshot or raw log is tracked.

Full serial app regression passed701 methods/123 suites. Core source did not
change; the preceding671/124 regression remains the Core baseline. Matrix
structure0 passed. This does not close the remaining grammar or Find scope.

## Advanced Find with two source windows

A new headless regression uses two WindowModels in one neutral library, each with
its own editor/Undo fixture. Replace All changes only its source note. The other
selection, query, text and Undo stack stay unchanged. Each editor can undo its own
replacement and persist its original text independently. Both fixtures disconnect
explicitly. All eighteen Find command/replacement/history methods passed.
No production source changed; native QA used the prior successful99184c8 build.

Isolated Find Sources QA created Source One QA and Source Two QA in independent
library windows. Each opened a separate Find window. The second started with empty
query/replacement and both checkboxes off. Its query/replacement were set to
café/coffee while the first used café/té. Reactivating the existing second Find
through Window retained its query/replacement while the first was changed.

Replace All in the first changed only Source One to té té. Source Two still showed
café café. The second Find retained its own two results and coffee replacement;
its Replace All changed only Source Two. Closing Source One removed its Find:
Window then listed only one Find and Source Two. Closing Source Two left no windows
available. This checks normal closure, not a forced-close or queued-event race.

After normal quit, read-only inspection of closed neutral SQLite confirmed exact
separate persisted contents. QA was unregistered by exact path and retired with
its runtime, preferences and closed library recoverable in Trash. Habitual app
unchanged. No screenshot or raw log is tracked.

Reopening Find through the editor bar emitted a fresh request: the first query
was cleared while its té replacement stayed. Reactivating the existing window
through Window did not clear it. Keep this distinction pending Drafts comparison;
do not claim query-default parity from isolation acceptance. Remaining Find
keyboard/default/background and reference acceptance still apply.

## Retained Find fields after closing and reopening

Drafts54.1.1 was checked with the neutral wrapping note. Use Advanced Find was
enabled temporarily. Find used Wrap, replacement Reference QA, regex off and
Ignore case on. Find returned one result. Closing with the native close button
and reopening with Command-F retained both fields and both options. No replacement
ran. Prior field values and the prior native-find preference were restored.

The toolbar regression failed before the correction. WindowModel now owns a
complete AdvancedFindRequest for its source window. Query, replacement and flags
survive Find view destruction. Interface requests preserve that query; script
requests keep their previous initialization, including an explicit empty query
and the existing omitted-query default. Existing API tests retain those checks.
New independent windows still start with their own default request. This does not
claim process-restart or global shared-default parity.

Forty-seven affected methods passed. The new case checks full request retention,
separate window defaults and unchanged script initialization. The local Xcode
build passed. Isolated rebuilt QA loaded Source Two, configured coffee/Reopen QA
with both flags on, and closed/reopened using both Done and native close. Both
fields, flags and two results remained. No replacement ran; closed-library
inspection confirmed the original coffee coffee source.

QA quit normally. Process absence was checked before exact unregistration. Its
bundle, preferences and closed library are recoverable in Trash. Usual Draftly
was unchanged. No screenshot or raw log is tracked. Remaining Find keyboard,
background, restart/default and reference acceptance is still open.

Full serial app regression passed703 methods/123 suites. Core source is unchanged
from the671/124 baseline. Matrix structure0 passed. No retry or deadline changed.

## Command-Return in the multiline Find field

Native Keys QA used preferAdvancedFind=true in its isolated setup. Command-F
opened Advanced Find. With focus in its multiline query, Command-Return did not
record Find. A click on Find did. A separate fresh QA with the preserved pre-fix
binary repeated this control: after Command-Return, History contained only disabled
Clear History; clicking Find added Find: Two. This direct UI control removes the
uncertainty of the first delayed preference-export observation.

FindWindow now handles Command-Return and Command-keypad-Enter before the native
text editor. It shares AdvancedFindCommands.find with the button. That command
records the current valid request and navigates its source editor. Empty/invalid
queries do not change history or selection. Handled events are not forwarded.
Plain Return and modified variants remain native text input. Escape still closes
only the Find window. The window callback holds its source model weakly and checks
that Find remains presented.

Two new headless methods cover key mapping, untouched ordinary/modified keys,
valid request/history/navigation and invalid-regex nonmutation. Twenty-one Find
methods and the local Xcode build passed. Full serial app705/123 passed; Core is
unchanged from671/124. Matrix structure0 passed. No retry or deadline changed.
Automatic tests do not dispatch events or construct visible Find windows.

Rebuilt native QA showed Find: Source in History immediately after Command-Return.
Plain Return inserted a newline into the query and changed its result count;
Escape returned to Source Two without closing it. Closed neutral storage retained
Source Two QA 🐼 plus coffee coffee. No replacement ran. This accepts the checked
keys and enabled-preference route, not all Find keyboard/background/default parity.

Both QAs quit normally. Exact active registrations were removed. An unregister
attempt for the never-launched preserved runtime returned-10814; no global reset
was used. Both runtimes, preferences and closed libraries are recoverable in
Trash. The habitual app was unchanged. No screenshot or raw log is tracked.

## Injected file-syntax access preferences

LibraryStore.syntaxDefinition(named:defaults:) used the supplied preferences for
features but called SyntaxFileAccess.read with global preferences for bookmarks.
A specific Core regression reproduced the failure with an isolated installed file.
The lookup now forwards the supplied preferences to file access too. The original
single-argument lookup still uses standard preferences. Formats are unchanged.

The regression passes with the injected bookmark, fails explicitly after its
removal and retains the installed definition. The combined integration passed
Core672/124 and app707/124 plus the local build and matrix structure0. The related
editor error presentation is a separate change below. No retry or deadline changed.

## Visible editor syntax errors and recovery

EditorBody previously discarded syntax resolution errors with try?. It now uses
EditorSyntaxPresentation to retain a definition or its explicit error. Missing or
invalid syntax displays a notice above the editable text. File definitions offer
Add File Syntax to reselect a source through the reviewed import flow. Rendering
uses plain text while the assigned grammar is unavailable; Note.syntax is not
changed and no successful grammar application is implied.

Two headless methods check missing grammar, unsaved content/selection retention,
invalid and absent files, repair, stable identity and unchanged installed data.
Together with the separate injected-preferences fix, full app707/124 and Core672/124,
local Xcode build and matrix structure0 passed. No retry or deadline changed.

Native isolated QA loaded the neutral Links QA note without its local bookmark.
It showed the explicit reselect-file notice while retaining the source. A neutral
edit was added. Add File Syntax and reviewed Replace restored the same named
file definition. The notice disappeared without removing the edit. Undo restored
the original source; Redo restored the edit. A final Undo left the exact original
source, confirmed by read-only closed-library inspection. The first cleanup check
incorrectly compared a displayed character count with UTF-16 length; it was
replaced with an exact source comparison. This was a check error, not data loss.

QA quit normally. Process absence was checked before exact unregistration. The
runtime, replacement grammar, preferences and closed library are recoverable in
Trash. The usual app was not opened or replaced. No screenshot or raw log is
tracked. File permission denial and native malformed-file paths still need their
own checks; this does not accept all file-syntax contracts.
