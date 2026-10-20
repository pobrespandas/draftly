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
General includes appearance, menu bar visibility, capture timeout, and preferred
find. The app menu has Editor Settings, Library Summary, and library-wide Empty
Trash with confirmation, including when no command window exists.

Pending:

- Complete General launch behavior and shortcut recording; finish the remaining
  included Settings categories and native appearance/geometry comparisons.
- Complete individual Markdown options, escaped line breaks, live changes, and
  visual/click checks for reference-help controls.
- Finish workspace management and expose all date/flag/sort/group/theme options.
- Store shared themes with stable identities; migrate local themes once.
- Complete Drafts theme import and verify MultiMarkdown/TaskPaper in all accesses.
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

Computer Use can read Drafts. Observing the QA Settings window still returns a
native-pipe error. The QA process was last confirmed live; an observation failure
is not proof of termination.

## 10 Data sync and personal distribution

Implemented: Core Data storage, compatible backup import, revisions, conflict
copies, action groups/syntax backup, local builds, and development-signed builds.
The main CloudKit container passed initial download, creation, and edit exchange
between the Mac and UTM VM. The access-date/content conflict fix was retested.
See [iCloud evidence](research/icloud-acceptance-2026-10-19.json).

Pending:

- Add shared themes and execution history to compatible backups.
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
