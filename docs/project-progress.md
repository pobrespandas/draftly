# Draftly Mac: implemented work and remaining work

Snapshot: 29 October 2026. This is the current index for continuing the Mac
implementation. The dated records contain the exact tests and observations. Do
not treat older statements about next steps, counts, or visual tolerance as the
current state. Update this index when a delivery changes the status.

Draftly has no paid tier. Do not gate features or label them as Pro. The
read-only `app.isPro` value exists for imported script compatibility and returns
true. A limitation in the installed Drafts reference is not a Draftly feature
restriction. Preserve original scripts and imported fields.

## Current checkout and installation

- Worktree branch: `agent/editor-current-line-2026-10-29`, at `701621d` when
  this snapshot was written. Its validated commits are pushed to that branch.
- The last locally known `origin/main` was `7c333b6`. It and this branch have
  diverged: seven commits were only on `origin/main`, and 89 were only on this
  branch. These are local remote-tracking references, not a fresh fetch. Review
  and integrate both histories without discarding independent website work.
- The installed `~/Applications/Draftly.app` reports bundle identifier
  `com.pobrespandas.draftly` and version `0.1.0`. The recent branch changes have
  not been installed in the habitual app. Source, QA and installation are
  different states.
- Keep team `NM92LU2KKV`, URL scheme `draftly://`, and the existing private
  container `iCloud.com.andrestobelem.draftly`. Keep `Note`, stable identities,
  old libraries, backups, Nerd Fonts and the integrated Markdown preview.

## Evidence and open gates

The [API matrix](research/action-api-matrix.json) has 572 inventoried members:
161 complete, 187 partial, 219 unclassified, three unavailable, and two
excluded at this snapshot. These counts are not a compatibility percentage.
Review each contract and its evidence. Do not treat an unclassified member as
absent. Keep the 25 first-party step types in scope. The structural matrix check
passed. The strict engine parity check still reports six partial contracts and
18 diagnostics. See [engine acceptance](research/engine-native-checklist.md).

At `721f716`, the full Swift runner matched discovery: 725 Core and 901 app
tests passed. All 80 Python script tests passed, as did the structural matrix
check. Later changes have focused tests and local Debug builds recorded in
[validation](validation.md); the complete suite has not been repeated for every
later commit. Previous intermittent concurrent Core timeouts remain unresolved.
A passing run does not establish their cause. Local builds and automated tests
do not prove native behavior, signing, iCloud convergence, or Drafts parity.

The reference is the archived documentation from 19 October 2026 and Drafts
54.1.1. Keep reference changes separate. Use the agreed **three-point** tolerance
for static visual alignment. Exclude dynamic shadows and text smoothing. Do not
commit screenshots or raw logs. The accepted earlier microphone cancellation and
recognition checks remain valid for the versions they tested; do not repeat them
without a distinct unresolved case.

## Actions and scripting engine

Implemented work includes the asynchronous entry and final report, serial
JavaScript worker, library exclusion, cancellation, timeout, step-scoped
callbacks and timers, included actions, queues, preservation of unknown or
disabled steps, and explicit errors for enabled unsupported steps. Legacy
adapters remain. Original action scripts remain unchanged. Focused and native
checks cover many cancellation, timeout, callback and recovery paths.

Remaining work:

- Close the six strict engine contracts: shared included scripts, separator
  imports, worker isolation and responsiveness, host request lifetime, task
  cancellation, and common asynchronous entry points. Separate implementation,
  automatic tests, native checks and reference blockers.
- Finish inclusion precedence, shared context and cycle cases that still need
  Drafts comparison. Finish real callback, owner-close, multi-window, URL and
  App Intent variants listed in the engine checklist.
- Investigate the intermittent concurrent Core waits without hiding failures
  through retries or longer deadlines.
- Audit every included API member and step: signatures, defaults, return values,
  errors, side effects and member-specific evidence. Preserve manual evidence
  during regeneration. Pass the strict core and global gates only when justified.

## Draft, Editor, syntax and prompts

Drafts support content, metadata, tags, flags, queries, versions, templates and
shared references. The editor supports UTF-16 selection and edits, Undo/Redo,
navigation and advanced find. Shared syntax rules support tasks, markers and
links; custom syntax definitions retain unknown fields. List typing, paste and
deletion have targeted atomic edit and Undo checks. Some comparisons and native
checks were completed in isolated QA.

