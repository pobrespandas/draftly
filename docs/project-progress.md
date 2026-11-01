# Project progress

Updated: 1 November 2026. This is the maintained continuation summary.
Historical test reports describe only the versions they tested.

## Partial list option decoding — 1 November

DraftListOptions now uses its existing defaults for absent fields while retaining
other saved options. Present values with invalid types, including null, still
fail decoding. Complete records keep the same keys and round-trip behavior.
This allows a per-field reset without discarding unrelated options. The new
regressions failed before the correction; 18 focused Core/app cases then passed.

## Encoded preference access — 1 November

The application can now prepare typed reads and edits for 44 encoded preference
field entries: syntax options, Markdown options and command shortcuts. Existing
setters and conflict rules remain authoritative. Reset removes one known override
and retains additional imported fields. Syntax references must match the resolved
definition. Feature names must be declared by that definition.

This is a preparation component. It performs no persistence, native registration
or authorization. Actual handlers still need grants, scoped syntax resolution,
name-collision checks, version comparison, approval and commit receipts. Device
values, native settings, list defaults and default Workspace access remain open.
No app endpoint or installed-app change is enabled by this component.

## Preference defaults preparation — 1 November

Settings and editor consumers now share the existing editor, capture, General,
HTML and Markdown defaults. This removes duplicate values before the application
preference catalog is connected. Legacy Boolean conversion and invalid HTML
marker fallback stay unchanged. Reading a default does not persist it.

Automatic checks passed 49 focused tests across seven suites and the local
Xcode app build. The three new characterization tests also passed before the
extraction. The generated Xcode target uses the package name `draftly` to read
package-only constants from Core. No public API or persisted format changed.
No native acceptance is claimed; this unit changes no controls or permissions.
The actual field catalog, preference handlers and local agent endpoint remain
pending. The installed application is unchanged.

## Current priority

Local agent access is in stage 1. The user accepted the full
[agent plan](plans/draftly-for-agents.md); remote implementation stays deferred.
The first code unit adds the package-internal AgentContracts target: request and
result envelopes, stable errors, typed resource references, a planned operation
catalog and baseline grant evaluation. It adds no app route, CLI, socket, MCP
server, Keychain entry, native permission or network listener.

The catalog declares 136 planned operations and enables none. Baseline decisions
retain the resource scope; Actions and native requests require further effect
authorization. Irreversible operations require human approval. The new tests
cover isolation, expiry/revocation, target kinds, revision-token requirements,
full-library backup authority, malformed/oversized messages, Unicode/decimal
transport, and distinct pending/error/result states.

Automatic validation passed one package-consumer test, 127 AgentContracts,
759 Core and 952 app tests with
complete result inventories, 286 Python tests, the structural matrix check,
and the final local app build.
See the [operation inventory](research/agent-operation-inventory.md) for reused
characterization evidence and remaining schemas and runtime enforcement work.
Contract definitions now cover 97 operation names: 93 static schemas and four
registry-bound preference forms. The application metadata catalog now declares 86 reviewed fields. Typed
preference readers, writers and the scoped endpoint are not connected.
They use one definition for validation, exported JSON Schema and request-local
defaults. Chunk checks use UTF-16; result shapes separate summaries from content.
The step effect catalog covers all 25 executor step types and always requires
runtime review for enabled steps. It does not authorize script execution.
Preference writes and imports also require contextual effect review. Action
updates bind payload IDs to targets; reorder requests must cover the target set
exactly once. Unknown Action/step/presentation data stays intact. Writes return
receipts rather than scripts. Lifecycle results distinguish wait expiry,
cancellation, timeout and ambiguous effects. actionGroups.get closes a missing
explicit read path; it has no executor yet. A separate UTC validation regression
rejects impossible calendar dates and trailing text while retaining valid leap
days and fractional precision. PR #31 passed all required CI checks and merged
at `0ba56b2`. A separate lifecycle correction now binds a busy termination reason
to the busy error code. Its focused regression failed before the correction and
passed afterward. The complete Swift suites, Python tests, structural matrix
check and local build passed after this correction.

Workspace permission review found two catalog gaps. Workspace queries now
require draftsRead as well as workspacesRead. Applying a Workspace requires
contextual effect authorization before theme or file references can load.
The focused permission regression failed before the correction and passed after
it. These checks remain unexposed baseline policy, not runtime enforcement.

