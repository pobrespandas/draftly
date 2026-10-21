# Draftly implementation and remaining work

Updated: 20 October 2026.

Draftly works as a local Mac app. Mac parity is not complete. The current work is
the Actions engine delivery. See [architecture](architecture.md) for the baseline
and [Actions execution](actions-engine.md) for the new async route and its limits.
Keep the identity Draftly, `Note`, existing identities and libraries, original
action scripts, Nerd Fonts, and the integrated Markdown preview.

## How to read this status

- **Implemented** means the code exists. It does not imply complete parity.
- **Automatically tested** means specific assertions passed.
- **Verified in use** means a recorded native check passed for that case.
- **Pending** includes missing code, incomplete contracts, and native checks.

The [API matrix](research/action-api-matrix.json) owns individual member evidence.
The [visual matrix](research/visual-parity-2026-10-19.json) owns visual acceptance.
[Validation](validation.md) and the [core audit](research/core-actions-audit.md)
retain historical results. Later results supersede earlier counts.

## Current verification

| Check | Latest result |
| --- | --- |
| App tests | 382 passed after owner lifetime and deadline checks |
| Core tests | 350 passed; original actions run on both routes |
| Python tools | 32 passed |
| Local Xcode build after native services and canonical exclusion | Passed; signing disabled |
| Matrix structure check | 0 errors |
| Whitespace check | Passed |
| Strict core and global parity | Still open |

The matrix contains 562 API members: 106 complete, 139 partial, 312 unclassified,
3 unavailable, and 2 excluded. It also tracks 25 step types. These are inventory
counts, not a compatibility percentage. The reference remains Drafts 54.1.1 and
the archived official documentation from 19 October 2026.

## Architecture refactoring completed 19 October 2026

The baseline tag `pre-refactor-2026-10-19` is published on origin. The six code
stages are implemented. See [architecture](architecture.md) for component
responsibilities, dependency direction, and acceptance. Current work preserves
behavior. Native visible acceptance was deferred under the background test policy.

Three tests that displayed and moved windows were removed. Hidden window tests
now reject ordering and activation. Shared fixture synchronization replaces
repeated queue-draining helpers. A new test covers tag changes across injected
peer windows. The final suite passed 170 app and 267 core tests.

API classifications and the original action scripts are unchanged. Mac parity,
async execution, and the broader native acceptance roadmap remain incomplete.

## 1 Draft contracts

Implemented: creation, lookup, queries, content, titles, dates, coordinates,
tags, flags, organization states, syntax, versions, logs, and templates.
Specific tests cover tag normalization, identity, date and folder queries,
UTF-16 edits, storage failure rollback, revisions, and shared draft references.
Recorded native checks cover metadata, text, selection, saving, and Undo/Redo.

Pending:

- Finish evidence for each included member, defaults, returns, and errors.
- Complete syntax-specific tasks, multiple states, markers, and links.
- Finish grammar and recent-tag contracts, Mustache, and custom template tags.
- Complete native version and execution-history access checks.
- Verify permalinks from another app.
- Resolve the readonly `Draft.tags` reference versus retained direct assignment.
- Close `Draft.query` reference dependencies and parent/descendant tag behavior.
- Compare out-of-range `Draft.insert` with Drafts when Pro access is available.

## 2 Editor contracts

Implemented: text and selection APIs, load/new/save synchronization, native
Undo/Redo, focus, recent drafts, navigation, tasks, and separate advanced find.
Tests cover UTF-16, Unicode, line boundaries, immediate visible edits, and Undo.
The preferred find checkbox was verified with both Cmd-F interfaces.

Pending:

- Finish per-member properties, activation, navigation, recent-draft evidence,
  and `editor.draft` contracts.
- Connect the preferred tab string to each syntax configuration.
- Finish tasks, markers, links, Arrange, and their variants.
- Finish advanced find options, result navigation, replacement, cancellation,
  and native-find coexistence.
- Finish negative dictation/transcription cases and text preservation.
- Keep the Mac scan-document unavailability evidence separate from file OCR.

## 3 Workspace contracts

Implemented: saved filters, exclusions, dates, folder views, flags, sorting,
access dates, presentation options, groups, default workspace, and installation
URL decoding. Tests cover persistence, unknown fields, missing references,
query order, and several visible-window applications.

Pending:

- Finish each name, date, link, query, and per-folder sorting contract.
- Complete unknown access-date and flags-first acceptance.
- Verify initial folder, groups, and themes by identity in actual windows.
- Compare query results with visible rows after restart and backup restore.
- Verify external installation links and missing references without partial changes.
- Complete shared theme persistence needed by workspace application.
- Compare `QueryDate.create()` in Drafts; the archived signature contradicts
  its description. Keep this comparison blocked, not accepted.

## 4 Syntax prompts and core steps

Implemented: built-in syntax selection, custom definitions, validation and
storage, prompt controls and response transport, Create Draft, and Configure
Window. Version and prompt validation failures have targeted regressions.

Pending:

- Finish official custom grammar features and multiple task states.
- Verify syntax install, replacement, external files, reload, URLs, and built-in
  name collisions. Preserve unknown fields.
- Finish all included Create Draft and Configure Window variants.
- Finish Prompt and SelectPrompt constructor/factory, defaults, controls,
  subtitles, icons, help, focus, scrolling, and native presentation.
- Verify cancel, Escape, close, and non-cancelable prompts.
- Keep unavailable reference comparisons pending without Drafts Pro.

## 5 Actions engine

Implemented: legacy adapters and runAsync, a serial JavaScript worker,
execution identity, current step, cancellation requests, and a final report.
The report distinguishes asynchronous-script timeout. A library gate prevents
concurrent runs. Step epochs isolate script completion and timers. Included
steps share context; enabled unknown steps fail before execution. Imported
unknown or disabled steps remain stored.

Tests cover original actions, promise rejection, duplicate completion, stale
step timers, cancellation, timeout, queues, circular includes, and success
metadata. New session tests cover final report identity and cancellation while
preserving completed host effects.

Pending:

- Finish native acceptance of the migrated UI, URL, and App Intent entry points.
- Remove remaining synchronous waits in native capability adapters. The new
  worker script wait uses continuations and scheduled timer events.
- Complete run/step callback tokens, late callbacks, reentry, simultaneous
  windows, and cancellation/timeout from every entry.
- Complete native include and remaining context/queue acceptance. UUID and
  templated-name resolution now have automatic tests on both execution routes.
- Close the fourteen required engine evidence records. The strict auditor
  rejects missing records.