Remaining work:

- Complete per-member defaults, errors and native acceptance for Draft and
  Editor, including query relations, recent items, versions, logs and links.
- Complete syntax grammar variants, multi-state tasks, markers, links, custom
  installation and file/URL lifecycle. Check IME, paste and deletion variants,
  selection, Undo/Redo, performance and visible resource-limit errors.
- Complete advanced find options, navigation, replacement and cancellation, and
  its interaction with native find. Complete Prompt and SelectPrompt options,
  focus, icons, cancellation and presentation; finish Create Draft and Configure
  Window variants.
- Keep the archived `QueryDate.create()` contradiction and Draft.insert bounds
  comparison pending until they can be observed in Drafts. Do not invent parity.

See [editor and scripting](editor-scripting-2026-10-22.md) and the
[core audit](research/core-actions-audit.md).

## Integrations and automation

Implemented paths include URL and App Intent execution, HTTP, XML-RPC, local
files, bookmarks, Mustache, HTML conversion and preview, Shortcuts, AppleScript,
shell, Calendar, Reminders, voice and location. Coverage differs by operation.
Recent fixes cover FileManager creation, copy/move overwrite and recovery,
root containment, JSON/text/tag input, reusable listing paths, and Unicode
Mustache names. These changes have local and focused test evidence; real iCloud
Drive is separate. The app has explicit unavailable responses where a native
operation cannot establish success.

Remaining work:

- Complete HTTP and XML-RPC response types, dates, binary values, invalid
  responses, network errors, cancellation and timeout. Finish HTML conversion
  grammar, options and interactive preview. Markdown renderers may renumber
  reversed ordered-list source markers; rendered parity is not accepted.
- Check files and bookmarks with real sandbox grants, stale or denied access,
  restart, iCloud Drive, concurrent path changes and Drafts behavior. Complete
  Mustache folder behavior against real cloud storage.
- Complete confirmed Mail and Messages delivery and their failure/cancellation
  paths. Do not send a message without explicit authorization for recipient and
  content. Complete EventKit, Shortcuts, AppleScript, shell, speech, location and
  Apple model contracts and applicable native checks. Record denial,
  cancellation and system unavailability separately from implementation defects.
- Finish URL and system-delivered App Intent variants and real callbacks for
  each relevant capability. Hardware and permission gaps remain explicit.

## Inspector and action organization

The inspector has step controls, configuration, searchable symbols, editing
copies, Save/Cancel, shortcut handling, groups and sections. Imported unknown
fields and disabled steps are retained. Action and group imports, replacement
review, group symbol display and group editing received focused corrections.
An isolated QA session checked a live Directory group, order, separators,
Cancel and Replace. No imported actions were run in that check.

Remaining work:

- Complete the 25-step control and option review, platform behavior, validation,
  execution effects and reference comparison. Do not infer unsupported contracts.
- Verify create, edit, duplicate, move, order and delete; confirm Save, Cancel,
  atomic failure, export, backup and restoration. Keep imported shortcut
  conflicts and unknown payloads.
- Finish visibility and order across list, editing bar, search and menus, plus
  confirmations, notifications and post-result tags and flags. Complete visual
  comparison with equivalent actions where the reference permits it.
- Verify a genuine group export from the Drafts app and external link opening.
  The Directory group check is not evidence for that export format.

See [the inspector inventory](action-inspector-2026-10-22.md).

## Workspaces, Settings and personalization

Workspace management, filters, sort and presentation options, shared themes,
local preferences and backup fields exist. Settings includes General, Editor,
Shortcuts, Bookmarks, Markdown and HTML. Per-syntax fonts, layout, input options,
autocorrection and Writing Tools controls have focused tests and selected QA
checks. Nerd Fonts and unknown configuration fields are retained.

Remaining work:

- Finish Workspace operations and each filter, date, flag, per-folder sort,
group, theme, initial-folder and reference contract. Check visible rows against
queries after restart and backup restore; reject invalid references without a
partial application.
- Complete native and visual acceptance of all Settings categories and editor
options. Check launch at login, physical global shortcuts, startup/restoration,
actual system autocorrection and Writing Tools, and Touch Bar when hardware is
available. Keep accepted specific checks; do not mark the whole category done.
- Finish theme import/render coverage, file access and reload, legacy migration,
backup restoration, shortcuts and Markdown/HTML options. Preserve content,
selection and Undo/Redo while settings change.

