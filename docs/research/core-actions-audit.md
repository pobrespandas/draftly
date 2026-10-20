# Core Actions audit — 2026-10-19

## Version storage and Prompt transport follow-up — 2026-10-19

Implemented: revision saves now use the commit hook and rollback on failure.
Prompt field options cannot replace required arguments. Prompt.show rejects
invalid responses before changing published field values or the chosen button.

Automatically tested: nine version tests and eleven Prompt tests passed. The
full run passed 254 core and 154 app tests. The local build and 15 auditor tests
passed. Version tests include SQLite reopen, empty content, pending Unicode text,
readonly history, isolation, and failure followed by an unrelated commit.
Prompt tests include cancellation and 19 invalid response forms.

Draft.saveVersion and Draft.versions now have specific contract evidence.
The inventory is 106 complete, 139 partial, 312 unclassified, three unavailable,
and two excluded members. Strict core acceptance stays open with 820 diagnostics.
Prompt members remain partial. Native options and presentation need acceptance.
The native version-history interface is separate from stored-value contracts.

The raw test and strict-check transcripts were removed at the user's request.
The results above are historical summaries. Repeat the checks for new acceptance.

## Metadata and editor focus follow-up — 2026-10-19

Implemented: Draft UUID is read-only. UUID lookup accepts either letter case.
Title extraction handles CRLF and Unicode line separators. Editor activation
closes the preview and restores focus. Deactivation preserves other text fields.
The active property checks the editor view. Navigation and focus methods have
void returns.

Automatically tested: 234 core tests and 92 app tests passed in the final full
run. The local Xcode build, matrix validation, and 15 auditor tests passed.
Draft metadata has 36 specific tests. Workspace application has seven tests;
identity has three. Editor properties have 12 tests.

Verified in use: `core-next-acceptance.json` passed strict UUID assignment,
case-independent lookup, CRLF title, focus, UTF-16 selection, Undo, and Redo.
See `screenshots/delivery-one-2026-10-19/core-next-passed.txt` and its screenshot.
The final editor text is recorded in `core-next-final.txt`.

Recorded 21 additional Draft member contracts. The matrix now has 104 complete,
141 partial, 312 unclassified, three unavailable, and two excluded members.
Strict core acceptance remains open with 842 diagnostics. Counts are inventory.
Draft.query remains partial for missing archived reference dependencies and
parent-tag behavior. Workspace.installURL has a shared decoder and receiver, with external URL
installation acceptance pending. Editor tab preferences
remain syntax-independent. These differences are not accepted as parity.

Workspace installation follow-up: the URL receiver now uses the same decoder as
scripting. Invalid payloads fail before storage. Unknown fields and identities
survive decoding and backup restoration. Five Workspace identity tests passed.
The final full run passed 234 core and 92 app tests. The Xcode build passed.
External URL opening remains pending; installURL stays partial.

## Delivery one evidence closure — 2026-10-19

Recorded: 22 members now have specific evidence for Draft tag methods, eight
Editor text/selection/save/new methods, and eleven Workspace filter, query,
and presentation members. Draft.tags stays partial because the archived property
is readonly but Draftly preserves its legacy assignment behavior.

Automatically tested: 221 core tests passed. New files check explicit editor
save and new before the runner's final flush, storage failure preservation,
native UTF-16 range undo, and exact Workspace query orders and filters.
The separate native run passed 42 tests in four suites. Four explicit persistence
tests passed in the core target. The regular matrix check and 15 auditor tests
passed. Strict core acceptance remains open with 978 diagnostics.

Verified in use: last action appeared on the neutral row. Normal search preview
showed the body, while matching preview showed line 3. The final paired snapshots
have identical editor content. An external edit before that pair is recorded
separately. The isolated replay passed all Editor, tag, and Workspace assertions.
Two earlier replay fixtures collided with existing tags and are rejected.
Evidence and actions are in `screenshots/delivery-one-2026-10-19`.

The matrix has 83 complete, 162 partial, 312 unclassified, three unavailable,
and two excluded members. Counts are inventory, not compatibility percentages.
The handoff now starts after this evidence closure. Metadata tests prepared for
delivery two also exposed writable UUID, case-sensitive lookup, and title line
boundary defects. These fixes pass but need their own reviewed acceptance.

## Draft, Editor, and Workspace follow-up — 2026-10-19