## 6 Integrations and automation

Implemented paths include URLs, App Intents, HTTP, XML-RPC, local files,
bookmarks, Mustache, Markdown, HTML conversion and interactive preview,
Shortcuts, AppleScript, shell, Mail, Messages, Calendar, Reminders, speech,
location, and Apple models. Coverage and native availability vary.

Recent work connects Markdown preferences to previews, HTML Preview steps,
Action templates, file names/folders, and scripting `processTemplate`. HTML
paste has Unicode, selection, Undo/Redo, tag-name, and clipboard regressions.
Bookmark creation and Forget were verified with a neutral folder. Battery and
positive dictation/transcription evidence remain valid.

Pending:

- Finish async URL/Intent results, parameters, destinations, and real callbacks.
- Complete local HTTP/XML-RPC server cases, dates, binary data, malformed
  responses, network errors, cancellation, and timeout.
- Finish bookmark restart, actual Action access, stale/denied permissions,
  iCloud Drive, and Mustache folder contracts.
- Finish HTML structures/options, native paste from another app, preview data,
  and cancellation. The regex converter is not complete HTML parity.
- Finish native acceptance for Mail, Messages, Calendar, Reminders, Shortcuts,
  AppleScript, shell, location, and Apple models.
- Separate permission denial, cancellation, system unavailability, and defects.
- Require an authorized recipient and content before sending any real message.

## 7 Action inspector and organization

Implemented: step editing, configuration values, description/options, shortcuts,
groups, sections, ordering, visibility fields, confirmation, notifications, and
success tags/flags. Shortcut validation is shared. Original scripts are intact.

Pending:

- Complete imported options, visual icon selection, step/platform editors,
  and uniform order/visibility in every access.
- Verify edit copies, cancel, atomic import, confirmation, and result effects.
- Finish create/edit/duplicate/move/reorder/delete acceptance for actions/groups.
- Finish export/backup/restore, retained unknown fields, shortcut conflicts,
  and visual inspector parity.

## 8 Preferences and personalization

Implemented: fonts/Nerd Fonts, size, spacing, margins, maximum width, typewriter
scrolling, shortcuts, themes, and workspace management. Settings has General,
iCloud, Bookmarks, Markdown, HTML, Editor, and Shortcuts categories.
General includes appearance, menu bar visibility, capture timeout, preferred
find, launch-at-login registration, initial-window policy, three global shortcut
recorders, and After Success move navigation. Current workspace snapshots preserve advanced filters, tag presence,
unknown fields, and per-folder order on save and application. Missing references
are rejected before Save Current persists. Native missing-reference and failed
save checks remain pending.
The app menu has Editor Settings, Library Summary, and library-wide Empty
Trash with confirmation, including when no command window exists.

Pending:

- Verify launch-at-login on a service-capable installation, physical global-key
  delivery, and the remaining startup/restoration variants. Initial-window policy,
  recording, persistence, and the recorded action navigation paths passed their
  specific checks. Finish the other included Settings categories and native
  appearance/geometry comparisons.
- Complete individual Markdown options, escaped line breaks, live changes, and
  visual/click checks for reference-help controls.
- Verify workspace date/flag/per-folder sort controls in native use. They are
  implemented. Group and theme selectors are also implemented. Their saved
  selections and Cancel passed a native QA check; full application/restart
  coverage and visual parity remain open.
- Shared themes now use generic library records with stable identities and
  optional backup data. Local definitions migrate once per device and library.
  Native create/save/edit-cancel/restart/render and selection/Undo passed in QA.
  Native backup record recovery passed. Restored-theme rendering, legacy
  migration, and Mac+VM sync remain pending.
- Drafts theme file import now validates and preserves complete source, with
  review and explicit rendering limits. Native file import/save/replace/cancel
  passed. Exact scope rendering now has background tests for Markdown/custom
  syntax. Verify it natively and complete other syntax/interface coverage. Verify MultiMarkdown/TaskPaper in all accesses.
- Verify restart, backup, selection, content, and Undo after configuration changes.
- Keep local device preferences separate from shared library definitions.

## 9 Main window capture and search

Implemented: native split panels, tracked toolbar separators, tabs, draft rows,
tag capsules, flags, footer statistics, action panels, menu bar commands,
swipe Archive/Trash, batch/context operations, and Merge with Archive default.
Capture has its own persistent buffer/window. Quick Search is independent from
list filters. Two macOS Services have implementations and recorded native checks.

Pending:

- Complete paired visual captures at 1033 × 734 and 1200 × 800 points; review
  850 × 600. Cover themes, activation, search, panels, tabs, and selection.
- Finish typography, icon, material, action-panel, toolbar, and tab parity.
- Finish one-point alignment measurements and Dock/Finder/app-switcher icon checks.
- Repeat rapid transitions, Reduce Motion, resize, focus, Undo, overflow,
  swipe, and VM redraw checks. Preserve chosen widths.
- Finish status-menu icons/separators/recents, empty clipboard, no-window Empty
  Trash cancellation, Quit with edits, and Merge integration.
- Finish Services/capture/search from another app, without a main window, with
  multiple windows, after restart, and after save failures.
- Update the habitual app only after the required regressions pass.

Computer Use can read Drafts and QA Settings. The earlier native-pipe failure
recovered; later Settings interactions passed their recorded checks. A future
observation failure must still be checked against the actual process state.

## 10 Data sync and personal distribution

Implemented: Core Data storage, compatible backup import, revisions, conflict
copies, action groups/syntax backup, local builds, and development-signed builds.
The main CloudKit container passed initial download, creation, and edit exchange
between the Mac and UTM VM. The access-date/content conflict fix was retested.
See [iCloud evidence](research/icloud-acceptance-2026-10-19.json).

Pending:

- Shared themes and execution history are included in compatible backups with
  rollback tests. Native merge recovery and restart passed for the recorded
  fixture. Complete the remaining conflict, syntax, group, and failure cases.
- Repeat restore/migration and unknown-field checks for all new fields.
- Repeat the broad main-container matrix with both clients connected: metadata,
  revisions, actions/groups/order, workspaces, syntax, themes, Trash/Restore,
  access dates, and concurrent text variants.
- Verify a signed update with a different executable and existing library.
- Verify effective team and profiles on both recipients.

Offline checks remain postponed. Two physical Macs are additional coverage.
Developer ID, notarization, and public distribution are outside this delivery.

## 11 Audit performance and final acceptance

Pending:

- Review all unclassified members and resolve included partial contracts.
- Complete exact signatures, defaults, returns, errors, and specific evidence
  for all included objects and 25 step types. Preserve manual evidence.
- Run strict core and global checks. A normal structural check is not parity.
- Measure search/selection/scrolling with 10,000 drafts; measure editing,
  search/selection/Undo/save with 100,000 characters. Record typical/max times,
  hardware, build, data, and storage. Fix stalls and text loss.
- Complete integrated native runs and local/signed builds.
- Preserve explicit Pro, permission, hardware, and postponed-check limitations.

## Repository cleanup and next session

- Split app coordination, delegate, commands, and Settings out of the scene file.
- Removed three tests that repeated a toolbar identifier array. Native layout,
  animation, state, data, and Actions regressions remain.
- Removed two redundant test transcripts, four old root build logs, and generated
  caches. Kept app products, signed packages, frozen references, and VM evidence.
- Removed obsolete ignore-template sections and duplicate/stale README claims.
- Updated the glossary for merge sources, capture, backup contents, and execution.
- Removed the session evidence directory at the user's request. Current results
  remain summarized here; removed artifacts are not available for reinspection.

Next implementation priority requested by the user: the Actions engine. Start
from its initial session; the worker and real async entry do not exist yet.
Repository organization is a separate task and does not close engine contracts.

Both apps were reset locally without a recovery copy after explicit confirmation.
Drafts shared data and its app preferences were deleted through Finder. Draftly's
local store, 34 temporary QA libraries, and 14 preference domains were removed.
Both apps opened with 0 drafts and empty editors. Drafts iCloud is off; the new
local Draftly build has no CloudKit container. Remote iCloud data was not reset.
The new local Draftly is `.build/xcode/Build/Products/Debug/Draftly.app`.
All former screenshots, the `docs/research/evidence` directory, three local build
evidence directories, and ten additional generated logs were removed on request.
Generate new native captures for future acceptance. Historical validation text
is retained as a summary, not as an inspectable artifact.

Excluded: mobile platforms, widgets, MCP, Chat Console, third-party AI/connectors,
and Mail Drop. Native Apple models remain in the Mac scope.


## Version control review 19 October 2026

The initial review found `main` equal to `origin/main` and an empty index.
The user then authorized commits and push. The changes are split by behavior
below. Use Git history and remote tracking status for the publication state.

### Include in commits

- Production Swift and JavaScript changes, including the new source files.
- Their contract and regression tests, including the five unchanged fixtures.
- `Configuration/Info.plist` Services metadata, `Package.swift`, and the generated
  Xcode project. Keep the project source references aligned with added app files.
- README, glossary, this status, validation summaries, and compatibility matrices.
- The benchmark tool and frozen API reference needed by the auditor.

Shared files were staged by change. Each staged source snapshot was copied to
a temporary build directory. Swift tests compiled the app and checked each
change before its commit. The final run covers the complete change set.

| Commit | Scope |
| --- | --- |
| `fix(core): enforce draft editor and workspace contracts` | Identity, focus, prompt responses, version rollback, installation decoder, and member tests |
| `fix(ui): stabilize panels and align draft presentation` | Split transitions, row measures, toolbar state, redraw, footer statistics, and visual matrix |
| `refactor(app): separate lifecycle commands and settings` | Source extraction and generated project references |
| `feat(markdown): apply preferences to previews and templates` | Renderer settings and template integration with contract tests |
| `feat(capture): add native capture services and preserve pending edits` | Services registration, capture routing, and failure handling |
| `feat(settings): add preferences and library commands` | Settings pages, app menu, bookmarks, HTML paste, and shared Trash command |
| `feat(actions): add execution sessions and final reports` | Initial session, legacy adapters, cancellation, timeout, and reentry tests |
| `chore(repo): clean artifacts and record implementation status` | Ignore rules, package warnings, glossary, README, and status summaries |

The first extraction-only candidate exposed failures already covered by pending
identity and redraw fixes. It was not committed. The corrections precede the
extraction in the final history. Full asynchronous execution remains pending.

### Keep local or ignored

- `.build`, app bundles, archives, generated caches, and logs.
- Screenshots and regenerated session evidence.
- `Configuration/Signing.xcconfig`, profiles, certificates, private keys, and env files.
- User databases, captures, exports, backups, and machine preferences.
- Xcode user state, Python cache, and the local handoff.

Keep `CLAUDE.md` and `.claude` as tracked symlinks to their existing sources.
The signing example and public app/container identifiers may stay tracked.
The tracked-file scan found no private keys, GitHub tokens, AWS access keys, or
matching device identifiers. No signing profile, private signing config,
database, or log is tracked. This targeted scan is not a full security audit.

### Push gate

Push only the tested commits, after reviewing their staged diff and running the
checks in README. A complete Mac parity claim is not justified. Engine async
work, native acceptance, and strict gates remain open. No history rewrite or
force push is needed for the current branch state.

## Async native input delivery — 20 October 2026

The async host now covers prompts and confirmation, file transcription, calendar
editing and creation, and Apple model responses. Model tools reject closed
requests and discarded sessions. Legacy adapters remain compatible. Live
dictation and the remaining synchronous native adapters still need review.

The final background run passed 260 app tests and 313 core tests. The unsigned
Xcode build and normal matrix check passed. The strict engine gate remains open
with 120 evidence diagnostics. Real acceptance for the new dialogs, transcription,
EventKit persistence, and model tools is pending. See docs/validation.md for
specific cases. The full Mac plan remains open.


## Current engine delivery — 20 October 2026

Dictation and AppleScript use cancellable native adapters in the async route.
AppleScript preserves missing values and native record fields. Neutral real QA
verified AppleScript success and cancellation, prompt keyboard behavior, selector
filtering, and URL confirmation cancellation. A launcher-only Debug refresh was
invalid; all accepted new checks were repeated with the complete code image.

The final run passed 288 app tests and 322 core tests. The unsigned build and normal
matrix check passed. The strict engine gate has 44 evidence diagnostics. All 14
engine records remain partial, with specific pending native checks and limits.
No API member classification changed. Real dictation and the remaining native
capability checks are pending. The full Mac plan remains open.

## Current native wait delivery — 20 October 2026

Interactive HTML, file panels, bookmarks, and composition use async host adapters.
Native interruptions and expired replies stop later effects. Shared file/message
payloads preserve the legacy route. Real QA passed embedded HTML data and
cancellation, Save cancellation, and exact Unicode export. Real Mail/Messages,
bookmark persistence, standalone HTML, and other native variants remain pending.
Composition options that the adapter cannot implement fail explicitly; they stay
compatibility limits. Printing, arrangement, and sharing outcomes still need work.

