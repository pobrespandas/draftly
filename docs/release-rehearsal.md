# Release rehearsal

The release workflow checks a candidate source tree when a version tag is
pushed or when it is started manually. Its rehearsal job has read-only
permissions. It does not create a release or deploy the website.

Use an existing tag in the form `vMAJOR.MINOR.PATCH`. The tag must identify the
current `main` commit. It must match
`CFBundleShortVersionString`. `CFBundleVersion` must be a positive integer.
The workflow runs the test suites, matrix structural check, and local build.
It checks the built app identity and URL scheme. The local build uses an ad hoc
signature. It is not a release package.

The history check reads all GitHub releases and the public appcast. A first
release can proceed without an appcast only when no stable release exists.
Later candidates must exceed every published stable version and build. The
appcast must retain every stable GitHub release. Missing, malformed, or
inconsistent history stops the rehearsal. A duplicate release tag also stops
it, including a draft or prerelease. The check does not authenticate a package
or publish either source.

## Before enabling publication

- Keep `DRAFTLY_UPDATES_ENABLED` unset until update termination and active
  Actions have been verified in a real update. The headless termination tests
  do not establish the Sparkle installation path. Do not use a test key for a
  public build.
- Verify the updater, signed feed, and key recovery process.
- Add and verify Developer ID signing, notarization, and the production
  CloudKit profile. Verify all nested code and the installed app.
- For a signed candidate, `verify-cloud-signing.py` can require the expected
  bundle, team, container, `Production` CloudKit environment, `production`
  push environment, and Developer ID with hardened runtime. This check does
  not notarize the app or establish Gatekeeper acceptance.
- Apply the history check immediately before publication as well as during the
  rehearsal. Reject concurrent publication and verify the candidate artifacts.
- Publish the package and verify its public bytes before changing the feed.
  Preserve the current site and feed if a later step fails.
- Test a release with two distinct signed executables and a copied library.
  Verify cancellation, recovery, offline behavior, and update authenticity.
- Validate CloudKit Production migration separately. The rehearsal does not
  test synchronization or move Development records.

Do not use the rehearsal as evidence that a public release is ready. A tag
push does not start a publication in this version of the workflow.

## CI signing candidate

The optional candidate job runs after a successful rehearsal. It is disabled
unless the repository variable `DRAFTLY_RELEASE_SIGNING_ENABLED` is `true`.
Leave it disabled until the Developer ID profile and credentials are ready.
The job runs only on a GitHub-hosted macOS runner. It creates a temporary
Keychain, installs one profile without replacing an existing profile, imports
the certificate, and stores notarytool credentials in that Keychain. It removes
the temporary Keychain and its own installed profile at the end of the step.

Configure the repository variables `DRAFTLY_DEVELOPER_ID_PROFILE` and
`DRAFTLY_SPARKLE_PUBLIC_KEY`. Configure the protected secrets
`APPLE_DEVELOPER_ID_P12_B64`, `APPLE_DEVELOPER_ID_P12_PASSWORD`,
`APPLE_DEVELOPER_ID_PROFILE_B64`, `APPLE_NOTARY_API_KEY_B64`, and
`APPLE_NOTARY_KEY_ID`. Team API keys also need `APPLE_NOTARY_ISSUER_ID`.
The P12, profile, and `.p8` values are base64-encoded file contents. The
workflow does not pass the original secret values into the package process.
Do not put these values in the repository or job logs.

The release signing job requires the macOS 27 SDK and Swift 6.4 or later.
Older SDK builds cannot include the macOS 27 Private Cloud Compute integration.
The current hosted runner was observed using Xcode 26.6, so it cannot create
the public candidate until a suitable toolchain is available and selected.

A successful candidate is uploaded as a GitHub Actions artifact, not as a
GitHub Release. If notarization fails after submission, the job preserves the
submitted ZIP and receipt as a recovery artifact. The job has only been tested
with simulated tools; it has not signed or notarized a real candidate.