Implemented: line expansion uses native UTF-16 boundaries for LF, CR, CRLF,
and Unicode separators. Single Workspace writes use the existing batch save
path, including rollback. Loading a draft synchronizes the native editor before
the next script statement. Selection changes synchronize immediately. A new
draft clears the previous native undo history without adding a load undo entry.

The first live run found a load/edit/undo failure: undo restored the previous
editor text. The native coordinator had not received the new draft before the
edit. The correction passed a dedicated native regression and a repeated live
action. The failed run is not acceptance evidence.

Automatically tested: 18 new core tests cover six Draft helpers, four Editor
range and selection members, five Workspace members, and load/update failures.
One new native regression checks loading, editing, undo, redo, selection, and
preservation of the previous draft within one action. The full core run passed
159 tests, including the five original action fixtures. The local Xcode build
passed. The regular matrix check and 15 auditor tests passed. Strict core
acceptance remains open with 1111 diagnostics.

Verified in use: the neutral v2 action passed Draft text helpers, UTF-16
selection, CRLF expansion, edit, native undo/redo, Workspace creation, save,
find, enumeration, query, and application. The query returned one draft. The
window showed that same draft with its tag and title sort. Evidence is in
`screenshots/three-core-contracts-2026-10-19`. The directory includes the action,
success text, and the final native screenshot and UI text. It uses the isolated
Visual QA library. Personal notes were not changed.

Fifteen more member contracts now pass. Draft.insert remains partial: the
reference says range-checking but does not define whether invalid indices clamp.
Its valid zero-based behavior passed, while Drafts comparison remains Pro-gated.
The inventory has 61 complete, 184 partial, 312 unclassified, three unavailable,
and two excluded members. These counts do not measure compatibility coverage.

## Native item acceptance and Version review — 2026-10-19

Implemented: Version content, UUID, and creation timestamp are read-only as
declared by the reference. Revision deletion rolls back on a storage failure.
The public Note identity and library format did not change.

Automatically tested: six new Version tests check immutable snapshots, typed
timestamps with milliseconds, unique stable UUIDs, cached draft references,
missing relations, deletion, and storage failure. The failure test confirms
that later script statements do not run and the revision survives backup.
The preceding full core run passed 140 tests before the failure case was added.
The final focused regression passed 71 tests. The matrix check and all 15
auditor tests passed. The strict core check still has 1205 diagnostics.

Verified in use: an imported neutral action opened the native SelectPrompt in
the isolated Visual QA library. The Unicode title appeared unchanged. The
subtitle appeared below the title in smaller text. The explicit star.fill
symbol appeared. Missing and invalid symbols did not display a fallback icon.
Searching for `fallback` matched the third item's subtitle. Selecting it returned
the original `invalid-icon` ID. A separate Cancel run returned to the same blank
editor and reported cancellation. No note content changed.

Evidence is in `screenshots/select-prompt-item-2026-10-19`: `native-items.png`,
`selected-result.txt`, and the reproducible `action.json`. This acceptance closes
the three display fields. All six SelectPromptItem members and all five Version
members now have specific contract evidence. Native verification is not required
for Version's model operations. QueryDate.create() remains blocked by Drafts Pro.

## SelectPromptItem and reference-app check — 2026-10-19

Implemented: SelectPrompt no longer inserts a document icon when an item has no
symbolName. Only an explicit valid SF Symbol creates an image view. Six new
member tests cover SelectPromptItem construction, factory arguments, ID
uniqueness, Unicode titles, separate subtitles, and optional symbol names.
A native control test checks missing, valid, and invalid symbols.

Automatically tested: the 65 Action API and QueryDate tests passed. A separate
run passed all 11 NativeCoreContractsTests, including the icon regression.
The regular matrix check and all 15 auditor tests passed. Constructor, factory,
and ID now have complete member evidence. Title, subtitle, and symbolName remain
partial until their native display checks pass. No live rendering is claimed.

Verified in use: Drafts opened its action panel and New Action menu. Selecting
New Action opened the Drafts Pro upgrade window instead of an action editor.
The check did not create an action or change a draft. The upgrade window was
closed. Evidence is `screenshots/querydate-2026-10-19/drafts-pro-gate.txt`.
QueryDate.create() remains blocked by this license gate. Its return value in
Drafts was not observed. The Apple Developer team does not remove this gate.

The inventory now has 38 complete, 207 partial, 312 unclassified, three
unavailable, and two excluded members. The core delivery remains open.

