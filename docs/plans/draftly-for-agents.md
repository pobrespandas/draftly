# Draftly for agents

Status: implementation proposal. Updated: 31 October 2026.
Code reviewed at `290d558`. This document plans work; it does not claim that
an agent interface, permissions, or remote access already exists.

## Goal and accepted decisions

Make Draftly a complete tool for external agents while the person can continue
writing. Support notes, the editor, organization, Actions, Workspaces, Settings,
themes, syntax, imports, exports, backups, and existing native integrations.
Use the product mission, values, and constitution to guide the design.

Accepted by the user:

- Support local and remote agents. Implement local access first.
- Plan remote access now, but implement it in a future stage.
- Initial remote access uses a private network or VPN, not a public service.
- Authorize reading, writing, and execution as separate capabilities.
- Include administration of Actions and scripts, Settings, themes, syntax,
  imports, and backups. A narrower notes-only endpoint is not the final goal.
- Keep irreversible deletion, backup restoration, and permission grants under
  human control. Agents can request these operations, not approve themselves.
- Review code and software design as part of preparing this capability.

This expands the earlier exclusion of MCP for this proposed work only. It does
not add an embedded model, a model subscription, a Pro edition, a public relay,
or direct access to CloudKit. Existing app functionality remains available.

## Architecture and code review

Read the [targeted architecture audit](../research/agent-readiness-audit-2026-10-31.md)
for source evidence, risks, and required extractions. Keep useful existing
boundaries. Do not perform a repository-wide cosmetic refactoring.

The app process remains the sole owner of LibraryStore, editor state, windows,
and native operations. An agent process never opens Library.sqlite directly.
Add a concrete application service, AgentCommandService, with serialized inputs
and outputs. It coordinates existing commands; it does not copy domain rules.
Its handlers receive explicit library, editor registry, permission store,
operation registry, and native-host dependencies.

Use three implementation boundaries:

1. An internal AgentContracts target contains Sendable request and result types,
   schemas, operation identifiers, and capability descriptions. It has no AppKit,
   Core Data, JavaScriptCore, or network dependency.
2. Application handlers validate grants, resolve targets, coordinate edits and
   invoke existing Core rules and native adapters. MainActor owns mutations.
   Permission evaluation is pure; I/O adapters enforce its decisions.
3. A bundled `draftly-agent` executable provides JSON CLI and MCP stdio adapters.
   Both use the same operation registry and reach the app through a private
   Unix-domain socket. The executable contains no alternative library writer.

Use the official Swift MCP SDK, pinned initially to 0.12.1, and its documented
2025-11-25 baseline. Newer protocol versions require an explicit compatibility
change. Do not rely on experimental MCP task features for operation correctness.
The current public specification has changed since that baseline; see sources.

The socket lives in a per-user directory with mode 0700 and socket mode 0600.
Use a short random path under the user's temporary directory; keep its locator
in local app support. Validate ownership and reject symlink substitution.
Requests use bounded length-prefixed UTF-8 JSON. Only one app broker owns the
library endpoint. Delete stale endpoints only after ownership and liveness checks.
The CLI may launch the installed app in the background after connection setup;
first-use approval uses Draftly UI. If access is disabled, return a clear error.
On screen lock, pause new agent requests and cancel pending interactive work;
external effects already submitted can only be reported, not assumed reversed.
No local TCP listener, global command symlink, login daemon, or automatic client
configuration change is installed by default.

## Connection and permissions

Add Settings > Agents: enable local access, connect a client, review capabilities
and targets, expire or revoke access, stop work, and inspect recent activity.
The feature starts disabled. Provide copyable configuration for clients and the
absolute bundled executable path. Give connections user-visible names; a name
supplied by an agent is not proof of identity.

Pair with an ephemeral challenge displayed by the app and approved by the person.
Store a distinct high-entropy credential for each approved connection in Keychain.
The helper accepts a connection UUID and obtains its credential from Keychain.
Limit Keychain access to the signed app and helper; verify this in the installed
package. Never put a token in command arguments, files, URLs, logs, or MCP tool
descriptions. A session is tied to its connection, grant,
library, and service epoch. Expiry defaults to one hour. The user can explicitly
choose renewable access; every request still checks expiry and revocation.
Credentials and grants are local device state, excluded from sync and backups.
A same-user process that steals a credential is outside this boundary's isolation
claim; pairing does not sandbox all software running as that macOS user.

Grants allow either a whole library or explicit resource IDs. Default to selected
IDs and read access. New drafts created within an authorized task are added to
its target set. A Workspace is a saved query, not an access-control container.
If used to choose targets, resolve and display its current IDs at approval time;
future matches are not silently authorized. Reads, counts, snippets, resources,
logs, and events must all filter unauthorized data before returning results.

