# QA installation cleanup

Date: 21 October 2026. Related identity commit: `a571078`.
This is separate from the bundle migration. No source code, tests, scripts,
reference documents or reproducible fixtures were removed.

## Removed installations and generated output

These six installations were checked by path and bundle ID, unregistered and
moved to recoverable Trash:

- Draftly Callback Helper.
- Draftly Engine QA.
- Draftly Restore QA.
- Draftly Scale QA.
- Draftly Theme QA.
- Draftly Visual QA.

Visual QA quit through its normal save path before cleanup. The main signed app
at `~/Applications/Draftly.app` is the only Draftly installation left in that
Applications folder. Original Drafts was not changed.

Twenty-two obsolete build directories were removed. Their measured allocated
size was 1,563,308,032 bytes. The directory names under `.build` were:

```text
actions-audit         actions-contract-qa  cloud-qa
core-audit            core-audit-qa        main-cloud-qa
main-cloud-receiver   main-cloud-vm        main-parity-qa
parity-qa             refactor-check       roadmap-qa
rows-qa               settings-html        verification
visual-close          visual-parity        visual-parity-qa
visual-qa             xcode                personal
icloud
```

The last three build directories were removed only after preserving their old
app packages. Three other generated app bundles were removed without deleting
the surrounding fixtures: Core Closure QA, Context Menu QA and the temporary
Identity Check. The empty Identity Check folder was also removed.

## Preserved data and recovery

Keep the legacy app archives under:

`~/Library/Application Support/Draftly/IdentityMigration-2026-10-21/LegacyPackages`

The local, personal and iCloud ZIP archives were extracted into temporary folders.
Every regular file hash matched its source package. The original executable
packages were then moved to Trash. Do not run both bundle identities on the same
library. An archive preserves a package; it does not prove an old binary can read
future library formats.

QA libraries, preference domains, fixture sources, syntax and audio files,
exports, VM transfer packages, profiles, certificates and CloudKit data remain.
Mixed fixture directories, distribution archives and VM folders were kept.
Current Swift test output and the new local/signed builds were kept. Cleanup did
not follow the `.build/debug` and `.build/release` symlinks.

The ignored `.build/qa-installations-preserved.json` stores retained app metadata
and QA library IDs. `.build/qa-preserved-config` keeps the extra cloud test plists.
The manual TextEdit registration fixture was saved under `/tmp` and moved to
recoverable Trash after the check. No fixture was added to the draft library.

## Validation

The installed app still passed deep signature, bundle, team, profile and container
checks after cleanup. macOS resolves `draftly://` to this installation. The user
confirmed opening the neutral historical draft through that scheme.

Legacy executable packages published a second pair of Services. Their bytes were
archived before removal. The Services cache was refreshed after retiring their
registrations. TextEdit then showed exactly one Capture to Draftly and one
Capture to Draftly with Options, alongside the unchanged Drafts services.
No global LaunchServices reset was used. Historical stale database entries or
recoverable Trash entries are not active installations.

Only the installed main Draftly process remained after the manual session. No QA,
build, test, fixture server or TextEdit process remained. The headless suites and
builds were validated in the identity commit. Artifact removal did not remove or
change their contracts. The full Mac cloning plan remains open.
