# Release rehearsal

The Release rehearsal workflow checks a candidate source tree. It does not
create a release, sign a distribution app, or deploy the website. It has no
access to signing secrets or write permissions.

Start it manually with an existing tag in the form `vMAJOR.MINOR.PATCH`. The
tag must identify the current `main` commit. It must match
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