Capability families:

| Capability | Authorized work | Additional conditions |
| --- | --- | --- |
| drafts.read / drafts.write | Read, search, create, edit, organize and recover drafts. | Target IDs and revision checks. Trash is recoverable. |
| editor.read / editor.write / ui.present | Read editor context, edit ranges, select, navigate or show UI. | Explicit window ID; focus changes require ui.present. |
| actions.read / actions.manage / actions.run | Inspect definitions, edit Actions/groups, execute selected Actions. | Execution does not imply permission for all script effects. |
| workspaces.read / workspaces.manage / workspaces.apply | Query, manage and apply definitions. | Apply needs a window and presentation access. |
| appearance.read / appearance.manage | Themes, syntax and preview configuration. | Preserve unknown fields and stable IDs. |
| preferences.read / preferences.write | Documented, typed local preferences. | Exclude credentials, connection grants and system permissions. |
| files.read / files.write | Import/export and existing file utilities. | User-approved bookmark roots; canonical path checks. |
| backups.export / backups.restore | Export full backup or request restore. | Full-library authority; restore needs a one-use human approval. |
| native.use | Individual integrations. | Separate service, destination and effect grants. macOS permissions still apply. |
| scripts.unrestricted | Shell, AppleScript, external Shortcuts or unrestricted native automation. | Explicit broad-access warning and one-use human approval. |
| destructive.request | Request purge or permanent resource deletion. | Exact targets and one-use human approval. |

Approvals bind the normalized request, targets, expected versions, and grant.
They expire after five minutes, are consumed once, and become invalid on edits,
revocation, or service restart. Agents can inspect pending status or cancel;
there is no tool that grants access or accepts an approval. Denial and expiry
are distinct results. An operation needing a system permission reports that
need and lets the person act in macOS; it never approves a system prompt.

## Operation coverage

Generate CLI commands, MCP tools, schemas and documentation from one registry.
Expose named operations, not a generic endpoint that evaluates arbitrary code.
Each entry defines inputs, outputs, required capabilities, side effects,
interaction needs, implementation status and contract tests.

| Family | Required operations |
| --- | --- |
| Discovery | Server/version/status, granted capabilities, operation schemas, library summary scoped to the grant. |
| Drafts | List, search, get metadata/content, create, update, UTF-16 patches, duplicate, merge, archive, trash, restore, flag, tags, syntax, versions and revision restore. |
| Queries | Existing query language, dates, exclusions, flags, folder and sort; normal/search snippets, pagination. |
| Editor | Enumerate authorized windows; get current draft, text and selection; navigate, range edits, tasks, markers, links, find/replace, Undo/Redo, open a target window and preview. |
| Actions | List/get/create/update/duplicate/move/reorder/delete; groups, sections, visibility, shortcut validation; all existing step descriptors and unknown payload preservation. |
| Execution | Start, inspect, wait, cancel and obtain final report; included/queued Actions, prompts and pending human input. |
| Workspaces | List/get/query/create/update/duplicate/reorder/delete/apply; folders, filters, presentation, groups and themes. |
| Personalization | Typed preference schemas/get/update/reset; fonts/layout, local shortcuts, bookmarks, Markdown/HTML, themes and syntax install/replace/reload/export. |
| Import/export | Existing formats with validate/preview/commit; field preservation and atomic import behavior. |
| Backups | Validate/export/preview restore/request restore, preserving existing conflict recovery rules. |
| Native services | Existing file, clipboard, HTTP/XML-RPC, HTML, mail/messages, calendar/reminders, Shortcuts, speech, location and model operations through guarded handlers. |
| Activity | Grant-scoped changes, operation state, affected resource IDs and audit summaries. |

Read-only rendering never loads remote content without the appropriate network
permission. File operations use approved roots and existing bookmark handling;
block traversal, escaped symlinks, and implicit access to another root.
Network grants name allowed services, hosts and ports. Check redirects and
resolved destinations as well as the first URL; sending draft content requires
both draft-read authority and destination authority. Reading clipboard content
and writing it are separate effects. Treat application-opening URLs as native
launch effects, not a way to bypass network or execution grants.
Secret preferences and Keychain values are never returned by a settings tool.
Reset affects specified preference keys, not data or grants. Changes to login
behavior, global shortcuts or OS integration require human confirmation.

Interactive operations declare their needs before execution. A noninteractive
request returns interaction_required instead of opening a panel. With authorized
interaction, prompts and SelectPrompt accept typed answers bound to operation
and step IDs; secure input and protected OS prompts stay in native UI.
Do not expose arbitrary JavaScript evaluation in an HTML preview.