## QueryDate member review — 2026-10-19

This review uses the archived QueryDate page with SHA-256
`9cc6104f2420e9e1c16018a243c55d5bc94dc6f8cb023ba42ac5231851e154be`.
It does not refresh the reference or change public APIs.

Implemented: the existing value object and shared Workspace date evaluator
passed the reviewed contracts. No runtime change was needed. Constructor,
date, days, field, and type now have separate matrix evidence. Initial values
are recorded as Draftly defaults. The reference does not specify them.

Automatically tested: six member tests and two calendar evaluation tests passed.
They cover independent instances, Date restoration with milliseconds, negative
and positive offsets, all date fields and range types, unknown access dates,
inclusive start bounds, and exclusive next-day end bounds. A 23-hour day checks
that evaluation uses calendar days. The broader Action API run passed 59 tests.
The auditor's 15 Python tests passed. The regular matrix check passed.

Verified in use: no new native verification is claimed. These five contracts
are value and model operations. The factory still requires a Drafts check:
the archived signature says `create(): Workspace`, but its description creates
a QueryDate and Draftly returns QueryDate. Its matrix status remains partial.

The full inventory now has 562 members: 312 unclassified, 210 partial,
35 complete, three unavailable, and two excluded. These counts are inventory,
not a compatibility percentage. The strict core check still fails with 1271
diagnostics. A diagnostic is not a member count. The core delivery remains open.

## Reference and evidence

The installed reference is Drafts 54.1.1. The matrix records the official page
URLs, source hashes, exact names, member kinds, signatures, and descriptions.
This pass reviews 149 entries: Draft (57), Editor (45), Workspace (30), Script
(2), QueryDate (6), and Task (9). Constructors count as entries.

Each entry separates implementation, targeted test evidence, and live checks.
A test link does not prove every branch of a member contract. The core delivery
remains open. The matrix records known limits. Other API objects remain outside
this pass, except for related versions, logs, and syntax values.

Reference pages:

- <https://scripting.getdrafts.com/classes/Draft>
- <https://scripting.getdrafts.com/classes/Editor>
- <https://scripting.getdrafts.com/classes/Workspace>
- <https://scripting.getdrafts.com/classes/Script>
- <https://docs.getdrafts.com/docs/drafts/filtering>

## Implemented corrections

- `Draft.query` accepts omitted tags, ascending order by default, and flagged
  drafts first. The old boolean fourth argument remains accepted.
- Search supports terms, phrases, exclusions, title and tag fields, flag fields,
  AND, OR, and regular expressions. Queries and the list use the same matcher.
- One JavaScript object represents each draft in an action. Queries do not erase
  pending changes. Editor replacements refresh that cached object.
- Color labels match the existing Draftly UI. Stored indices remain unchanged:
  red 1, orange 2, yellow 3, green 4, blue 5, purple 6, gray 7. This corrects the
  previous scripting label mismatch. It does not migrate imported color values.
- Trash keeps the previous archive state. Gray survives a script update.
- Draft location fields default to zero. Script saves retain the last selection.
  Loading an unsaved draft now fails explicitly.
- Task interactive text, compact task labels, linked-item fields, and marker
  prefixes follow the reference shapes. TaskPaper uses its own task state ranges.
- Custom template tags are available to both template engines.
- Workspace queries and visible rows share date, flag, tag, and sort rules.
  Display options affect the list. Dates reconstruct as JavaScript Date objects.
  Group references and local theme preferences apply to the window. Missing
  references fail before the window changes. Theme application does not overwrite
  the user's global theme preference.
- Script changes register native undo before the next script statement. Undo and
  redo restore text and selection and update the cached draft.
- Step timers and completion handles expire at the step boundary. Late promise
  failures cannot change a later step. Host calls expire when execution ends.
- `ActionExecutionResult` distinguishes success, cancellation, and failure.
  Menus, URLs, and App Intents use this result. The boolean `run` adapter remains.
  Execution still waits through the existing main-run-loop mechanism.
- Logs use the API status names. Renaming an action keeps its log relation.
  Cancellation messages are retained in the log.
- Reference refresh keeps evidence, flags changed signatures, retains removed
  members, and keeps the previous snapshot on a fetch failure.

## Automated and live evidence

