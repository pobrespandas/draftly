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
- App Store Connect has no app record in this account. It also shows an updated
  Developer Program agreement that requires the account holder's review.
  No agreement was accepted by the agent.

## Private-record investigation

The user authorized investigating a private App Store Connect record, without
publishing or enabling TestFlight. Creation was attempted with macOS, name
Draftly, and the existing `com.pobrespandas.draftly` identifier. Apple rejected
it because that app name is already in use. No app record was created.

The user was asked whether to use Draftly by Pobrespandas for only the private
record. Until that decision arrives, do not substitute another name. This
investigation has not established that a private record will fix iCloud's
storage name or icon. Do not describe it as a proven requirement or solution.
Do not add iCloud Documents entitlements or move records as a branding fix.

## Acceptance

After any confirmed metadata change, reopen System Settings and verify both
the displayed name and icon. Portal success alone is insufficient. Keep this
acceptance separate from CloudKit synchronization and app distribution.
The storage entry `cloudqa` is a separate test container; this investigation
did not delete it or its data.
