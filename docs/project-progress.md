# Project progress

Updated: 31 October 2026. This is the maintained continuation summary.
Historical test reports describe only the versions they tested.

## Current priority

Repository cleanup is validated. Continue product work from the subsystem
records below, keeping current guidance separate from dated evidence.
Do not add app functionality during that cleanup. Draftly has one edition.
Drafts Pro restrictions are reference blockers, not Draftly feature restrictions.

## Source, publication, and installation

- The user requested 0.1.2 specifically to test a public update and reinstall.
  This is a one-time manual release exception: no app feature changed since
  0.1.1. Normal automated publication still rejects version-only changes.
  Version 0.1.2/build 3 is in preparation, not published or accepted yet.
- Website follow-up PR #17 passed website CI and was integrated at `c22e4df`.
  Firebase version `cfa7ec5f7a704616` adds the top GitHub link and corrects the
  initial DMG fallback to 0.1.1. All 28 files and the signed feed were preserved.
  Both public buttons and notes were checked in the browser. The release site
  source variable now identifies that verified source checkpoint.

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
