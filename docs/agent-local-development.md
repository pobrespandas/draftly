# Local agent transport development

This is a developer guide for unfinished agent access. The released app has no
Agents setup screen or published endpoint yet. Do not treat the tests below as
permission to connect to a personal library.

## Current components

- AgentContracts owns the request, response and authentication envelopes.
- AgentLocalSecurity owns credential access, process identity and private-file
  policy. It does not depend on the library or the application.
- AgentLocalTransport owns Unix sockets, bounded frames and the local client.
- AgentSocketBroker connects authenticated socket sessions to AgentCommandService.
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

This command requires the signed setup that is still pending. The socket argument
is currently explicit; a private locator and automatic app startup remain future
work. Do not use this temporary path as permanent client configuration.

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

Only JSON mode exists in this unit. MCP stdio and the official SDK are still
pending. No remote listener, daemon, global symlink or client configuration is
installed.

## Private wire protocol

Both ends require the current user's UID and verify the peer's running code from
a kernel audit token. The helper trusts the app identity; the app trusts the helper
identity. A PID, claimed name or filesystem path is not proof of identity.
Verification occurs before a credential is sent or accepted.

Each frame has a four-byte unsigned big-endian payload length and UTF-8 JSON.
Empty frames and frames above eight MiB are invalid. Authentication frames have
a separate 1024-byte limit. Hello contains only apiVersion, connectionID and the
32-byte credential. Welcome contains either libraryID or an error, never a session
handle. The server keeps that handle privately and checks current authority on
every request. The client rejects replies for another request ID.

A listener creates a new random directory under a trusted user-owned temporary
parent. Directory mode is 0700; socket mode is 0600. The shared private-file policy
rejects unsafe owners, modes, links and extended allow ACLs. Cleanup checks the
owned inode and never removes unrelated stale endpoints. A stable locator and
single-broker-per-library coordination still need implementation.

Socket I/O runs on bounded worker queues, not MainActor. A broker admits at most
eight client connections. Authentication has a 15-second deadline; normal frames
have a 30-second deadline. Close and task cancellation interrupt pending I/O.
Descriptor borrowing prevents reuse during a pending operation. The broker closes
sessions and removes its endpoint when stopped or destroyed.

## Validation and remaining acceptance

Headless tests use real local sockets and temporary files, fake credentials and
in-memory libraries. They cover framing, limits, timeouts, cancellation, scoped
reads, revocation, peer rejection and cleanup. They do not request system
permissions or read personal data.

Complete signed app/helper provisioning and packaging, real Keychain sharing,
human pairing and management, stable host library identity, live editor and lock
notifications, locator publication and MCP before enabling normal app access.
Mutations, receipts, native-effect enforcement and the remaining operation families
are separate unfinished work. Remote access remains a future stage.

For the credential/profile decision, read
[ADR 0001](adr/0001-agent-device-keychain.md). Apple Security's public SecCode.h
provides kSecGuestAttributeAudit. The SDK sys/un.h provides LOCAL_PEERTOKEN.
[Apple's Security source](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/SecCode.cpp)
explains why audit-token lookup replaces PID-based lookup.
