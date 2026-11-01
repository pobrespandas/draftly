# Project progress

Updated: 1 November 2026. This is the maintained continuation summary.
Historical test reports describe only the versions they tested.

## Expected-library handshake binding — 1 November

Pairing and credential authentication now accept an optional expectedLibraryID.
A mismatch is permissionDenied before a review or credential lookup. Bound
challenges acknowledge the library; clients reject missing or wrong library
responses. Absent expectations retain the existing JSON shapes and explicit
socket access. Present invalid/null IDs fail rather than silently fall back.

Three raw-socket tests first reproduced the unsupported binding. After the
implementation, 76 app and 14 contract tests passed across six focused suites.
The generated local app build also passed.
New tests cover legacy shapes, invalid types, correct/wrong library requests,
zero credential reads on refusal and clients checking acknowledgements.
This is transport-level binding, not signed-helper or normal-app acceptance.
Stable CLI lookup and routing are the next adapter step.

## Publication responsibility refactor — 1 November

The concrete problem was mixed ownership in AgentLocalHost: transport and
permission orchestration also managed retained publication attempts and cleanup
errors. AgentHostPublications now owns retained attempts and cleanup results.
The host keeps all authority checks and the original effect order. AgentHostLocator keeps file
validation, serialization and exact-epoch replacement. No protocol or public API
was added. A publication remains distinct from a grant, as defined in the glossary.

The reference tag is pre-refactor-host-publications-2026-11-01 at 08070f9.
Before editing, complete Swift inventories passed: 1 consumer, 146 contracts,
763 Core and 1169 application tests. All 286 Python tests, the structural matrix
and the local app build passed. This is a local checkpoint, not signed acceptance.
After extraction, the 139 focused tests and all 2079 complete Swift tests passed
with the same inventory. All 286 Python tests and the structural check passed.
The generated local app build passed and kept its identity and URL scheme.
No manual UI check was needed for this internal extraction; signed-helper
acceptance remains outside this refactor. No test was removed or
consolidated: the cleanup, contention and later-epoch cases cover different paths.

The preserved order is socket stop, session invalidation, publication withdrawal
and lease release. Both owner checks still surround publication, and the
original cleanup retries and error results remain. The handoff now starts with a
current checkpoint; earlier journals remain available as historical evidence.
No new functionality or installed-app change belongs to this refactor.
Its assembly and discovery prerequisites are integrated through PRs #53 and #54.
PR #55 passed all required checks in exact-head CI 41301495867 and merged as
24366fa. CI verified the complete Swift inventory above and the local app build.
The refactoring stage is integrated; the installed app and release are unchanged.

The next functional step is stable library routing with expected-library checks
during pairing and authentication. The [full agent plan](plans/draftly-for-agents.md)
remains unfinished; this refactor does not complete local agent access.

## Private host locator — 1 November

AgentHostLocator now publishes private atomic discovery hints with library ID,
publication epoch and Unix socket path. Its strict versioned catalog rejects
malformed, unknown, oversized, duplicate and unsafe records. Snapshot readers create no
metadata or lock files. A later epoch and other libraries survive old cleanup.
AgentLocalHost publishes only after broker creation and owner validation. Stop
closes transport before withdrawal and retains exact epochs and a cleanup error
when withdrawal fails. Explicit later close/suspend can retry safely.

The helper now has discover, with an optional explicit state parent for QA. It
checks its own provisioned identity first. It returns hints, not credentials or
proof of live authorization. Automatic destination selection, client configuration
export and signed-helper acceptance remain pending. The normal app is unchanged.

Seven locator tests and five host integration cases cover read-only discovery,
private modes/aliases/FIFO, bounds, Unicode paths, directory replacement, catalog
capacity, publication/resume, cleanup contention and old-close safety. The final
focused run passed 39 tests before the separate backup assertion correction.
Complete local Swift results then passed with verified inventories: 1 consumer,
146 contracts, 763 Core and 1169 application tests. All 286 Python tests passed
and the structural matrix has zero errors. The helper and generated local app
builds passed. Discovery PR #54 passed exact-head CI 41300584226 and merged as
9338a4f; that does not prove signed-helper acceptance. Helper help and two negative discovery smoke checks passed,
without creating state. These do not prove positive signed-helper discovery.
The earlier full run found the independent backup-comparison fixture defect
recorded below; its correction has a separate commit.

## Host backup assertion and CI investigation — 1 November

The host read-preservation test compared raw backup bytes. A full local run
observed a mismatch. Note collection order is not a storage contract: persistence
decodes dictionary values, and reload can change that order. The fixture now
compares every backup field while sorting only the note collection by identity.
A regression case reverses the note order and explicitly changes content, ID,
tags, date and an unknown field to check that real payload changes remain visible.
The 15 focused host tests passed, including the new regression case. Production,
backup formats and collection ordering are unchanged.

The initial PR #53 CI run 41297544381 failed. Its host tests passed, but the
application process returned zero with an unfinished XML report during
TypewriterScrollingTests. No assertion failure or cause was recorded. Diagnostic
run 41298598924 executes only that suite on main, without the new host changes.
The isolated diagnostic passed; it does not identify the cause or prove that
the original full-run interruption was pre-existing. Do not merge #53
until a complete exact-head check passes. No deadline or retry was added. The assertion correction is commit ed30f41.
Its exact-head CI run 41298902468 later passed all required checks. PR #53
merged as 0a38ac4. The original interruption still has no confirmed cause.

