# Local agent transport development

This is a developer guide for unfinished agent access. The released app has no
Agents setup screen or published endpoint yet. Do not treat the tests below as
permission to connect to a personal library.

## Current implementation checkpoint

The sections below record incremental development. Their statements about
missing handlers describe the checkpoint at which each section was written.
The current branch implements authenticated action and group reads, action
step defaults, shortcut validation, `actions.create`, `actions.update`,
`actions.duplicate`, `actions.move`, `actions.reorder`, `actionGroups.create`, and
`actionGroups.update`, `actionGroups.duplicate`, and `actionGroups.reorder`.
The branch also implements `workspaces.list`, `workspaces.get`,
`workspaces.query`, and `workspaces.update`. They enforce the connection's workspace scope. A workspace
is a saved query and does not grant access to the drafts that match it. The
query returns only drafts permitted by the same connection.
Updates require an expected version and a signed retry key. They commit the
workspace and receipt together. An update cannot change its position; ordering
needs a separate operation. Automated tests cover authorization, conflicts,
recovery, and revocation. A signed isolated run also updated one granted
workspace, repeated the request, and read back the saved value. The test
connection was revoked and the host stopped. The run did not validate an
installed release or screen-lock handling.
An optional native host wrapper can check each concrete invocation before
handoff and again after a result. If authority is lost after handoff, it reports
an unknown outcome. It also retains an uncertainty flag when the native host
throws after handoff, so an Action runner that converts errors to reports does
not erase that fact. Use one wrapper per execution. It does not authorize scripts, library access, templates,
or execution. The existing automation executor can now use the wrapper with
either a visible editor or a headless editor. Agent Action execution remains
unavailable. The executor has an opt-in target-draft editor scope that leaves
other pending editors alone and still detects conflicts on the target. The
default continues to cover the library for existing automation routes. This
scope does not restrict scripts or other library accesses. Runtime checks at
every bridge and an approval path are still required.
The Action runner also accepts an optional per-request script check before
dispatch, including asynchronous requests. Tests deny a draft update in both
visible and headless automation and in the synchronous script path. The check
is not itself an authorization policy. A separate draft policy checks current
grants, scope, and lock state for draft lookup and update. Guarded draft queries
filter their input before evaluation and fail closed if no filter is installed.
The policy rejects unclassified operations.
This incomplete policy is not connected to an agent executor. It does not yet
cover initial context, native Action steps, nested execution, final disposition,
or the full runtime contract.
The runner can also check each enabled Action step before it runs and check
completion before the final editor flush and disposition. Guarded failures do
not flush pending editor text as error cleanup. A filtered catalog limits
included Action resolution and is rechecked after asynchronous preparation.
Initial configuration under that filter requires a separate check before the
prompt and again before saving. Action execution remains unavailable until
these checks and the approval flow cover every path and are connected to the
agent service.
An initial Action authority checks the current connection, target draft,
Action scope, approved definition, and permissions for script, include,
configuration, and text insertion steps. Its completion check requires write
permission. Other step types remain unavailable in this policy. Initial
expansion uses only approved, unchanged Action definitions. A configuration
save can update the approved snapshot only for the allowed configuration fields.
If authority changes after the save, the outcome is uncertain and execution
stops. Runtime effect approval and durable operation recovery still need
integration.
The guarded native host can wait for a human decision before an asynchronous
effect. It checks current authority again after the decision. Synchronous calls
cannot wait and are denied when this decision is required. This hook is not yet
connected to the agent service.
Pending reviews retain normalized request fields and the resolved effect
snapshot for the app to present in Settings. Listing them refreshes their
validity first. Stop Work and permission changes invalidate reviews. Operation
routing can wait for a decision and recheck resolved effects before consuming
it. Cancellation withdraws a pending review. The agent service still needs to
route supported operations through this flow.
Native effect reviews bind the concrete operation and its parameters to a
single-use decision. Unclassified effects are denied. File writes and
unrestricted automation require library scope, and unrestricted automation
also requires its separate capability. The reviewed QA Action executor routes share, Open In and print steps through
this review flow. It checks the approved Action definitions,
target scope and current version snapshots again before the effect. The QA service exposes Action execution only when reviewed execution is enabled.
Installed acceptance covers share. Open In and print have headless coverage;
their installed review and cancellation checks remain pending.
The operation registry tracks ownership, waiting, cancellation and completion.
A cancellation request does not claim completion before the work returns.
Unexpected interruption after work starts has an unknown outcome. Transport
access to operation status and cancellation is connected. The reviewed QA host
also connects a private durable journal. Isolated installed restart checks are
recorded in [the operation checkpoint](agent-operation-checkpoint.md).
Within one host lifetime, repeated Action request IDs return the same operation.
Changed request fields fail with a version conflict. Removing a completed
operation does not permit its request ID to start work again. Request history
has a fixed limit and rejects new work when full. The journal reserves request
identity before execution. On reopen it returns saved results or marks pending
work as unknown. It never restarts a reserved request automatically.
For the guarded draft operations, the runner checks authority again before it
returns a result to the script. If authority changes after an update, it stops
the Action and records an unknown outcome even when the script catches the
error. The automation result and operation registry retain that state. Production
acceptance remains pending. Normal app activation remains disabled.
Creating an action requires access to the full library. Action changes use
an expected version, a signed retry key, and an atomic action and receipt
transaction. Recovery checks the current grant. A client with resource scope
cannot change a shortcut, because conflict checks use the entire catalog.
Moving an action requires access to both the action and its destination group.
It is a separate operation from `actions.update`.
Duplicating an action requires access to the full library. The copy has no
keyboard shortcut, so it cannot conflict with the original.
Creating a group requires full-library access. It rejects names and IDs that
collide with existing groups and preserves implicit group identifiers.
Editing a group also requires full-library access. A rename updates its actions
in the same transaction and preserves the IDs of other groups.
Duplicating a group requires full-library access. It copies the group's actions
without their keyboard shortcuts and commits the copies and receipt together.
Group reordering requires full-library access and a version for the complete
list. The native editor assigns a new order to each item in the affected list.
With full-library access, `actions.groups` returns an `orderVersion` for the
complete group list. Each cursor page checks that version and reports a conflict
if the list changed. Scoped reads do not return a full-library version.
The write validates the full target set and commits all orders and the receipt
together. Action reordering also requires full-library access and the complete
set of actions in one group. A full-library `actions.list`
request with a group ID and the `all` surface returns an order version for the
complete group. Its cursor pages reject concurrent changes.

