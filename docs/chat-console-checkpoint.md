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

These components are not connected to the UI. Next steps:

1. Add a bounded loopback listener with cancellation and one-time consumption.
2. Validate ID-token signatures with the official discovery document and JWKS.
   Check issuer, audience, expiry, nonce, and the selected account identity.
3. Store the validated identity, issued client ID, tokens, scopes, and expiry
   together. Persist a stable host ID before the first authorization attempt.
4. Add serialized token refresh and sign-out. A late refresh must not restore
   a signed-out account.
5. Load the account model catalog and stream Responses requests directly.
   Require `response.completed` before reporting success.
6. Connect the console UI. Replace the Codex dependency after direct native QA.
7. Add authorized MCP tools through the existing permission and review rules.

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

## Official contracts

- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [ID-token validation](https://developers.openai.com/siwc/website)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
