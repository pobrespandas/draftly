# Agent connection Settings

Read this guide when changing the human review or management interface. For the
socket protocol and helper commands, use [local development](agent-local-development.md).
This interface is enabled in isolated agent QA. Normal app startup remains
gated. Read [current readiness](agents-ai-readiness.md) before reporting closure.

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
Normal startup does not provide that model yet. Signed isolated QA has verified
app/helper identity, Keychain sharing, local discovery, limited reads, revocation,
and shutdown. Normal startup still requires verified lock observation and final
distribution acceptance. Keep each gate separate.

The model delegates enable and disable to the host. That command owns listener
startup and shutdown; the view does not create a broker. The model checks the
stored and effective enable state after the command. A no-op cannot report a
successful change. The operation transport cannot call these human-only methods.

Recent activity, Stop Work, client configuration export, and native operation
reviews are connected to the QA host. Their installed acceptance differs by
path. The latest QA verified idle Stop Work and revocation of an open MCP read
session. Active-operation Stop Work remains open. Earlier effect-review evidence
is recorded in the [operation checkpoint](agent-operation-checkpoint.md).
A displayed active grant alone is not proof of installed-client acceptance.

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
in Git. The normal Settings tab and full operation access still need acceptance.
Use the current readiness record for later signed pairing and restart evidence.


## Chat access consent

Chat Console creates its own limited connection after native confirmation.
The scope follows the current editor draft and its window, not every selected
row in the draft list. Reading and editing are separate choices. The confirmation
states that approved content can go to the selected ChatGPT account.

The current grant lasts 15 minutes. Account or context changes, another
conversation, disconnect, and chat closure end the session. Normal disconnect
revokes and cleans up its connection. Existing Settings revocation invalidates
the chat without a second revocation transaction. The host suspends chat access
with its other sessions. Storage cleanup errors remain visible.

The signed QA accepted a read grant and a real ChatGPT read. It did not accept
editing, actual expiry, or Stop Work during an active operation. See the
[current evidence and pending cases](agents-ai-readiness.md#status-and-evidence).
