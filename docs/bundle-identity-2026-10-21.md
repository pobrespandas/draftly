# Main app identity migration

Date: 21 October 2026. Reference commit: `b6f5219`.
Reference tag: `pre-bundle-identity-2026-10-21`.

## Implemented

The main bundle ID is `com.pobrespandas.draftly`. The display name is Draftly.
The signing team remains `NM92LU2KKV`. The URL scheme remains `draftly`.
The container remains `iCloud.com.andrestobelem.draftly`, private Development.
The user briefly requested a new container, then chose to keep the existing one.
No new container was created. QA identities and historical records are unchanged.

The app copies explicit local preferences from `com.andrestobelem.draftly` before
SwiftUI, AppStorage and AppController initialize. Existing destination values
win. Registered defaults and global preferences are not copied. Unknown keys
and binary bookmarks are copied. Each write is synchronized and checked before
the completion marker is stored. Failures stop startup and offer Try Again or
Quit. Completed migration does not import later legacy changes. The legacy domain
is unchanged. Native helper mode exits before migration. QA and cloud test modes
skip migration.

The library stays at `~/Library/Application Support/Draftly/Library.sqlite`.
No model, stored format, public scripting API, Note identity or backup contract
changed. The Keychain service remains `com.draftly.action-credentials`.

Apple Developer now has the explicit App ID Draftly with iCloud and push enabled.
It uses the existing container. The profile `Draftly Mac and VM 2026-10-21`
covers both registered devices and existing development certificates. It expires
on 21 October 2027. The account name and membership are unchanged.

Build scripts accept `DRAFTLY_BUILD_OUTPUT` for isolated outputs and
`DRAFTLY_PROVISIONING_PROFILE` for an installed manual profile. Profile and style
settings apply to the app target, not package resource bundles. QA mode keeps its
own bundle ID, container and Info.plist under either signing mode. The signing
checker can require an expected bundle ID, team and container.

## Automated checks

- Before changes: 630 core methods and 531 app methods passed.
- After changes: 630 core methods and 539 app methods passed through the checked
  runner. The eight new migration methods include parameterized write failures.
- Python: 66 tests passed, including five build-script tests and nine signing
  checks. The first Python run used an interpreter without Pillow. The complete
  run used the Homebrew interpreter with Pillow installed.
- Migration tests cover unknown fields, Unicode, binary values, destination
  precedence, registered-default exclusion, repeat runs, missing source, failed
  reads/writes, read-back failure, retry and QA exclusion. They use neutral domains.
- Build-script tests use fake commands and temporary paths. They do not build,
  sign, provision or open a real app.
- The local Debug build and manual signed universal Release build passed. Both
  used isolated output directories. The signed package and installed copy passed
  deep signature and expected-identity checks. Their embedded profile covers two
  devices. No notarization or Developer ID claim is made.

## Verified in use

A coherent SQLite backup was made before opening the habitual library. The
current LibraryStore opened this copy with seed data disabled. All 37 generic
records stayed identical: five notes, fourteen revisions, six actions, eleven
execution records and one access record. A full backup was also saved locally.
Copies are under `~/Library/Application Support/Draftly/IdentityMigration-2026-10-21`.
These contain user data. They are outside Git and excluded from build cleanup.
Legacy local, personal and iCloud app packages are preserved as verified ZIP
archives in the LegacyPackages subfolder. Their extracted file hashes match the
original packages. The executable copies were moved to Trash after validation,
so they do not publish duplicate Services. Legacy App IDs and profiles remain.
Do not run old and new packages against the same library at the same time.

The original preference domain had three explicit keys. It stays unchanged.
The installed app has the migration marker and all three keys. Capture text and
recent draft IDs match the preserved values. Window-frame preferences can change
when the native app opens or restores a window. Their current value is not a
content-conservation check.

A signed temporary app used the new identity, existing container and a new empty
local store, with seed data disabled. It downloaded two historical neutral notes
and eight versions. No library file was copied into this receiver. This proves
server access with the new identity, not the complete two-client sync matrix.

The Release was installed at `~/Applications/Draftly.app` after conservation and
signature checks. The app opened all original local drafts, received the remote
records and reported a completed iCloud upload in Settings. A read-only comparison
confirmed that all original 37 records were still present without changes.
macOS resolves `draftly://` to the installed app. The user opened the neutral
historical draft through its URL and confirmed the expected draft in Draftly.
Computer Use could not trigger that protocol because browser policy blocks it.
TextEdit showed exactly one Capture to Draftly service and one Capture to Draftly
with Options service after old package registrations were retired. The neutral
TextEdit document was saved to a temporary path and moved to recoverable Trash.
Neither capture service was invoked in this registration check.

## Remaining checks and limits

Keychain authorization, privacy permissions and bookmark resolution under the new
signed identity need separate native checks. Values and entries were preserved;
no private credentials were read, exported or logged. The app may request new
permissions. Launch at login remains unavailable in the current installation;
this is existing functional backlog, not a completed migration capability.

The profile covers the VM, but this delivery does not claim a new VM installation
or repeat the full sync matrix. Offline acceptance remains deferred. The complete
Mac cloning plan stays open. Resume at the Workspace per-view sort mismatch in
`docs/refactoring-ui-2026-10-21.md`, unless the user changes that priority.
