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