The registry is the complete inventory. An existing unsupported operation must
return unavailable with a reason, never a successful placeholder. Legacy
compatibility gaps stay visible. They cannot be reclassified merely to close
the agent project. An operation is complete only when all its included fields
have handlers, permission checks, and tests.

## Requests, consistency and results

Use versioned JSON contracts. IDs are UUIDs and dates are ISO 8601 UTC. Return
structured results and a concise text summary; never make clients parse a
localized status string. Use stable errors: invalid_input, permission_denied,
not_found (also used to conceal unauthorized resource IDs), version_conflict,
editor_conflict, busy, interaction_required, unavailable, storage_error,
cancelled, timeout, outcome_unknown, and retry_window_expired. Include a
request ID and retry guidance without leaking unauthorized resource details.
Inputs specify library ID, explicit resource/window
IDs, an operation/request ID, and expectedVersion for mutations.

Lists default to 50 items, maximum 200. Use grant-bound opaque snapshot cursors
with a ten-minute lifetime and a stable UUID tie-breaker. An expired or invalid
cursor returns an error, not a silently restarted page. Cap each JSON message
at 8 MiB; read large content in UTF-16 chunks. Stage larger imports and backups
as bounded chunks with a verified digest and a total 256 MiB initial limit.
Reject larger data explicitly. Stream processing and later adjustable limits
must not block MainActor. Initial limits are product defaults, not performance
acceptance thresholds.

Return an opaque expectedVersion token derived from the complete editable
resource state. Exclude access-date changes for draft write conflicts. Include
a generation for pending editor edits so edit-then-revert is also detectable.
The service resolves current editor content as well as stored content. Divergent
unsaved windows return editor_conflict; never choose one silently. Agent writes
apply a compare-and-set at the same serialized mutation point as persistence.
On conflict, return the current token only if the caller can read the target.

Extract an application edit coordinator to apply visible text edits through the
existing editor mutation and synchronization rules. Maintain selection with
UTF-16 validation and one Undo group per accepted agent edit. Update peer views
without focus theft. History-based agent restore checks the current version;
it is not an unconditional overwrite. Visible Undo/Redo needs an explicit window
and rejects a stale target or stack token. Headless edits use revisions rather
than pretending that an invisible editor has the user's Undo stack.

Read/search does not count as editor access. Explicit opening does. Keep the
current meaning of unknown historical access dates. Query and mutation logic
must reuse TagRules, Workspace evaluation, EditorFindQuery, syntax definitions,
ActionCatalog, and existing persistence validation.

Mutations return success only after storage succeeds. Validate an entire batch
before writing it. Library-only data batches are atomic; external integrations and
Actions are not rollback transactions. Cross-store batches that mix library
writes, preferences, Keychain or external effects are rejected. Local preference
changes use a write-ahead operation record and verify the stored values. After a
crash, reconcile those values or report outcome_unknown; do not claim that a
UserDefaults write and a Core Data receipt formed one transaction. Record completed effects if a later step
fails. Keep the existing Note type, IDs, unknown data, library location and backup
compatibility. Add generic records and optional backup fields only when needed
and covered by migration tests on copies.

## Execution, retries and recovery

Use operation states queued, running, waiting_for_user, succeeded, failed,
cancelled, timed_out and outcome_unknown. Persist operation ownership and
metadata locally. Every handle belongs to its connection and grant. Revocation
blocks reads of that handle and cancels ongoing work at the next effect boundary.
Operation handles survive transport reconnects, but not silent authority renewal.
A cancelled write that has already committed returns its committed result, with
cancellation recorded as too late. Never report rollback of a completed effect.
Expose operation get/wait/cancel to every transport. An MCP client without task
extensions can poll the same handle. Transport disconnect is not cancellation;
explicit cancellation, expiry, app quit and revocation have defined cleanup.

For library data writes, persist an idempotency receipt in the same Core Data transaction
as the resource mutation. Use a new generic record kind, with request ID,
connection identifier hash, normalized request hash, affected IDs and resulting
version tokens. Store no credentials or raw request content there. These receipts
may follow the existing library's sync; grants and local audit logs never do.
Receipt entries are not part of user backup exports. A restore changes the local
service epoch and invalidates prior retry handles before accepting new work.
Keep receipts for 30 days; older keys return retry_window_expired and require
fresh review, not automatic replay. A reused key with different inputs is invalid.
Issue signed retry keys from the service with their creation time, grant and
epoch bound into them. This lets the service reject expired keys even after
receipt cleanup. Clients obtain a key before each new mutation; they reuse that
key only for the same request. Verify authorization before returning any receipt.