The final run passed 315 app tests, 330 core tests, and 32 Python tooling tests.
The unsigned build and normal matrix check passed. Strict engine acceptance is
open with 42 diagnostics; all 14 engine records remain partial. API member
classifications are unchanged. See docs/validation.md for exact evidence.

The engine unknown disabled imports contract has passed its specific automatic
and native checks. Thirteen engine records remain partial; strict engine parity
reports 39 diagnostics. This is separate from the 562-member API inventory. See
the latest validation entry for the independent window-close control and payload
round trip.

The current separator delivery adds shared non-executable presentation and
retains management controls. Native QA checked the list heading, horizontal
line, edit/save order, and exclusion from search. Bar/menu/picker and native
backup recovery checks remain pending. The separator contract stays partial.
Inclusion and queue tests also found and fixed retained pending queue state in
the legacy failure/cancellation route. Final checks passed 388 app tests, 361
core tests, Python32, and the unsigned build. Matrix structure is valid; strict
engine parity still reports 39 diagnostics. See the latest validation entries.

Native follow-up checked separator order after restart, the editing bar divider,
and absence of an executable separator in the Actions menu. URL queue cancellation
kept the completed child edit in Inbox, stopped later work, and delivered one
observed cancel callback without success parameters. Native error/timeout,
separate targets, picker, and backup recovery checks remain open. The matrix
records partial acceptance and specific executed regression tests.

Native URL queue failure and the production 120-second timeout also passed.
Both kept the completed child text in Inbox, stopped later steps/actions and
Archive, recorded Error, and delivered one observed matching error callback
without success parameters. Separate targets and remaining native entry points
still need acceptance. The queue record remains partial.

Separate-source/target cancellation passed through a URL using the matching
visible editor. Both drafts kept their own completed text in Inbox. The editor
finished on the target and one cancel callback was observed. Separate-target
error/timeout and remaining native entry points are still pending.

Native static and dynamic inclusion cycle checks passed. Static cycles preserve
the original text; dynamic cycles retain earlier effects and stop the cyclic
subtree, tail, and success disposition. The engine cycle safety contract is now
complete, with its 50/51 depth boundary documented as a Draftly policy. Two
engine records are complete and twelve remain partial. Strict parity reports
36 diagnostics; entry-point equivalence and full Mac acceptance remain open.

Native URL CPU deadline acceptance passed with responsive filters and retained
text. Direct UI and Intent variants remain pending. New async-limit cases pass,
but an unreturned rejected promise still becomes timeout. Its two error-report
assertions are recorded known issues; this is not accepted promise parity.

The subsequent correction resolves those rejection issues. The runtime observes
engine-level unhandled rejections, including intrinsic async promises; caught
rejections still succeed. Native URL checks passed for all three cases. A new
per-worker authority also rejects unknown, altered, and repeated host requests
before effects. Full checks passed 388 app and 373 core tests without known
issues, plus the unsigned build. Remaining native contracts stay partial.

CPU task cancellation and cross-step promise/timer regression cases passed.
Native overlap with two independent windows and URLs also passed: the second
request returned busy without edits, while the owner completed successfully.
Intent overlap and the other required native variants remain pending.

The strict evidence check now rejects complete records backed by directly
disabled or known-issue tests and missing method references. Explicit test files
support suites in shared source files. Python37 and matrix structure passed;
strict engine acceptance remains open with 36 diagnostics. The user-authorized
two disposable Shortcuts were deleted and their absence was verified.

Native inclusion by UUID survived a real inspector rename. Template-name
inclusion resolved the renamed action and both calls shared one global. The
shared-inclusion record stays partial: configuration precedence and native first-use configuration acceptance remain
unresolved. Both runners now prompt for required first-use values, distinguish
confirmation from imported defaults, and save accepted values atomically.
Cancellation, storage failure, concurrent edits, and included-action ordering
have specific background tests. The regression run passed 388 app and 390 core
tests. Native configuration checks remain pending.


Native first-use text configuration passed: Escape retained the source, Unicode
acceptance reached the editor, and confirmation survived a restart. Included
static cancellation kept the original text; dynamic cancellation kept the prior
root effect. History confirmed the final results. Other field types, new required
fields, and configuration precedence remain pending. The record stays partial.


Native Boolean/number configuration and new-required-field checks passed. Invalid
numeric input was rejected without losing the checkbox or text. Acceptance kept
false and zero as typed JavaScript values. An imported revision retained prior
confirmation and prompted only for its added field. Configuration precedence
remains unresolved.


Completion and timer isolation now has native URL acceptance for old handles,
removed old timers, current-step waiting, duplicate completion, and failure
precedence. The specific automatic cases passed in a focused five-suite run.
That engine record is complete. Returned rejection also passed natively; its
shared timeout record remains partial. Entry-point acceptance is still open.


Current-image direct UI CPU timeout and native URL 120-second queued timeout
passed. Filters stayed responsive during CPU work. Both failures kept prior text
in Inbox and stopped later steps/Archive. The queued timeout delivered exactly
one error callback without success parameters. The new actual-worker automation
boundary case and existing context cases passed (nine methods). App Intent and
separate-target variants remain pending; no broader closure is claimed.


Action installation by URL now saves the decoded set atomically. Storage failure
rolls back replacements and new actions. Four focused installation cases, both
URL target regressions, and the unsigned Debug build passed. Native failure
injection was not performed. Existing import compatibility evidence remains
scoped to its recorded checks.


The actual RunDraftActionIntent.perform now has isolated background tests for
success, errors, busy reservation, CPU/async deadlines, and cancellation. The full
run passed 401 app and 391 core methods. Xcode metadata extraction passed without
new visible parameters. Native Shortcut dispatch remains pending. Review found a
separate headless-owner overlap gap before pending saves; it is not accepted yet.


The headless-owner overlap gap is fixed. Canonical library exclusion is checked
before pending saves or selection changes in automation and single/batch window
actions. A real overlapping intent regression failed before the correction and
now passes across five accesses. The final full run passed 402 app and 391 core
methods. Native system delivery of these new cases remains pending.


Native Shortcuts now verifies success, production CPU timeout, and a 120-second
queued timeout on a different note. Mixed Intent/URL overlap passed in both
directions, including two windows and an owner without a matching editor. The
synchronous-deadline and process-local exclusion records are complete. Remaining
cancellation, source-close, callback, and capability variants stay open.


