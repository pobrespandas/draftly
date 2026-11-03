# Chat Console checkpoint

## Direct ChatGPT connection

The direct connection is in progress on PR #105. The current UI still uses
the Codex account model. Do not describe direct sign-in as available yet.

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

These components are not connected to the UI. Next steps:

1. Connect the tested login service to the account UI and account index.
2. Add saved-account selection without mixing registrations or credentials.
3. Add installed acceptance for login, Keychain storage, and process restart.
4. Add serialized token refresh and sign-out. A late refresh must not restore
   a signed-out account.
5. Load the account model catalog and stream Responses requests directly.
   Require `response.completed` before reporting success.
6. Connect the console UI. Replace the Codex dependency after direct native QA.
7. Add authorized MCP tools through the existing permission and review rules.

Keep one account-session owner per installed app. Serialize refresh for each
renewable session. The current console history is owned by each window and can
overwrite another window's history. Resolve that before reliability acceptance.
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

## Official contracts

- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [ID-token validation](https://developers.openai.com/siwc/website)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
