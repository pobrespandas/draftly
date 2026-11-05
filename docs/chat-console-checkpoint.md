# Installed read-only permissions acceptance — 3 November 2026

The user approved a new CLI/MCP read-only grant in the signed `2ea267b` QA.
The app and current helper showed the same pairing code. Native review selected
only the neutral draft `QA own MCP café 🐼 — only this draft.` and its current
window. Capabilities were exactly `drafts.read` and `editor.read`. Renewal and
entire-library access stayed off. The actual deadline was `13:53:30Z`.

The installed CLI listed only that draft. A direct read of the other existing
neutral draft returned `not_found`. Mutation preparation, a direct draft write,
and an editor write returned `permission_denied`. A later read confirmed that
the approved text was unchanged. A single MCP process read the approved draft,
rejected the other draft, and omitted write tools.

Native Stop Work withdrew the endpoint and denied the existing authorized MCP
reader. The connection showed Paused. Explicit resume reused the same grant and
expiry; the same MCP process read again. At `13:53:32Z`, that process received
`permission_denied`, without text, after real expiry. A new CLI read also failed.
The host remained published and the unrevoked, nonrenewable grant record was
unchanged. The last pre-expiry CLI read had succeeded.

The QA then stopped, revoked the expired connection, and fully exited. Discovery
was empty. Original shared preferences and saved window state were restored and
verified. The normal library was not opened. The QA bundle and neutral test
library remain available for later checks. The private evidence and recovery
location are recorded in `/tmp/draftly-agent-qa-followup.json`.

This proves fresh pairing, one read-only scope, negative writes, actual expiry,
and Stop Work for an open read session. It does not prove Stop Work during an
active mutation, native effect, or pending effect review, nor every client's
compatibility. Those acceptance gates remain open. Earlier entries follow.

# Installed model selection acceptance — 3 November 2026

A fresh signed app and embedded helper from `2ea267b` replaced only the named
Agent Chat QA bundle. The previous bundle, shared preferences, and saved window
state have private recovery copies. The QA retained its temporary library and
separate ChatGPT account/history namespace. The normal library was not opened.

Native UI selected ChatGPT GPT-6.1-Sol. The QA fully exited and the process was
confirmed absent. After reopening, Chat Console retained that model identifier,
and tools remained disconnected. Agents Settings showed access off and no
approved connections. Two neutral drafts are present for the next scope test.
This closes installed model-choice persistence for this path. It does not prove
account renewal, account switching, or a new model response after restart.

The QA is open on Agents Settings with access off. A new read-only pairing and
15-minute grant require fresh user approval. No new grant was created. The
local non-secret checkpoint is `/tmp/draftly-agent-qa-followup.json`. Its private
work directory holds recovery files. Do not restore shared preferences while
the QA is running. Stop the QA and verify process exit before restoration.

# Model selection follow-up — 3 November 2026

The selected model now persists separately from conversation history. Restoring
it does not restore a tool grant. A missing ChatGPT model stays selected but
cannot send, so startup does not silently switch providers. Eight console tests
passed, including restored ChatGPT and Apple Cloud choices. Installed restart
acceptance for this change is pending. Full CI `41608020603` passed for the
preceding `33b8b41` source.

# Current status — 3 November 2026

Read [agents and AI readiness](agents-ai-readiness.md) for the current closure map.

Signed isolated QA verified direct ChatGPT tool reading, native read consent,
Keychain sharing with the installed helper, an installed MCP read session, and
revocation for new CLI requests and an existing MCP session. Stop Work removed
the idle host publication. Full process exit and restart retained the ChatGPT
account and conversation with local access off. The QA is closed. Original
preferences and saved window state are restored.

Normal host startup, screen-lock acceptance, active-session Stop Work, installed
expiry and negative access cases, remaining handlers, and final distribution
are not complete. No agents release is established. The sections below record
chronological work; an earlier pending statement is not the current result.

# Chat Console checkpoint

## Direct ChatGPT connection

The direct connection is in progress on PR #105. The installed QA account sheet
uses direct ChatGPT OAuth. Real sign-in and restoration after full process exit
passed. The account model catalog and completed Responses worked in installed
QA. Native Stop removed a partial response, and the next request succeeded.
Draftly's own local tool bridge and native consent are now implemented behind
the existing host gate. Installed read-only tool use passed as recorded above.
Editing and the remaining acceptance cases are pending.
Connections to external MCP servers are out of scope for now.

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
7. Finish installed acceptance for the native local-tool consent and execution path.

Keep one account-session owner per installed app. Serialize refresh for each
renewable session. Console history merges saved conversations and message IDs before each write.
MainActor serializes these writes across app windows. A two-window regression
checks shared messages and separate conversations. Installed acceptance remains
pending. Window selection and active response state remain local to each window.
Local agent pairing and grants remain separate from provider login. MCP tools must use the existing
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

## Scope correction — 3 November 2026