Worker runtime operations now enforce serial queue ownership. A scalar probe and
two actual worker cases verify host suspension, timer success, cancellation, and
explicit close/release off MainActor. Full regression: 402 app and 392 core methods;
unsigned Debug build passed. Native acceptance of the assertion build remains
pending. The worker record is still partial.


Native theme link acceptance now covers the configured green underline and
disabling Link Mode with Unicode selection intact. Exact Drafts precedence and
other theme interface mappings remain open. General Settings was inspected in
Drafts: launch-at-login and main-window-at-launch controls exist. Their Draftly
implementation and lifecycle acceptance remain pending. See validation for the
observed controls and limits. Workspaces, Settings, and personalization are not
closed.


Launch at login now uses the system service and exposes approval/errors. Three
isolated contract methods, full regression (419 app and 416 core), and the
unsigned build passed. QA showed the system notFound/unavailable path. Real
registration and login acceptance remain pending. Main-window launch policy and
configurable global shortcuts are not implemented by this change.


Show main window at launch is implemented with local persistence and scene
suppression/restoration policy. Early explicit window requests wait for the
scene opener. Native QA passed disabled/enabled startup, warm and cold URL
selection, and capture without the main window. Full regression passed 421 app
and 416 core methods. Dock reopen and other installation/restoration variants
remain pending. Configurable global shortcuts are still next.


General now exposes three global shortcut recorders with local persistence,
shared conflicts, clearing, and Carbon registration. Native recording, conflict
rejection, restart persistence, and capture inside QA passed. The attempted
synthetic event from another app did not trigger capture; global delivery stays
unverified with cause unresolved. See validation. Full regression passed 422 app
and 419 core methods before the two final focused corrections; final focused
checks and build passed. This does not close global shortcut acceptance.


Global hotkey registration now uses fresh identities. Focused tests verify
rejection of stale events and identity exhaustion; the build passed. Physical
global delivery remains pending. Drafts After Success navigation was inspected:
Create New Draft and Open Next Draft are the two choices. Draftly integration
and behavior acceptance remain open.


After Success move navigation is connected to General, single-window execution,
and single context commands. Automation retains the processed draft identity
separately from editor navigation. Multiple-target execution retains its agreed
last processed draft. Eight contract methods, the full regression (432 app and
419 core), and the unsigned build passed. Native interaction and exact Drafts
comparison remain open; see validation for the fallback and batch policies.


Native After Success navigation now passes Actions-menu Archive to scratch,
Trash to the next visible draft, original archived text retention, and preference
persistence after restart. The preference was restored to Create New Draft.
Action-panel, URL presentation, Undo, and exact Drafts acceptance remain open.
The neutral action fixture is saved under scripts/fixtures for repeat runs.


Native action navigation also passed from the action panel and a confirmed URL
on a visible owner. The URL left the scratch selected and delivered one success
callback. Undo/Redo in that scratch and the original archived text passed their
checks. Older Undo stack retention, headless variants, list-end behavior, exact
Drafts comparison, and the physical global-key check remain pending.


Execution history now joins themes in compatible version 1 backups. Six specific
methods and the full regression (432 app and 425 core) passed. The unsigned build
passed. Native recovery and connected synchronization remain pending.


Native Import now routes action and note files through one transaction per file.
It also preserves distinct texts that share an incoming note ID. Five specific
methods, the full regression (432 app and 430 core), and the unsigned build
passed. Native recovery and failure injection remain pending. Multi-file
selection has a per-file boundary; earlier successful files are retained.


Native backup recovery passed export, import into a separate local library,
restart, and export again. All source records matched by identity and full data,
including 75 execution records. One unrelated neutral note/revision from a
selection mistake remained as an explicit destination extra. Syntax/group arrays
were empty. This does not close conflict, failure, or connected-sync acceptance.


Native content-conflict recovery passed in Recovery QA. Both texts survived.
The recovered revision and execution use the copied note identity; the existing
execution still uses the edited original. Export comparison verified the graph.
Other conflict variants, native storage failure, syntax/groups, and connected
sync remain pending.


Markdown preview now respects processor line breaks instead of forcing paragraph
whitespace preservation. An offscreen WebKit contract failed before the fix and
passes after it. Full regression passed 435 app methods and 430 core methods;
the unsigned build passed. Live Settings refresh and Drafts comparison remain
pending after a Computer Use connection failure. Global physical-key delivery
also awaits the user's result. The full Mac plan remains open.


A disk-backed conflict-restore failure/retry contract passed with the other six
history-backup methods. Failure preserves the complete graph across reopening;
retry commits one recovered graph. Repeated successful conflict import remains
open: current restore assigns a fresh recovery identity on each conflict.


Repeated successful conflict import now reuses a stable recovery graph. It
preserves a newer access date, keeps edited recoveries, and does not merge
unrelated notes by content. Two new contracts and all nine history-backup
methods pass. Full regression passed 435 app and 433 core methods; the unsigned
build passed. Native and connected-sync checks remain pending. Old random
recovery identities are retained without content-only migration.


ActionLog now enforces readonly bridge fields and maps known status spellings
without case sensitivity. Two specific contracts failed before the fixes and
pass after them. Full regression passed 435 app and 435 core methods; unsigned
build and matrix structure passed. Draft.actionLogs has specific evidence for
filtering, order, types, dates, empty history, and independent arrays. Native
acceptance and the remaining ActionLog paths stay partial.


Action log deletion now rolls back and propagates storage failures. Legacy and
worker tests cover failure, retry, void return, unrelated history, and disk reopen.
Action relation tests cover rename, deletion, and same-name replacement. Full
regression passed 435 app and 437 core methods; build and matrix structure passed.
Required native and remaining member variants keep these contracts partial.


Template tags now preserve names that overlap JavaScript prototype properties
through both renderers and later steps. Three specific methods pass, including
legacy and worker cases. Full regression passed 435 app and 440 core methods;
build and matrix structure passed. Template members remain partial. Computer
Use briefly reconnected but input failed again; native acceptance stays open.


Strict audit now validates historical additionalAutomatedTests as well as
supportingTests and reports malformed collections without a crash. All 38
Python tooling tests pass; matrix structure has zero errors. Strict core remains
at 800 diagnostics and engine at 27. Neither gate is accepted.


Draft.find now excludes inherited JavaScript cache keys. The extended existing
contract passes on legacy and worker routes after failing on both before the fix.
Metadata36, full app435/core440, and unsigned build passed. Native comparison
remains separate.


