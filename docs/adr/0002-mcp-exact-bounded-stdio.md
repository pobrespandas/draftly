# Keep MCP bounded and preserve exact domain JSON

Use the official Swift MCP SDK 0.12.1 for protocol dispatch, with the selected
2025-11-25 baseline. Use a bounded stdio transport around it. The SDK's standard
stdio reader accumulates a line without a size limit. Its Value type represents
noninteger numbers as Double. Those choices do not meet Draftly's input budget
or exact JSON parameter contract.

Named tools accept typed parameters. They also accept parametersJSON, an exact
JSON object string, instead of typed parameters. Both forms produce the same
AgentRequest for the same named operation. Neither form can choose another
operation, library or grant. Typed numbers that would change during SDK decoding
are rejected before dispatch with instructions to use the exact form. Never
round them silently. Resource data and tool responses use JSON text rather than
lossy SDK structured values. High-precision values in a host schema must also
round trip before that schema can be advertised.

The transport bounds line size, buffered messages, active requests and their
input bytes. Responses remain active until their output write completes. Duplicate
active request IDs cannot replace pending work. Batch messages are rejected in
this selected protocol profile. Do not claim complete compatibility with every
older version that the SDK can negotiate. Check those versions separately before
expanding the supported profile. No experimental task feature, sampling, client
elicitation or HTTP server is required by this adapter.

A shared AgentHelperConnection serializes host requests and retains one Unix
session for cursor ownership. A status heartbeat keeps the idle session alive;
it does not extend a grant or replay an operation. New work after a connection
failure requires a new request. Long-running mutation/control routes still need
their operation-registry acceptance before exposure.

The SDK remains pinned. Do not replace its protocol server with a custom JSON-RPC
server. The custom transport enforces local limits; application handlers remain
the authority for permission, target resolution and effects.

## Sources checked on 1 November 2026

- [Pinned Swift SDK](https://github.com/modelcontextprotocol/swift-sdk/tree/0.12.1)
- [SDK Value](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/Sources/MCP/Base/Value.swift)
- [SDK stdio reader](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/Sources/MCP/Base/Transports/StdioTransport.swift)
- [SDK protocol versions](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/Sources/MCP/Base/Versioning.swift)
- [Protocol version changes](https://ruby.sdk.modelcontextprotocol.io/protocol-versions/)

Real SDK clients over pipes and the real Unix bridge are required test evidence.
These tests do not prove human pairing, provisioned Keychain access, helper
installation or signed updates. Keep those checks separate before activation.