Workspace schemas preserve the canonical model and its string metadata without
filling creation defaults. Queries share the draft page schema and do not replace
saved filters. Shared resource rules bind update IDs and complete reorder lists.
Apply results bind both the Workspace and window. Canonical fields that the model
cannot retain fail explicitly; unknown metadata strings stay unchanged. No actual
query, mutation, theme resolution or window application is enabled yet.

Agent batches now share one limit of 10,000 resource targets across transport,
policy, order lists and mutation receipts. A focused regression failed before
the correction because requests could exceed the receipt capacity. The limit
prevents accepting a batch whose complete result cannot be represented.

Draft mutation contracts cover creation, explicit changes, original-snapshot
UTF-16 patches, duplication, ordered merge, organization, flags, tags, syntax,
revision restoration and purge. Patches reject ambiguous or overflowing ranges.
Merge defaults to archive. Batch receipts cover all targets; duplicate and merge
results need a new identity. These contracts do not mutate notes or implement
version checks, transactions, editor coordination or Undo yet. PR #32 passed
required CI and merged at `0a2b7ab`.

The schema gateway now rejects missing or empty expectedVersion headers for
mutations independently of grant evaluation. Its regression failed before the
correction. Live version comparison remains an unimplemented handler boundary.

Editor contracts add a separate task-mark read operation, explicit window/new
window selection, no focus by default, bounded snapshots and versioned edits.
Window and draft IDs bind replies; selection and preview replies must reflect
the request. Open, navigation and preview still require contextual effect review.
Shared text validation preserves the existing draft range rules. No editor
command, actual Undo, window opening or live query runs through agents yet.
PR #33 merged at `620781c`; PR #34 merged at `d4d7c63` after required CI passed.

Import-source contracts now share exclusive input alternatives with exported
JSON Schema. They distinguish inline text, staged transfers, bookmarked relative
paths, installation links and HTTPS sources. Path and URL checks do not grant
file or network access. A focused regression detected missing required fields in
the exported alternatives before this was corrected.

Appearance contracts preserve canonical theme fields, imported data and exact
syntax source strings. Built-ins use names; installed definitions use UUIDs.
Added explicit selection state, named built-in routes, file Reload and targeted
theme replacement. Selection versions remain separate from definition versions.
Installation does not select a theme unless requested with a selection token.
File-backed reads and writes still require contextual effect review. All actual
parsers, imports, persistence, rendering and local preference changes remain
handler and native acceptance work. PR #35 passed CI and merged at `2b8478b`.

Preference contracts now require an explicit application-supplied field registry.
Requests cannot register fields or read raw storage names. Typed contexts separate
device, syntax, feature and command settings. Defaults, inheritance, read-only
state and approval requirements stay distinct. The production allowlist is not
yet built; use the new preference source inventory before connecting consumers.
A separate consumer module now checks construction without @testable access.
It reproduced inaccessible synthesized initializers before explicit package
constructors were added. The fixture registry is not evidence of application
field coverage. A separate
regression rejects null replies for resolved nonnullable inherited/system values;
declared system inheritance and invalid-store states remain distinct.

Bookmark contracts expose metadata only, preserve requested Unicode names,
reject arbitrary paths and self-approval fields, and bind Forget results to their
target. Stable local bookmark IDs, protected picker approval and scope filtering
remain application work. Creating a bookmark does not grant agent file access.
PR #36 passed required CI and merged at `229db77`.

Stage 1 is not closed: the production preference catalog, the other 39 operation
schemas, detailed script/native
effect checks and real executors still need implementation. Real agent clients have
not been connected. The habitual app remains the released 0.1.3.

## Released first-click correction

Repository cleanup and the human-readable documentation pass are integrated.
The current fix addresses a draft-list click that only changed focus when the
editor was focused. Native table click handling now owns that focus transition.
The installed 0.1.2 release and an isolated QA build of the old code reproduced
the issue. The corrected QA build selected the target draft on the first click
in both directions, with the same library and preferences.

