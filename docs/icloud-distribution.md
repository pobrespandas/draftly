# iCloud and installation

Public Developer ID releases use the existing container with CloudKit
Production and production push entitlements. Use [release operations](releasing.md)
for public signing, notarization, updates, and recovery. The configuration
below describes Development and registered-device personal builds. Those
profiles do not authorize public distribution.

Current identity: 21 October 2026. Historical server checks retain their dates.
Read [the identity migration record](bundle-identity-2026-10-21.md) for data
conservation, installation and remaining native checks.

For the storage entry name and icon, read [iCloud display identity](icloud-identity.md).
Its current acceptance is incomplete; the container description alone did not
change the name shown by macOS.

## Development and personal configuration

The configured team is `NM92LU2KKV`. Apple reports its name as
`Andrés Tobelem`. Xcode does not list a separate team named `pobrespandas`.
The team can now provision CloudKit and push notifications. This Mac was
registered through automatic signing. The new main development profile expires on
21 October 2027 and covers the registered Mac and UTM guest.

The main app uses these identifiers:

- App: `com.pobrespandas.draftly`.
- Container: `iCloud.com.andrestobelem.draftly`.
- Database: private.
- CloudKit environment: Development.
- Push environment: development.

`Configuration/Signing.xcconfig` remains local and ignored by Git. The app
keeps the existing generic Core Data schema and library location. Local
preferences, credentials, and security bookmarks do not become CloudKit records.

## Build outputs

| Command | App path | Signing |
| --- | --- | --- |
| `scripts/build-app.sh --local` | `.build/xcode/Build/Products/Debug/Draftly.app` | Ad hoc, no iCloud |
| `scripts/build-app.sh --icloud` | `.build/icloud/Build/Products/Debug/Draftly.app` | Apple Development, iCloud |
| `scripts/build-app.sh --personal` | `.build/personal/Build/Products/Release/Draftly.app` | Apple Development, iCloud |
| `scripts/build-app.sh --cloud-qa` | `.build/cloud-qa/Build/Products/Debug/Draftly.app` | Separate test app identity, iCloud |

The outputs do not overwrite each other. The signed build requests device
registration when required. The signing check compares the app identity,
container, team, environments, and profile expiry with the signed entitlements.
It also verifies the code signature. A passed signing check does not prove a
server association or a successful sync.

Run `scripts/package-personal.sh` to build the Release app and create:

- `.build/distribution/Draftly-personal.zip`.
- `.build/distribution/Draftly-personal.zip.sha256`.
- `.build/distribution/signing-report.json`.

This package uses a development profile. Only registered Macs covered by that
profile can use it. The `Draftly Mac and VM 2026-10-21` profile covers the host
and registered VM.
Set `DRAFTLY_PROVISIONING_PROFILE="Draftly Mac and VM 2026-10-21"` when building
with that installed profile. Check the embedded profile after each build.
Register each additional Mac and regenerate the profile before building its
package. The package is not notarized. General installation through Gatekeeper requires a Developer ID
certificate, the correct profile, and notarization. Those steps are not claimed
by this package.

## Test isolation

The cloud test app has bundle ID `com.andrestobelem.draftly.cloud-qa`. It uses a
stable temporary library ID in `.build/cloud-qa-config/Info.plist`. It does not
open the normal library or seed default actions. Rebuilding the app keeps that
ID. Its local library is under the system temporary folder in
`Draftly-UITesting/<ID>/Library.sqlite`.

The test app now uses `iCloud.com.andrestobelem.draftly.cloudqa` in Development.
It has a separate local store. A container change creates a new local library ID;
the previous ID and local store remain intact. Use only neutral test data. Do not
use the test app to edit personal notes. The normal
`--ui-testing` mode still disables CloudKit. It cannot prove sync acceptance.

## Server checks

The first signed test launch used the main container. It saved a neutral note
locally, but setup failed with partial failure and permission failure. The nested
server message was `Invalid bundle ID for container`.

After sign-in, the Developer Portal showed the test App ID assigned to the main
container. The checked assignment did not resolve the server rejection. Apple's
TN3164 describes this case and recommends a new container for development when
an association has not reached the CloudKit server. No main-app assignment was
removed and no production environment was reset.

The test build now uses a dedicated container. Its initial launch reported
`CKError.badContainer`. The container then appeared in CloudKit Console. After
relaunch, the app reported a completed upload. A second, empty local library
received the note from the private database. The app opened the recovered note.
A read-only comparison confirmed its ID, content, tags, syntax, flag, folder, and
creation and modification dates. No local restore or file copy populated the
receiver. Its source store remains intact.

This is a real server round trip on one Mac. It does not prove two-Mac convergence.

The UTM QA guest is registered. A separate manual QA profile covers the host
and guest. The QA app launched from the guest Applications folder. The shared
package uses this two-device profile. An automatic rebuild can select the older
one-device profile. Check `registeredDeviceCount` before a guest installation.
The main personal package still uses its separate profile. See
[UTM validation](utm-icloud-validation.md) for cross-client evidence.
The main app's original container now passed the isolated server round trip
below. Its guest checks remain open.

## Main container server round trip

On 19 October 2026, an isolated build used the actual main identity
`com.andrestobelem.draftly` and container `iCloud.com.andrestobelem.draftly`.
`DraftlyCloudTesting` selected a new temporary library and disabled seed data.
The normal app quit through its save path before the test app opened.

