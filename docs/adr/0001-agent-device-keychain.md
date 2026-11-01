# Use the data protection keychain for agent credentials

Draftly agent credentials use the macOS data protection keychain, a dedicated
access group and device-only, unlocked accessibility. This lets the app and its
signed helper share credentials without granting access to the existing Action
credential store. AgentLocalSecurity owns this integration; it has no library,
editor, UI or execution dependency.

Legacy file-based ACLs can name trusted programs without new provisioning.
However, Apple documents that the noninteractive query controls do not suppress
all legacy keychain prompts. Do not use that route or fall back to it after a
modern-keychain failure. Use LAContext.interactionNotAllowed for each operation.

The group is NM92LU2KKV.com.pobrespandas.draftly.agent-access. The app retains
com.pobrespandas.draftly; the future helper uses com.pobrespandas.draftly.agent.
Check the running code's Apple signature, team and identifier, then its exact
keychain group and unsafe debugging/injection entitlements. The OS must also
authorize the group through the provisioning profile. A stored credential does
not grant library access without a live connection grant.

Restricted entitlements need profiles. Package draftly-agent inside an app-like
wrapper so it can carry its own profile; a standalone executable has no place
for one. The intended bundled path is
Contents/Helpers/DraftlyAgent.app/Contents/MacOS/draftly-agent. Do not create a
login daemon or global command link. Configure and verify both signed profiles
before enabling pairing. This decision does not change any existing identity,
profile, entitlement, Keychain item or installed app.

Only the application adapter can create or remove an item. The helper adapter
can read its connection item. This is an application boundary, not protection
against compromised software that runs as the same user or code deliberately
signed by the team's signing authority. Credentials are not synchronized and do
not belong in backups, configuration, command arguments or logs.

## Sources checked on 1 November 2026

- [Apple: Keychain access groups](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
- [Apple: Data protection keychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)
- [Apple: Noninteractive authentication](https://developer.apple.com/documentation/security/ksecuseauthenticationuifail)
- [Apple: Distribution-signed macOS code](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
- [Apple: Helper provisioning](https://developer.apple.com/forums/thread/836816)
- [Apple Security source: SecItem.h](https://github.com/apple-oss-distributions/Security/blob/main/keychain/headers/SecItem.h)

The installed SDK SecCode.h states that dynamic SecCodeCheckValidity is secure
against changes to the process's file-system source. SecTask reads entitlements
from the current process; this avoids trusting a copied Info.plist or an on-disk
replacement as proof of current process authority.

## Acceptance still required

Headless tests inject SecItem calls. They can check query policy and error paths,
but cannot approve actual sharing, profile coverage, locked-keychain behavior or
updates between two signed helper versions. Complete those checks in an isolated
signed session before pairing or transport activation. Keep the previous app and
helper packages available for recovery.