The Swift suites cover the five original action scripts, query contracts,
Unicode ranges, metadata, workspace backup recovery, native list application,
synchronous native undo, step isolation, timeout, rejection, circular inclusion,
queue cancellation, and storage failure. Three Python tests check reference
parsing and evidence retention.

Computer Use ran `Core acceptance` from the Actions menu in DraftlyCoreQA.
The action changed Unicode text, performed undo and redo, added `core`, saved
and applied a workspace, and checked its query result. The visible result showed
`Core acceptance passed`, one row, title ascending, and hidden row tags.
The screenshot is `screenshots/core-actions-2026-10-19/native-acceptance.png`.
The QA app used a new temporary library and was closed after the check.

No draft operation ran on the user's normal library. The normal Draftly and
Drafts windows were read to compare their header and tab bars.

## Remaining acceptance limits

- Shared syntax definitions now support custom tasks with multiple states, markers,
  links, and capture styles. Full grammar parity and all built-in contexts remain open.
- Access-date sorting and filtering have targeted tests. Full native acceptance
  of scripted date filters and all window entry points remains open.
- Advanced find has a separate interface and honors `preferAdvancedFind`.
  Its full comparison with Drafts remains open. `scanDocument()` returns an empty
  string on Mac. File OCR is a separate operation. VisionKit scanning excludes macOS.
- Imported Drafts themes are not supported. Local theme preference branches have
  automated checks; all appearance transitions still need live acceptance.
- URL and App Intent entry points use the shared result, but their asynchronous
  end-to-end behavior still needs live checks. Native callback tests use a host.
- The existing run-loop wait can admit UI reentrancy. Tests reject a second run
  on the same runner. Cross-window reentrancy still needs a full acceptance pass.
- Test associations identify relevant regression coverage. A complete assertion
  set for every documented default and error is still a closure requirement.

## Visual comparison reported during this pass

With tab bars visible in both apps, Drafts starts its tab bar after the filter
sidebar. Draftly spans the full window. Draftly therefore moves the filter
sidebar down by about 36 points. The current split controller creates generic
split items; the reference behaves as a native full-height sidebar. No tab-bar
layout fix was included in this core pass.

The draft-list search field is shorter and slightly lower in Draftly. The header
buttons are smaller. Header spacing also differs. These are visual follow-ups;
the comparison does not count as pixel-aligned acceptance.

## Expanded audit — 2026-10-19

The dated official inventory now has 562 unique members. Manual evidence survives
regeneration. The structure check passes. The closure check still identifies
356 unreviewed members. Do not treat this inventory as complete compatibility.

This pass adds targeted contracts for SelectPrompt items, typed configuration
values, AppleScript and Shortcut responses, callback result routing, strict
UTF-16 range inputs, query errors, library execution isolation, timeout behavior,
Device values, and imported separators. The matrix records implementation,
automated tests, live checks, and known limits separately. System, utility, and
advanced steps have a separate inventory of 25 entries.

A temporary native action verified editing, undo, redo, selection, a prompt, and
a battery read. External callback delivery remains pending. SelectPrompt still
uses a popup; searchable results remain a UI gap. Access-date queries, full
syntax grammar, advanced find, and exhaustive workspace presentation remain
open. The earlier visual observations above describe the earlier core pass;
see the later visual validation entries for subsequent toolbar and sidebar work.


## Points 6–11 implementation pass — 2026-10-19

### Implemented

The reference archive stores the original HTML in deterministic gzip files.
Each object and step records its URL, capture date, and SHA-256 hash. The
archive covers 562 members and 25 step types. Drafts 54.1.1 remains the installed
behavior reference. A refresh keeps manual evidence. A changed contract marks
its acceptance for review. A changed step page marks its steps for review.

`--check --require-parity` is separate from the classification check. It rejects
included partial or absent contracts. It requires specific normal, default, and
error cases, valid test names, and native evidence or a reason why it is not
needed. It also rejects missing scope objects, steps, engine contracts, invalid
archives, stale reference reviews, and exclusions outside the approved list.
These checks validate evidence records. Human review must still confirm that
an assertion proves its member contract.

`Note.accessedAt` is optional. Old notes keep an unknown date. A successful
editor load records access without changing content, creation date, modification
date, or versions. Queries and previews do not record access. Stale note saves
keep the latest known access date. Backup and restore retain it. A duplicate
starts with an unknown access date.

Access sorting places unknown dates last in both directions. UUID order breaks
ties. An enabled access-date filter excludes unknown dates. Workspace queries
and visible rows use the same evaluator. No Core Data schema change is needed.

