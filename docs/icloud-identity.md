# iCloud display identity

## Target

The iCloud storage entry should show Draftly and its app icon. Keep the existing
container `iCloud.com.andrestobelem.draftly`, private records, app identifier,
team, signing profiles, and distribution method.

## Observed on 31 October 2026

- The signed app already declares display name Draftly and icon file Draftly.
- Apple Developer listed the container description as
  `iCloud com andrestobelem draftly`. It was changed to Draftly. The identifier
  stayed unchanged, and the saved list showed Draftly afterward.
- System Settings was closed and reopened at Manage Storage. Its entry still
  showed `draftly` and a generic icon. The portal description change therefore
  does not establish that the user-visible identity is fixed.
- CloudKit Console exposes container visibility, database/schema controls,
  sharing fallback, tokens, and permissions. The inspected pages did not offer
  a storage icon control. No schema, permissions, records, or visibility changed.
- Before this investigation, App Store Connect had no app record. It showed an updated
  Developer Program agreement that requires the account holder's review.
  No agreement was accepted by the agent.

## Private-record investigation

The user authorized investigating a private App Store Connect record, without
publishing or enabling TestFlight. Creation was attempted with macOS, name
Draftly, and the existing `com.pobrespandas.draftly` identifier. Apple rejected
it because that app name is already in use. No app record was created.

The user then authorized Draftly by Pobrespandas for only the private record.
Apple created record `6829288536` with the existing app identifier. It remains
in preparation for submission. Its publication setting was changed to manual
and saved. No build was uploaded, no review was requested, and TestFlight was
not enabled. The installed app name and bundle identifier were not changed.
The default App Store version field is 1.0; it is not the public DMG version.

The general app page has no direct icon upload control. Apple's [app icon
guide](https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon)
says App Store Connect receives the icon from an uploaded build. This does not
prove that an uploaded build would correct the CloudKit storage entry. Do not
request new signing certificates or upload a build based on that hypothesis.

The user questioned the private-record route. Investigation now focuses on
how macOS obtains storage-entry metadata for Developer ID apps. The installed
0.1.1 app has the correct display name and its Draftly.icns resource. Apple's
CKTool JS 1.3.2 exposes container name and optional imageUrl in its response;
the inspected base API exposes getContainers and getTeams, not a setter for
that image. The local cktool command list also has no branding command.
No authorization token was generated or credential used for this inspection.

The [Info.plist reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html)
defines NSUbiquitousContainerName for the iCloud Drive name. That is not proof
that it controls this CloudKit storage entry. No iCloud Documents capability,
entitlement, or speculative metadata key was added.

## Acceptance

After any confirmed metadata change, reopen System Settings and verify both
the displayed name and icon. Portal success alone is insufficient. Keep this
acceptance separate from CloudKit synchronization and app distribution.
The user accepted the cosmetic difference for now. On 31 October, the user
explicitly authorized permanent deletion of both `draftly` and `cloudqa` data
from all synchronized devices. Both system confirmation sequences completed.
After reopening Manage Storage, `draftly` was absent. `cloudqa` still showed
129.1 KB. Its deletion is therefore requested, but not verified. Do not claim
that both entries are gone. Other apps, including Drafts, were not changed.
An active client can create new data later; this operation does not uninstall
apps or delete their local libraries.
