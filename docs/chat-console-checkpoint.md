# Chat Console checkpoint

## Direct ChatGPT connection

The direct connection is in progress on PR #105. The installed QA account sheet
uses direct ChatGPT OAuth. Real sign-in and restoration after full process exit
passed. The account model catalog and completed Responses worked in installed
QA. Native Stop removed a partial response, and the next request succeeded.
MCP login and authorized tools remain pending.

`ChatGPTAuthorization` creates a fresh state, nonce, and PKCE verifier. It
builds the official authorization request. Callback validation checks the
loopback address, port, path, state, and issued client ID. It rejects duplicate
security parameters. Returning sign-in cannot replace the registered client
ID. The code exchange uses the exact callback URI and form encoding.

`ChatGPTCredentialStore` keeps each complete credential record in one Keychain
item. Items do not synchronize. They use device-local, unlocked access.
Bundle identity separates installed QA from production. Failed updates do not
delete the old record or fall back to files. Tests use an injected backend;
they do not read an account or save real credentials.

`ChatGPTCallbackListener` starts on IPv4 loopback before the browser opens.
It accepts one validated callback. Invalid callbacks do not consume the
attempt. Requests, connection count, connection lifetime, and attempt lifetime
are bounded. Cancellation closes the listener and pending connections. Browser
replies contain no code or credential.

`ChatGPTIdentityVerifier` uses JWTKit 5.8.0 to verify RS256 signatures. It loads
the official discovery document and restricts JWKS to the official HTTPS host.
It selects the exact key ID and does not fall back to another key. It checks
issuer, audience, nonce, expiry, issue time, optional not-before time, authorized
presenter, and the selected account subject. Only validated claims become a
`ChatGPTIdentity`. Raw library errors do not reach the UI. Keys are cached for
ten minutes. Unknown key IDs can trigger a refresh at most once per 30 seconds.

`ChatGPTLoginService` joins the loopback callback, code exchange, identity
verification, and Keychain write. It persists a stable host ID before login.
Returning login uses the saved client and subject. Failed or cancelled work
does not replace the saved session. A pending issued client survives an expired
code in memory so a retry can reuse it. Starting a different registration clears
that pending client. Plan permissions come from granted scopes, not identity.
`ChatGPTHTTP` uses an ephemeral session without cookies or saved URL credentials.
It rejects redirects and bounds response size and duration. It does not log
requests, responses, codes, or tokens.

`ChatGPTAccountModel.shared` owns accounts across app windows. Preferences keep
only the host ID, registration IDs, and selected ID. Account details and tokens
stay in Keychain. A failed additional login keeps the previous active account.
The direct account sheet supports selection, login, cancellation, and sign-out.
Production console startup no longer initializes a Codex connection.

`ChatGPTProvider` loads the active account's visible models from the public API.
It sends structured history with `store: false` and `stream: true`. The bounded
SSE decoder handles UTF-8, comments, multiline data, and all line endings.
Only a completed response can enter saved history. Partial streams, refusal,
usage limits, stale responses, and unconnected tools do not count as success.
Account changes cancel active chat work and reject late catalog results. A
missing model does not silently select another provider.

The obsolete Codex account, process, and chat sources and their protocol
fixtures are removed. The direct provider tests replace their relevant chat
contracts. There is no Codex executable or app-server requirement for this path.

`ChatGPTSessionService` shares refresh work between callers. A device-local file
lock also excludes other owners of the same account. Before refresh, it saves
an uncertainty marker in Keychain. A lost response or failed rotated-token write
requires sign-in after restart; it does not repeat the old token automatically.
Successful refresh replaces credentials, scopes, and expiry together. Sign-out
blocks new requests, waits for pending rotation, attempts remote revocation,
and clears local tokens while retaining the registration. The UI reports when
remote revocation was not confirmed. Login commits use the same lock and reject
a returning session that changed while authorization was in progress.

Next steps:

1. Finish full CI and the remaining chat reliability checks.
2. Check account changes during real inference and multiple-window history.
3. Add installed acceptance for refresh and sign-out. Unit coverage is not
   proof of provider revocation or installed multi-account behavior.
4. Run full CI after removing the obsolete Codex paths. The prior macOS 26
   failure was in a removed process test; removal is not proof of green CI.
5. Require `response.completed` before reporting inference success.
6. Complete regression and CI validation.
7. Add authorized MCP tools through the existing permission and review rules.