## Local host assembly — 1 November

AgentLocalHost now constructs one real loaded-library binding, private metadata
file, permission registry, read service, pairing coordinator and optional broker.
All metadata and admission paths share its owner validator. The default native
application check rejects an unprovisioned build before creating agent state.
Construction does not enable or start transport. Human Settings commands and
explicit resume/suspend/close commands control its lifetime. Close invalidates
sessions and pending decisions before releasing the library lease.

Fourteen assembly tests use real temporary SQLite stores and Unix sockets, with
explicit in-memory credentials and signature substitutes. They cover Settings
approval/Cancel, scoped reads, revoke, reopen, close, retained models/services,
lock/resume, owner loss, transient contention, failed startup compensation and
unreadable metadata. They also check that failed compensation reports
outcomeUnknown rather than a false disabled preference. The first focused eight
suites passed 125 tests; the final assembly suite passed 14 after that added
error case. Complete final Swift results passed with verified inventories:
1 consumer, 146 contracts, 763 Core and 1156 application tests. All 286 Python
tests passed and the structural matrix has zero errors. The generated Xcode app
build passed. No test opens a window,
requests a permission, records audio or uses personal data.

Normal AppController startup, locator publication, editor/lock adapters, signed
helper packaging and real shared-Keychain acceptance remain pending. This does
not activate access in the installed app or complete local agent functionality.

## Host checks for human pairing — 1 November

AgentPairingCoordinator now requires an explicit host validator. Requests,
reviews and approval check ownership. A second check after target resolution
prevents stale reviews from creating credentials. Polling observes host loss and
invalidates pending and approved results without deleting previously saved grants.
Temporary contention preserves a prepared review but cannot approve it or extend
its deadline. A failed request refresh cannot create a challenge.

Seven new specific tests cover those boundaries. The five affected suites passed
93 tests. Complete Swift results passed with verified inventories: 1 consumer,
146 contracts, 763 Core and 1142 application tests. All 286 Python tests passed,
and the structural matrix has zero errors. The local app and isolated Settings
preview builds passed. Neither build was launched.
Transport, Settings and the memory-only manual preview explicitly supply
their validator. Normal host construction, locator publication and signed helper
acceptance remain pending. No installed app or listener was activated.

PR #51 passed its complete exact-head CI, including the required summary check,
and merged as aa15c417. This also integrated PR #50 through the preserved history.
PR #52 later passed complete exact-head CI and merged the read-admission and
pairing follow-ups as 3afa1b3f. The local host assembly is a separate change.

## Host checks at read admission — 1 November

AgentCommandService now requires an explicit host validator. It checks ownership
before transport start, before and after credential authentication, and before
and after each read. A lost owner clears sessions and cursors; restoring the
proof does not restore those sessions. Temporary contention returns busy without
revoking an otherwise valid session. Existing locked-start behavior is unchanged.

Three specific service tests cover denied startup/authentication, stale sessions,
temporary contention and ownership loss during a read. A real temporary SQLite
lease test verifies admission after ownership closes. The five affected suites
passed 72 tests. The local app build passed. Transport and MCP fixtures
explicitly inject their test validator.
Normal host construction, pairing admission, locator publication and signed helper
acceptance remain pending. The installed app and released package are unchanged.

## Stable local library binding and ownership — 1 November

AgentLibraryLocation now identifies the loaded SQLite store without changing its
metadata or Note data. AgentHostLease keeps a local library ID across reopen and
holds both location and physical-file locks. A coherent closed database copy gets
another agent binding even when its Core Data UUID is unchanged. Replacing the
file at the same path also requires a fresh binding. Aliases share one owner.

Corrupt or foreign identity records fail without repair. Deletion cannot bypass
a held owner. Validation checks the loaded store, current paths and saved binding;
a changed owner stays invalid for that host epoch. Normal host startup and locator
publication still need to use these checks. No installed app or listener was
activated. See [the decision](adr/0003-local-agent-library-binding.md).

Focused tests use temporary real SQLite stores and preserve draft IDs and content.
They cover reopen, copies, replacement, aliases, moves, Unicode paths, lock
release, temporary contention, metadata changes, corrupt records, deleted identity
files and unsupported storage. Sixteen host tests and six state-directory tests
were added. Final complete Swift inventories passed: 1 consumer, 146 agent
contracts, 763 Core and 1131 application tests. All 286 Python tests passed. The
structural matrix has zero errors. The generated local app build passed. These
are automatic filesystem/SQLite checks, not signed host or normal startup
acceptance. PR #50 initially lacked its required summary check. PR #51 later
passed complete exact-head CI and merged the preserved history of both PRs.

## Private local state extraction — 1 November

AgentStateDirectory now owns the private agent directory, bounded reads, atomic
CAS replacement and advisory file locks. AgentConnectionFile delegates to it and
keeps connections.json, connections.lock and its byte format unchanged. The
shared file policy still owns permission, ACL and link checks. Credentials remain
outside these files.

The focused metadata, registry, Settings and state-directory suites passed 43
checks. Existing file tests retain their names and coverage. New checks cover
independent files, byte budgets, invalid names, held lock lifetime, inode and
directory replacement, unsafe aliases and exclusion by an actual child process.
The generated local app build passed. This is an extraction for the host identity
and ownership work; it does not activate a listener or prove signed access.