The test created one neutral note with Unicode, a tag, and a Blue flag. A second
signed app used the same main identity and container but a new empty local
library ID. No library or fixture was copied into that receiver. CloudKit
supplied the note and both revisions. The receiver opened the note in the UI.

Read-only comparisons matched identity, content, tags, flag, syntax, archive
state, Trash state, and creation and modification dates. Revision identity
sets also matched. This proves the main identity's server association and a
real server round trip on this Mac. The earlier rejected request used the QA
app identity. This result does not prove that earlier QA association changed.

Apple issued a separate main development profile for the host and UTM guest.
The signed `MainCloud QA` package is in `.build/utm-share/MainCloud.zip`. It
keeps a temporary library and does not replace the earlier cloud QA app.
The installer in that folder refuses to replace an existing MainCloud app.

The user restored console input. The guest installed the signed main package.
It received the neutral note and two revisions through CloudKit. The nine note
contract fields matched. Opening the note changed only its access date.

The return edit exposed a defect. A local access update could replace a remote
content payload. Its revision still arrived. Access updates now use separate
`noteAccess` records in the existing generic store. They do not write the note
payload or its modification date. Backups retain the effective date in `Note`.
All clients must use the correction. Older clients retain the old behavior.

Signed build 4 passed the repeat with access during a remote edit. Both stores
held two notes and eight matching revisions. All nine note fields matched.
The Mac UI opened the returned text after relaunch. The guest process path and
binary hash matched the installed build. Earlier repeats opened a cached backup
from Spotlight and do not count as acceptance of the correction.

The complete main-container matrix remains open. Repeat offline, concurrent
content, Trash/Restore, and organization cases with the corrected clients.
The dedicated QA results remain separate.
Evidence is in `.build/main-cloud-evidence`: source and receiver snapshots,
Info files, signature reports, comparison results, and screenshots. The local
source store remains intact. The personal library was not used for the test.

## Status behavior

Settings observes the library status. It distinguishes account checks, a signed
out account, restricted access, temporary account errors, active operations,
completed uploads, completed downloads, and operation failures. Nested CloudKit
errors show their cause without record identifiers or payloads. An unrelated
successful download does not clear an upload failure.

`Check iCloud Account` refreshes account status. It does not force an upload or
promise an immediate retry. Core Data manages sync scheduling. A completed
upload does not prove that another Mac received the records.

## Install or update

1. Export a full backup from the current app. Keep it outside the app bundle.
2. Quit Draftly. Check that it reports no save error.
3. Keep the previous app until the update passes acceptance. Move the new app to
   Applications. Replace only the app bundle. Keep the library folder.
4. Open the new app. Check note identities, content, tags, revisions, Workspaces,
   actions, groups, and syntax definitions.
5. Relaunch the app. Check the same data again before removing the old app.

The main builds use the same bundle ID and
`~/Library/Application Support/Draftly/Library.sqlite`. The app does not migrate
data into its bundle. Do not run local and signed main builds at the same time.
Do not switch CloudKit environments on a personal library for a test. The first
iCloud acceptance must use a copied or temporary library.

An older app may not understand newer data. Keep the pre-update backup for a
rollback. Close the app before a filesystem copy of the library. Copy the whole
folder, including SQLite sidecar files.

## Acceptance record

Implemented:

- Separate local, signed, test, and personal build outputs.
- Explicit private database and CloudKit environment.
- Signature and provisioning checks and a personal package.
- Account state and operation state reporting.
- Persistent history for local stores, ready for a later CloudKit launch.
- An isolated cloud test library with a stable identity.

Automatically tested:

- Concurrent operations, failed operations, nested errors, and account states.
- Local save, reopen, identity preservation, and backup recovery.
- Signing checks reject mismatched identities, missing rights, wrong environments,
  and expired profiles.

Verified in use:

- Apple generated main and test profiles with CloudKit and push rights.
- The signed test app launched and saved a neutral note locally.
- Settings displayed the real initial setup failure. The portal assignment was correct.
- The dedicated QA container accepted an upload and supplied the same note to an
  independent local store. Its identity, content, and metadata matched.
- The neutral note survived a signed rebuild and relaunch with the same test library.
- The host and UTM guest passed the dedicated QA cases. Both stores contained
  ten notes, eleven revisions, one Workspace, one group, one action, and one
  execution record. Note contract fields and identity sets matched.
- Both concurrent variants remained available in guest Revision History.
- Guest Ethernet was restored after the offline test.

Pending:

- The main container passed initial download, guest creation, and return edits.
  Repeat its broader matrix after the access-record correction.
- The dedicated QA container passed the named host-plus-UTM cases. Physical
  two-Mac hardware coverage remains separate.
- Repeat the QA acceptance with the main container. Dedicated QA passed offline
  edits, reconnection, concurrent revisions, Trash/Restore, and app relaunch.
- Broaden signed update coverage beyond the QA bundle replacement. The guest
  installed and verified signed build 2 with the same executable and library ID.
- Complete Developer ID and notarization if installation must work without
  registered-device development profiles.

This record does not close iCloud acceptance.

## Apple references

- [Debugging Core Data sync](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer).
- [Core Data with CloudKit](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer).
- [CloudKit database scope](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontaineroptions/databasescope-4c72t).
- [Development and Developer ID distribution](https://help.apple.com/xcode/mac/current/en.lproj/dev31de635e5.html).
- [Signing Mac software with Developer ID](https://developer.apple.com/developer-id/).
- [Updating membership information](https://developer.apple.com/help/account/membership/updating-your-account-information/).