The headless table test covers selection-to-editor routing, multiple selection,
and suppression of programmatic selection callbacks. It does not simulate a
physical click. Native click acceptance was checked separately with Computer Use.
The corrected QA build also retained a fresh edit while switching notes and
handled Command-click multiple selection. Complete local checks passed 759
Core, 938 app, and 285 Python tests; the local app build and structural matrix
passed. QA used a temporary library and was closed and unregistered afterward.
Version [0.1.3/build 4](https://github.com/pobrespandas/draftly/releases/tag/v0.1.3)
is public and installed on this Mac. PR #26 integrated the fix at `b307c77`.
Required PR CI `41250495492` passed. Tag `v0.1.3` started the automatic release
run `41250992295`; all release checks, signing, notarization, asset publication,
and site promotion passed. No local publication shortcut was used.

Sparkle offered 0.1.3 to installed 0.1.2 and completed Install and Relaunch.
The installed package passed strict signature and Gatekeeper checks. With the
editor focused, one click opened each of three neutral drafts. The 24 library
records retained their identities and payloads; only three access dates changed.
Both preference domains were retained. Expected changes were window frames,
recent draft IDs, and Sparkle's last-check time. A coherent database backup,
preference exports, and the old app remain in the private local build directory.
Both site download buttons now point to the 0.1.3 DMG. A new public download
matched its checksum. This update does not establish new CloudKit acceptance.

Draftly has one edition. Drafts Pro restrictions are reference blockers, not
Draftly feature restrictions. Continue other product work from the subsystem
records below, keeping current guidance separate from dated evidence.

## Source, publication, and installation

- The user requested 0.1.2 specifically to test a public update and reinstall.
  This is a one-time manual release exception: no app feature changed since
  0.1.1. Normal automated publication still rejects version-only changes.
  Version [0.1.2/build 3](https://github.com/pobrespandas/draftly/releases/tag/v0.1.2)
  is now public. Its signed and notarized DMG and all seven public assets
  passed verification. Firebase promotion `da4410a0a1d306b0` preserved all 28
  site files and the previous update items.
- On this Mac, Sparkle offered 0.1.2 to installed 0.1.1, downloaded it, and
  completed Install and Relaunch. Version 0.1.2/build 3 then passed signature,
  Gatekeeper, neutral-note retention, editing, Undo, and Redo checks.
- The app bundle was removed to Trash and reinstalled from a new public DMG
  download. The app reopened as 0.1.2 and retained the neutral note. Existing
  preference values were retained; only Sparkle's last-check time differed.
  Data was retained deliberately. This is not an empty-library installation
  test or a new CloudKit synchronization acceptance.
- At the 0.1.2 checkpoint, the public site selected that version for both
  download buttons and release notes.
  Old public tags and assets remain unchanged.
- Website follow-up PR #17 passed website CI and was integrated at `c22e4df`.
  Firebase version `cfa7ec5f7a704616` adds the top GitHub link and corrects the
  initial DMG fallback to 0.1.1. All 28 files and the signed feed were preserved.
  Both public buttons and notes were checked in the browser. After 0.1.2,
  the release site source variable was updated to its verified `3922ee3`
  checkpoint, matching the live site's source label.

- The clean-install correction is integrated in main through PR #13, merge
  `1ea567e`. Required PR CI run `41226934559` passed.
- Public release: [0.1.1](https://github.com/pobrespandas/draftly/releases/tag/v0.1.1).
  The signed and notarized DMG passed a clean macOS 26 VM installation without
  a repair helper or manually written marker. Both preference domains were
  empty and the local library was absent before launch.
- GitHub public assets and the promoted signed appcast passed verification.
  Both website download buttons were observed pointing to the 0.1.1 DMG.
  Existing site files and the 0.1.0 appcast item were preserved.
- The user authorized correcting the early, still unpublished 0.1.1 tag to
  integrated `1ea567e`. Only that tag was excepted temporarily; the original
  protection and active tag workflow were restored before publication.
- A later read-only inspection found 0.1.1 in the habitual installation. This
  does not establish a full migration or update acceptance check. Source,
  package validation, publication, and installation are separate states.

## Repository and CI cleanup

The cleanup branch separates check selection from native execution. Its final
required check preserves the existing protected-check name. Release preflight
rejects unchanged package inputs before it allocates native or signing jobs.
See [CI and publication](ci-cd.md) for selection rules and validation.
These changes are integrated through PR #14 (`e8c832c`). Its full hosted CI
run `41230093909` passed, including native tests and local app compilation.

Publication and cleanup integration are complete. Preserve the published tag
and assets. Website-only CI run `41230802922` passed website tests and the required
Ubuntu result; native, script, and matrix jobs were skipped. The saved earlier classifier commit
`74cd477` remains preserved on its original branch; the cleanup replaces its
partial design rather than discarding that branch.

## Evidence and open acceptance

- PR #19 shares the disposable Git fixture between the CI and release selector
  tests. All 16 focused cases and names remain. Full hosted CI `41235528547`
  passed before integration at `894b81c`. No redundant test removal was justified.
- Automated publication is configured but not yet accepted end to end.
  Signing, staging, and publication flags are enabled after the DMG transfer
  correction passed CI. Publisher identity and lock handling passed the
  Ubuntu-only run `41236743915`. No app was built or published by that check.
  The 0.1.2 release used local publication tools. Its tagged commit includes
  a skip instruction, so it did not exercise the tag-triggered workflow.
- PR #21 fixes missing DMG files in the candidate artifact. Its regression
  failed before the fix and passed afterward. All 285 Python tests, actionlint,
  and matrix structure passed locally; hosted CI `41236763902` passed the
  script path without a native app build. The fix is integrated at `8f1c565`.
  A real hosted signing-to-publication run remains pending for the next app
  release with package changes. See the release guide.

- The release fix passed complete local Swift reports: 759 Core and 937 app
  tests. Its Python suite passed 268 tests and website tests passed three.
  Hosted manual and PR CI runs also passed. These totals are not API coverage.
- The Actions matrix structural check passes. The strict engine check still
  reports 18 diagnostics across six partial contracts. Cleanup must preserve
  those classifications and their evidence.
- The API inventory contains 572 members: 161 complete, 187 partial, 219
  unclassified, three unavailable, and two excluded. These are inventory
  categories, not a compatibility percentage. The matrix is authoritative.
- Keep the accepted microphone evidence. Do not repeat it without a distinct
  unresolved case. Hardware, permissions, native behavior, and reference
  comparison remain separate evidence types.

Use [engine acceptance](research/engine-native-checklist.md),
[API compatibility](compatibility.md), [Settings acceptance](settings-personalization-2026-10-22.md),
and [UI acceptance](ui-flows-2026-10-21.md) for their remaining cases.
The [previous consolidated snapshot](archive/project-progress-before-cleanup-2026-10-31.md)
and [historical checkpoints](archive/status-before-cleanup-2026-10-31.md)
retain older implementation and acceptance records.

## Next work

1. The user accepts the generic iCloud storage icon for now. See
   [iCloud identity](icloud-identity.md) for the private-record investigation
   and authorized cloud-data deletion. Draftly disappeared from Manage Storage;
   cloudqa deletion remains unverified. Keep the existing container identifier.
2. Continue Actions and editor contracts, inspector and integrations, Settings,
   and remaining data/synchronization acceptance from their subsystem records.

Keep `com.pobrespandas.draftly`, team `NM92LU2KKV`, `draftly://`, and container
`iCloud.com.andrestobelem.draftly`. Keep Note, identities, original scripts,
unknown imported fields, old libraries, backups, Nerd Fonts, and preview.
Offline tests remain deferred. Mac plus VM is the current two-client setup.

The ignored `docs/claude-handoff.md` contains local paths and active operation
journals. Use it when present; do not commit credentials, raw logs, screenshots,
package outputs, or personal data. The tracked summary must remain sufficient
for a new checkout to find the next step.


## Preserved work in other checkouts

The main checkout at `~/ws/pp/draftly` contains previous uncommitted website
changes and local skill deletions. It remains unchanged by this cleanup; its
branch was not reset or updated over that work. The cleanup checkout is clean.
Preserve and review those independent changes before updating that checkout.


## Preserved open PRs

PR #9 retains the separate first-staging recovery proposal. Its workflow
conditions need review against the new preflight before integration. PR #11
is now closed. Its source-link purpose is retained by the website follow-up.
Old cancelled checks do not establish acceptance. Preserve both branches.