## Human connection review and Settings — 1 November

Implemented the grant editing copy, human Settings model and native review and
management view. Cancel does not save or approve. Existing edits check the grant
ID before replacement. Pairing requires a prepared review and code comparison;
changing choices invalidates that review. Missing IDs remain visible. Revocation
shows its current state immediately and reports credential cleanup per connection.

The Agents tab is conditional on a configured AppController model. Normal startup
still supplies none. Signed helper setup, real Keychain sharing, stable host and
locator/lifecycle work remain required before activation. Recent activity, Stop
Work and full operation access are not complete.

Eighteen specific headless tests cover defaults, Cancel, stale copies, error
retention, frozen selections, approval, revocation, metadata errors, authority
binding, accessibility labels and recreation from serialized metadata. The
separate native memory-only preview passed Cancel/reopen, code comparison,
approval, Save/reopen, Revoke, Deny, Pause, resource filtering, Escape, scrolling
and light/dark checks. An observed missing title in resource accessibility labels
was corrected and checked again. The preview was closed and unregistered; its
app went to Trash and its temporary preferences were removed. No endpoint,
Keychain adapter or personal library was used. Final complete Swift inventories
passed: 1 consumer, 146 agent contracts, 763 Core and 1109 application tests.
All 286 Python tests passed. The structural matrix has zero errors. The generated
local app build passed. This evidence does not approve normal startup or signed
pairing.

PR #49 passed exact-head CI and was merged as 74188c6. The installed app and
release remain unchanged. See [connection UI](agent-connections-ui.md).

## Pairing socket and CLI connect — 1 November

Implemented a separate pairing introduction on the private socket and the helper's
connect command. The signed peer check precedes the request. The helper shows a
comparison code and polls for the person's decision. Only poll and cancel controls
exist; the client cannot supply grants, credentials or approval. Approval returns
a connection UUID. Normal requests still authenticate through Keychain and check
the current grant. No normal app route starts the broker yet.

Pairing frames are limited to 4096 bytes. Each conversation binds its challenge
ID; another conversation cannot inspect or cancel it. At most two pairing waits
use the eight client slots. Disconnect and broker destruction release pending
requests. Cancel after approval reports the completed effect rather than a false
revocation. Name validation is shared with persisted connection metadata.

Six protocol tests and sixteen socket tests cover the new path. Together with the
existing transport, registry and lifecycle suites, focused checks passed. The
compiled helper passed connect help, invalid-argument and unsigned-refusal smoke
checks without reading credentials or showing windows. The decision waiter also covers
approval racing a deadline, invalid wait budgets and task cancellation. Final complete Swift inventories passed: 1 consumer, 146 agent contracts,
763 Core and 1091 application tests. All 286 Python tests passed. The structural
matrix has zero errors. The helper and generated local app builds passed. No
signed pairing or native UI acceptance is claimed. PR #48 passed CI and was integrated as db659c7.

Remaining: Settings review and management bindings, helper wrapping/profiles,
real Keychain sharing, locator and host/editor/lock adapters. The installed app is
unchanged. This does not complete local agent access or enable remote access.

## Human pairing lifecycle — 1 November

AgentPairingCoordinator now owns temporary connection requests. A request creates
no grant or credential. Human review binds a fresh review ID, comparison code,
name, capabilities, exact resource IDs and expiry. The default remains selected
IDs and read access for one hour. Whole-library and renewable grants require an
explicit choice. A comparison code is not proof of client identity.

Approval rechecks resource resolution and calls the existing persistent registry.
Duplicate approval, stale reviews and cross-request review IDs cannot create a
second connection. A storage failure is terminal for that pairing attempt; it is
not retried by polling or another click. Denial, cancellation, expiry and
invalidation remain distinct. Wall-clock rollback and monotonic expiry cannot
extend the five-minute challenge. Disable, lock and unreadable metadata invalidate
pending decisions. The runtime must call invalidatePending on lifecycle events.

Settings bindings remain pending. The pairing socket now verifies the signed
helper before creating a request. UI bindings, signed helper packaging and native pairing acceptance remain
pending. No installed app or personal data changed.

Automated evidence: 15 focused contracts and the full Swift inventories passed
(1 consumer, 140 agent contracts, 763 Core, 1075 application tests). The 286 Python
tests passed, the generated local app build passed, and the structural matrix has
zero errors. Tests use in-memory
metadata and fake credentials, not real Keychain data or windows. The setup flow
still requires native UI and signed-client acceptance.

## Local MCP adapter — 1 November

Implemented the official Swift MCP SDK 0.12.1 over bounded stdio. Shared metadata
binds named CLI calls and MCP tools to the same application requests. Available
tools respect grants and host schemas. Scoped draft resources retain pagination
sessions. The review prompt reads data without changing notes. Typed decimals
that would lose precision are rejected; parametersJSON preserves exact input.

Automatic validation: complete Swift inventories passed (1 consumer, 140 agent
contracts, 763 Core, 1060 application tests). All 286 Python tests passed. The
structural matrix has zero errors. Real SDK tests cover pipes, the Unix bridge,
concurrent discovery, revocation, resource scope and malformed or oversized input.
The compiled unsigned helper passed initialization, authorization refusal, clean
EOF and oversized-line checks. No personal data or native permissions were used.