The host does not start in the normal app. Agent access remains unavailable in
released builds. The signed helper and host still need a real installed-app
pairing and MCP session. Screen-lock behavior also needs a reliable initial
state and signed native checks. Protected-data notifications describe keybag
availability. They do not establish every graphical screen-lock transition.
Do not use them alone as proof that the screen is unlocked. See the
[Apple Developer Forums discussion](https://developer.apple.com/forums/thread/850327).
As an additional restriction, the app suspends agent sessions when protected
data becomes unavailable. It also rejects admission while protected data is
unavailable. Availability does not automatically resume a suspended session.

For isolated signed integration testing only, compile the app with
`DRAFTLY_AGENT_QA` and start it with both `--ui-testing` and
`--agent-isolated-qa`. This uses the temporary UI-test library and creates the
host for pairing. The test adapter does not detect screen lock. Do not use it
with personal data or ship a build that defines this flag. A successful test
does not validate lock behavior or normal startup.

The isolated host also connects reviewed Action execution. Its permission review
offers draft writes, editor writes and native effects. Each native effect still
requires an interactive request and a separate human review.

On 2 November, a Developer ID build with this flag and a signed embedded helper
opened an isolated library. Settings showed access disabled at startup. The
helper discovered the host and both sides showed the same pairing code. A
native sheet presented the permission review. The client received access to one
action. The signed helper read that action through CLI and MCP, while a request
for another action returned `not_found`. After revocation, the CLI returned
`permission_denied`. Stop work disabled the host. This did not test lock state,
an installed release, every client, or all supported operations. The signed
test build must exclude `get-task-allow`; the host rejects it.

A second isolated signed run granted action management for the test library.
The helper prepared and created a neutral action. Repeating the same request
returned the same receipt, and the catalog contained one copy. The activity
view showed the requests. The test connection was revoked and stopped.

Another isolated signed run created an action group and repeated the request.
The receipt was identical and the catalog contained one copy. The embedded helper
in that test came from an earlier build. It required an explicit request ID for
the read-only group listing. A release candidate must build the app and helper
from the same revision. A subsequent isolated run used matching signed builds:
CLI listed groups without a request ID, and MCP created a group and recovered
the same receipt without a duplicate. The test connection was revoked and
stopped. This was a QA app, not an installed release.

A later isolated run used matching signed builds to rename a group through the
CLI. Its 18 actions moved to the new name. All five group IDs stayed the same.
Repeating the request returned the same receipt. A separate run read an empty
test library, revoked the connection, and received `permission_denied` on the
next CLI request. Both test hosts were stopped. These checks do not inspect the
Keychain item separately or verify screen lock or an installed release.

Another isolated run used matching signed builds to duplicate a group with 18
actions through the CLI. The copies had new action IDs. A repeated request
returned the same receipt, and the library contained one copied group. The
connection was revoked and the test host was stopped.

An isolated signed CLI session read all five groups, reversed their order, and
recovered the same five resource receipts on retry. The connection was revoked
and the host stopped. Separate CLI invocations do not share a cursor session.
A later isolated MCP session read five groups across three pages and received
the same order version on every page. The test connection was then revoked.
Changes between pages have automated coverage.

A signed isolated CLI run read a complete group, reversed its 18 actions, and
received the same 18 resource receipts on retry. The connection was revoked
and the test host stopped. This did not test a release installation.

A signed isolated run granted access to one of two neutral workspaces. CLI
listing and detail returned the granted workspace; the other returned not found.
The first helper required explicit request IDs. A later signed run verified
the corrected read-only contract without explicit IDs and confirmed the same
resource boundary. Both test connections were revoked and their hosts stopped.

A signed isolated run also tested a workspace query with access to the workspace
and two of three drafts. The result contained the permitted matching draft. It
excluded a permitted nonmatching draft and a matching draft outside the grant.
A direct read of the excluded draft returned not found. The test connection was
revoked and the host stopped. This run used a test-only unlocked session and
does not validate screen lock handling or an installed release.

## Current components

- AgentContracts owns the request, response and authentication envelopes.
- AgentLocalSecurity owns credential access, process identity and private-file
  policy. It does not depend on the library or the application.
- AgentLocalTransport owns Unix sockets, bounded frames and the local client.
- AgentMCP maps shared operation metadata to the pinned official MCP SDK.
- AgentSocketBroker connects authenticated socket sessions to AgentCommandService.
- AgentEditorRegistry projects pending editor text for an explicitly bound library.
- draftly-agent is the helper executable. It imports no Core Data or app model.

The broker is not started by any app route. Its constructor rejects disabled or
locked access. Tests explicitly create it with an in-memory library and fake
credentials. Real process-signature checks are replaced only inside those tests.

## Session state during startup

The native host must fail closed until it has a reliable unlocked-session state.
AppKit workspace session notifications describe switching user sessions. They do
not establish the screen-lock state or a safe initial value. Register workspace
notifications on `NSWorkspace.shared.notificationCenter`. Validate screen lock,
unlock, session switching, and startup while locked in signed native QA before
using these signals to resume a broker. An uncertain state must deny access.
See [Apple's session notification documentation](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification).

## Build the helper

Run `swift build --product draftly-agent`. Use `swift build --show-bin-path` to
find the output directory. The executable supports `--help` and `--version`.
An unsigned build rejects credential access. It does not ask for a password or
fall back to another credential store.

The JSON command is:

```text
draftly-agent json --connection APPROVED_UUID --socket ABSOLUTE_SOCKET_PATH < request.json
```

This command requires the signed setup that is still pending. Explicit socket
access remains supported. For a stable destination, replace --socket with:

```text
draftly-agent json --connection APPROVED_UUID --library LIBRARY_UUID < request.json
```

Use the device-local libraryID returned by discover. It is not a draft ID or a
Core Data store UUID. For an isolated library, add --state-parent followed by its
absolute parent directory. The same destination arguments work with status,
capabilities, call, mcp and connect. Parsing keeps paths with spaces and Unicode.

The helper resolves that exact library on each new physical connection. A missing
host returns unavailable; it never chooses another available library. Unsafe or
corrupt state returns its error without repair. Bound pairing and authentication
also check the actual server library. There is no fallback to an unbound handshake.
A lost connection does not replay the failed operation. A later explicit request
can resolve a new publication. Automatic app startup remains future work.

Input is one bounded JSON request, terminated by end-of-file. For example:

```json
{"apiVersion":1,"requestID":"11111111-1111-4111-8111-111111111111","operation":"server.status","targets":[],"parameters":{}}
```

The helper fills a missing libraryID from the authenticated host. It preserves an
explicit libraryID, which the app must check. Output is one JSON response. A
transport/setup or operation failure produces an error code and a nonzero status:
2 for invalid input, 3 for authorization, 4 for conflicts or busy, 5 for an
unavailable capability, and 1 for other failures. A result or accepted operation returns status 0;
accepted does not mean the operation has finished. Credentials are never command
arguments, input fields, configuration or log output.

The helper also supports status, capabilities, call OPERATION and mcp. The call
command reads a tool argument object from stdin. MCP uses newline-delimited
JSON-RPC over stdio and the official Swift SDK 0.12.1. Its selected protocol
baseline is 2025-11-25. Batches are rejected in this profile.

MCP advertises only available operations with granted capabilities and schemas.
The host advertises only its connected handlers. Isolated QA also connects
reviewed Action execution. Resources use scoped draft
pages and opaque cursors. The draftly_review_draft prompt reads an authorized
draft; it does not mutate it. Draft content remains untrusted data.

Tool arguments use targets and parameters. Use parametersJSON, an exact JSON
object string, instead of parameters when a decimal cannot survive SDK decoding.
The two forms are mutually exclusive. Non-read operations require an explicit
requestID. Neither form selects another operation, library or grant. Responses
contain exact JSON text. See [ADR 0002](adr/0002-mcp-exact-bounded-stdio.md).

AgentHelperConnection serializes requests and retains the session for cursors.
Its heartbeat keeps the socket alive without extending authority. Failed work is
not replayed. Revocation closes the host client. Pipe input has an eight-MiB line
limit, bounded buffering and at most 16 active requests. Output completion releases
an active slot. No remote listener, daemon, global symlink or client configuration
is installed.

## Private wire protocol

Both ends require the current user's UID and verify the peer's running code from
a kernel audit token. The helper trusts the app identity; the app trusts the helper
identity. A PID, claimed name or filesystem path is not proof of identity.
Verification occurs before a credential is sent or accepted.

Each frame has a four-byte unsigned big-endian payload length and UTF-8 JSON.
Empty frames and frames above eight MiB are invalid. Authentication frames have
a separate 1024-byte limit. Hello contains apiVersion, connectionID, the
32-byte credential and an optional expectedLibraryID. Welcome contains either
libraryID or an error, never a session handle. The server keeps that handle
privately and checks current authority on
every request. The client rejects replies for another request ID.

A listener creates a new random directory under a trusted user-owned temporary
parent. Directory mode is 0700; socket mode is 0600. The shared private-file policy
rejects unsafe owners, modes, links and extended allow ACLs. Cleanup checks the
owned inode and never removes unrelated stale endpoints. AgentHostLease provides
single-owner coordination. The private locator holds discovery hints only.

Socket I/O runs on bounded worker queues, not MainActor. A broker admits at most
eight client connections. Authentication has a 15-second deadline; normal frames
have a 30-second deadline. Close and task cancellation interrupt pending I/O.
Descriptor borrowing prevents reuse during a pending operation. The broker closes
sessions and removes its endpoint when stopped or destroyed.

## Validation and remaining acceptance

The isolated host can receive an AgentEditorRegistry built from that same
LibraryStore and a provider of live WindowModels. Call refreshMembership at
window registration and removal, including when no agent request is active.
This records a window opened, edited and closed between two reads. A read also
refreshes the supplied models, but it cannot recover missed lifecycle events.
Current draft reads then use
pending text without saving or touching selection, focus or Undo. A conflicting
pair of dirty editors returns editor_conflict. Search and sorting use projected
text, after scope filtering. Historical revisions remain stored snapshots.
Text is compared with the editor's acknowledged baseline by exact code units.
The UI dirty flag can lag that text change; it is not the only pending-text test.
Per-draft generations detect changes between reads, including edit and revert;
selection changes and activity in other drafts do not affect the token.

For application assembly, use AppController.agentEditorRegistry(for:). It checks
the current library, caches one instance and supplies the actual registered
models. Its registration/removal paths refresh membership. Library changes and
controller release invalidate the old registry. The factory is lazy; normal
startup does not create a listener or enable permissions by requesting it.
Before activation, connect host shutdown to application context changes, verify
the lifecycle in native use and complete system-lock and signed-helper acceptance.
Editor mutations remain unfinished.

Headless tests use real local sockets and temporary files, fake credentials and
in-memory libraries. They cover framing, limits, timeouts, cancellation, scoped
reads, revocation, peer rejection and cleanup. They do not request system
permissions or read personal data.

Complete signed app/helper provisioning and packaging, real Keychain sharing,
human pairing and management, live editor and lock notifications before enabling
normal app access. Host identity and publication are implemented in the isolated
assembly. The installed isolated checks in
[the operation checkpoint](agent-operation-checkpoint.md) verify one signed
app/helper path. They do not establish normal startup or screen-lock behavior.
Remaining operations and durable execution recovery are unfinished. Remote
access to Draftly is outside the current scope.

For the credential/profile decision, read
[ADR 0001](adr/0001-agent-device-keychain.md). Apple Security's public SecCode.h
provides kSecGuestAttributeAudit. The SDK sys/un.h provides LOCAL_PEERTOKEN.
[Apple's Security source](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/SecCode.cpp)
explains why audit-token lookup replaces PID-based lookup.

Real SDK client/server tests use owned pipes and the Unix bridge. They cover
concurrent discovery, scoped resource pages, UTF-16 reads, review prompts,
revocation, exact decimals, duplicate IDs, oversized input and broken output.
A compiled unsigned helper completed MCP initialization, refused private access,
closed cleanly on EOF and rejected oversized input with exit status 2. These
checks do not prove signed helper installation or human pairing.


## Pairing lifecycle integration

AgentPairingCoordinator supports the human setup flow through the private socket
handshake. It is not an MCP tool. The broker verifies the signed helper before
request().
Show the comparison code and treat the client name as an untrusted label. Resolve
selected resource IDs from the current library, then prepare a human review.
Approve with that review ID and the displayed code. Replacing a review invalidates
its old ID. A saved query must first become a visible, fixed selection of IDs.

Poll state without creating credentials. Human denial, caller cancellation,
five-minute expiry and lifecycle invalidation are terminal. On lock, disable,
library closure or service restart, invalidate pending decisions. A failed
persistence attempt requires a new challenge; do not retry the same approval.
Signed packaging, setup UI and normal app startup remain unfinished.


## Pairing command and wire protocol

The helper supports this setup command:

```text
draftly-agent connect --name CLIENT_NAME --socket ABSOLUTE_SOCKET_PATH
```

The current executable requires signed provisioning before it can use this route.
It validates its own identity, verifies the app peer and sends a bounded pairing
introduction. It writes a comparison code to stderr. The person must review the
request in Draftly; the command cannot approve itself. After human approval,
stdout contains a pairing reply with the connection UUID. Configure subsequent
commands with that UUID. The helper obtains its credential separately from
Keychain. The pairing response never contains that credential or a library grant.
The terminal reply is pairing history, not proof of current authorization.

The app broker accepts either the existing credential introduction or a distinct
pairing introduction. Pairing frames have a 4096-byte budget and strict keys.
The challenge response contains pairingID, a comparison code and expiresAt in
Unix seconds. A bound introduction also carries expectedLibraryID; its challenge
must acknowledge the same libraryID before the CLI displays the code. An absent
expectation keeps the legacy message shape. Invalid or null IDs are rejected.
A control frame contains only apiVersion, pairingID and poll or
cancel. A client cannot query another conversation's ID. The initial and each
subsequent frame has a 15-second I/O deadline. Disconnect cancels pending work.
At most two pairing waits use the broker's eight client slots.

AgentPairingClient owns the decision wait. The CLI uses its asynchronous
half-second polling with a five-minute deadline.
It returns the approved UUID once, or the existing error exit category for denial,
cancellation, expiry, invalidation or failure. Cancel after completed approval
reports that completed approval; it does not claim that the grant was revoked.
If approval wins the race with deadline cancellation, the client returns the
completed approval. A timeout is reported only when cancellation won while the
request was still pending. Stopping the broker invalidates pending decisions and
closes their channels.

Headless tests cover real socket pairing, scoped normal authentication after
approval, no credential reads while pending, denial, expiry, lock, disabled access,
failed persistence, cross-conversation rejection, capacity, disconnect and broker
destruction. Decoder tests cover authority injection, malformed replies and frame
limits. The compiled unsigned helper passes help and invalid-input checks and
refuses pairing before credential access. This is not signed-use acceptance.


For human review controls, editing copies and the isolated native preview, use
[Agent connection Settings](agent-connections-ui.md). The normal app still needs
its host setup before it supplies that Settings model or starts the broker.


## Local host ownership

Use AgentLocalHost to assemble the loaded library, lease, registry, service,
pairing coordinator and broker. It supplies the same owner validator to both
admission paths and private metadata access. Construction never listens. Use
explicit lifecycle commands to resume, suspend and close it. Close before a
library change or app shutdown; a locator is not proof of ownership.

Normal AppController startup still needs editor and lock adapters and
a provisioned signed helper. Keep it disconnected until those checks pass.
In-memory credential and signature substitutes belong only in test fixtures and
the isolated manual preview. Assembly tests do not prove signed acceptance.

The private binding uses the actual store parent and a versioned identity file.
Copies and replacements do not inherit grants. Failed record decoding never
silently creates a replacement. A deleted identity cannot bypass an active owner.
See [ADR 0003](adr/0003-local-agent-library-binding.md) for the identity rules.
Agent state paths must also remain protected from future file-write tools; a
folder grant must not become a way to edit grants or bypass the app writer.


## Discover a local host

The helper supports `discover` and `discover --state-parent ABSOLUTE_PATH`.
The default parent is the normal Draftly Application Support folder. Use a
neutral library folder for isolated QA. The helper verifies its own provisioned
identity before reading. An absent catalog returns an empty JSON array.

Each result contains libraryID, epochID and socketPath. The host publishes no
credentials or business data there. Results can be stale. A successful discovery
is not proof that a host is live or authorized. Use --library UUID to select that
exact library, or keep explicit --socket access. Both routes verify the signed
peer and authenticate through the credential route. The library route also
checks the server's library acknowledgement. The helper can export a copyable stdio configuration as described below.
Automatic app startup is not implemented yet.

The host withdraws only its own epoch. A failed withdrawal leaves transport
stopped and records locatorCleanupError. Another explicit suspend or close can
retry that exact cleanup without removing a later owner. Readers do not remove
stale records or sockets. The private catalog is excluded from library backups.

## Export client configuration

Run `draftly-agent configuration --connection UUID --library UUID` with the
absolute helper executable path. Add `--state-parent ABSOLUTE_PATH` only for an
isolated library parent. The command prints an MCP `mcpServers` JSON object.
Copy or merge that object into the client configuration that you choose.

The command uses its own executable path. Export from the final bundled helper;
a development build path can disappear. The server key includes the connection
UUID so distinct connections can coexist. The command never installs client
configuration, starts the app, reads Keychain, or grants access. It contains
routing identifiers, not a credential. Successful export does not prove that the
helper is provisioned or that the connection is live. Pair and approve access in
Draftly before using it. Normal app activation remains pending.

## Prepare the signed helper wrapper

Use `scripts/package-agent-helper.py --help` for the isolated packaging command.
Supply the compiled executable, a profile for `com.pobrespandas.draftly.agent`,
a signing identity, version, build and a new output directory. The output parent
must exist. The tool creates `DraftlyAgent.app` under that new directory. It
never changes the installed app or enables access.

The tool checks the helper identity, team, expiry and allowed Keychain group
before creating output. It signs with hardened runtime, verifies the exact Apple
code requirement and entitlements, and checks that the profile permits the leaf
certificate. A failure leaves the isolated candidate for inspection. Use a new
output path for another attempt; an existing candidate is never replaced.

This prepares a wrapper, not a public release. The enclosing app still needs its
own Keychain entitlement and a valid profile. Verify actual app/helper sharing,
locked-session behavior, embedding, outer signing and notarization before normal
activation. A local build or mocked signing test proves none of those checks.

## Retry key envelope

Requests can carry an optional `retryKey` beside `expectedVersion`. The field
is separate from operation parameters. Omitted keys remain compatible with
existing read requests. A supplied key must contain between one and 4096 UTF-8
bytes. The shared limit also applies to signed key verification.

Named tools expose this optional field for operations outside the read-only
catalog. CLI JSON and named-tool input preserve it. The local client keeps it
when it binds a request to the authenticated host library. This transport support
does not authorize a mutation or validate a signature.

Canonical request fingerprints exclude the retry key because the key signs
that request. Authorization and signed-key verification remain separate checks.
Service key issuance and guarded mutation dispatch are not implemented yet.
Do not treat transport support as an available write handler.

## Check real Keychain sharing

Use the [manual probe](../Tools/AgentKeychainProbe/README.md) when both signing
profiles are available. Its build command does not execute the probe. Keep the
signed exercise separate from automatic tests. The probe uses a new neutral
connection and checks cleanup. It does not query existing connections.

## Check a draft version before mutation

`AgentDraftReading.checkedSnapshot` checks an expected version with the same
version calculation used by draft reads. It returns both stored and projected
state. Stored changes, pending text changes and edit-then-revert generations
invalidate the prior version. Access dates do not. Divergent pending editors
produce `editor_conflict`; a missing draft produces `not_found`.

This internal check does not save, select or synchronize an editor. It does not
check a grant and does not reserve a snapshot across an `await`. A mutation
handler must check current authority and signed retry keys, then check the live
version immediately before mutation. Editor synchronization, Undo, receipts and
recovery remain required before enabling that handler.

## Prepared editor commands

The connected `editor.setSelection` and `editor.replaceRange` handlers require
an explicit window, access to its current draft, editor and draft write
capabilities, and a current editor version. Prepare a retry key through
`mutations.prepare`. Preparation does not edit text or move the cursor. Ranges
use UTF-16 offsets and cannot split a surrogate pair.

Execution checks authority and window generation. An attached native view must
be synchronized and must not have marked text. Range replacement also requires
the native edit callback and rejects running Actions. It marks edits pending
before script-edit synchronization registers Undo. Normal autosave owns the
stored change. Selection alone does not save text or invoke Undo.
Neither command changes focus.

If a callback interrupts the command, the receipt stays unknown. Text already
applied remains pending. Repeated confirmed requests return their prior result
without applying the edit or selection again. Receipts bind the request ID,
parameters and original grant. Changed requests and grants cannot recover them.
Receipts are bounded and belong to the current host lifetime. A new host has new
keys and window identities. Offscreen native Undo/Redo checks passed. Installed
selection and range acceptance and the remaining editor mutations are pending.

## Coordinate a stored draft mutation

Use `AgentEditorRegistry.synchronizeMutation` after current authorization and
expected-version checks. It protects matching editor projections while the
caller commits, then synchronizes the committed note through the existing Undo
callback. It does not select or focus a window. Unconfirmed tag input remains
editable; clean tag fields refresh from the saved note.

The synchronous commit closure receives the candidate note and a reserved
editor generation. It must return the normalized, committed note. The caller
still owns durable storage and an atomic mutation receipt. The registry keeps
that generation stable through its own synchronization and acknowledgement.
Actual callback edits and navigation still invalidate it.

A storage failure retains prior pending text and Undo. If no external state
changed, it also restores the prior generation for a safe retry. A callback
conflict after storage does not roll back committed data. Consult the durable
receipt before retrying; never report rollback based only on a thrown error.

This internal coordination is not an exposed write handler. Service key
issuance, signed-key checks, receipts and recovery remain separate integration
work. No normal application startup enables agent writes.

## Existing-draft update storage

`AgentDraftWriting.update` combines admission checks, a current signed retry key,
the read version, editor coordination and an atomic note/receipt transaction. It
supports every field in the existing `drafts.update` schema. Explicit modified
dates use the package-only preservation option; other updates keep the existing
automatic modification-date rule. Omitted script metadata remains unchanged.

Receipt recovery checks current admission and authority before returning a
previous result. It does not apply the mutation or add Undo again. A removed
grant or resource scope cannot read an old receipt. Before the final commit,
the writer rechecks admission, the key, execution exclusion and the reserved
editor state. A failed gate rolls back the note, revisions and receipt together.

Read summaries and receipt versions use the same pure encoding. The receipt
uses normalized stored data and the editor generation reserved for that commit.
Subsequent human edits can invalidate that version; recovery still returns the
original committed receipt without overwriting newer pending text.

This is an internal writer. Service key issuance, CLI/MCP routing and normal
activation are not connected yet. Creation needs task-owned target scope; it is
not implemented by this existing-draft path. Do not treat this storage check as
native sync, public release or completed agent access.

### Installed editor command check — 2 November 2026

The signed QA app and embedded helper at `e10eeaa` passed a local CLI check.
The isolated library contained two neutral drafts. The connection allowed draft
reads and writes and editor reads and writes for one draft and its window.
It did not allow the entire library.

`editor.setSelection` selected `café` after an emoji at UTF-16 offset 3 and
length 4. `editor.replaceRange` replaced that range with `té`. Native Undo
restored the original text and selection. Repeating the same request returned
the saved result without applying the change again. Native Redo still restored
the replacement. The editor read reported no pending changes after autosave.

After the user selected the excluded draft, `editor.get` returned `not_found`.
The excluded draft retained its text. Revocation then returned
`permission_denied`. Stop Work disabled access. QA quit normally, its exact
LaunchServices registration was removed, and the usual app reopened with its
10 drafts.

This check used CLI, not an external MCP client. It does not establish input
method composition support, durable editor receipts after restart, notarization,
or production screen-lock behavior. Normal agent access remains disabled.

### Installed print admission check — 2 November 2026

The signed app at `b828459` accepted a scoped MCP print request. The native
review showed the concrete print text, format and resource targets. Allow once
reached the print adapter, which rejected the catalog's `plainText` format
before showing a print sheet. The operation retained an unknown outcome and
was not replayed. No print job was submitted.

The adapter now accepts `plainText` as a text format, including case variants.
The focused regression passed 54 tests in three suites. Installed print-sheet
and cancellation acceptance remain pending on the corrected build. The QA
connection was revoked, Stop Work disabled access, and QA quit normally.

### Installed print and Open In cancellation — 2 November 2026

The signed corrected app at `9486d69` and its embedded helper passed the
installed MCP print review and cancellation check. Allow once opened the native
print sheet with one page. Cancel returned `cancelled` through `operations.get`.
The print effect was `failed`, not completed. No print job was submitted.

A new connection had access to the isolated QA library only. Through the CLI,
it prepared and created a neutral Open In Action. MCP execution then presented
a review with the file name and text. Allow once opened the native share picker
with `QA-neutral`, a 42-byte text document. Cancelling the picker returned
`cancelled` with a `shareFile` effect marked `failed`. No destination was chosen.
The earlier scoped print request also reached review, before the format fix.

The connection was revoked and Stop Work disabled access. QA quit, its exact
LaunchServices registration was removed, and the usual app reopened with its
10 drafts. These checks used the signed helper and a custom MCP probe. They do
not establish support for a named external client or production screen lock.

### Reviewed clipboard Action steps

The QA executor supports clipboard steps through the asynchronous native review
path. Replace reviews only the write. Append and prepend review the clipboard
read first, then review the resolved text before writing. A malformed read
stops the Action before any write. HTML and rich-text output review the rendered
HTML before the native clipboard conversion. Script clipboard calls remain
outside the permitted script API.

Each write requires `native.use`, the current Action and draft scope, an
interactive request and a single-use review. Failed writes stop following
steps. The effect journal distinguishes confirmed writes, failed writes and
unknown responses. Focused tests cover these paths. Installed clipboard review
and actual pasteboard acceptance remain pending. Normal access remains off.

### Installed clipboard write — 2 November 2026

The signed app at `fd55684` and embedded helper passed a scoped MCP Copy check.
The connection allowed only the source draft, its window and the Copy Action.
The review showed “Copy text to the clipboard” and the exact neutral text.
Technical details remained available in a collapsed disclosure.

Allow once returned a succeeded operation with one completed clipboard effect.
A native paste into a new temporary draft preserved the emoji and line break.
The original draft remained unchanged. The connection was revoked and Stop Work
turned access off. QA quit and its exact registration was removed.

This checks plain-text replacement. Installed append, prepend, formatted output
and denied clipboard-read behavior remain pending. No personal clipboard data
was read through the agent connection.

### Reviewed link Action steps

URL steps now suspend for a concrete native-effect review in the QA executor.
The review shows the final URL after template expansion and tag encoding.
The connection needs native permission and current Action and draft access.
Opening the URL requires a single-use decision. A rejected native result stops
following Action steps. The journal records confirmed handoff or an unknown
result. A completed handoff means macOS accepted the open request; it does not
prove that a destination loaded or completed its own effects.

Focused tests cover encoded Unicode destinations, rejection, changed authority,
and waiting for approval before native handoff. Installed URL acceptance remains
pending. Script URL calls are still outside the permitted script API.

Web links use native permission. Application URL schemes can start automation
outside Draftly. They also require `scripts.unrestricted` and library scope;
ordinary native permission cannot authorize them. The current QA Settings do
not offer unrestricted scripts, so these requests remain denied. Relative
URLs are invalid. JavaScript, data and local file URLs are denied before review.
Tests verify that application links cannot use the web-link permission path.

### Connected typed preference reads

`preferences.get` now reads the scalar device fields supported by
`AgentDevicePreferenceAccess` and the list fields supported by
`AgentListPreferenceAccess`. It requires `preferences.read`. The command reads
the app's defaults through an injected store; tests use a separate suite.
It returns the effective value, origin, override flag and opaque version tokens.
Invalid scalar overrides remain stored and return a null invalid reading.

A batch with an unsupported address returns unavailable without partial values.
Native preferences still need their read adapters connected. Update and reset remain unavailable. Schema descriptors describe the
contract, while operation availability describes the connected handlers.
Focused service tests cover permission denial, stable and changed tokens,
invalid overrides, list defaults, unsupported batches and locked admission.
Installed CLI and MCP acceptance for this handler remains pending.


Markdown option maps and command shortcuts now use the existing encoded read
adapter. Missing stores use their defaults. Malformed or wrongly typed stores
return an invalid reading without rewriting the source or unknown fields.
The default Workspace uses its resource-aware adapter. A stored reference needs
both `workspaces.read` and scope for that Workspace; otherwise it returns
`not_found` without disclosing the identifier. Focused service tests cover these
paths. Native installed acceptance and preference writes remain pending.


Syntax preference reads now require both `preferences.read` and
`appearance.read`. Built-in references resolve from the built-in definitions.
Installed references also require their syntax resource in the connection scope.
The resource picker includes installed syntaxes. The encoded adapter reads font,
layout, input, display, indentation and feature settings from their existing
stores. Inherited values use the registered global preference; invalid global
values reject the read. System-derived options retain a system origin and null
value until an override exists. No syntax or preference is changed by a read.
Focused service and settings tests cover permission denial, inheritance,
overrides, system values and installed-resource isolation. Installed CLI/MCP
acceptance for these syntax reads remains pending.
