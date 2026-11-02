# CI and publication

## Check selection

CI selects checks on Ubuntu before it allocates a Mac runner. The selector is
`scripts/ci-change-scope.py`. Its tests cover deleted and renamed files,
unknown inputs, missing revisions, mixed changes, and final job results.

| Changed input | Checks |
| --- | --- |
| Documentation and repository guidance | Selection and final result |
| Website code | Website tests on Ubuntu |
| Scripts and release workflows | Script tests on macOS |
| Actions contract data | Matrix structure on Ubuntu |
| App, resources, dependencies, native tests, or build drivers | Native tests, local build, script tests, matrix structure |
| Unknown input | All checks |

Script tests stay on macOS because some test macOS command adapters. They do
not compile the app. The script job resolves the pinned Sparkle tools before
running tests that check real appcast signatures. Native compilation and Swift tests have their own job.
Explicit diagnostics select their native check and use a separate summary
name. They do not report the full required-check name. A manual full run selects all
checks. A missing revision selects all checks; an unreadable revision fails.

The required check retains the name `Build and test on macOS` for compatibility
with branch protection. It now reports the combined result on Ubuntu. Each
selected job must succeed. Each unselected job must be skipped. A failed,
cancelled, missing, or unexpectedly skipped job fails the required check.
This follows GitHub's documented [job dependency rules](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-jobs).

## Validation

Native CI and the release rehearsal allow 120 minutes per job. This budget
includes dependency resolution, compilation and tests. Incomplete test reports
still fail verification even when the process exits before this limit.

Run the script suite, website tests, matrix structural check, and `actionlint`
when changing workflow selection. The actionlint configuration declares the
existing `xcode-27` runner label. Run native tests and a local build when the
selector or native workflow changes. Keep generated reports outside Git.

A successful local run is not a protected PR check. GitHub must recognize the
required check on the PR before integration. Source, signed candidate, public
release, website promotion, and installed app are separate states.

## Release selection

A version tag requests the trusted main workflow. Pull requests and normal
main pushes do not publish. An Ubuntu preflight checks the tag, version,
published history, and changes before it allocates macOS or signing runners.

`scripts/release-changes.py` compares package inputs with the latest stable
published tag. Documentation, tests, website code, and workflow changes do not
create a new app release. Changing only the version and build in Info.plist
also does not qualify. App code, resources, bundle settings, dependencies, and
packaging drivers qualify. Unknown top-level inputs qualify conservatively.
Malformed metadata, missing tags, or unrelated history stop the preflight.
An explicit recovery run can resume the existing candidate; its identity and
assets still pass the later recovery checks.

Signing, notarization, release uploads, and Firebase promotion retain their
existing protected environment and publication flags. The preflight adds no
credentials or bypasses. See [release operations](releasing.md) for
candidate validation, writer locks, journals, and recovery.

The website reads the published appcast. Both download buttons derive the
versioned DMG URL from that feed. Promotion preserves the live site files and
old release items. Verify the public feed, GitHub assets, and both buttons
after each release. A source change alone does not update the live site.

## Candidate transfer

The signing job must transfer the DMG with its checksum, manifest, and notary
receipt. The staging job verifies those original bytes; it does not rebuild
the installer. Failure recovery must also retain an image already submitted
to Apple. The workflow policy test expands the actual upload patterns against
a disposable candidate and checks that these files survive the transfer.

This check covers file selection. A successful hosted signing and publication
run is still required to accept the complete pipeline. The local 0.1.2 release
does not provide that hosted acceptance.

## Configured publication state, 31 October 2026

The repository flags for signing, staging, and publication are enabled.
The release environment still limits credential use to main. PR checks and
ordinary main pushes do not publish. A valid version tag without a CI skip
instruction requests the main workflow; preflight still rejects unchanged
package inputs before native allocation. Published tags and assets stay fixed.

Run `41236743915` verified the existing publisher identity from GitHub, read
Hosting, and acquired, checked, and released the site writer lock. All signing
and publication jobs were skipped. This proves publisher access and lock
handling, not a complete hosted release.

PR #21 corrected the artifact transfer. Run `41236763902` passed the script
checks and required result without native compilation. Local validation passed
285 Python tests, actionlint, and matrix structure. The next app release with
package changes must verify hosted signing, artifact transfer, publication,
and site promotion before end-to-end automation acceptance is recorded.