`scripts/verify-release-candidate.py` checks a restored candidate against its
tag, source commit, checksum, update key, app metadata, signature, notarization,
and Gatekeeper. It does not sign or publish the candidate. Restore the original
artifact for a recovery; do not build a different ZIP under the same version.
For workflow recovery, dispatch the release workflow with the same tag and the
run ID that contains the original candidate artifact. The workflow downloads
and verifies that artifact. It does not run the signing job again. A rerun of
the original signing job is rejected. A missing artifact or failed verification
stops recovery. The GitHub ruleset `Protect release version tags` blocks updates
and deletion of `v*` tags. It allows new tags. Inspect an interrupted signing
run before taking further action.

## Local signed candidate

`scripts/package-release.py` prepares a candidate without publishing it. It
requires an installed Developer ID provisioning profile and a Keychain
notarytool profile. It builds with the existing team, bundle ID and CloudKit
container, with production CloudKit and push settings. It checks the signature,
submits the ZIP to Apple, waits for acceptance, staples the app and checks
Gatekeeper before it writes the final ZIP and `READY` marker.

Use a new destination outside the repository or in its ignored `.build`
directory. The command never replaces an existing candidate. It requires a
clean source tree and a version tag that points at the current commit. It
checks the source again after the build. Update checks stay disabled unless a
valid Sparkle public key is provided. Keep them disabled until the real update
acceptance is complete.

```sh
python3 scripts/package-release.py --tag v0.1.0 --output .build/release-candidates/example \
  --profile 'Developer ID profile name' --notary-profile 'Keychain profile name'
```

The output keeps `notary-submission.zip` and, after the service returns an
identifier, `notary-submission.json`. The submitted ZIP is not the
final stapled package. If the wait fails, inspect that submission with
`xcrun notarytool info` before deciding whether to submit again. A candidate
without `READY` must not be published. This workflow and its mocks have not
yet produced a real Developer ID package.

## Prepare a signed appcast

Run `swift package resolve` to obtain the pinned Sparkle signing tool. Install
the Python `cryptography` dependency in the release environment. Give
`scripts/prepare-appcast.py` the candidate directory, a new output directory,
and a UTF-8 release notes file. Supply the 32-byte Ed25519 seed as base64 in
the protected `DRAFTLY_SPARKLE_PRIVATE_KEY` environment variable. Never put it
in a command argument, repository file, or log.

The command checks the candidate checksum, app metadata, update settings, and
embedded public key. It checks the public release history, verifies any current
signed feed, preserves its stable entries, signs the archive and the new feed,
and verifies the feed with Sparkle. The appcast output has a `READY` marker only
after these checks pass. It points to the future GitHub Release URL and does
not upload anything. It must not be deployed until the release workflow also
independently validates the signed candidate and verifies the public ZIP.

The app requires signed feeds and verifies update archives before extraction.
It does not allow Sparkle's automatic installation option; the user confirms
each update.
The appcast tool does not enable update checks. Real update acceptance and key
recovery remain pending.

## Stage the site without publishing

`scripts/firebase-stage-appcast.py` can inspect the live Firebase Hosting
version and stage a signed appcast in a new, finalized version. It does not
create a release or change the live channel. The caller supplies a short-lived
Firebase access token in `DRAFTLY_FIREBASE_ACCESS_TOKEN`; do not print or save
the token. Supply the expected live version and the app's public key to stage.

The staging check verifies the feed signature and version history, reads all
live file hashes and the live configuration, and preserves them in the staged
version. It rejects missing files, changed historical release items, unsafe
upload URLs, and a live version that changes during staging. It also checks the
public appcast ETag against the live Firebase file hash.

Use `--journal PATH` to record the staging operation before the Firebase
request. Keep this journal with the candidate and feed. Use `--resume` with
the same journal to continue an existing staged version. Recovery checks the
live base, feed hash, operation label, and staged files before it proceeds.
It can also verify a finalized version after an interrupted run. An existing
draft or public GitHub release is accepted only during recovery.

If the journal says `creating`, the result of the create request is unknown.
Inspect Firebase for the operation label before taking further action. Do not
create another version automatically. A journal does not lock the live site.

On 29 October 2026 the live site contained 26 files. After the action catalog
was merged from `main`, all 24 repository site files matched the public bytes.
The two additional live paths were `/__/firebase/init.js` and
`/__/firebase/init.json`. This comparison does not authorize a direct deploy:
it must also preserve future update feeds and coordinate other site writers.
The Hosting release API does not document an atomic condition on
the previous live version. Before adding promotion, route every site writer
through a shared serialization mechanism and verify the live version and
public release assets. The staged version alone is not safe publication or
proof of a working update.