Keep one account-session owner per installed app. Serialize refresh for each
renewable session. Console history merges saved conversations and message IDs before each write.
MainActor serializes these writes across app windows. A two-window regression
checks shared messages and separate conversations. Installed acceptance remains
pending. Window selection and active response state remain local to each window.
MCP login remains separate from provider login. MCP tools must use the existing
grant, review, cancellation, and revocation rules.

The full agents and AI goal also includes the remaining local operation
handlers, installed pairing and limited access, pause, Stop Work, revocation,
the signed helper, and complete installed CLI and MCP sessions. This checkpoint
does not replace that scope or establish its acceptance.

The earlier installed QA verified Codex-managed sign-in and persistence after
process exit. It did not verify inference. The restricted model process could
not read that saved session. Do not reuse those credentials for direct login.
Direct login needs a separate consent for Draftly.

The previous macOS 26 CI failure remains open. It concerns Codex process access
tests. Direct OAuth work does not establish that the existing CI failure is
fixed. Full regression, installed direct login, real inference, and tools
remain pending. Local agents remain disabled by default.

Local validation on 3 November 2026 passed seven focused authorization and
credential-store tests in serial mode. The unsigned native Debug build also
passed. These checks do not establish real OAuth or Keychain acceptance.

The callback follow-up passed eleven focused tests in serial mode. A real
loopback HTTP request with the wrong state received 400. The next valid request
received 200 and consumed the attempt. Cancellation and failed browser launch
completed without a pending waiter. HTTP parser checks rejected other hosts,
methods, duplicate Host fields, bodies, and ambiguous framing. The unsigned
native Debug build passed again. Provider login and inference remain untested.

The identity follow-up passed sixteen focused tests in serial mode. Test tokens
use temporary RSA keys and Security framework signatures. Cases cover valid
string and array audiences, false signatures, missing claims, wrong identity,
expiry, nonce, algorithms, critical headers, key rotation, refresh limits,
untrusted discovery, and duplicate keys. The first test build failed on a
test-only actor-isolation error. It passed after that error was corrected.
Two project-generator tests and the unsigned native Debug build passed. SwiftPM
and Xcode lockfiles resolve the same dependency versions. A public metadata
request confirmed the official issuer, JWKS URI, RS256 support, and revocation
endpoint. No user token was requested or read for this check.

The login-service follow-up passed twenty-two focused tests in serial mode.
Six transaction cases use an injected vault, authorization response, and token
exchange. They cover saved-session restoration, stable host identity, subject
mismatch, expired-code retry, late results after cancellation, denied plan
scope, and Keychain failure. The first test build failed on the fixture vault's
actor isolation. The corrected fixture passed. Two project-generator tests
and the unsigned native Debug build passed. These checks do not establish real
provider login, installed Keychain acceptance, refresh, sign-out, or inference.

The account-controls follow-up passed thirty-seven focused tests in serial
mode, including the existing console tests. New cases cover shared rotation,
durable uncertainty, revoked scopes, sign-out during rotation, remote revocation
failure, lease exclusion, symlink rejection, account restoration, and failed
additional login. A signed renewed ID token without a login nonce is accepted
only for the previously verified account. The first lifecycle test build failed
because a throwing read needed `try` inside `#require`. The corrected tests
passed. Two project-generator tests and the unsigned native Debug build passed.

Installed Direct Chat QA completed real authorization and showed Signed in.
It used a separate bundle identity, temporary library, and Keychain service.
QA quit through the app menu. A process check confirmed the old process exited.
The same installed binary reopened and showed Signed in without browser login.
The normal app and the older QA copies were not changed. The copy is ad hoc
signed; this is not release-signing or helper-distribution acceptance. It remains
open on the account sheet. Native refresh, revocation, inference, tools, and
multi-account acceptance remain pending. No tokens or account labels are tracked.

The direct-provider follow-up passed forty-five focused tests in serial mode.
This includes native loopback HTTP without a Content-Type header. Two generator
tests and the unsigned native Debug build passed. Installed QA loaded the real
account catalog. Initial Responses requests failed because their HTTP response
did not include Content-Type. The decoder now permits the missing header and
still requires valid SSE frames and a completed response. Repeated native menu
actions were interrupted by focus changes. The user was asked to leave input
free for a short acceptance check. Real response completion and cancellation
were pending at that point. One accidental neutral paste in the isolated editor was
undone; an empty QA draft remains. The normal library was not changed.

