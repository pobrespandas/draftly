# Agent connection Settings

Read this guide when changing the human review or management interface. For the
socket protocol and helper commands, use [local development](agent-local-development.md).
This interface is not yet enabled in normal app startup.

## Ownership and current behavior

AgentConnectionsSettingsModel connects the view to AgentConnectionRegistry and
AgentPairingCoordinator. It must use the same registry and library as the pairing
coordinator. Construction rejects a different authority owner or library.

The view edits AgentGrantEditingCopy. Cancel discards that copy without writing
metadata, creating a credential or approving a request. Existing grant edits
check the original grant ID before Save. A replacement grant invalidates an old
editing copy. Missing selected resource IDs stay visible and must resolve before
Save. A resource title is not its identity.

Pairing starts with selected IDs and read access. The person first reviews the
fixed permissions, IDs, name, expiry and renewal choice. Approve stays disabled
until the code comparison is checked. Changing the copy invalidates its review.
Deny ends a request. Cancel closes the form without accepting it.

The registry owns persistence, immediate blocking and credential cleanup.
Revocation updates the displayed record and disables editing. Failed cleanup is
reported per connection. A failed save keeps the editing copy. Recreating the
Settings model reads the serialized grant fields rather than writing defaults.

## Host integration still required

Settings displays the Agents tab only when AppController has a configured model.
Normal startup does not provide that model yet. The host must first finish signed
helper provisioning, real Keychain sharing, stable library identity, locator and
single-broker ownership, lock observation and shutdown behavior.

The model delegates enable and disable to the host. That command owns listener
startup and shutdown; the view does not create a broker. The model checks the
stored and effective enable state after the command. A no-op cannot report a
successful change. The operation transport cannot call these human-only methods.

Recent activity, Stop Work, client configuration export and native operation
reviews remain separate unfinished work. Do not add nonfunctional controls for
them. A displayed active grant is not proof that a signed client is installed or
that native operations have been accepted.

## Manual UI check

Run `scripts/preview-agent-settings.sh` after the headless tests finish. The
command builds a separate app and prints its path. It does not open a window.
Open that app explicitly for a manual session. It uses the production view and
commands with neutral metadata and credentials in memory. It starts no endpoint
and uses no Keychain adapter, personal library or system permission.

The preview includes a light/dark selector and a button to create neutral
requests. Neither control belongs to the released interface. Do not use the
preview as signed-client or persistent-storage acceptance.

The manual session on 1 November checked:

- Cancel discards a changed name and permission; reopening restores defaults.
- Review shows the exact selected permission and resource. Approve stays disabled
  until the comparison checkbox is set.
- Approving the neutral fixture adds its connection to the list.
- Save changes permissions and selected IDs; reopening shows the saved choices.
- Revoke shows Revoked immediately and disables Edit.
- Deny removes a pending request. Disabling access shows Paused.
- Resource filtering, Escape, scrolling and light/dark rendering work.
- Resource accessibility labels include title, kind and UUID. The initial view
  omitted the title; that defect was corrected and checked again.

The preview was closed normally. Its app was unregistered and moved to Trash;
its disposable preference domain was removed. No screenshots or raw logs belong
in Git. The normal Settings tab, signed pairing, restart with real local stores
and full operation access still need acceptance.