See [Settings and personalization](settings-personalization-2026-10-22.md).

## Main window and daily flows

The window has split panels, toolbar, tabs, note rows, filters, action panels,
menus, swipe actions and Merge with Archive selected by default. Capture,
Quick Search and Services have separate paths and recorded native checks.

Remaining work:

- Complete paired visual comparison at 1033 × 734 and 1200 × 800 points, with
  a narrow-window review at 850 × 600. Cover light/dark, active/inactive,
  panels, search, tabs and selection. Verify capture dimensions and scale.
- Finish observed differences in typography, symbols, materials, toolbar,
  tabs, panels, menus, list rows and settings. Apply the current three-point
  static tolerance; do not count malformed captures as acceptance.
- Complete transition, resize, Reduce Motion, focus, selection, Undo, overflow,
  swipe and VM redraw checks. Finish Services, capture and searches across
  no-window, multiple-window, restart and save-failure scenarios. The physical
  global key and Spotlight checks require their own real observations.

See [window and daily flows](ui-flows-2026-10-21.md) and
[visual review](research/visual-parity-2026-10-19.json).

## Data, iCloud and distribution

The repository includes a macOS CI workflow for pull requests and pushes to
main. It runs the Python checks, the Actions matrix structural check, the Swift
test inventory, and an unsigned local app build. CI does not publish a release.
The workflow has not yet been verified on a GitHub-hosted runner.

Sparkle 2 is linked in the app. Update checks are disabled unless the main app
has an explicit build setting, a valid public key, and the configured HTTPS
feed. Do not enable them yet. Update safety during active Actions, Developer
ID signing, notarization, release publishing, and real update acceptance are
still pending. The manual release rehearsal has read-only permissions and does
not publish.

The library uses the existing generic Core Data schema. Backups include shared
themes and action execution history with compatibility checks. Development
signing and isolated cloud QA exist. Earlier Mac-plus-VM checks confirmed
selected download, creation and edit paths, including a follow-up for access-date
conflicts. They do not establish the full main-container matrix.

Remaining work:

- Validate all new fields, old-library migrations, unknown fields, identities,
  conflicts, backup and restore on copies. Repeat main-container synchronization
  with both clients connected for content, metadata, revisions, actions, groups,
  Workspaces, syntax, themes, Trash/Restore and access dates. Check concurrent
  variants and avoid data loss.
- Review and integrate both current Git histories. Run complete tests and local
  and signed builds on the integrated result. Verify the effective profile,
  team, bundle identifier, entitlements and existing container.
- Before replacing the habitual app, verify library and preferences, keep the
  prior package, install the signed candidate, and check restart, Services,
  URLs and data. A signed build is not a sync test.
- Design and implement an update mechanism before distributing Draftly. The
  current personal ZIP is a package, not an automatic update system. Decide how
  the app checks for updates, presents them, and installs them. Define version
  and build ordering, trusted release metadata, signature verification, failure
  recovery, and behavior when no network is available. Do not change the app
  identity, team, URL scheme, or existing CloudKit container as a shortcut.
  Test updates between different signed executables on copies of existing
  libraries and preferences, including interrupted installation and recovery.
  Verify backups, unknown fields, notes, actions, and editor state as applicable.
  Validate development-signed updates on registered Macs. Keep Developer ID,
  notarization, and public distribution as a separate later decision.
- Measure 10,000-draft list/search/selection and 100,000-character editing,
  search, Undo and save. Record conditions and typical/max times. Fix stalls
  and data loss without inventing an acceptance threshold.
- Run integrated acceptance and record implemented, automatic, real-use,
  user-confirmed and blocked results separately.

Offline validation remains postponed. Mac plus VM is the available reference;
two physical Macs add coverage. Developer ID, notarization, public distribution,
mobile platforms, and previously excluded services remain outside this scope.
See [iCloud and distribution](icloud-distribution.md) and
[Mac plus VM](utm-icloud-validation.md).