The native follow-up replaced the manual model menu with a native Picker.
The desktop control tool still lost menu references; a coordinate selection
followed by a fresh AX snapshot confirmed the selected ChatGPT model. The
installed app then returned a completed neutral response. A longer neutral
request showed partial text and a Stop control. Stop cleared the partial text,
kept the user message, and showed no cancellation error. A subsequent request
returned a new completed response. This proves real text inference and local
stream cancellation on the installed QA copy. It does not prove MCP tools,
provider revocation, all models, multi-account switching, or release signing.
Two empty drafts remain from neutral editor input that was undone during UI
automation. The normal library was not changed.

Full CI run 41589286253 targets 260df45. Tooling, website, and matrix passed;
native checks were still running at the last observation. The Picker follow-up
needs its own final CI result. The QA copy remains open with the neutral chat.

## Official contracts

- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [ID-token validation](https://developers.openai.com/siwc/website)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)

## MCP credentials in progress

`MCPConnectionCredentialStore` keeps complete records in a separate Keychain
service. Each record binds a connection ID to one HTTPS resource endpoint and
authorization server. It rejects endpoint substitution. QA bundle identity
separates its records from production. ChatGPT uses its existing service.
`DeviceCredentialStore` provides the shared device-local Keychain operations.
Writes report failures and do not delete the previous item.

Before refresh, the store persists an uncertainty marker. A failed replacement
keeps this marker across restart. This is storage support, not a working MCP
login. The session owner, discovery, browser flow, renewal, connection UI, and
authorized tools remain pending. The pinned SDK's `TokenStorage` methods do not
throw. Do not hide Keychain errors behind that interface or retry an uncertain
refresh automatically.

Validation: six credential tests passed serially, including the existing
ChatGPT Keychain tests. Both project-generator checks passed. Installed MCP
login and production Keychain acceptance are not yet verified.

`MCPConnectionSession` coordinates renewal across callers and checks required
scopes again after renewal. It saves uncertainty before network work. It holds
a device-local lease during renewal. Disconnect blocks new callers, waits for
renewal, and removes the saved record. This is local disconnect; remote
revocation is not implemented. A conditional credential replacement rejects a
late result if the saved session changed or was removed. Network renewal is
injected for now. Browser login and real MCP transport integration remain open.

Full CI run `41590666299` completed successfully for commit `52f5d32`.
This validates the direct ChatGPT baseline. It does not cover the later
Apple labels, history merge, or MCP credential and session changes.

Validation: six MCP credential and session tests passed serially. They cover
coalesced renewal, returned scope checks, disconnect during renewal, durable
uncertainty after network failure, and rejected completion after deletion.
Both project-generator checks passed. These tests inject renewal responses;
they do not establish a working MCP server login or remote revocation.

## MCP authorization discovery and request

`MCPAuthorizationDiscovery` loads protected resource metadata, then OAuth or
OIDC authorization server metadata. It verifies the resource and issuer. It
requires S256 and HTTPS. Multiple issuers require an explicit advertised choice.
Requests have no credentials. Redirects are denied and responses are bounded by
the shared HTTP implementation. A malformed successful document stops discovery;
only HTTP 404 tries the next discovery path.

`MCPAuthorizationRequest` creates fresh state and a PKCE verifier. It binds the
authorization and token requests to one resource, client, and redirect URI.
Callback checks cover destination, state, duplicate parameters, and a returned
issuer. The verifier remains in memory. The browser session, client registration,
token response exchange, connection UI, and installed login remain pending.

Reference: https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization

Validation: all six discovery and authorization-request tests passed serially.
Both project-generator checks passed. Next, use `ASWebAuthenticationSession`
with the app's registered callback scheme. Apple documentation was checked for
session start, cancellation, and presentation-context ownership. The native
browser flow is not implemented or accepted yet.

## Scope clarification — Draftly's own MCP server

The user expects Draftly to provide its own MCP server. That local server is
already implemented in `AgentMCP`. It runs through the signed helper and the
application's local permission service. Its authentication is native pairing
and limited grants, not an external server's OAuth login. Finish the installed
Draftly server and console-to-Draftly permission path first. An external MCP
server URL is not a prerequisite for this work.

The outbound MCP browser and code-exchange implementation is staged separately
from the active console. `MCPBrowserAuthorization` uses the system web session.
`MCPLoginService` validates callbacks, exchanges the code, checks cancellation,
and saves complete credentials under the same session lease used by renewal.
It rejects a login result if the saved session changed while login was pending.
It currently requires a registered public client ID. Dynamic registration,
connection UI, real-server acceptance, and remote revocation remain open.
Nine request, session, and login tests passed serially. Login tests use injected
browser and HTTP responses. The native browser has compiled but has not passed
installed interactive acceptance. Do not report it as a usable console feature.