Actions and native side effects use a local operation journal written before
starting each effect. Do not claim exactly-once mail, HTTP or shell execution.
After a crash, reconcile data receipts; mark unresolved external effects
outcome_unknown and never replay them automatically. Included and queued Actions
inherit the same principal and cannot widen authority. Recheck grants, target
scope, action version and approvals at each effect boundary.

Call ActionRunner.runAsync through a new agent adapter with the existing
per-library execution exclusion and ActionExecutionReport. Do not expose the
current first-name match as an agent identity lookup: use action UUIDs. Bind
execution to a snapshot of the Action and included definitions; changes after
approval require new approval. Preserve legacy callers through an explicit
interactive-user execution context, rather than implicitly trusting missing
agent context.

Permission checks must cover typed ScriptCommand, dispatchAPI, native host
calls, HTTP/XML-RPC paths, template file reads, queued/included Actions and final
tag/flag/folder effects. An ActionHost wrapper alone is insufficient. Unknown
agent-origin operations are denied. Shell, AppleScript and external Shortcuts
cannot be constrained by note IDs after launch; require unrestricted approval,
show the broader scope, and retain OS controls. Script creation/editing does not
implicitly authorize execution.

Local activity records default to 30 days and contain IDs, timestamps, operation
names, result codes and effect summaries. Omit note text, script source, tokens,
URLs with credentials and prompt answers. Let the user clear this local history.
Treat note content, tool output and imported scripts as untrusted data, not
instructions to expand access. Provide client guidance about prompt injection;
no server can guarantee a model will interpret every note safely.

## Interfaces and compatibility

The CLI has `status`, `connect`, `capabilities`, `call`, and `mcp` entry points.
`call` accepts a named operation and JSON on stdin; it uses the same schemas as
MCP tools. Stdout contains JSON or MCP frames only; diagnostics go to stderr.
Use exit 0 for completed results or accepted operation handles, 2 for invalid
input, 3 for authorization, 4 for conflict, 5 for unavailable, and 1 for other
failures. Final operation failures remain explicit in structured output.

MCP uses named tools and scoped draft resources. Offer optional user-invoked
prompts for capture, organization, and reviewing edits. Resources and prompts
have the same authorization checks as tools. Publish a separate agent-use skill
with connection setup, safe read/edit/verify flows, revision conflicts, approvals
and operation polling. Keep this skill distinct from the repository development
skills. Its instructions never grant authority; the app enforces grants. Do not require sampling or client
elicitation to perform core work. The server provides no LLM itself.

Keep existing URLs and App Intents working. Move shared validation and data
commands behind common handlers in separate compatible changes. Preserve their
current user confirmation behavior and return formats. Do not silently attach
agent grants to legacy external links or treat those routes as bypasses for an
agent credential. Document that macOS-user-level software can still invoke other
user-authorized app interfaces outside this scoped API's security boundary.

## Delivery stages and acceptance

1. **Contracts and architecture characterization.** Inventory all operation
   families and native effects against existing descriptors and code. Add
   characterization tests for save order, Cancel, unknown fields, queries,
   conflicts and native cleanup. Record every entry's owner, permission,
   input/output schema and coverage. Preserve current uncommitted documentation
   separately. Close when the inventory has no unspecified operation or effect.
2. **Local broker and authorization.** Add contracts, app service, socket,
   helper, pairing, grants, approvals, local journals and Settings > Agents.
   Implement discovery and read-only access. Close when unauthorized callers
   cannot obtain titles, counts, content, resources, errors or activity, and
   disable/revoke closes access without modifying library content.
3. **Drafts, queries and editor.** Extract only the required edit coordinator
   and common query commands. Add mutations, version tokens, transaction
   receipts, batches, Undo and headless revisions. Close after concurrent
   human/agent writes, multi-window conflicts, Unicode, retry and storage-failure
   tests preserve text and selection.
4. **Actions and native effects.** Thread authority through every runner path;
   add management, groups, scripts, prompts, operation handles and native grants.
   Close after direct, included, queued, async and final effects enforce grants,
   cancellation and final results. Existing scripts and user routes remain valid.
5. **Workspaces and personalization.** Expose complete management, editor
   options, themes, syntax, bookmarks and typed settings through existing rules.
   Close after cancel/save/reopen, missing references, unknown data and field-level
   consumer checks pass. Changes preserve content, selection and Undo.
