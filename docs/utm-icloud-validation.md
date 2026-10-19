# iCloud validation with UTM

Date: 19 October 2026.

## Test environment

- Host: the development Mac.
- Guest name: Draftly iCloud QA.
- UTM: 4.7.5.
- Backend: Apple Virtualization.
- Guest installer: macOS 27.0.1, build 26A434, from Apple.
- Guest memory: 8 GiB.
- Guest CPU: four cores.
- Guest disk: 64 GiB.
- Test container: `iCloud.com.andrestobelem.draftly.cloudqa`, Development.

The VM is a second client. It does not establish physical two-Mac hardware
coverage. It can establish cross-client CloudKit behavior. The guest needs the
same iCloud account as the host and its own local library. Do not clone a library
into the guest.

## Transfer folder

`.build/utm-share` contains the signed QA app, its signing report, a checksum,
and the fixture manifest. The host-only import fixture is in
`.build/utm-fixtures/QA-sync-fixture.json`. Share only the transfer folder with the VM.
Do not share the normal library folder or the user's home folder.

Import the fixture on the host only. The guest must receive its notes,
Workspace, group, action, and revision through CloudKit. The fixture has eight
notes with fixed IDs. The dedicated container also has the earlier neutral
round-trip note. The expected total is nine notes, including one in Trash.

The development profile must cover the guest device before it can run the app.
Get the guest provisioning UDID from System Information. Register that device,
refresh the QA profile, and replace the shared package with the newly signed app.
Do not use an ad hoc signature as proof of CloudKit signing.

## Cases and required evidence

| Case | Check |
| --- | --- |
| Initial download | Eight fixture IDs, content, Unicode, tags, syntax, flags, and dates match. |
| Organization | QA Sync Workspace, group, safe action, and saved revision arrive. |
| Host to guest | Change QA Host → VM on the host. The guest displays the marker. |
| Guest to host | Change QA VM → Host in the guest. The host displays the marker. |
| Metadata | Change tags and flag on one client. Check the other client. |
| Archive | Move the QA Archive note to Inbox. Check both clients. |
| Trash/Restore | Restore QA Trash Restore. Check both clients. Do not empty Trash. |
| Offline | Disconnect the guest network. Edit QA Offline and restart the guest app. Check local content, reconnect, and check the host. |
| Concurrent edits | Edit QA Concurrent on both clients while the guest is offline. Reconnect. Check convergence and recoverable variants in revisions. |
| Action | Run QA Sync — Safe Log in the guest. Check the result and action history. |
| Update | Quit the guest app. Replace only its app bundle with a new signed build. Check identities and text after relaunch. |

A failed case remains open. A completed local save is not a remote acceptance.
Record each client's observed result. Do not substitute a test count for native
acceptance.

## Results

Implemented and prepared:

- The user completed Setup Assistant and iCloud sign-in.
- Apple completed the approved annual device review. All three existing devices remain.
- Apple registered the guest. The manual QA profile covers the host and guest.
- The signed QA package passed entitlement and signature checks.
- Finder installed the app in the guest Applications folder.
- The guest received all source records through CloudKit. No fixture or library was copied into its local store.

Automatically checked against native data:

- A read-only SQLite snapshot contains ten notes on each client.
- Note identity sets match. Content, dates, tags as sets, flag, syntax, archive state, and Trash state match.
- Both clients have eleven revisions, one Workspace, one group, one action, and one execution record.
- Organization and revision identity sets match.
- Both concurrent variants remain in both revision stores.
- The installed guest bundle reports build 2. Its code signature passes verification.

Verified in use:

| Case | Observed result |
| --- | --- |
| Initial download | All nine source notes arrived, including the eight fixture notes. Unicode and metadata survived. |
| Organization | QA Sync Workspace applied its tag filter and title order. The QA Sync group and safe action appeared. |
| Host to guest | The host marker appeared in the guest list and stored content. |
| Guest to host | A new guest note and an edit to QA VM → Host appeared on the host. |
| Metadata | The host added qa-metadata-host and changed Yellow to Blue. The guest received both. TaskPaper remained selected. |
| Archive | The guest moved QA Archive to Inbox. The host received the change. |
| Trash/Restore | The guest restored QA Trash Restore. The host received the change. Trash was not emptied. |
| Offline | Guest Ethernet was inactive. Offline edits survived app quit and relaunch. Ethernet was restored. The host received the offline marker. |
| Concurrent edits | Each client saved a different variant while the guest was offline. Both clients converged on the guest variant. Both variants appeared in stored revisions. Guest Revision History displayed each variant. |
| Action | QA Sync — Safe Log ran in the guest. Execution History displayed Success and the neutral log. The execution record reached the host. |
| Package update | The guest quit the app and replaced only its signed bundle. Build 2 opened with all ten note identities and text preserved. |

The package update changed the bundle build number and signature. It kept the
same executable and library ID. This proves bundle replacement for this package.
It does not prove a future binary or schema migration.

The first CloudKit setup took several minutes. Logs showed account lookup,
zone setup, and subscription setup before records arrived. A local save or an
active operation was not counted as a remote pass.

Archive Utility could not extract the ZIP on the shared volume (error 513).
Copying the ZIP to guest Downloads and extracting there succeeded. Partial
extraction files remain isolated in the transfer folder. Do not use them to run
the app.

## Open differences and scope

Before relaunch, the guest editor sometimes left a line from the previous draft
drawn below the new content. The character count and stored payload matched the
new draft. Read-only snapshots showed no content contamination. This visible
refresh defect remains open. A later relaunch rendered the selected note cleanly.

The named Mac-plus-VM CloudKit cases passed in the dedicated Development
container. The VM is connected to Ethernet again. The normal personal library
was not used. This result does not close the main container acceptance,
Developer ID, notarization, or physical two-Mac coverage.

## Main container follow-up

The restored console received input. The signed main identity downloaded its
neutral note and two revisions. A return edit exposed a conflict between access
and content writes. The revision retained the new text, but the active content
returned to the prior version. This case failed before the correction.

Access now uses a separate generic record. Signed build 4 passed the repeat.
Both stores held two notes and eight matching revisions. Nine note fields
matched. A guest creation and remote edit arrived on the Mac. Opening during
that edit did not replace its text. The Mac opened the result after relaunch.
The guest process path and binary hash confirmed the tested package. Cached
Spotlight backups caused earlier invalid repeats; those do not count.

The main profile covers both clients. No personal library was used. The complete
main-container matrix remains open. Repeat offline, concurrent content,
Trash/Restore, and organization cases with the corrected build on both clients.
Access-record convergence remains outside this completed content comparison.

## Evidence

Local evidence is in `.build/utm-evidence`. It includes Apple registration and
profile screenshots, download screenshots, network state, offline relaunch,
both revision variants, execution history, signing reports, and a read-only
cross-client comparison. `.build/utm-share/guest-records.json` contains only the
isolated neutral QA records. Device identifiers are not stored in this document.

## References

- [Using iCloud with macOS VMs](https://developer.apple.com/documentation/virtualization/using-icloud-with-macos-virtual-machines).
- [UTM macOS guests](https://docs.getutm.app/guest-support/macos/).
- [UTM shared directories](https://docs.getutm.app/settings-apple/sharing/).