## CI staging

The optional staging job is disabled by default. It runs only when
`DRAFTLY_RELEASE_STAGING_ENABLED` is `true` and the candidate job succeeds.
It requires the signed candidate, `docs/releases/vVERSION.txt`, the Sparkle
key, and Firebase Workload Identity Federation. Set
`DRAFTLY_GCP_WIF_PROVIDER` and `DRAFTLY_GCP_SERVICE_ACCOUNT` as repository
variables. Store `DRAFTLY_SPARKLE_PRIVATE_KEY` as a secret. Restrict the Google
identity to this repository and the trusted release workflow. Do not enable the
job until its effective Firebase permissions have been tested. Firebase lists
`firebasehosting.sites.update` for changes to Hosting resources, but its public
permission list does not establish a separate staging-only permission. A role
that can stage may also be able to publish. If so, use a controlled mediator or
another enforced boundary before granting access. See the [Firebase Hosting
permission reference](https://docs.cloud.google.com/iam/docs/roles-permissions/firebasehosting).

The job verifies the candidate, signs the feed, stages a Firebase version,
saves its journal and receipt, and prepares a GitHub draft. It does not publish
the release or promote the Firebase version. Recovery downloads the staging
artifact from the same run as the original candidate. It requires the journal;
an absent journal or an unknown create outcome stops for inspection. Artifacts
expire after 14 days, so preserve the candidate and checkpoint for recovery.
This job has not yet run on GitHub or used real credentials.

## Stage a GitHub draft

`scripts/stage-github-release.py` can create a draft release and upload the
candidate ZIP, checksum, candidate metadata, and signed appcast. It does not
publish the draft. It requires the candidate, appcast, and the same release
notes used for the appcast. The caller supplies the Sparkle signing seed in
`DRAFTLY_SPARKLE_PRIVATE_KEY` and authenticates `gh` with release write access.

```sh
python3 scripts/stage-github-release.py --candidate .build/release-candidates/example \
  --appcast .build/release-appcasts/example --notes release-notes.txt
```

The command verifies the ZIP paths, extracts into a temporary directory, and
checks Developer ID signing, production entitlements, the stapled ticket, and
Gatekeeper. It checks the signed feed and archive signature, then confirms the
tag and current remote main point to the candidate source. It checks them
again before creating or uploading. It checks asset size and GitHub's SHA-256
digest after upload. It does not overwrite an existing asset. After an
interruption it accepts matching draft assets and uploads only missing ones;
it stops if an asset, release title, or notes differ.

This command has been tested with a fake GitHub client and disposable keys.
No real candidate has passed its signing checks. Do not publish a draft until
public asset download, coordinated Firebase promotion, update installation,
and CloudKit Production have been verified independently.

## Publish the verified GitHub draft

`scripts/publish-github-release.py` checks the candidate and signed feed again,
then checks that a finalized Firebase staging receipt still preserves the live
site. It can publish a matching draft and download each public asset without
credentials. It checks every downloaded size and SHA-256 digest. It writes
`PUBLIC_VERIFIED.json` only after the assets and Firebase staging still match.
It does not promote the Firebase version.

The command requires `DRAFTLY_RELEASE_PUBLISH_ENABLED=YES`, the Firebase
access token, the Sparkle signing seed, GitHub write access, and the receipt
from Firebase staging. Do not enable it before the real signed-candidate,
update, and CloudKit Production acceptance checks. The default workflow does
not set this flag. The command has only been tested against fake services.

```sh
python3 scripts/publish-github-release.py --candidate .build/release-candidates/example \
  --appcast .build/release-appcasts/example --notes release-notes.txt \
  --firebase-receipt .build/release-site/example.json
```

If an upload or public download fails after GitHub publishes the release, do
not create or overwrite another release. Inspect the existing release and the
live site, then rerun the checks with the same verified assets. A live site
change stops the process; restaging may be required. A verified public GitHub
release alone does not authorize Firebase promotion.
