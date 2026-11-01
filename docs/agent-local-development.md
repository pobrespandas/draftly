# Local agent transport development

This is a developer guide for unfinished agent access. The released app has no
Agents setup screen or published endpoint yet. Do not treat the tests below as
permission to connect to a personal library.

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
The current host implements eight read operations. Resources use scoped draft
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
assembly; this is not signed installation acceptance.
Mutations, receipts, native-effect enforcement and the remaining operation families
are separate unfinished work. Remote access remains a future stage.

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