6. **Import/export, backups and recovery.** Add staging, preview, atomic commit,
   one-use restore/deletion approvals and old-backup acceptance. Close after
   failed import, crash recovery, ambiguous effects and backup round-trips retain
   identities and do not restore credentials or grants.
7. **Local release acceptance.** Test real installed clients, CLI, permissions,
   accessibility, disable/revoke, upgrade and uninstall behavior. Ship the signed
   helper with the app and test Sparkle updates on Mac and VM. Publish local
   setup guidance and operation reference. Claim support for Codex and Claude
   Code only after each real client has passed its own end-to-end session.
8. **Future remote stage.** Implement the design below only after local closure
   and renewed user authorization. Its pending status does not hide missing local
   work or count as delivered remote support.

Each stage reuses accepted native evidence where the path is unchanged. Do not
repeat the accepted microphone tests. New permission and cancellation boundaries
need their own focused checks, not a blanket repetition of private-data tests.

Each stage uses atomic scoped commits, focused tests then the necessary full
checks, an isolated manual QA session where required, and updated progress and
handoff. Keep functional fixes separate from refactorings. Do not remove existing
contract tests merely because new transport tests look similar. No app release
is needed for this planning-only document.

## Future remote design — planned, not implemented

Reuse contracts, grant checks, operation handles and app authority. The first
remote route runs the bundled MCP stdio helper through SSH over a private network
or VPN. SSH account/key setup remains a human system task; do not enable Remote
Login or alter firewall rules automatically. The helper still needs a Draftly
grant; network or SSH access alone does not grant library access.

A later private HTTPS adapter can expose Streamable HTTP for clients that cannot
launch SSH. Bind only an explicitly selected private/VPN interface, with valid
TLS, host/origin validation, bounded requests and connection-specific authority.
Use MCP OAuth authorization code with PKCE and resource-bound tokens, not one
shared static token for every user. Keep grants and approvals owned by the Mac.
Do not build public hosting, a relay, or browser-accessible internet exposure as
part of local work. Verify protocol and SDK versions again before this stage.

The Mac must be online, unlocked and running Draftly in its user session. If
asleep, disconnected or locked, return unavailable or interaction_required.
Do not queue new mutations for later surprise execution. Mark in-flight effects
according to their known state; reconnection queries operation handles and never
blindly repeats an external effect. Remote connections pause on screen lock;
local grants also cannot approve protected UI while locked.

Remote acceptance adds two-client isolation, wrong-host and invalid-token tests,
TLS validation, revoked SSH/MCP grants, dropped connections, sleep/restart,
no-public-interface exposure, and the same operation coverage as local access.
Public ChatGPT/Claude services cannot reach this private route by assumption;
that requires a separately authorized public connectivity design.

## Validation and definition of done

Automated tests use in-memory or temporary stores, preferences, sockets and
injected hosts. They do not open/activate/move windows, request permissions,
record audio, send mail or use personal data. Test framing, malformed messages,
size/rate limits, unknown versions, replay, approval tampering, expired grants,
path traversal, out-of-scope searches, events and action effects. Use a per-client
limit of four active requests, one mutation at a time per library, and the
existing one-Action-per-library rule; return busy rather than an unbounded queue.

Run both Swift inventories, Python, structural Actions audit, local and signed
builds after integration. Add schema/inventory checks so deleting a required
operation cannot make closure pass. Protocol conformance tests use a real SDK
client over stdio. Manual QA covers the actual editor, Undo/Redo, pairing,
approvals, prompts, native cancellation, real client setup and signed updates.
Native permission and hardware blocks remain recorded per operation.

Local completion requires every included registry entry to have implementation,
specific tests, applicable manual evidence and a working UI/agent path. A genuine
system limitation needs evidence and a contractual unavailable response. A known
partial implementation is not complete. Report implemented, automatically tested,
verified in real use, user-confirmed and blocked separately. Remote remains a
separate future acceptance. Neither local completion nor this plan declares
Draftly's full cloning or CloudKit acceptance finished.

## Sources and protocol evidence

Consulted on 31 October 2026:

- [MCP current specification](https://modelcontextprotocol.io/specification/latest)
  resolved to 2026-07-28. It differs from the selected released SDK baseline.
- [Swift SDK 0.12.1](https://github.com/modelcontextprotocol/swift-sdk/releases/tag/0.12.1)
  was the latest release returned by the official repository during this review.
- [Pinned SDK README](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/README.md)
  documents the 2025-11-25 protocol baseline and stdio support. Reproduce against
  this release, not an unpinned main-branch example.
- [MCP security guidance](https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices)
  informs credential handling, scope checks and transport separation.

These sources support protocol choices, not a claim of client interoperability
or security certification. Those require the tests and sessions above.
