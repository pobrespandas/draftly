# Release rehearsal

A version tag dispatches the release workflow from protected main. The
release workflow also accepts a manual dispatch on main. It checks the
candidate source tree before accessing release credentials. Its rehearsal job has read-only
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
`APPLE_NOTARY_KEY_ID`, and `APPLE_NOTARY_ISSUER_ID`. Use a team API key.
Apple does not support individual API keys with `notarytool`. See
[Apple API key documentation](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api).
The P12, profile, and `.p8` values are base64-encoded file contents. The
workflow does not pass the original secret values into the package process.
Do not put these values in the repository or job logs.

The release signing job requires the macOS 27 SDK and Swift 6.4 or later.
Older SDK builds cannot include the macOS 27 Private Cloud Compute integration.
The macOS 26 hosted runner was observed using Xcode 26.6. The candidate job
selects GitHub's `xcode-27` preview image instead. GitHub diagnostic run
40932376170 passed the toolchain gate with Xcode 27.1 and Swift 6.4. The image
has not yet produced a real signed candidate. The rehearsal continues on macOS 26.
See the [GitHub runner image list](https://github.com/actions/runner-images#available-images).
The manual candidate packager uses the same toolchain check before building.

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

## Inspect website changes before staging

`scripts/site-overlay.py` compares two committed website trees with the public
site. Supply their full commit hashes in `--base` and `--target`, and provide a
short-lived Firebase token in `DRAFTLY_FIREBASE_ACCESS_TOKEN`. The base must
represent the site source that was deployed. The command reads Firebase and
public files. It does not write to Firebase or publish anything.

For each changed path, it checks that the live bytes match either the base or
the target. An independent change is a conflict. Unchanged paths are not
replaced. The command checks the Firebase snapshot before and after reading.
It rejects redirects, invalid paths, symlinks, and a public ETag that differs
from the Firebase snapshot. The output lists the changes and deletions.

This inspection is not a lock. A writer can change the site after it finishes.
Release staging uses the same comparison when given site source commits. It
stages the intended changes with the appcast. Promotion is not implemented.
Route all site writers through an enforced shared coordinator before relying on
this check for publication.

## Stage the site without publishing

`scripts/firebase-stage-appcast.py` can inspect the live Firebase Hosting
version and stage a signed appcast in a new, finalized version. It does not
create a release or change the live channel. The caller supplies a short-lived
Firebase access token in `DRAFTLY_FIREBASE_ACCESS_TOKEN`; do not print or save
the token. Supply the expected live version and the app's public key to stage.

The staging check verifies the feed signature and version history, reads all
live file hashes and the live configuration, and preserves files outside the
intended website changes. With `--site-base` and `--site-target`, it checks the
committed website changes against the live files and stages them with the feed.
The target must be the checked-out commit. The journal retains compressed
website payloads and recovery checks them against the same source. It rejects missing files, changed historical release items, unsafe
upload URLs, and a live version that changes during staging. It also checks the
public appcast ETag against the live Firebase file hash.

Staging requires `--journal` before it can change Firebase. Use the staging
directory path `firebase-journal.json`. Keep this journal with the candidate and feed. Use `--resume` with
the same journal to continue an existing staged version. Recovery checks the
live base, feed hash, operation label, and staged files before it proceeds.
It can also verify a finalized version after an interrupted run. An existing
draft or public GitHub release is accepted only during recovery.

The feed uses a gzip header with no filename and a zero timestamp. Staging
saves the original compressed bytes next to its journal as
`firebase-journal.json.feed.gz`. Keep the payload with the journal and feed.
Recovery and publication verify its hash and decoded content. They do not
recompress it. A missing or changed payload stops recovery and publication.
Older checkpoints without this payload require inspection and restaging; they
cannot use automatic recovery.

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
`DRAFTLY_GCP_WIF_PROVIDER`, `DRAFTLY_GCP_SERVICE_ACCOUNT`, and
`DRAFTLY_SITE_BASE_COMMIT` as repository variables. The site base must identify
the committed site source last deployed to the live site. Store `DRAFTLY_SPARKLE_PRIVATE_KEY` as a secret. Restrict the Google
identity to this repository and the trusted release workflow. Do not enable the
job until its effective Firebase permissions have been tested. Firebase lists
`firebasehosting.sites.update` for changes to Hosting resources, but its public
permission list does not establish a separate staging-only permission. A role
that can stage may also be able to publish. If so, use a controlled mediator or
another enforced boundary before granting access. See the [Firebase Hosting
permission reference](https://docs.cloud.google.com/iam/docs/roles-permissions/firebasehosting).

The job verifies the candidate, signs the feed, stages a Firebase version with
the checked website changes, saves its journal and receipt, and prepares a
GitHub draft. It does not publish
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

## Credential state on 29 October 2026

A Developer ID identity and a matching Production profile are installed on the
local Mac. An isolated archive passed notarization and Gatekeeper after Sparkle's
helpers were signed. A Sparkle release key was created locally. The user
recovered the seed from Google Password Manager on a second device and verified
it against the public key on the Mac. This does not complete release acceptance.

To verify a recovered seed, use `scripts/verify-recovered-sparkle-key.py` in a
private terminal with Python and the `cryptography` package. Pass the saved
public key file with `--public-key-file`. Paste the recovered seed only at the
hidden prompt, never as an argument or in chat. The command checks the derived
public key and prints only a match or failure. Clear any clipboard used for the
transfer. A matching result confirms the recovered seed; this check does not
verify Developer ID or notarization key recovery.

After exporting the Developer ID identity as an encrypted PKCS#12 file, use
`scripts/verify-developer-id-backup.py` with `--backup` and `--certificate`.
The certificate argument must be the expected public Developer ID certificate
from the trusted local Keychain, not a certificate supplied by the backup. The
tool requests the archive password with hidden terminal input. It checks the
certificate fingerprint, team, and matching private key. It does not import the
identity, validate Apple trust or prove recovery on another device.

The encrypted Developer ID archive and its password are stored in separate
Apple Passwords entries. On the Mac, the stored archive matched the local file
byte for byte, and the stored password opened it and passed the identity check.
Recovery of those entries from another device has not been verified. The Apple
Passwords notarization key also matched its local file on the Mac; its
second-device recovery has not been verified. Keep the local originals until
those recovery checks succeed. Never put recovered credentials in command
arguments, logs, Git, or chat.

The public GitHub repository has active rulesets that protect version tags and
prevent deletion and non-fast-forward updates of main. Main requires a pull
request and a successful current `Build and test on macOS` check, including for
administrators. The release environment allows only main. It holds no secrets.
These settings do not provide independent review of workflow changes. Store
release credentials only as environment secrets after testing the source
restriction. Signing and staging jobs remain disabled.

Tags run a dispatcher with no release secrets. It requests the trusted release
workflow on main. The rehearsal rejects dispatches from other branches before
any credential job can run. The workflow still verifies the exact tag and
source commit. The environment has no required reviewer, so a valid release
can run automatically. Main requires zero independent approvals for this
single-maintainer repository; the maintainer must inspect workflow changes.
Test the environment restriction before adding credentials or enabling jobs.

## Site writer lock component

`scripts/release-lock.py` provides a Cloud Storage lock for a future site
coordinator. It creates one fixed object with `ifGenerationMatch=0` and
deletes only the recorded generation. Its journal records the bucket, object,
owner and operation state before a remote change. A lost response requires
explicit recovery. Recovery does not retry creation or delete another owner.
The journal file and its directory are synced before each remote change. If
sync fails, the command stops without issuing that change. After a failure,
inspect the journal before recovery because an atomic replacement may already
have changed its visible state.

The `check` operation compares the journal scope, owner, and generation with
the current object without changing it. It is a point-in-time check, not an
atomic guard on a later Hosting write. It cannot stop a writer that bypasses the
coordinator or a manual lock deletion after the check.

This component has fake-service tests. The release workflow now holds it from
Firebase staging through public verification. Other Firebase writers can still
bypass it unless IAM restricts the publishing path. Before
publication, all writers need an enforced coordinator with exclusive Firebase
credentials and suitable access controls. Do not enable publication based on
this lock alone. No bucket or IAM policy was created for this component.

On 29 October 2026, the project IAM policy included a human project owner and
Firebase service agents. A project owner can bypass this lock with direct
Hosting access. The project had no Cloud Storage buckets at that time. This
inspection did not establish effective inherited permissions or restrict any
identity. A coordinator therefore needs both a dedicated lock bucket and an
enforced publishing path; a cooperative lock alone is not sufficient.

Do not automatically expire or clear a lock. Before manual recovery or release,
confirm that its writer and any pending remote requests have stopped. Preserve
the journal and inspect the remote object and generation. An abruptly lost
runner may also lose its journal and require manual investigation. Never remove
an unfamiliar lock to unblock a release.

## Promote the verified site

`scripts/promote-firebase-release.py` requires an existing public GitHub release,
a matching `PUBLIC_VERIFIED.json`, the signed appcast and its staging receipt.
It reuses candidate, public-asset and site verification before promotion. It
requires the held site writer lock and checks ownership before the request and
before acceptance. The coordinator must keep that lock for the whole release.
The lock check does not prevent a writer that bypasses the coordinator.

The command writes a durable pending journal before the Firebase release POST.
If the response is lost, recovery can verify an already-promoted version without
another POST. If the original version remains live, recovery stops: the earlier
request can still be in flight. Inspect Firebase and stop all pending writers
before further action. A public-feed mismatch leaves the journal pending.
The command marks completion only after Firebase and the public HTTPS appcast
match the verified release. It does not release the writer lock.

Set `DRAFTLY_RELEASE_PROMOTION_ENABLED=YES` only after release acceptance.
The command also requires the existing publication flag and credentials. Pass
`--candidate`, `--appcast`, `--notes`, `--firebase-receipt`, `--journal`,
`--lock-bucket` and `--lock-journal`. Keep journals outside Git. This component
has fake-service tests; the production coordinator and real promotion remain
unverified. See the official [Firebase release API](https://firebase.google.com/docs/reference/hosting/rest/v1beta1/sites.releases/create).

## Coordinated publication workflow

The protected main workflow can now publish the verified GitHub draft and
promote its matching Firebase version. Set
`DRAFTLY_RELEASE_PUBLICATION_ENABLED=true` only after acceptance. The staging
job acquires the site lock before creating Firebase versions. Publication
rechecks the lock, candidate, public assets and live site. Promotion verifies
the public HTTPS feed. The workflow releases the lock only after that step
succeeds. The final checkpoint upload runs even after failure.

A staging-only run keeps the lock for inspection. A recovery run verifies the
original held lock; it does not silently create a new one. If the journal has
an uncertain create or release, use the lock recovery procedure before
continuing. The workflow does not automatically expire or delete a stale lock.

Use `operation=verify-publisher` on main, without a tag, to check the federated
identity and lock without signing or publication. This is a separate job from
candidate creation. See [release infrastructure](release-infrastructure.md)
for the current access controls and remaining real checks.

## Website source checkpoints

Each coordinated staged version records its target Git commit in the Firebase
`draftly-site-source` label and both source commits in the journal and receipt.
Publication checks these values against the candidate. Recovery must use the
original source commits. It cannot replace them with current environment values.

A new run reads the base source from the live version. The bootstrap variable
`DRAFTLY_SITE_BASE_COMMIT` is used only when no source label and no public appcast
exist. It was verified against the initial live site at commit `a955f00`.
Once a feed exists, a missing or invalid source checkpoint stops the run.
This prevents a later release from guessing which site source is live.

## Production preparation on 30 October 2026

PR #4 passed hosted CI run 41005481716 and merged into main at a29aebc.
The release environment now has the Developer ID archive and password, the
Production profile, the Sparkle seed, and the notarization key, key ID and
issuer ID. Secret values were sent through standard input. They were not
written to Git or command arguments. Apple accepted a read-only notarization
history request with this key and issuer. This confirms authentication. It
does not confirm that the hosted signing job can use every secret.

CloudKit Console initially showed only Users in Production. The reviewed
Development schema added CD_Record with five application fields and fourteen
indexes. Users stayed unchanged. CD_Record grants write access to its creator;
it has no public read or general iCloud create grant. The app uses the private
database. The schema deployment completed. The exported Production schema
matches Configuration/CloudKitProduction.ckdb and the reviewed export exactly.
Its SHA-256 is
9ac59aeccbcaa415626c6ddfaf62a892e460addfa4c294c5085241544069788d.
Schema deployment does not copy Development records.

A signed native probe uses the main bundle identifier, existing Developer ID
Production profile and container. It runs directly from a temporary app bundle,
without LaunchServices registration, AppController or preference writes. Its
two LibraryStore instances use separate temporary directories and seed=false.
Only a neutral note with UUID DD71668E-2039-4ACB-8209-202610300001 is compared.
The native CloudKit call saved and fetched a neutral CD_Record in the separate
private zone DraftlyProductionProbe20261030. The account status was available.
This confirms real Production access, signing and the container association.
The Core Data stores must still confirm export, fresh import and return editing.
The first headless attempt logged BGSystemTaskSchedulerErrorDomain code 3;
that harness result is not an application regression or a sync acceptance. Mac-to-VM convergence, migration
of existing data and complete object coverage remain separate checks.

Publication flags remain disabled. No public version tag, GitHub release,
live appcast or replacement of the usual application has occurred.

The AppKit harness also logged scheduler code 3 for both Core Data stores.
The reader still had no records. The probe was stopped after this result;
no transport pass or timeout acceptance is recorded. Continue this check with
an isolated, normally launched application that can register background tasks.
The temporary stores and neutral Production fixtures remain available.

## Active-action update regression on 30 October 2026

The local QA updater found a real termination defect. A neutral asynchronous
script completed and saved its result. Sparkle still waited for the app to
exit. ActionTerminationCoordinator scheduled its reply on the default RunLoop
mode. That mode did not run during the termination wait. The failed QA session
was stopped explicitly. Its later replacement does not count as a normal
update pass.

The coordinator now schedules its reply on DispatchQueue.main. A headless test
runs a common mode without running the default mode. The test failed before
the fix and passed after it. Existing idle, save-failure and reply-once cases
also passed. No timeout or retry rule changed.

The manual repeat used a Developer ID signed QA host with this exact fix and
an existing, different QA destination executable. Both use the isolated
com.pobrespandas.draftly.updater-qa identity and the same temporary library ID.
The source host was Debug; the target was the earlier Release QA fixture.
This is a termination regression check, not notarized release acceptance.
A signed loopback catalog offered 0.2.0 build 2 to 0.1.0 build 1. The app kept
build 1 while its ninety-second action was active. After the action completed,
Sparkle replaced the app and relaunched build 2 without external termination.
The Unicode editor text, note identity and successful action record survived.
Computer Use reopened the note and showed the saved action marker.
The QA app quit normally after the repeat. The loopback server stopped.
Only the temporary apps were unregistered. The usual app was not replaced.

Full local Swift results matched the inventory: 759 Core and 935 application
cases. These counts show execution completeness, not API compatibility.
Public release verification and notarized main-identity update remain pending.

## Production native transport follow-up

Normal macOS application launch resolved the probe's background scheduling
error. The signed probe reported an available account, saved the neutral note,
and imported that exact UUID and text into a fresh Core Data store. A change
made in that store was exported. A separate cold-reader launch then imported
the changed text with the same UUID. All stores used temporary directories.
The probe did not instantiate AppController or change the usual preferences.

Two live same-process return checks did not receive the change before their
fixed deadline, including the check with remote notification registration.
Do not count fresh import as proof of live push reception. Continue with real
separate clients, including Mac and VM. Existing-library migration, complete
object coverage and convergence remain pending. The probes are stopped and
were unregistered. No Production record was copied from Development by the
schema deployment.

## First release notes and source gate

PR #7 passed hosted CI 41010858004 and merged at 04a7127. The termination
regression test now compiles on the macOS 26 and 27 SDKs. Production code still
uses the same DispatchQueue.main fix that passed the native QA repeat.

Each version tag needs UTF-8 notes at docs/releases/vMAJOR.MINOR.PATCH.txt.
The source preflight rejects missing, empty or invalid UTF-8 notes before the
workflow starts its test and signing jobs. The initial v0.1.0 notes describe
the current product and identify the remaining compatibility checks. They do
not claim complete Drafts parity or completed CloudKit acceptance.

A CLI regression reproduced the previous preflight accepting a tag with no
notes. The source gate and Unicode/read-only cases now pass. All 259 Python
tests and the structural matrix check passed locally. The release flags remain
disabled. Notes in Git are preparation, not a published release.

## Neutral legacy recovery check

A headless local helper imported the two saved neutral guest exports from the
19 October VM check into temporary Record stores. It created a library backup,
restored that backup to an empty store, and reopened the result. Current model
values matched by identity, including all encoded fields and relationships.
The main-container fixture retained two notes and eight revisions. The wider
fixture retained ten notes, eleven revisions, one action, one group, one
Workspace and one execution record. No personal library or cloud store was
opened by this check.

The first helper compared unsorted storage arrays and reported a mismatch for
the wider fixture. LibraryStore does not promise a note-array storage order.
Comparison by UUID confirmed equal values; persisted order fields stayed part
of those value comparisons. This was a harness issue, not a data correction.
These exports do not validate migration of Development mirroring metadata or
Production cross-client convergence. Keep those acceptances separate.

## Production live round trip on 31 October 2026

Probe E passed with both clients open. The host ran macOS 27.2 (26B123).
The UTM guest ran macOS 26.6 (25G72). Both clients used the Production
container `iCloud.com.andrestobelem.draftly`, the main app identity, and
isolated local libraries. The personal library was not opened.

The guest ZIP SHA-256 was
`31f2dd38cae78c73209b237bc01b65ea98abefc0366c8b10a62cd6edd4b10102`.
The guest passed signature verification and Gatekeeper assessment. The host
was recovered from that same executable. Its explicit role was set to `host`
and its bundle was signed again with the existing Developer ID identity.
Both clients reported an available account and successful push registration.

The host created neutral note `DD71668E-2039-4ACB-8209-202610300006`.
The guest received a remote notification, reported `HOST_TO_GUEST=PASS`,
and saved its edit. The host then received a remote notification and reported
`GUEST_TO_HOST_LIVE=PASS; CONTENT=PASS; TAGS=PASS; FLAG=PASS; UUID=PASS`
and `CROSS_CLIENT_NOTE_ROUND_TRIP=PASS`. Neither client was restarted during
the round trip. The return took several minutes.

This verifies the isolated live note round trip in Production. It does not
prove the complete synchronization matrix, Development data migration,
public updater acceptance, or public release. Earlier failures remain valid
observations. This result does not establish their cause.

## Main-identity updater restart on 31 October 2026

A repeat used the internal 0.0.9/build 0 origin harness and the unchanged
notarized v0.1.0 ZIP. The signed test appcast and archive were served only
on loopback. This does not verify the public HTTPS endpoints.
Computer Use confirmed the version offer, release notes, extraction, and
Install and Relaunch. After that click, no app lookup or explicit open was
performed. Process inspection found PID 17518 at the updated path ending
`update-acceptance/Draftly.app/Contents/MacOS/Draftly`, with build 1.
Strict signature verification passed. Its executable SHA-256 was
`50e9aaedf9dee13a0faa06c10e5c3cb0982aa09bb305d185d814b993dcad4cb3`,
which matches the definitive candidate. Automatic restart passed in this
repeat. The origin is a harness; the earlier full-app active-action test
remains separate evidence. Negative cases and public endpoint checks remain.

The user clarified that they reopened the app in the earlier attempt.
Do not attribute that reopening to Computer Use. The earlier attempt did
not establish automatic restart or an updater defect.

## Negative updater checks with a valid origin signature

On 31 October, strict deep verification passed before and after the negative
checks. With the loopback server stopped, Sparkle reported a retrieval error.
With a one-byte-modified ZIP, it reported an improper-signature error and
blocked installation. After restoring the definitive ZIP, closing the update
offer cancelled without replacement. The origin remained build 0 in each
case. This proves unavailable-server handling, archive authenticity rejection,
and cancellation before download. It does not prove a mid-download network
interruption, interruption during installation, or public HTTPS delivery.
The earlier invalid-origin observations do not provide this acceptance.

## Download interruption and recovery

On 31 October, a throttled loopback transfer showed 66 KB of 7.5 MB before
the server was stopped. Sparkle reported a download error. The origin retained
build 0 and passed strict deep signature verification. After restoring the
server, a new attempt installed the definitive ZIP and restarted PID 19435
at the updated Draftly executable path. No app lookup or explicit open occurred
after Install and Relaunch. Its signature passed and executable hash matched
`50e9aaedf9dee13a0faa06c10e5c3cb0982aa09bb305d185d814b993dcad4cb3`.
This verifies a transport interruption and subsequent recovery, not a power
failure during the atomic installation step.