### Tested automatically

The Swift run passes 151 tests: 99 core tests and 52 app tests. This includes
five unchanged original actions. The added cases cover old payloads, backups,
storage failure, stale saves, unknown dates, both sort directions, date filters,
Workspace persistence, query versus window results, and editor load behavior.
Window tests cover access failure without losing content or selection.

The audit tool passes 14 tests. These cover evidence retention, reference
changes, duplicate inventory, archive corruption, missing contract cases, native
evidence, approved exclusions, and an empty inventory. The structure check
passes. The strict gate fails as expected. The existing 356 unclassified and
199 partial members are not promoted by these tests. No compatibility percentage
is inferred from test counts.

### Verified in use

Computer Use ran the new app in the temporary visual QA library. The sort menu
contains Accessed. Selecting it shows `Sort: Accessed ↓`. Opening neutral note
33 moves it to the top. Its displayed modification date remains 13:34. The QA
library keeps 50 Inbox drafts. The personal library was not used for these tests.

### Still open

This pass does not complete points 6–11. The remaining work includes individual
member acceptance, custom grammars and multi-state tasks, advanced-find parity, the
async execution session, native URL and App Intent acceptance, integrations,
inspector parity, and the remaining Workspace and personalization contracts.
Native access-date filter acceptance and all load entry points need further
checks. iCloud acceptance remains separate. No messages were sent.


### Advanced find follow-up

`editor.showFind(true, initialQuery)` opens a separate sheet. The action-bar
button uses the same entry point. False or omitted preference keeps native
find. The sheet supports literal and regular-expression queries, match case,
result navigation, and Replace All. Literal replacements keep dollar signs and
backslashes. Regex replacements support capture groups. All ranges use UTF-16.
An invalid regex displays an error and disables replacement.

Automated cases cover Unicode offsets, pattern escaping, literal replacements,
regex captures, empty queries, end-of-text matches, invalid patterns, initial
queries, and unchanged editor selection when the interface opens.

Computer Use searched for café in neutral QA note 50. One result appeared.
Replace All changed it to té. Done returned to the editor. One native Undo
restored café. No personal draft changed. The interface has not completed its
full behavior and appearance comparison with Drafts. That acceptance stays open.

## Core contract pass — 19 October 2026

Implemented:

- Shared syntax definitions serve scripting and the editor. Imports preserve unknown
  fields. File definitions use local security bookmarks. Backups retain definitions.
- Task changes use UTF-16 ranges. Stale snapshots return false. Native task clicks
  use the same rules and retain Undo.
- Workspace defaults copy a local selected workspace into a new identity. Group
  and theme references resolve before the window changes.
- Create Draft supports folder, tags, syntax, flags, and background creation.
  Configure Window validates options before application. Prompt exports step tags.
- SelectPrompt uses a searchable list with separate subtitles.
- Speech callbacks accept background delivery. Deferred dictation uses the main
  run loop and native text insertion. Cancel does not change the source.

Automatically tested:

- The local build passed. Both Swift test targets passed: 63 app tests and 114 core
  tests. The five original action fixtures remain unchanged by this pass.
- The audit has 15 tests. Core classification passes. Strict core parity still fails.
  Test totals do not establish compatibility.

Verified in real use with the isolated Core QA library:

- A custom grammar survived restart. A task click changed state; Undo restored it.
- SelectPrompt filtered a subtitle with Unicode, returned the correct item, and
  preserved source text on Cancel.
- Transcription returned text from a neutral generated audio file. Dictation returned
  recognized text. `showDictate()` inserted text; Undo restored the exact source.
  A second session opened Dictation; Cancel preserved content and selection.
- `scanDocument()` returned an empty string and preserved the source. The SDK marks
  the VisionKit scanning camera unavailable on macOS. File OCR is not scan acceptance.

Closure remains open. The core inventory has 214 members: 27 complete, 186 partial,
 and one unavailable. Remaining work includes per-member defaults and errors, full
syntax grammar behavior, native Prompt options, first-party step variants, advanced
find comparison, Workspace acceptance, and denied-permission speech cases. Same-name
built-in syntax overrides and native syntax-install URLs still need acceptance.

Use `--scope core --require-closure` to check classification. Use
`--scope core --require-parity` to check acceptance. The latter must remain red
until the included contracts have specific evidence and required native checks.