Workspace scripting now retains manual order, tagged filtering, native list
options, and non-API metadata. Four methods on both runners cover query, save,
application adapter, installation, backup, defaults, precedence, and invalid input.
Full app435/core444 and unsigned build passed. Create/query/update are partial
again until affected native checks are repeated; previous evidence is preserved.
Strict core has 809 diagnostics. The full plan remains open.


Next/previous editor navigation now retains the prior cached Draft selection.
The two extended methods pass all four legacy/worker cases after failing before
the fix. Full app435/core444, unsigned build, and matrix structure passed. Native
selection/focus acceptance and remaining error variants stay pending.


All five library deletion entry points now share rollback and error propagation.
Disk-backed action/workspace cases cover failure, unrelated save, reopen, and
retry. Full app435/core445 and unsigned build passed. Native acceptance currently
requires the user to unlock the Mac; Computer Use also has recorded service
assertions. These do not establish a Draftly failure.


Mustache rendering now stays in the action context instead of creating a host
context on MainActor. The async route therefore uses its worker and script
deadline. Two worker contracts and existing template/tag cases pass. Full
app435/core447, unsigned build, and matrix structure passed. Native and remaining
engine/Mustache acceptance stay partial.


Directory Mustache rendering now retains prototype-named files and partials.
Instance factory methods coexist with the original static calls. The extended
directory contract passes both runners, including defaults, escaping, missing
files, and traversal rejection. Full app435/core447 and unsigned build passed.
Three audited members remain partial pending their specific native checks.


XML-RPC now uses awaited HTTP on the async route instead of MainActor RunLoop
polling. Three methods cover wire conversion, actual JS response, fault/error
values, injected transport cancellation/timeout, and gate cleanup. Full
app435/core450, unsigned build, and matrix structure passed. Real server and
native XML-RPC acceptance remain pending; the member is partial.


Float on Top now changes from outline to fill with its window state. Three
toolbar tests and the unsigned build passed. Computer Use confirmed both states
in refreshed Engine QA. App and menu icons now share generated notes-and-pencil
geometry. Resource previews passed inspection; Dock/Finder/menu-bar acceptance
remains open. See the latest validation sections.


XML-RPC CDATA coverage passed seven focused tests against the unchanged parser.
The earlier loss claim was an inference that runtime checks did not confirm.
Params and error now have specific partial evidence. Real transport character
sets, server/native acceptance, grammar, and date/binary mapping remain open.


XML-RPC now rejects duplicate payload blocks, extra param values, and multiple
types in a value. Five malformed cases reproduced silent acceptance before the
fix. Full app436/core453, unsigned build, and matrix structure passed. This is
a bounded grammar correction; XML-RPC and the full Mac plan remain partial.


XML-RPC now has real loopback HTTP coverage for request bytes, Unicode/CDATA,
faults, and invalid responses. Full app436/core454 and matrix checks passed.
Native automation, date/binary mapping, transport character sets, and remaining
grammar stay open. The test does not close the full integration.


XML-RPC fault fields now reject missing or incorrect types without inventing a
fault code. Four red cases and a typed JavaScript fault check cover the change.
Full app436/core455, unsigned build, and matrix structure passed. Three response
fields now have specific partial evidence; full integration acceptance is open.


Real loopback XML-RPC cancellation now has an error-envelope check and server
confirmation of TCP disconnect. Full app436/core456 and matrix checks passed.
This is transport evidence, not native UI cancellation acceptance.


Current Engine QA passed native action-list checks for discarded, intrinsic,
and caught promise rejection. Earlier text survived failure; later insertion
and archive did not run. History showed two errors and one success. Other
entry-point, timeout, and cancellation variants remain pending.


Engine QA action-list acceptance now includes returned promise rejection and
the production 120-second async wait timeout. History confirmed both errors.
Panels responded during the wait; completed writes and Inbox state survived.
A subsequent action succeeded. Other entry points and CPU-bound responsiveness
remain unaccepted.


Actions now exposes Cancel Running Action for the current window. Automatic
checks and native menu/history checks passed, including a later successful run.
Full app437/core456 and unsigned build passed. Other menu action availability
while busy and remaining native cancellation variants are still open.


Action entry controls now share the current-window availability rule, including
the pending phase. Menu and palette behavior passed native busy/cancel checks.
Five focused tests and the unsigned build passed. Cross-window busy presentation
and native list/bar disabled appearance remain pending.


Library busy state now reaches every window from the execution gate, including
new windows. Native two-window menu/ownership/recovery checks passed. Automatic
checks also cover an independent library. Full app437/core456 and unsigned build
passed. Remaining native entry-point and presentation checks stay open.


Current QA passed native CPU-loop responsiveness and deadline checks. A panel
transition completed while Cancel remained enabled and runs were disabled. Both
runs recorded timeout without tail or archive effects. CPU cancellation remains
unaccepted: the attempted cancel lost to the deadline.


Native CPU menu cancellation now passed on current QA: enabled Cancel was
observed during the loop, history recorded Cancelled, and a later action
succeeded. This does not claim instant interruption or close other native
worker/cancellation variants.


Current QA passed Prompt and SelectPrompt accept/cancel through the worker
bridge. Unicode, discarded field edits, subtitle search, selected identity,
and final history status were checked. Other options and interruption paths
remain pending; this does not close these APIs or the engine.


Failed executions now retain prior script console output in stored history.
Both runners, context.fail/throw/cancel, repeated Unicode lines, multiline text,
and custom cancellation reasons passed tests. Native history output passed.
Full app437/core457 and final unsigned build passed. Old lost output cannot
be recovered; no history format or existing record is changed.


Context.cancel now preserves omitted-message semantics on the async path. Both
runners pass exact Unicode reason, undefined return, current-script completion,
quiet cancellation, and stop/disposition tests. Native history defaults passed.
Full app437/core458 plus final focused checks and unsigned build passed. Other
native notification and script-continuation variants stay pending.


Context.cancel has complete member evidence for the frozen valid-input contract.
Native current-script continuation, undefined return, stop/disposition, reason,
and imported notification settings passed. Both runner routes and quiet
notification behavior have specific automatic checks. Other Context, callback,
Workspace, engine, and global acceptance remain pending.


The application icon and menu template now share a simpler stacked-sheet mark.
Asset generation, small-size render inspection, and the unsigned build passed.
Live Dock, Finder, and menu appearance still need verification for this revision.


No-wait callbacks now leave response collections and template tags unchanged.
Both runner routes pass four specific cases. Native script and step checks pass.
Full regression passed app437/core459; the unsigned build passed. Other callback
contracts remain pending.