The earlier pipe implementation rescanned partial lines and stalled a large-input
test. Incremental scanning fixed it; deadlines were not increased. The exact
number decoder correction is a separate commit. The generated local app and helper builds passed. Signed installation and
human pairing remain unverified.

Normal app activation remains pending: signed helper packaging and Keychain
sharing, human pairing/management, locator and host/editor adapters. Mutations,
durable receipts, native authorization and remaining contracts are not complete.
Remote access remains future. PR #46 was integrated as 1040a3e after its required
CI passed; this MCP work is a separate change. The habitual app is unchanged.

## Exact JSON integer-boundary correction — 1 November

AgentJSONValue previously tried Int64 before Decimal. Foundation could round a
near-integer fraction before the agent schema checked it. The decoder now reads
Decimal first and selects Int64 only when the value is exactly integral and in
range. Strings, booleans and null remain distinct. Three focused tests cover
fractions, integer boundaries and nonnumeric values. The new fraction regression
failed before the fix and passed after it. No library format changes.

## Local socket and JSON helper — 1 November

AgentLocalTransport now provides bounded Unix-socket framing and a local client.
AgentSocketBroker authenticates those connections through AgentCommandService.
The draftly-agent executable has a JSON command, help and protocol-version output.
It links no app model or Core Data and reads credentials only through the dedicated
helper Keychain adapter. No normal app route constructs the broker yet.

Both peers must have the current UID and the expected signed process identity,
checked from kernel audit tokens before credential transfer. Private directories
and sockets use the shared file/ACL policy. Frames and authentication have size
and time limits. Socket I/O stays off MainActor. Stop, deinitialization and
cancellation close owned resources. Disabled or locked access cannot start a
listener. Request authority remains checked by the application service.

Four new handshake tests and thirteen socket tests passed. Socket tests use real
local I/O, temporary paths, fake credentials and in-memory libraries. They verify
scoped reads, revocation, peer rejection before credential lookup, size limits,
timeouts, cancellation, response identity, private modes, symlinks and cleanup.
Full Swift inventories passed: 1 consumer, 131 contracts, 763 Core and 1049 app.
Python 286, the structural matrix, helper build and local Xcode build passed.
Unsigned CLI smoke checks returned the expected errors without credential access.

PR #45 exact head 50c3ce5 passed CI 41281420773 and merged as d93a536.
The installed app remains unchanged. This helper is a build product, not an
installed or provisioned client. Signed packaging/profiles, real Keychain sharing,
human pairing/management, stable locator and single-broker coordination, live
library/editor/lock adapters and MCP remain pending. JSON mode currently needs
an explicit socket path. See [local development](agent-local-development.md).
Other handlers, mutation receipts and native effects remain unfinished.

## Device-local credential adapter — 1 November

AgentLocalSecurity provides a dedicated data-protection Keychain adapter shared
by the application and future helper. It has no library, editor or view dependency. The
application maps it to the existing registry through a small adapter. Items use
the exact agent access group, a connection UUID, device-only unlocked protection
and a noninteractive authentication context. Create is exclusive. The helper can
read; only the application adapter can create or remove an item.

Current-process validation pins the Apple signature, team and role identifier.
It checks the exact group and rejects debug/injection entitlements before any
SecItem call. The OS must also authorize the group. Missing items, denied access,
interaction requirements, cancellation, unavailable service and storage failures
remain distinct. There is no fallback to legacy or Action credentials.

Eleven headless tests inject the native item calls. They check queries, roles,
create-only behavior, failures and registry integration. The real test process is
rejected by production identity validation before the injected item boundary.
No real credential or personal Keychain item is used.

Full Swift inventories passed: 1 consumer, 127 contracts, 763 Core and 1036
application tests. Python 286, the structural matrix and the local Xcode build
passed. These checks do not prove signed sharing.

The existing app entitlements and profiles remain unchanged. Pairing cannot use
this adapter until both app and helper profiles authorize the group and real
sharing is verified. Package the helper in an app-like wrapper; see the
[credential decision](adr/0001-agent-device-keychain.md). Signed sharing, lock
behavior and replacement across signed versions remain pending.

PR #44 exact head 5c02fc7 passed CI 41280392312 and merged as 3a5e770.
The authenticated read service is integrated, not installed or enabled.

## Authenticated read service — 1 November

AgentCommandService now authenticates internal sessions and executes eight read
operations against the application library. Each request checks current connection
authority and validates its contract. Discovery reports actual handler availability;
registering a contract alone cannot make it executable. All mutation handlers and
the remaining read families are unavailable.

Draft reads filter by scope before counts, queries, previews and revisions. They
reuse Workspace rules and the existing preview formatter. Paging freezes only IDs
and order, with signed session/grant-bound cursors. Text chunks use UTF-16 without
splitting Unicode scalars. No read updates access dates or persists an edit.