The user excluded external MCP servers for now. The active PR removes outbound
MCP discovery, OAuth, and credential code. The local branch
`at/mcp-external-deferred-20261103` retains that work for reference. It is not a
prerequisite or an available console feature.

Prioritize Draftly's own local MCP server and ChatGPT's use of its authorized
tools. The existing server uses the signed helper, native pairing, Keychain,
and limited grants. Keep that authority path. Do not add an inbound remote
HTTP server or substitute OAuth for local pairing. ChatGPT model authentication
remains separate. The console must check grants before each local call and
must honor pause, Stop Work, revocation, and effect reviews.

Full CI `41590666299` passed for baseline `52f5d32`. Later history and scope
changes still need full CI. No installed tool-using chat acceptance exists yet.

Full CI `41592308292` passed for `ae0587a`, including native macOS checks.
The current external-MCP removal still needs its own full CI validation.

After removal, all 15 focused ChatGPT credential, provider, and console tests
passed serially. Both project-generator checks passed. The own-MCP tool bridge
is still missing; no tool execution is advertised by Chat Console.

## Own MCP tool bridge in progress

`AgentAvailableTools` now owns discovery filtering and named tool definitions.
The MCP server and the console adapter use the same schemas. Unavailable
handlers and capabilities outside the current grant are excluded. Duplicate
operation descriptors fail validation instead of replacing earlier entries.

`AgentChatToolSession` accepts a backend that already owns an authenticated
local session. Tool arguments cannot select another connection, library, or
operation. Each call refreshes discovery before dispatch. Call IDs are reserved
before execution and cannot trigger replay. Cancellation and invalidation reject
late results. The host remains responsible for live grants, scope, versions,
reviews, effects, and operation cancellation.

This adapter is not yet attached to ChatGPT inference or the native permission
UI. Do not report tool-using chat as available. Next, handle completed function
calls and their outputs in the direct ChatGPT provider, then attach the adapter
to a user-approved local connection. Keep the full installed-agent acceptance
and helper distribution work in scope.

The native adapter takes an existing `AgentCommandService.Session`. Before each
request, it obtains the authorized library ID from that session and binds the
request to it. It never accepts a library ID from model arguments. Invalidation
closes its owned service session. Tests first exposed a missing library binding;
the native adapter now uses the same binding rule as the local MCP client.

Validation: 14 real SDK/local-host MCP tests and two catalog tests passed after
the shared-catalog change. Both native chat-adapter tests passed after the
library-binding fix. They check permitted Unicode text, hidden resource denial,
call-ID replay rejection, revocation, and late-result invalidation. Both project
generator checks passed. This does not prove tool execution through a real
ChatGPT response or installed native approval.

## Direct ChatGPT tool continuation in progress

`ChatGPTProvider` now accepts an optional authenticated `AgentChatToolSession`.
It sends functions inside the `draftly` namespace. This follows the ChatGPT plan
route, which supports namespaced function tools but not hosted MCP tools.
The app executes the local call through its own permission service.

Only a completed model response can supply executable calls. Names must match
the advertised tools. Call IDs and arguments are bounded. Duplicate call IDs
are rejected before a batch starts. Calls run serially and have no automatic
retry. Discovery refreshes before each inference round and local call. Account
identity and cancellation are checked around each network and local step.
The stateless continuation includes returned output items, reasoning items, and
matching function results. Calls and rounds are bounded; the last allowed model
round cannot start another local effect. Text-only callers keep tools disabled.

The account owner supplies its session-epoch check to the provider. The native
console does not yet pass a tool session. Permission UI, real model tool calls,
installed acceptance, Stop Work, and helper distribution remain pending.

References checked: OpenAI Sign in with ChatGPT preview limitations and the
function-calling guide. The official Python SDK confirms the optional function
call namespace field. No external MCP client is added.

Validation: 20 focused tests passed serially across direct provider, local tool
continuation, account, console, and local permission-adapter suites. The new
continuation tests use simulated model events with the real permission service.
They check scoped text, reasoning and result continuation, duplicate batches,
revocation, and account changes. No real ChatGPT tool invocation is accepted yet.
Full CI `41594155092` passed for scope cleanup `b4ccd5f`; the tool bridge and
continuation changes still need full CI.

The unsigned native Debug build passed for `12c1c9c` with the worktree package
name override. Full CI `41595947234` now validates that commit. No signing,
notarization, installed tool invocation, or native approval acceptance is implied.


## Native local-tool consent in progress

The console has a Draftly tools button. It is disabled without an available,
enabled local host. The native confirmation identifies the current draft and
offers reading or editing. It states that approved content can go to the selected
ChatGPT account. Access targets the exact draft and editor window and expires
after 15 minutes. Editing includes text, tags, flags, and versions.

The host creates a separate connection for the chat. It uses the existing
Keychain credential and authenticated command-service session. The console
uses the same tool definitions as MCP and calls that service in process.
It does not expose a remote HTTP server or use hosted MCP.