Finder Get Info now confirms the new mark in the installed QA bundle. Live Dock
and menu-template inspection remain pending because their Computer Use targets
timed out. Other QA and Finder controls worked.


CallbackURL preserves prototype-named outgoing string parameters. Both runners
and a native action pass specific key, Unicode, return, and replacement checks.
Full regression passed app437/core460; the unsigned build passed. CallbackURL
remains partial for other value and error contracts.


Returned callback step data now preserves prototype-named keys. Four specific
cases pass across script/step and both runners. Full regression passed
app437/core461 and the unsigned build passed. Native response-key acceptance
is pending: the Mac locked before the helper update and fixture execution.
The engine strict gate still reports 27 diagnostics.


Shortcut no-wait now reaches the native process launch. Both runner routes pass
twelve response/option cases. Six background process tests cover input lifetime,
cleanup, default wait, cancellation after launch, timeout, and launch errors.
Full regression passed app443/core462; the unsigned build passed. Actual
Shortcuts no-wait acceptance stays pending while the Mac is locked.


Failed Shortcut processes now report an exit status when stderr has no useful
text. Unicode diagnostics stay exact. Six process cases and four script/step
cases pass; failures retain earlier effects and publish no successful result.
Full regression passed app444/core463; the unsigned build passed. Actual
Shortcuts and remaining status variants still need acceptance.


Included step ownership now has six specific cases across both runners and
name/UUID/template references, with nested native/script effects. The current
engine preserves owner, step, index, and execution identity. Seven focused
inclusion methods pass. No production change was needed. Configuration
precedence and native acceptance still keep the inclusion contract partial.


Native action, step, and presentation codecs now retain unknown flat JSON fields.
Single/array edit, repeated import, export, backup, restore, disabled execution,
and typed-collision cases pass. Full regression passed app444/core466; the
unsigned build passed. Installed-app acceptance is pending while the Mac is
locked. The import contract returns to partial for that newly exposed coverage
gap; earlier native foreign-payload evidence stays recorded.


Installed QA acceptance now passes returned callback keys and single native
action import/edit/restart/export with unknown fields. Wrapped and mixed native
imports remain open. Actual Shortcut no-wait script and step checks pass launch
return and response suppression. Waited execution reached timeout; two direct
CLI controls also stalled, although the Shortcut editor completed the fixture.
The cause is not established. Waited output is not accepted. See validation.md
for the isolated library, build identity, and exact check scope.


Grouped and mixed action imports now preserve each native entry instead of
remapping it as a Drafts export. Four specific cases pass; three reproduced the
loss before the fix. Full regression passed app444/core467 and the unsigned
build passed. Installed container acceptance remains pending.


Queued error/cancel effects on another draft now have four specific legacy/async
cases. They preserve completed effects, suppress success effects, stop the queue,
and select the matching callback. Full regression passed app444/core468. Native
entry coverage remains pending; no production change was needed.


Installed wrapped mixed import now passes execution, restart, and UI backup
export. The complete native action and foreign identity/payload/script survive.
Container inspector edits and native restoration remain separate acceptance.


Unknown disabled imports now passes its added native/container acceptance:
inspector edits survive restart, native restore recovers exact definitions,
and the restored action executes. That engine record is complete. Other engine
records remain partial. Library Organization editing needs a separate UI review.


Library Organization now exposes separate row buttons and opens the action
inspector locally. Native Edit, Cancel, Save, reopen, group Edit/Cancel, and Done
passed in QA. Ten relevant existing tests and the unsigned build passed. This
resolves the observed management access path, not full inspector parity.


Native UI close cancellation now passes at Command-W and the window close
button: history recorded Cancelled, completed writes remained in Inbox, no
tail or Archive ran, and a subsequent action succeeded. URL/Intent owner-close
and multiwindow acceptance remain open.


Native URL owner-close now returns one matching cancel callback and retains
completed text without success effects. A new offscreen test covers real
owner-notification filtering and observer removal. Full regression passed
app445/core468. Intent and multiwindow native acceptance remain pending.


Native two-window URL ownership passed: closing the non-owner kept callback
count zero; closing the owner produced one matching cancel callback. Intent
and same-draft ownership variants remain pending. A remaining-window menu
context observation needs source review before a fix is claimed.


Native App Intent owner-close now reports cancellation in Shortcuts, retains
completed draft text without success effects, and permits a subsequent successful
Intent. Existing actual-perform and lifetime/error tests pass. Same-draft
multiwindow ownership and other capability variants remain open.


A native delayed callback after cancellation no longer has acceptance pending
for the completed-next-action sequence: the helper confirmed its delayed URL
open, while history and editor retained Cancelled/Success and the next result.
Other late-response and native capability variants remain open.


Expired/new native callback sequencing now passes with distinct response values:
the cancelled request keeps Cancelled and the next accepts only fresh data.
The existing router cancellation test now rejects the old token during a new
pending request. Full regression passed app445/core468. Other capabilities
and entry variants remain open.


Imported editing bar labels and icon choices now affect rendering and survive
export and backup. Focused tests, the app build, and native QA button execution
passed. The full app suite passed 446 tests. The full core run did not finish
and was stopped; its cause remains open. Native inspector edit/cancel acceptance
and other imported presentation options remain pending.


A full regression recheck completed successfully: app446/core471. Matrix
structure passes. The prior core stall did not reproduce; its cause remains
unknown. This result replaces the incomplete run as the latest full test
evidence, but does not close native inspector acceptance or API parity.


Native inspector acceptance now passes for editing bar Label and Show Icon:
cancel discards both changes, save retains both, and the fixture was restored.
Other imported options and full inspector parity remain pending.


Imported action tint strings now affect list and editing bar colors and have
an inspector selector. Unknown names survive export and backup. Focused tests
and core471 passed. The full app run had two automation start-marker failures;
the isolated five-test recheck passed. Full-run cause and native palette
acceptance remain pending.


Automation cancellation tests now wait for a saved ready signal instead of
racing startup and a completion timer. Full regression passed app447/core471.
No production execution behavior changed. Native action tint acceptance is
still pending.


Native tint acceptance passes for imported green/orange rendering in list and
bar, plus inspector save/cancel and restoration. Drafts has an empty action
list and disabled creation/directory controls. Exact palette comparison and
remaining color/appearance cases stay pending.


Corrected required native import evidence fields using the existing verified
recovery record. All25 auditor tests pass. The engine strict gate reports27
diagnostics; other engine contracts remain partial. No new native acceptance
is claimed by this record correction.