Seventeen new headless tests use in-memory libraries and fake credentials. They cover scoped
reads, current authorization, paging, Unicode, revision ownership, malformed input,
version tokens and oversized output. Full inventories passed: 1 consumer,
127 contracts, 763 Core and 1025 application tests. Python 286, the structural
matrix and the local Xcode build passed. Real client and UI acceptance remain pending.
See [architecture](architecture.md#authenticated-agent-reads) for exact limits.

This is an internal service, not enabled agent access in the installed app.
Signed Keychain verification, pairing/management UI, lock notifications,
stable host library identity, live editor generations, Unix socket, CLI/MCP,
mutations, receipts and native-effect enforcement remain required. Remote access
is future work. The full local agent objective remains unfinished.

## Workspace installation regression found in connection CI — 1 November

PR #43 CI 41278698974 failed an existing Workspace URL test. Repeated decoding
can produce a different JSON key order in imported API metadata. Direct string
comparison then asks to replace an unchanged Workspace. This is independent of
agent connection storage.

The router now compares canonical copies of API metadata for installation only.
It does not rewrite stored metadata, change Workspace equality, or ignore unknown
fields. A deterministic regression changes key order and whitespace, checks that
the library remains unchanged, and checks that a real unknown-field change still
requires review. The regression failed before the fix and passed after it.
All four Swift inventories passed: 1 consumer, 127 contracts, 763 Core and 1008
application tests. Python 286, the structural matrix and the local Xcode build
passed. PR #43 exact head 35991f5 passed CI 41279495897 and merged as 71f0e3e.
No manual app
installation or native acceptance is claimed by this change.

## Local connection storage foundation — 1 November

The application has a private metadata file and an internal connection registry.
New access is disabled. New connections default to selected-resource reads and
a one-hour grant. Metadata round trips retain the grant identity and expiry.
Credentials are separate, and management results never include them. Unsupported
metadata versions or security fields fail closed without overwriting the file.

Nineteen headless tests cover real private-file replacement/reopening, conflicts,
unsafe permissions, links, FIFOs and extended ACLs, plus credential validation,
expiry, revocation, grant replacement and partial storage failures. Credential
operations use injected memory adapters. Full Swift inventories, Python 286 and
the structural matrix passed. No personal Keychain, signed helper or real client
was used; those are not approved by these tests.

The production Keychain adapter, pairing/management UI and secure transport remain
pending. The read service above is not connected to those components or to the
installed app. Stored metadata is outside the library and sync/backup payloads.
The installed app is unchanged.

## Protected approval foundation — 1 November

AgentApprovalStore now binds one-use human consent to the normalized request,
effect snapshot, grant identity/state and service epoch. It reuses existing
validators and rejects declared capabilities or targets outside the grant.
A replacement grant cannot reuse consent from the old grant. No approval tool is
registered for agents. The actual human review UI is not connected yet.

Sixteen headless tests cover exact consumption, default normalization, changed
parameters/targets/versions/effects, Unicode, connection isolation, separate terminal
states, time limits, clock rollback, grant replacement/edits, lock/restart,
capacity, forged authority parameters and the wire-frame size boundary. A new
boundary regression failed before normalization budgets were separated from the
wire limit, then passed. Full Swift inventories, Python 286 and
the structural matrix passed. This is internal state-machine evidence, not real
human approval, authentication or complete native-effect authorization.

The future service still needs stable stored grants, lock/revocation hooks, a
fresh effect resolver, protected review UI and guarded execution. Approvals are
memory-only, bounded and lost on restart. They do not replace mutation receipts
or local write-ahead recovery. Installed app and personal data are unchanged.

## Native and Workspace preference coordination — 1 November

The application has adapters for login registration, Spotlight and the default
Workspace reference. Native coordination uses the existing models and reports
pending approval, unavailable service, busy state, failure and cancellation.
A native effect completion is separate from the verified local reset and operation record.
Human approval is required for both native settings; Spotlight changes require
full-library authority. No adapter issues that approval or enables an endpoint.

Workspace reference reads and preparation check capabilities and resource scope
before lookup. The common target-membership rule also serves baseline request
policy. Missing stored references remain unchanged and do not become successful
new references. Reset prepares removal without applying a Workspace.

Twelve new headless application tests passed with injected native services and
temporary preference domains. Full Swift inventories, Python 286, structural
matrix and local Xcode build passed. These checks are not real OS integration
acceptance. All preference operations still need the authenticated command
service, version checks, protected approvals and durable operation records.

## Scalar and list preference preparation — 1 November

Typed adapters now read 30 scalar preference fields and nine local list fields
from an explicit temporary-testable preference domain. They prepare changes and
per-field resets without writing them. Invalid legacy data is reported and kept.
List reads use the existing consumer and preserve legacy-key precedence. Prepared
list edits retain unknown fields and reset the selected legacy override too.
The adapters share a concrete typed reading value.

Eight new application tests cover defaults without writes, typed Unicode and
numeric values, invalid values, private/native-field rejection, list round trips,
legacy precedence and reset. All complete Swift inventories passed after the
change. Python 286 and the structural matrix check passed. Native and Workspace
coordination is described above. Authorization, verified local writes and
operation records remain open. No local endpoint or installed-app change is
enabled.

## Partial list option decoding — 1 November

DraftListOptions now uses its existing defaults for absent fields while retaining
other saved options. Present values with invalid types, including null, still
fail decoding. Complete records keep the same keys and round-trip behavior.
This allows a per-field reset without discarding unrelated options. The new
regressions failed before the correction; 18 focused Core/app cases then passed.

## Encoded preference access — 1 November

The application can now prepare typed reads and edits for 44 encoded preference
field entries: syntax options, Markdown options and command shortcuts. Existing
setters and conflict rules remain authoritative. Reset removes one known override
and retains additional imported fields. Syntax references must match the resolved
definition. Feature names must be declared by that definition.

This is a preparation component. It performs no persistence, native registration
or authorization. Actual handlers still need grants, scoped syntax resolution,
name-collision checks, version comparison, approval and commit receipts. Device
values, native settings, list defaults and default Workspace access remain open.
No app endpoint or installed-app change is enabled by this component.

## Preference defaults preparation — 1 November

Settings and editor consumers now share the existing editor, capture, General,
HTML and Markdown defaults. This removes duplicate values before the application
preference catalog is connected. Legacy Boolean conversion and invalid HTML
marker fallback stay unchanged. Reading a default does not persist it.

Automatic checks passed 49 focused tests across seven suites and the local
Xcode app build. The three new characterization tests also passed before the
extraction. The generated Xcode target uses the package name `draftly` to read
package-only constants from Core. No public API or persisted format changed.
No native acceptance is claimed; this unit changes no controls or permissions.
The actual field catalog, preference handlers and local agent endpoint remain
pending. The installed application is unchanged.

## Current priority

Local agent access is in stage 1. The user accepted the full
[agent plan](plans/draftly-for-agents.md); remote implementation stays deferred.
The first code unit adds the package-internal AgentContracts target: request and
result envelopes, stable errors, typed resource references, a planned operation
catalog and baseline grant evaluation. It adds no app route, CLI, socket, MCP
server, Keychain entry, native permission or network listener.

The catalog declares 136 planned operations and enables none. Baseline decisions
retain the resource scope; Actions and native requests require further effect
authorization. Irreversible operations require human approval. The new tests
cover isolation, expiry/revocation, target kinds, revision-token requirements,
full-library backup authority, malformed/oversized messages, Unicode/decimal
transport, and distinct pending/error/result states.

Automatic validation passed one package-consumer test, 127 AgentContracts,
763 Core and 1007 app tests with
complete result inventories, 286 Python tests, the structural matrix check,
and the final local app build.
See the [operation inventory](research/agent-operation-inventory.md) for reused
characterization evidence and remaining schemas and runtime enforcement work.
Contract definitions now cover 97 operation names: 93 static schemas and four
registry-bound preference forms. The application metadata catalog now declares 86 reviewed fields. Typed
preference readers, writers and the scoped endpoint are not connected.
They use one definition for validation, exported JSON Schema and request-local
defaults. Chunk checks use UTF-16; result shapes separate summaries from content.
The step effect catalog covers all 25 executor step types and always requires
runtime review for enabled steps. It does not authorize script execution.
Preference writes and imports also require contextual effect review. Action
updates bind payload IDs to targets; reorder requests must cover the target set
exactly once. Unknown Action/step/presentation data stays intact. Writes return
receipts rather than scripts. Lifecycle results distinguish wait expiry,
cancellation, timeout and ambiguous effects. actionGroups.get closes a missing
explicit read path; it has no executor yet. A separate UTC validation regression
rejects impossible calendar dates and trailing text while retaining valid leap
days and fractional precision. PR #31 passed all required CI checks and merged
at `0ba56b2`. A separate lifecycle correction now binds a busy termination reason
to the busy error code. Its focused regression failed before the correction and
passed afterward. The complete Swift suites, Python tests, structural matrix
check and local build passed after this correction.

Workspace permission review found two catalog gaps. Workspace queries now
require draftsRead as well as workspacesRead. Applying a Workspace requires
contextual effect authorization before theme or file references can load.
The focused permission regression failed before the correction and passed after
it. These checks remain unexposed baseline policy, not runtime enforcement.

Workspace schemas preserve the canonical model and its string metadata without
filling creation defaults. Queries share the draft page schema and do not replace
saved filters. Shared resource rules bind update IDs and complete reorder lists.
Apply results bind both the Workspace and window. Canonical fields that the model
cannot retain fail explicitly; unknown metadata strings stay unchanged. No actual
query, mutation, theme resolution or window application is enabled yet.

Agent batches now share one limit of 10,000 resource targets across transport,
policy, order lists and mutation receipts. A focused regression failed before
the correction because requests could exceed the receipt capacity. The limit
prevents accepting a batch whose complete result cannot be represented.

Draft mutation contracts cover creation, explicit changes, original-snapshot
UTF-16 patches, duplication, ordered merge, organization, flags, tags, syntax,
revision restoration and purge. Patches reject ambiguous or overflowing ranges.
Merge defaults to archive. Batch receipts cover all targets; duplicate and merge
results need a new identity. These contracts do not mutate notes or implement
version checks, transactions, editor coordination or Undo yet. PR #32 passed
required CI and merged at `0a2b7ab`.

The schema gateway now rejects missing or empty expectedVersion headers for
mutations independently of grant evaluation. Its regression failed before the
correction. Live version comparison remains an unimplemented handler boundary.

Editor contracts add a separate task-mark read operation, explicit window/new
window selection, no focus by default, bounded snapshots and versioned edits.
Window and draft IDs bind replies; selection and preview replies must reflect
the request. Open, navigation and preview still require contextual effect review.
Shared text validation preserves the existing draft range rules. No editor
command, actual Undo, window opening or live query runs through agents yet.
PR #33 merged at `620781c`; PR #34 merged at `d4d7c63` after required CI passed.

Import-source contracts now share exclusive input alternatives with exported
JSON Schema. They distinguish inline text, staged transfers, bookmarked relative
paths, installation links and HTTPS sources. Path and URL checks do not grant
file or network access. A focused regression detected missing required fields in
the exported alternatives before this was corrected.

Appearance contracts preserve canonical theme fields, imported data and exact
syntax source strings. Built-ins use names; installed definitions use UUIDs.
Added explicit selection state, named built-in routes, file Reload and targeted
theme replacement. Selection versions remain separate from definition versions.
Installation does not select a theme unless requested with a selection token.
File-backed reads and writes still require contextual effect review. All actual
parsers, imports, persistence, rendering and local preference changes remain
handler and native acceptance work. PR #35 passed CI and merged at `2b8478b`.

Preference contracts now require an explicit application-supplied field registry.
Requests cannot register fields or read raw storage names. Typed contexts separate
device, syntax, feature and command settings. Defaults, inheritance, read-only
state and approval requirements stay distinct. The production allowlist is not
yet built; use the new preference source inventory before connecting consumers.
A separate consumer module now checks construction without @testable access.
It reproduced inaccessible synthesized initializers before explicit package
constructors were added. The fixture registry is not evidence of application
field coverage. A separate
regression rejects null replies for resolved nonnullable inherited/system values;
declared system inheritance and invalid-store states remain distinct.

Bookmark contracts expose metadata only, preserve requested Unicode names,
reject arbitrary paths and self-approval fields, and bind Forget results to their
target. Stable local bookmark IDs, protected picker approval and scope filtering
remain application work. Creating a bookmark does not grant agent file access.
PR #36 passed required CI and merged at `229db77`.

Stage 1 is not closed: the production preference catalog, the other 39 operation
schemas, detailed script/native
effect checks and real executors still need implementation. Real agent clients have
not been connected. The habitual app remains the released 0.1.3.

## Released first-click correction

Repository cleanup and the human-readable documentation pass are integrated.
The current fix addresses a draft-list click that only changed focus when the
editor was focused. Native table click handling now owns that focus transition.
The installed 0.1.2 release and an isolated QA build of the old code reproduced
the issue. The corrected QA build selected the target draft on the first click
in both directions, with the same library and preferences.

The headless table test covers selection-to-editor routing, multiple selection,
and suppression of programmatic selection callbacks. It does not simulate a
physical click. Native click acceptance was checked separately with Computer Use.
The corrected QA build also retained a fresh edit while switching notes and
handled Command-click multiple selection. Complete local checks passed 759
Core, 938 app, and 285 Python tests; the local app build and structural matrix
passed. QA used a temporary library and was closed and unregistered afterward.
Version [0.1.3/build 4](https://github.com/pobrespandas/draftly/releases/tag/v0.1.3)
is public and installed on this Mac. PR #26 integrated the fix at `b307c77`.
Required PR CI `41250495492` passed. Tag `v0.1.3` started the automatic release
run `41250992295`; all release checks, signing, notarization, asset publication,
and site promotion passed. No local publication shortcut was used.

Sparkle offered 0.1.3 to installed 0.1.2 and completed Install and Relaunch.
The installed package passed strict signature and Gatekeeper checks. With the
editor focused, one click opened each of three neutral drafts. The 24 library
records retained their identities and payloads; only three access dates changed.
Both preference domains were retained. Expected changes were window frames,
recent draft IDs, and Sparkle's last-check time. A coherent database backup,
preference exports, and the old app remain in the private local build directory.
Both site download buttons now point to the 0.1.3 DMG. A new public download
matched its checksum. This update does not establish new CloudKit acceptance.

Draftly has one edition. Drafts Pro restrictions are reference blockers, not
Draftly feature restrictions. Continue other product work from the subsystem
records below, keeping current guidance separate from dated evidence.

## Source, publication, and installation

- The user requested 0.1.2 specifically to test a public update and reinstall.
  This is a one-time manual release exception: no app feature changed since
  0.1.1. Normal automated publication still rejects version-only changes.
  Version [0.1.2/build 3](https://github.com/pobrespandas/draftly/releases/tag/v0.1.2)
  is now public. Its signed and notarized DMG and all seven public assets
  passed verification. Firebase promotion `da4410a0a1d306b0` preserved all 28
  site files and the previous update items.
- On this Mac, Sparkle offered 0.1.2 to installed 0.1.1, downloaded it, and
  completed Install and Relaunch. Version 0.1.2/build 3 then passed signature,
  Gatekeeper, neutral-note retention, editing, Undo, and Redo checks.
- The app bundle was removed to Trash and reinstalled from a new public DMG
  download. The app reopened as 0.1.2 and retained the neutral note. Existing
  preference values were retained; only Sparkle's last-check time differed.
  Data was retained deliberately. This is not an empty-library installation
  test or a new CloudKit synchronization acceptance.
- At the 0.1.2 checkpoint, the public site selected that version for both
  download buttons and release notes.
  Old public tags and assets remain unchanged.
- Website follow-up PR #17 passed website CI and was integrated at `c22e4df`.
  Firebase version `cfa7ec5f7a704616` adds the top GitHub link and corrects the
  initial DMG fallback to 0.1.1. All 28 files and the signed feed were preserved.
  Both public buttons and notes were checked in the browser. After 0.1.2,
  the release site source variable was updated to its verified `3922ee3`
  checkpoint, matching the live site's source label.

- The clean-install correction is integrated in main through PR #13, merge
  `1ea567e`. Required PR CI run `41226934559` passed.
- Public release: [0.1.1](https://github.com/pobrespandas/draftly/releases/tag/v0.1.1).
  The signed and notarized DMG passed a clean macOS 26 VM installation without
  a repair helper or manually written marker. Both preference domains were
  empty and the local library was absent before launch.
- GitHub public assets and the promoted signed appcast passed verification.
  Both website download buttons were observed pointing to the 0.1.1 DMG.
  Existing site files and the 0.1.0 appcast item were preserved.
- The user authorized correcting the early, still unpublished 0.1.1 tag to
  integrated `1ea567e`. Only that tag was excepted temporarily; the original
  protection and active tag workflow were restored before publication.
- A later read-only inspection found 0.1.1 in the habitual installation. This
  does not establish a full migration or update acceptance check. Source,
  package validation, publication, and installation are separate states.

## Repository and CI cleanup

The cleanup branch separates check selection from native execution. Its final
required check preserves the existing protected-check name. Release preflight
rejects unchanged package inputs before it allocates native or signing jobs.
See [CI and publication](ci-cd.md) for selection rules and validation.
These changes are integrated through PR #14 (`e8c832c`). Its full hosted CI
run `41230093909` passed, including native tests and local app compilation.

Publication and cleanup integration are complete. Preserve the published tag
and assets. Website-only CI run `41230802922` passed website tests and the required
Ubuntu result; native, script, and matrix jobs were skipped. The saved earlier classifier commit
`74cd477` remains preserved on its original branch; the cleanup replaces its
partial design rather than discarding that branch.

## Evidence and open acceptance

- PR #19 shares the disposable Git fixture between the CI and release selector
  tests. All 16 focused cases and names remain. Full hosted CI `41235528547`
  passed before integration at `894b81c`. No redundant test removal was justified.
- Automated publication is configured but not yet accepted end to end.
  Signing, staging, and publication flags are enabled after the DMG transfer
  correction passed CI. Publisher identity and lock handling passed the
  Ubuntu-only run `41236743915`. No app was built or published by that check.
  The 0.1.2 release used local publication tools. Its tagged commit includes
  a skip instruction, so it did not exercise the tag-triggered workflow.
- PR #21 fixes missing DMG files in the candidate artifact. Its regression
  failed before the fix and passed afterward. All 285 Python tests, actionlint,
  and matrix structure passed locally; hosted CI `41236763902` passed the
  script path without a native app build. The fix is integrated at `8f1c565`.
  A real hosted signing-to-publication run remains pending for the next app
  release with package changes. See the release guide.

- The release fix passed complete local Swift reports: 759 Core and 937 app
  tests. Its Python suite passed 268 tests and website tests passed three.
  Hosted manual and PR CI runs also passed. These totals are not API coverage.
- The Actions matrix structural check passes. The strict engine check still
  reports 18 diagnostics across six partial contracts. Cleanup must preserve
  those classifications and their evidence.
- The API inventory contains 572 members: 161 complete, 187 partial, 219
  unclassified, three unavailable, and two excluded. These are inventory
  categories, not a compatibility percentage. The matrix is authoritative.
- Keep the accepted microphone evidence. Do not repeat it without a distinct
  unresolved case. Hardware, permissions, native behavior, and reference
  comparison remain separate evidence types.

Use [engine acceptance](research/engine-native-checklist.md),
[API compatibility](compatibility.md), [Settings acceptance](settings-personalization-2026-10-22.md),
and [UI acceptance](ui-flows-2026-10-21.md) for their remaining cases.
The [previous consolidated snapshot](archive/project-progress-before-cleanup-2026-10-31.md)
and [historical checkpoints](archive/status-before-cleanup-2026-10-31.md)
retain older implementation and acceptance records.

## Next work

1. The user accepts the generic iCloud storage icon for now. See
   [iCloud identity](icloud-identity.md) for the private-record investigation
   and authorized cloud-data deletion. Draftly disappeared from Manage Storage;
   cloudqa deletion remains unverified. Keep the existing container identifier.
2. Continue Actions and editor contracts, inspector and integrations, Settings,
   and remaining data/synchronization acceptance from their subsystem records.

Keep `com.pobrespandas.draftly`, team `NM92LU2KKV`, `draftly://`, and container
`iCloud.com.andrestobelem.draftly`. Keep Note, identities, original scripts,
unknown imported fields, old libraries, backups, Nerd Fonts, and preview.
Offline tests remain deferred. Mac plus VM is the current two-client setup.

The ignored `docs/claude-handoff.md` contains local paths and active operation
journals. Use it when present; do not commit credentials, raw logs, screenshots,
package outputs, or personal data. The tracked summary must remain sufficient
for a new checkout to find the next step.


## Preserved work in other checkouts

The main checkout at `~/ws/pp/draftly` contains previous uncommitted website
changes and local skill deletions. It remains unchanged by this cleanup; its
branch was not reset or updated over that work. The cleanup checkout is clean.
Preserve and review those independent changes before updating that checkout.


## Preserved open PRs

PR #9 retains the separate first-staging recovery proposal. Its workflow
conditions need review against the new preflight before integration. PR #11
is now closed. Its source-link purpose is retained by the website follow-up.
Old cancelled checks do not establish acceptance. Preserve both branches.
