# Project progress

Updated: 31 October 2026. This is the maintained continuation summary.
Historical test reports describe only the versions they tested.

## Current priority

Local agent access is in stage 1. The user accepted the full
[agent plan](plans/draftly-for-agents.md); remote implementation stays deferred.
The first code unit adds the package-internal AgentContracts target: request and
result envelopes, stable errors, typed resource references, a planned operation
catalog and baseline grant evaluation. It adds no app route, CLI, socket, MCP
server, Keychain entry, native permission or network listener.

The catalog declares 128 planned operations and enables none. Baseline decisions
retain the resource scope; Actions and native requests require further effect
authorization. Irreversible operations require human approval. The new tests
cover isolation, expiry/revocation, target kinds, revision-token requirements,
full-library backup authority, malformed/oversized messages, Unicode/decimal
transport, and distinct pending/error/result states.

Automatic validation passed 55 AgentContracts, 759 Core and 938 app tests with
complete result inventories, 285 Python tests, the structural matrix check,
and the final local app build.
See the [operation inventory](research/agent-operation-inventory.md) for reused
characterization evidence and remaining schemas and runtime enforcement work.
Thirty operations now have parameter/result schemas: eight discovery/draft reads,
18 Action/group operations and four operation lifecycle routes.
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

Stage 1 is not closed: the other 98 operation schemas, detailed script/native
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