Native separate-target UI queue failure and cancellation now pass: retained
writes, Inbox state, last-target editor, and stopped later work. Five queue
acceptance methods pass. URL/Intent queue variants remain pending.


Native URL cross-draft queued failure and cancellation now select one matching
error/cancel callback and retain completed writes without later work. App Intent
queue interruption and other callback variants remain pending.


Actual App Intent queued failure/cancellation now propagate the child result
through Shortcuts, retain completed writes in Inbox, and stop later work.
The QA shortcut parameters were restored. Remaining asynchronous interruption,
window-lifetime, and current-image timeout combinations stay pending.


Native URL owner-close cancellation now passes while a queued child waits on
a different draft: one cancel callback, retained Inbox writes, no later work.
Queued Intent owner-close and remaining timeout combinations stay pending.


Native queued Intent owner-close now passes with the exact source opened by
UUID and visible ownership confirmed. An initial non-owner run was stopped
separately and is not counted as owner-close acceptance. Retained writes and
Cancelled history passed. Current-image queued timeout combinations remain.


Current-image queued URL production timeout passed: one matching error callback,
retained Inbox writes, last-child editor, and no later queue work. Observation
times bracket the result; exact deadline delivery was not measured. UI/Intent
queued timeout checks on the current image remain pending.


Current-image queued Intent production timeout now passes: Shortcuts waited
for final error, retained Inbox writes and last-child editor passed, and no
later queue work appeared. An earlier interrupted run is not counted. The
current-image UI queued timeout remains pending.


The UI timeout attempt ended in cancellation after the editor changed to Q;
it is not accepted as timeout. Added queued-target coverage to the existing
owned-editor typing cancellation test. Full regression passed app447/core471.
The native UI production timeout check remains pending.


Backup restore now rejects duplicate IDs in all eight record collections before
writing. The regression failed before the fix and passes afterward without
changing the destination. Full app447/core471 and unsigned build pass. Native
import error presentation and sync acceptance remain pending. QA was not updated.


Native duplicate-draft backup rejection now passes on isolated QA imageca22fd59:
the error is visible and before/after full backup exports are byte-identical.
All existing notes, revisions, actions, and history stayed unchanged. Other
duplicate record kinds retain automatic coverage; sync remains separate.


Malformed recognized action/draft export JSON no longer falls back to a raw
text note through txt imports. Unclassified JSON text and unknown action fields
remain compatible. Full app447/core472, unsigned build, and matrix structure
pass. Native error presentation for this change remains pending.


Native txt imports of malformed recognized draft/action JSON now show their
specific errors. Both before/after full backups are byte-identical; no valid
prefix record or raw JSON note was added. QA is image13f8e82c. Broader import
and synchronization acceptance remain separate.


Multiple selected import files now prepare in isolation and commit changed
records once. Second-file and storage failures leave the destination unchanged;
disk reopen/retry and all eight backup collections have tests. Full regression
app447/core475 and unsigned build pass. Native multi-selection and staging
performance remain pending; QA was not updated.


Native multi-file picker acceptance passes on QA image785e0548: a rejected lot
leaves the full backup byte-identical; a valid mixed lot adds only its expected
action/note/revision. Restart preserves all record data by ID. Export array
order can change, so restart bytes are not identical. Performance and cloud
acceptance remain pending.


An optional release benchmark now measures10,000-note local imports, queries,
and100,000-character saves without visible windows or fixed thresholds. On
M2 Max/64 GiB, five fresh SQLite samples gave import median1092.570 ms and
maximum1296.808 ms; query median17.014 ms; save median196.603 ms. Data checks
and full app447/core475 pass. Native UI responsiveness and the remaining scale
acceptance stay pending. Reproduction and conditions are in validation.md.


### Imported action option gaps — 20 October 2026

Reviewed ActionImporter.decode against the five unchanged original action
fixtures. Foreign import explicitly maps description, tint, bar label/icon,
confirmation, assigned tags, disposition, shortcut, icon, and separator state.
It retains the full foreign object as rawPayload. Retention does not apply
these other settings:

| Field | Values present in original fixtures | Current behavior |
| --- | --- | --- |
| visibility | 2,480,2016 | Retained in rawPayload; presentation visibility stays at Draftly defaults. |
| notificationType | 0,1,2 | Retained; notifyOnSuccess/notifyOnError stay false. |
| backingAssignFlag | 0 | Retained when present; flagAfterSuccess stays nil. |
| groupDisposition | 0 | Retained; no imported group-disposition effect. |
| logLevel | 1,2 | Retained; no imported log-level policy. |
| groupUUID | Four UUIDs | Retained when present; import uses a group name or Imported. |
| backingPlatforms | 3 | Retained when present; no imported action platform restriction. |

Do not infer enum/bitmask meaning from these samples. Check the archived
reference and observable Drafts behavior before mapping values. Native Draftly
options use their typed persisted fields; this gap concerns foreign import.
Unknown numeric values must survive any later mapping. This audit does not
change the original scripts or claim completion of these imported options.


Notification import follow-up —20 October2026: notificationType0/1/2 now maps
to none/error/all, using the supplemental official wizard reference recorded
in validation. Original-fixture and both-runner tests pass. Raw unknown values
remain intact. Native notification delivery is still pending. Other foreign
option gaps in the preceding table remain open.


Log-level follow-up —20 October2026: foreign logLevel0/1/2 now controls none,
error-only, or complete execution history. Optional persistence preserves old
libraries and unknown integers. Both runners and the inspector use this
setting. Automatic and build evidence is in validation; native checks remain
pending. Other imported-option gaps remain open.

Native log-policy follow-up: six neutral actions confirmed None, Errors, All
history behavior. Inspector showed imported Errors and Cancel discarded a
change to None. Save/restart, timeout, and notification delivery remain pending.


Engine queue acceptance —20 October2026: queue cancellation is now complete.
Native UI production timeout passed after the earlier URL/Intent timeout and
interruption checks. Exact retained data and one root error were confirmed by
native export. Strict engine parity still has24 diagnostics across eight other
partial contracts. Full validation and remaining limitations are in the matrix.


Promise acceptance —20 October2026: promise rejection and asynchronous timeout
is complete for its named contracts. Direct returned-rejection URL now has one
correct error callback and retained Inbox text. Strict engine parity remains
open with21 diagnostics across seven other partial contracts.


Final callback acceptance —20 October2026: final callback selection is complete
for the named cases. Native merge and delayed-response checks passed. Strict
engine parity remains open with18 diagnostics across six partial contracts.


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