Disconnect, account changes, another conversation, another provider, and chat
closure invalidate the session. A context check also rejects a changed draft or
account before and after each request. The host invalidates chat sessions when
it suspends or receives a permission change. Stop Work and revocation retain
the existing review and operation cancellation rules.

Normal disconnect revokes the chat connection, removes its credential, and
forgets its revoked metadata. Other connections remain unchanged. Cleanup
failures reach the console. External revocation closes the chat session without
starting a second revocation transaction. Normal app host startup and its lock
adapter are unchanged. Signed helper distribution, normal activation, and
installed interactive acceptance remain pending. Do not describe this as an
available release feature yet.

Validation: 78 focused tests passed serially across connection, host, app-owner,
console, local adapter, and ChatGPT tool-continuation suites. The host tests
cover enabled admission, exact scope, expiry, cleanup, independent connections,
external revocation, and suspension. Console tests cover rejected attachment
and account sign-out. Both project-generator checks passed. Native approval
interaction and a real ChatGPT tool call have not been accepted yet.

The unsigned native Debug build also passed with the worktree package-name
override after the consent UI changes. Full CI `41595947234` passed for the
prior provider commit `12c1c9c`. The new consent and lifecycle changes still
need full CI and installed signed acceptance.

## Signed installed QA preparation — 3 November 2026

`AgentQAConfiguration` permits Info.plist startup only in a build compiled with
`DRAFTLY_AGENT_QA`. It keeps ChatGPT account preferences, credentials, and chat
history in a namespace derived from the temporary library UUID. Normal builds
keep their existing startup and account behavior. Thirty focused account,
console, app-owner, and identity-migration tests passed. Both project-generator
checks passed. The QA native build passed.

The matching Developer ID app and helper profiles are available in retained
local QA artifacts. The helper packager checked its profile, certificate, and
static signature. The installed QA app initially failed because its sibling
Debug library had a different signing team. Signing that library with the same
team fixed launch without disabling library validation.

Installed `Draftly Agent Chat QA 20261103.app` opened an empty temporary library.
Settings showed local access off and no approved connections. The test enabled
only that QA host. The embedded signed helper discovered its published endpoint.
This does not prove Keychain sharing, pairing, a tool call, or notarization.
The new official ChatGPT login is pending user completion. Do not reuse the
other QA accounts. Private preference and saved-state backups exist. Restore
them after this QA process exits. The normal app was not running at startup.

Local QA metadata: `/tmp/draftly-agent-chat-qa-20261103.json`. It records the
exact bundle, UUID, signature evidence, discovery, and backup locations. It
contains no tokens. The app remains open for the login. No grant was approved.
Full CI `41598564068` passed for native consent commit `698c883`; the QA isolation
changes still need their own full CI.


The signed QA now shows `Signed in` and loaded the account's real model list.
No model inference or local tool call has been accepted in this QA. Model menu
automation did not change the Apple selection. The user then asked to open the
login and leave it visible. Since sign-in had completed, the assistant left the
ChatGPT account sheet open with `Signed in`. Keep that UI in place. Do not
resume native input or replace this running QA without new user steering.
Independent source and CI work can continue. The QA source changes are not yet
committed. Preference restoration must wait until this process exits.


## Signed read-only acceptance completed — 3 November 2026

The user approved only reading the current neutral draft and its editor for
15 minutes. The native confirmation created a separate connection. Its saved
capabilities were exactly `drafts.read` and `editor.read`; its scope held one
draft and one editor window. No editing permission was granted.

GPT-6.1-Sol called `drafts.list` and `drafts.get` through the real local service.
The completed response returned the exact neutral Unicode text. Native Settings
activity recorded both successful operations. This is real model inference,
not an injected response. The app and helper ran with matching Developer ID
profiles. The helper authenticated and returned the same limited capabilities.
This verifies their real Keychain sharing for this QA connection.

An installed stdio MCP probe negotiated `2025-11-25`, listed read tools, omitted
write tools, and read the approved draft. Native console disconnect removed the
connection metadata and credential. The same MCP process then denied another
read without returning draft text. A new CLI request returned
`permission_denied`. The probe exited normally. This is generic MCP protocol
acceptance, not acceptance for a named external client or fresh helper pairing.

Stop Work then set access off and withdrew the published endpoint. There was
no active granted session at that point. Do not claim active-session Stop Work
or effect cancellation from that check. After complete process exit, reopening
the same app restored the signed-in account and saved conversation without a
browser login. Local access stayed off. The selected model returned to Apple
On-Device; model-choice persistence needs a separate correction or explicit UX.

The QA exited again. The original production-identity preference domain was
restored and compared with its private backup. Saved window state was restored.
The isolated account, chat history, temporary library, signed bundle, and
non-secret local evidence remain available for follow-up. No normal library
was opened. No combined notarization, real expiry, forbidden write, hidden-draft
negative case, or normal screen-lock behavior was accepted by this session.
