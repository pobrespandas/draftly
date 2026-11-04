# Agents and AI readiness

Updated: 4 November 2026. Work is on [PR #105](https://github.com/pobrespandas/draftly/pull/105).
Agents and AI are not complete or ready for an agents release.

This is the current status summary. The operation and chat checkpoints retain
historical evidence. A passed test applies to its recorded source and path.

## Latest bounded acceptance

The installed editing and Stop Work QA block is complete. Signed `f6f6190` and
`e9528d1` checked CLI/MCP edits, native Undo/Redo, conflicts, scope denial,
replacement, expiry, revocation, review cancellation, and uncertain effect
recovery without replay. Signed `13c3b1e` completed a real GPT-6.1-Sol editor
mutation and verification after fixing finalized stream-item handling. Full CI
[41765000703](https://github.com/pobrespandas/draftly/actions/runs/41765000703)
passed for that source. Read [installed editing acceptance](agent-editing-acceptance.md)
for the evidence and limits. QA is closed, grants are revoked, access is off,
and original shared preferences are restored. PR #105 remains in draft.
This closes one QA block. It does not close the broader readiness work below.

## Scope

Include Draftly's own local MCP server, CLI, Chat Console, Apple Intelligence,
and direct ChatGPT. Keep agent access off by default. The app owns the library,
editor, permissions, operation results, and native effects.

External MCP servers and inbound remote access through SSH, VPN, or HTTPS are
out of scope. New Mastodon, Dropbox, Box, Google Docs, OneNote, WordPress, and
Ghost integrations remain excluded. Existing native operation contracts remain
in the inventory. Model-provider authentication stays separate from local
agent pairing and grants.

## Status and evidence

| Area | Implementation and integration | Installed evidence | Remaining acceptance |
| --- | --- | --- | --- |
| ChatGPT account | Direct official OAuth, Keychain records, model catalog, session renewal, and account controls are connected. | The signed QA completed sign-in and restored the account after full process exit without another browser login. | Real renewal, uncertain renewal recovery, remote sign-out, and multiple-account behavior. |
| Chat Console tools | Shared MCP tool definitions, completed function calls, bounded continuation, and native consent are connected to the QA host. | GPT-6.1-Sol used `drafts.list` and `drafts.get`. It returned the exact approved Unicode draft text. Native activity confirmed both calls. Signed `13c3b1e` also completed one real editor mutation and verification. | Provider-inference cancellation and the remaining operation families; see the bounded installed checks above for editor recovery and conflicts. |
| Consent and grants | The chat creates a separate connection for the current draft and editor. Reading and editing are separate choices. The grant expires after 15 minutes. | The user approved reading. A fresh native pairing on signed `2ea267b` granted exactly `drafts.read` and `editor.read` for one draft and window. Another draft returned `not_found`; draft/editor writes returned `permission_denied` without text changes. The existing MCP process and a new CLI request were denied after the actual deadline. | Other resource families and their installed negative cases. Draft/editor editing scope, actual prepared-write expiry, and unexpired revocation passed in the bounded follow-up. |
| Keychain and helper | The app creates the connection credential. The signed helper uses it to authenticate. | The installed helper returned the same limited capabilities. This proves sharing for that QA connection. | Broader client setup and failure-path acceptance. |
| Installed MCP | The bundled helper exposes the local service through bounded stdio MCP. | A fresh native helper pairing negotiated `2025-11-25`, listed read tools, omitted write tools, and read the approved draft. It denied another draft and remained open through pause, resume, and actual expiry. | The bounded Codex and Claude Code editing flow passed on signed `fdc05d2`; other operations and post-update sessions remain open. |
| Revocation | Disconnect closes the chat session, revokes its connection, and removes its credential and revoked metadata. | An existing MCP process denied its next read. A new CLI request returned `permission_denied`. No draft text returned after revocation. | Revocation after native handoff and installed storage-failure cases. Revocation before a prepared draft write passed in the follow-up. |
| Stop Work | The host suspends transport, reviews, and operations. | On signed `2ea267b`, Stop Work set access off, withdrew publication, and denied the existing authorized MCP reader. Explicit resume let that same process read again without changing grant or expiry. | Broader native-effect interruption paths. Signed `e9528d1` passed Stop Work from a pending native review and process-interruption recovery after Share handoff. No external transmission was performed. |
| Restart | Account and conversation persistence are connected. A new host does not start a listener automatically. | The signed QA retained account and conversation after process exit. Access remained off. | A follow-up signed QA from `2ea267b` retained the selected ChatGPT model after verified process exit. Tools stayed disconnected and access stayed off. Other model/provider restart paths remain pending. Test permission and result recovery for the remaining operations. |
| Normal startup and lock | Builds with a bundled helper now construct an idle host outside QA. The default admission check requires a known console session, completed login, and protected data. Suspension notifications invalidate access before their main-thread callback returns. | Prior installed QA started with access off. Signed isolated QA exercised shared startup, lock suspension, explicit resume, one-second sleep, and unavailable-session restart. | Real screen lock, sleep/wake, initial locked startup, and explicit resume. Protected-data availability is not a guarantee of graphical unlock. |
| Distribution | App and helper profiles and signatures are checked. | Both ran installed with matching Developer ID identities. | Combined notarization, final release packaging, architecture checks, signed updates, and post-update CLI/MCP sessions. |
| Apple Intelligence | On-device and eligible Cloud modes use the same scoped local tool session as ChatGPT. Cloud requires the signed PCC entitlement and runtime availability. | A real on-device model read the expected neutral Unicode draft through the gateway in an isolated fixture. Native tool argument tests also prepared and applied one scoped edit. | Installed read/write, real-model edit decisions, live inference cancellation, Cloud eligibility and distribution, and Cloud inference. |

The signed session used neutral data in a temporary library with iCloud off.
The normal library was not opened. The QA exited and its original shared
preferences and saved window state were restored. Its separate ChatGPT account,
chat history, and library remain available for follow-up.

The follow-up signed read-only QA ended at the configured deadline
`2026-11-03T13:53:30Z`. At `13:53:32Z`, its existing MCP process returned
`permission_denied` without draft text. A new CLI read also failed. The host was
still published, and the grant record was enabled, unrevoked, nonrenewable, and
unchanged from before expiry. This distinguishes expiry from a manual stop or
revocation. The QA then stopped, revoked the test connection, and exited.
Shared preferences and saved window state were restored from the fresh backup.

## Normal startup follow-up

The normal path requires the bundled helper executable. Host construction still
validates the signed application identity and its Keychain entitlements before
creating agent state. Construction does not start transport or restore access.
A host failure does not stop the writing library from opening. The isolated QA
now uses the same startup and session admission path instead of a fixed unlocked
adapter.

Core Graphics console and login properties reject missing or inactive sessions.
They do not establish screen-unlocked state. Apple distinguishes protected-data
availability from graphical screen lock and does not guarantee equivalence.
See [Apple DTS on screen-lock state](https://developer.apple.com/forums/thread/850327)
and [session properties](https://developer.apple.com/documentation/coregraphics/window-server-session-properties).
Real screen-lock acceptance remains open. No private lock keys or notifications
have been added. The final focused run passed 54 application-host and local-host tests. The
native QA build passed. Signed installed QA checked default-off startup, lock
suspension, explicit resume, a one-second hardware sleep, and unavailable-session
restart. Read [session lifecycle acceptance](agent-session-lifecycle-acceptance.md)
for the evidence and remaining checks.

## Named-client handshake follow-up

Codex CLI 0.166.0 failed during initialization before it could request tools.
Its actual request contains `experimental: {"codex/auth-change": {}}`.
Swift MCP SDK 0.12.1 decodes experimental values as strings and rejects this
object. Draftly does not negotiate experimental client extensions. Its bounded
stdio transport now omits that unsupported capability object from SDK dispatch.
It keeps the protocol version, client identity, standard capabilities, request
ID, and original byte budget. Tool calls and authorization are unchanged.

The actual Codex request now completes initialization and ping through the SDK
in a regression test. All 20 MCP boundary and host tests passed. Installed
Codex and Claude Code sessions remain unaccepted. The first Claude probe also
exposed no tools while the local host was paused. The signed installed helper
accepted the captured Codex request after the correction. The QA is now closed,
the read grant is revoked, and original shared preferences are restored.

## Workspace creation and duplication

`workspaces.create` and `workspaces.duplicate` now have connected handlers.
Creation uses `WorkspaceDefaults` and then applies explicit input fields.
Duplication preserves the canonical metadata and uses a new identity. Both
require library scope because they create a resource outside a fixed selection.
Existing selected-resource `workspaces.update` remains supported.

The shared workspace component owns version checks and durable receipts.
Preparation does not write. Lost replies and service restart recover the same
receipt without another copy. Storage failure, revocation, expiry, and lock
before commit leave no new workspace. Existing identities cannot be overwritten
through creation. Results return a resource receipt, not readable metadata.

The final focused run passed 130 tests across service, availability, Workspace
schemas, and permission policy. The normal native build, without the agent QA
flag, passed. Project-generator tests passed two checks. Installed creation and duplication acceptance remain pending. Full CI
[41781501330](https://github.com/pobrespandas/draftly/actions/runs/41781501330)
passed at `01635d5`, before the window-application follow-up.

## Workspace order snapshots

`workspaces.reorder` now has a connected handler. Library-scoped lists return
an optional opaque `orderVersion` through the existing frozen-page mechanism.
Selected-resource lists omit it. Metadata or membership changes invalidate
library-scoped continuation pages and prepared reorder requests. Reorder
requires library scope and every current Workspace exactly once. It changes
only order values and returns receipts for the same resource set.

The batch uses the existing atomic Workspace commit. Storage failure leaves
the prior order intact. Retry and service-restart recovery return the original
receipt without another reorder. The final focused run passed 146 tests across
service, availability, Workspace/read schemas, and permission policy. The
normal native build passed. Full CI
[41781501330](https://github.com/pobrespandas/draftly/actions/runs/41781501330)
passed for `01635d5`. Installed order acceptance remains pending.

## Workspace window application

`workspaces.apply` now has a connected window adapter. It needs the selected
Workspace, the selected live window, `workspaces.apply`, and `ui.present`.
The expected version comes from `workspaces.get`. Preparation does not apply
the view. The native route resolves presentation references before it checks
the active session, unchanged grant, version, and window at the first view
effect. The general effect gate still blocks effects that need human approval
unless a review adapter handles them.

Integration tests preserve editor text, selection, dirty state, and stored
library data. They deny draft and editor reads without those permissions.
Empty windows work. An active Action returns `busy` and is not cancelled.
Stale definitions and closed targets fail. Native presentation failure before
submission can retry. A lost session or window after submission returns
`outcome_unknown`; reconnection does not replay it. Successful repeats return
the original receipt without replacing a later view change by the person.
These receipts belong to the host lifetime, not to the stored Workspace.

The final run passed 243 tests across service, availability, host, native
Workspace contracts, MCP, Workspace schemas, and permission policy. The normal
native build passed without the QA flag. Project-generator tests passed two
checks. Full CI passed for `f32f9d9` in
[41784775217](https://github.com/pobrespandas/draftly/actions/runs/41784775217).
Installed application acceptance remains pending. Direct Workspace deletion
still needs its review handler. Its storage transaction passed 18 focused tests;
that groundwork does not expose a new handler.

## Workspace deletion

`workspaces.delete` is connected only when the host supplies review and operation
control. Normal startup supplies those components and keeps access off by
default. A request waits for app review, checks its active session and Workspace
version again, and commits one deletion with a durable storage receipt. Drafts
remain. Stop Work cancels pending review. Completed retries return their result;
terminal states are not encoded as `accepted`.

Recovery can replace an unknown deletion result only with matching atomic
storage proof. It checks the request, connection, grant, and resource, then saves
the result without repeating the effect. Other terminal journal results stay
immutable. Tests reject foreign and duplicate result IDs. The final run passed
258 tests across 12 suites. The normal native build passed. Full CI for this
increment and installed acceptance remain pending.

## Draft metadata batches

Archive, trash, restore, flags, and tags now have direct handlers. They commit
all authorized targets with one receipt and synchronize pending editor state
through the shared mutation boundary. List and search pages provide a version
for their exact returned target set; the token grants no access. Tests cover
rollback, revocation, concurrent edits, scope, and repeats without another write.
The final run passed 266 tests across 16 suites. The normal native build passed.
Full CI and installed acceptance for these handlers remain pending.

## Draft syntax

`drafts.syntax` now uses the atomic metadata handler. Installed definitions
require `appearance.read` and resource scope. Built-in names use the app's
public definitions. The commit checks the stored definition again. Tests cover
Unicode names, changes in definition identity and content, and repeat results
after a later rename. The run passed 265 tests across 13 suites, and the normal
native build passed. Full CI and installed acceptance remain pending.

## Draft request session boundary

The service now supplies an exact active-session check to draft preparation and
writes. Each storage commit checks that session again. A persisted grant alone
cannot keep an invalidated request session alive. Seven regression cases prove
rollback and retry from a fresh session across the draft write paths. The run
passed 234 tests across ten suites. The normal native build passed. This is
source-level evidence; installed lifecycle acceptance remains pending.

## Draft creation scope

Create and Duplicate require library scope. A grant for named existing drafts
cannot authorize a new draft identity. Merge has the same scope rule. The shared tool catalog hides all
library-only tools from resource-scoped connections. Direct calls still check
the live policy. The run passed 238 tests across ten suites. The normal native
build passed. Full CI and installed acceptance remain pending.

## Draft merge

`drafts.merge` now commits one new draft and all original draft effects with a
durable receipt. It uses the native text and tag rules, an exact source version
set, and explicit content order. Library scope is required. Storage errors,
stale sources, editor changes, and ended authority prevent a partial merge.
Service recreation recovers the same result without another write, even after
a later user edit. New draft receipt tokens now match the first reader version.
The final run passed 270 tests across 13 suites. The normal native build passed.
Full CI, installed merge acceptance, and process-restart acceptance remain open.

## Apple model tool bridge

The console can attach tools to Apple models without a ChatGPT account. Model
names and data destinations appear in native consent. Changing the provider or Apple mode
revokes the prior connection. The response-scoped adapter uses the current
shared tool catalog and checks authorization again at execution. It has bounded
calls, a monotonic deadline, and cancellation checks across asynchronous reads.
The routine run reported 222 tests in nine app suites and three in one contract
suite, with the opt-in live probe disabled. A separate explicit on-device probe
passed using a neutral in-memory fixture. It verified an actual read and the
expected content. This is not installed-app or Cloud acceptance. The normal
native build and two project-generator checks passed.

Cloud access is conditional. Apple's [PCC access requirements](https://developer.apple.com/private-cloud-compute/)
require Small Business Program membership, fewer than two million first-time
App Store downloads, and an assigned managed entitlement. The documented routes
are App Store distribution and TestFlight or ad hoc tests. Developer ID website
distribution is not accepted as a compatible Cloud route by this project.
Account eligibility and approval have not been verified. The production mode
list now checks the actual signed entitlement as well as model availability.
No managed entitlement was added. Read [Apple's server-model guide](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)
for the platform and quota rules. Keep Cloud inference and tools in the goal;
the on-device result does not close that requirement.

## Reviewed draft purge

`drafts.purge` is connected when the editor, draft writer, native review store
and operation registry are present. It requires explicit destructive authority,
the exact target version set and a prepared request. The native review shows
only those trashed drafts and warns that their versions will be deleted without
Undo. Changes to stored or pending text, an ended session, denial or cancellation
prevent deletion. Commit rechecks authority, retry binding and editor state.
Only the selected drafts, revisions and access records are removed. Other Trash,
active drafts and action history remain. A matching atomic receipt can resolve
an interrupted operation without another delete. The recovered result persists
in the operation journal. The focused run passed 256 tests across ten app suites
and three tests in one contract suite. The normal native build passed.
Installed purge acceptance and full CI remain open.

## Theme reading

Five theme read contracts use app-owned catalog, preference and file routes.
Listing filters installed themes by resource scope without reading their files.
Selection hides an installed reference outside scope. Definition and export
reads check authority before and after resolution. File themes require
`files.read` and use the saved theme bookmark with a bounded regular-file read.
Failures return no cached definition. Exports support native JSON, Drafts JSON
and portable installation URLs. Imported Drafts fields remain in Drafts exports.
The focused run passed 150 app tests, 26 Core tests and three shared-tool
contract tests. The normal native build and two project-generator checks
passed. The nine mutation contracts, installed acceptance and full CI for this
increment remain open.

## Theme mutation

Creation, custom-theme update and duplication now use atomic theme receipts.
Creation and duplication require library scope. Update binds one custom theme
and its current version. A file duplicate requires `files.read`, rereads the
current file at commit and becomes a portable custom theme. Direct file update
requires the native Reload or replacement route. Theme selection is separate.
The handler rechecks cancellation and exact active authority after resolution.
Receipt recovery through a new service does not overwrite later user changes.
The focused run passed 163 app tests, 26 Core tests and 16 contract tests. The
normal native build and two project-generator checks passed. Six remaining
theme mutations, installed acceptance and full CI remain open.

## Current CI and installed-client state

Full CI [41808994708](https://github.com/pobrespandas/draftly/actions/runs/41808994708)
passed for `abd4e2d`, including strict inventory verification. The earlier live
probe skip rejection is resolved for that source. Full CI
[41813362305](https://github.com/pobrespandas/draftly/actions/runs/41813362305)
passed for diagnostic source `fdc05d2`. The signed GUI shows `console=true`,
`login=true` and `protectedData=false`. Admission stays off before pairing.

CI [41815621541](https://github.com/pobrespandas/draftly/actions/runs/41815621541)
failed on `2e28255`: a plain draft-reader catalog included transfer cancellation.
The shared capability predicate now requires file read or file write. The local
official SDK tests passed after that correction. The combined source, including
CLI transport recovery and backup readers, passed the complete strict Swift
inventory: 1 consumer, 183 contract, 822 Core and 1,599 app tests (2,605 total).
The normal native Debug build and two project checks passed. Full CI
[41818926971](https://github.com/pobrespandas/draftly/actions/runs/41818926971)
passed for `6ec09f6`. The later bookmark and cursor changes have local evidence
below; their full CI and installed acceptance remain required.

Signed isolated source `fdc05d2` passed real Codex CLI 0.166.0 and Claude Code
2.1.316 sessions after the user unlocked the Mac. Each client read the approved
draft and editor, received `not_found` for the other draft, prepared one append
with the current editor version and verified it. Native UI showed both lines.
The connection was revoked before expiry; a fresh CLI call was denied. Access
was disabled and QA closed. Read [client acceptance](agent-codex-claude-acceptance.md).
This accepts the tested flow only. Other operation families, lifecycle gates
and post-update client sessions remain open.

Full CI [41823966856](https://github.com/pobrespandas/draftly/actions/runs/41823966856)
passed for bookmark and cursor source `b667fe1`. Installed acceptance of those
later handlers remains open.

## Bookmark catalog and CLI pagination

`bookmarks.list` now filters resource scope and returns aliases, IDs and version
tokens without paths or saved permission bytes. IDs bind the alias, permission
bytes and a persisted local generation. Native Settings and Action writes use
that same store. Replacement, forgetting/recreation and corrupt metadata do not
redirect an old scoped grant. Failed identity persistence publishes no new ID.
The grant picker and resolver share the service's preference domain and expose
current bookmark and theme targets.

Cursors now survive CLI transport closure under the same connection and grant.
Other connections, changed grants, invalidation and Stop Work cannot reuse them.
Membership, query/target binding and both clocks retain their existing rules.
The real socket/CLI request test reads the next page and excludes hidden drafts.

The complete strict local run verified 1 consumer, 183 contract, 822 Core and
1,608 app tests (2,614 total). The native Debug build and two project checks
passed. A focused test checked invalidation with no remaining transport.
Installed acceptance and full CI remain open. Bookmark add/forget review and
file-source effect routes remain unfinished.

## Backup export, validation and restore preview

`backups.export`, `backups.validate` and `backups.previewRestore` now have direct
handlers. They require an explicit whole-library grant and their declared
capabilities. Export and preview also require editor tracking. Export preserves
pending text in saved drafts in its transfer without saving it. Credentials,
local file permissions and agent grants stay outside the backup model.

Validation and preview use the existing `LibraryStore.restore` in disposable
libraries. Preview reports only incoming counts and created/updated counts for
each collection. It does not return library content. Its version token binds
the source bytes and current stored library. Different pending editor bytes
return `editor_conflict`, including canonically equivalent Unicode text. The
engine's current conflict rules still apply, including keeping both draft
versions. No live library record is changed.

Inline and completed owned-transfer sources work. Bookmark and HTTPS sources
return `interaction_required` without reading a file or sending a request;
their native effect review paths remain open. No installation URL can enter the
backup route. `backups.requestRestore` remains unavailable until its reviewed,
version-bound mutation and recovery path is connected. The three source-set
handler names therefore do not prove complete backup or installed acceptance.
The combined source passed the complete strict Swift run: 1 consumer,
183 contract, 822 Core and 1,599 app tests. The native Debug build and two
project checks passed. Installed acceptance and full CI remain open.

## Scoped transfers and draft exports

All five declared `transfers.*` handlers and `exports.drafts` now connect to the
service. Buffers belong to one authorized connection and its exact grant. Export buffers
also retain their original draft scope. Transfer handles do not authorize work
in the operation registry. A new CLI transport with the same credential can
resume a transfer. Connection invalidation and Stop Work remove buffers. A
replaced grant, expiry or a different connection cannot read or cancel them.

Uploads use canonical Base64 chunks, byte offsets, a declared size and a SHA-256
digest. Finish prepares bytes only. It does not import library data. Imports
remain unavailable. Exports use current authorized draft snapshots, including
pending editor content. The existing backup format can include versions of only
those drafts. Text export accepts one draft and no versions. Export does not
flush editors, save library changes or write a destination file.

Limits are 32 MiB per transfer, 64 MiB reserved per host, 16 transfers and 64 KiB
per chunk. A transfer expires after five minutes or at grant expiry. A monotonic
deadline prevents clock rollback from extending it. Cancelling owned bytes requires file read or file write capability and
returns no content. A plain draft reader does not receive the cancellation tool. Other transfer operations retain
their declared read or write capabilities. Validation passed: 142 app tests,
180 contract tests, one consumer test, two project checks and the normal native
Debug build. Installed acceptance and full CI for this increment remain open.

## Installed syntax export

The service now connects `syntaxes.export` for a granted installed syntax. It
returns source text or a portable installation URL with bounded UTF-16 chunks.
File sources require `files.read` and a bounded read of the saved bookmark.
The handler rejects oversized, missing and non-regular files. It does not
change the library or select a syntax. The focused run passed 134 app tests,
30 Core tests and 13 appearance contract tests. The native Debug build passed. Installed acceptance and full CI for this
increment remain open.

## Bounded operation waiting

`operations.wait` observes an operation owned by the same connection. It
returns on completion, a pending human review or a bounded observer timeout
of 1 to 30 seconds. A timed-out or cancelled observer does not cancel the
underlying work and does not replay its effects. The registry allows at most
16 active observers. Socket and Chat Console requests use the asynchronous
service path, so a wait does not block other requests.

The observer checks current authorization while suspended and before returning
bytes. Revocation, changed grants, resource-scope changes, lock and session
invalidation prevent delivery. The helper allows five seconds of transport
margin for a maximum-length wait. Ordinary requests retain their 30-second
transport budget. The focused 199 tests and the native package-name build
passed. A strict full recheck verified 2,622 tests after an earlier unreported
Intent-process exit. Read [wait validation](agent-operation-waiting-acceptance.md).
Full CI [41829611557](https://github.com/pobrespandas/draftly/actions/runs/41829611557)
passed for `0f2b863`. Installed wait acceptance remains open.

## Reviewed action deletion

`actions.delete` now requires an app-owned human review, a prepared retry key
and the exact action version. The review shows the action name and states that
drafts and action history remain. Denial, cancellation, stale versions and
session invalidation prevent deletion. The storage transaction commits the
single action deletion and its receipt together. It shares the record-deletion
boundary used by Workspaces. A recovered request returns its receipt; it does
not delete a later action with the same ID. The operation journal can recover
a committed deletion after an uncertain result. No action-group deletion
handler is claimed by this change. Strict validation verified 1 consumer,
184 contract, 823 Core and 1,618 app tests (2,626 total). The native package-name
Debug build and two project checks passed. Tests cover six review decisions,
storage rollback, restart recovery and preservation of a recreated action.
CI and installed acceptance remain open.

## Reviewed action-group removal

`actionGroups.delete` follows the native removal rule. It moves member actions
to `General`, or to `Imported` when removing `General`. It keeps actions,
drafts and history. Scoped access must include every member action and the
destination group. Creating a missing destination requires library scope.
An empty group needs only its own resource scope. Both saved and implicit
groups use the same native staging function.

The app-owned review lists member names and the destination. Its binding
includes member IDs and versions. Changed members invalidate the review.
Storage commits the moves, group removal and receipt together. Recovery returns
the old result without moving recreated members or removing a recreated group.
The focal run passed 55 app tests in five suites and one Core test. Strict
validation verified 1 consumer, 184 contract, 824 Core and 1,621 app tests
(2,630 total). The native package-name Debug build and two project checks
passed. The first full attempt failed in the existing Intent Shell-start
fixture; its controlled-clock correction and final full run passed. See
[fixture validation](intent-shell-interruption-validation.md). Full CI
[41845487513](https://github.com/pobrespandas/draftly/actions/runs/41845487513)
passed for `b5985f1`. Installed group-removal acceptance remains open.

## Direct native requests

Thirteen typed native operations connect to existing adapters through an
app-owned execution environment. The latest six add dictation, transcription,
location, Shell, AppleScript and Shortcuts. Each concrete request needs native
consent. The host is created after approval and current authority checks.
Unrestricted automation requires library scope and its separate capability.
App startup still leaves access off.

Private output stays in memory. Journal recovery reports missing output rather
than repeating effects. Accepted work survives submitting-transport closure;
revocation and Stop Work still invalidate it. Request identity preserves distinct
Unicode bytes. Read [direct native validation](agent-direct-native-acceptance.md),
[transport lifetime](agent-accepted-operation-lifetime.md),
[request identity](agent-request-byte-identity.md) and
[the result-retention decision](adr/0005-agent-transient-native-results.md).
Strict validation verified 1 consumer, 193 contract, 824 Core and 1,634 app tests
(2,652 total). Native Debug build and two project checks passed. Real Shell tests
checked literal Unicode arguments, exit status and parent/child cancellation.
Installed acceptance of capture and automation and CI for this increment remain
open. The previous source `18a6e14` passed
[full CI](https://github.com/pobrespandas/draftly/actions/runs/41849728024).

Individual request records and operation indexes now remove the persistent
128-record limit. The old array remains as recovery evidence. A format marker
prevents older apps from ignoring new identities. There is no automatic pruning;
disk use grows with accepted work. Current validation and remaining installed
migration and storage-failure checks are in the
[retention review](agent-operation-retention-review.md).

## Direct editor preview

`editor.preview` now sets app-owned preview visibility without flushing pending
text. It requires the window and current draft in scope and both presentation
and draft-read capabilities. Active Actions, custom previews and composition
block it. Generation checks reject changes before submission. The journal
recovers results without another presentation. Local tests include real native
Undo/Redo and unchanged drafts and versions. Signed installed presentation is
still open. See [preview validation](agent-editor-preview-acceptance.md).

## Direct editor navigation

`editor.navigate` now uses the native visible list and selection path. Scope
must cover its window, source and destination. Pending saves require draft-write
permission. Stored content, pending editor state and list changes are checked
before selection. The registry records implicit affected drafts. Authority loss
after saving prevents later loading and returns an uncertain result without
replay. See [navigation validation](agent-editor-navigation-acceptance.md) for
local evidence and remaining installed and update checks.

## Direct editor opening

`editor.open` now supports explicit windows with their expected version and
new windows through the app-owned authorized scene factory. Source/window/target
scope and pending-save rights are checked before replacement. New window IDs do
not broaden a grant. Journal recovery never creates another scene or reloads an
editor. Source validation passed 174 focal tests, all 2,678 strict Swift tests and
the native Debug build. Installed focus, presentation and post-update client
acceptance remain open. See [opening validation](agent-editor-opening-acceptance.md).

## Direct theme selection

Installed and built-in selection now share native reference preparation and use
an atomic preference-domain commit for references and revision. The request binds
selection and target theme versions. File themes require file-read permission.
A final validation boundary and durable operation records protect scope, storage
failure and retries. The 177 focal tests, 2,685 strict Swift tests and native Debug
build passed. Signed installed appearance and process-restart checks remain open.
See [selection validation](agent-theme-selection-acceptance.md).

## Operation coverage

The required-operation manifest contains 137 names. A source-set review found
114 names in implemented or conditional handler sets. The other 23 names have
no direct handler in those sets. These counts do not prove that 114 operations
are complete, always available, or accepted in an installed app.

The review used `AgentCommandService.implementedOperations`, its conditional
availability, the draft/editor/preference writer sets, and the required
manifest. `server.schemas` remains authoritative for a configured connection.
Some native effects already run through reviewed Actions; that does not supply
a direct handler for every `native.*` contract.

| Family | Direct contracts still outside those handler sets |
| --- | --- |
| Syntax | `syntaxes.delete`, `syntaxes.install`, `syntaxes.reload`, `syntaxes.replace` |
| Bookmarks | `bookmarks.forget`, `bookmarks.requestAdd` |
| Imports | `imports.commit`, `imports.preview`, `imports.validate` |
| Backups | `backups.requestRestore` |
| Native operations | `native.http`, `native.xmlrpc`, `native.fileRead`, `native.fileWrite`, `native.htmlPreview`, `native.mail`, `native.messages`, `native.calendar`, `native.reminders`, `native.scanDocument`, `native.models` |
| Operation control and activity | `operations.answerPrompt`, `activity.changes` |

Keep the full [operation inventory](research/agent-operation-inventory.md) and
[required manifest](../Tests/AgentContractsTests/required-operations.txt).
Reconcile overlapping commands through existing domain rules. Do not remove a
required contract merely to reduce the unfinished count. Advertise a tool only
when its handler is connected and its current grant permits it.

`editor.undo` and `editor.redo` now use native editor history, prepared mutations,
version checks, and host-lifetime receipts. A 102-test service/editor run passed,
including read-only denial and replay without another Undo. Installed acceptance
for these two handlers remains pending.

`editor.tasks` now uses the current syntax task rules and the native replacement
path. Editor versions include syntax source, name, and feature state. A syntax
change rejects a prepared task edit even when text has not changed. The final
104-test service/editor run and native QA build passed. Installed task editing
acceptance remains pending.

`editor.replaceAll` now uses the shared find query with bounded replacement,
native selection preservation, and one native Undo change. The final focused
run passed 113 tests, and the native QA build passed. Output is limited to
8,388,608 UTF-16 units. Matching checks cancellation and a 250 ms deadline at
Foundation progress callbacks. A single template expansion also has a memory
bound. This is not a hard timeout for regex compilation or a separate worker.
Installed-client replacement acceptance remains pending.

The registry and private journal now support typed results for other reviewed
operations. They preserve names, capability checks, request identity, completed
effect records, and uncertain recovery. No additional handler is advertised.
App handlers must still connect their native approval and effect paths. The
service/host integration run passed 162 tests; the final registry/journal run
passed 24 tests after stricter result validation. Native-effect acceptance is
still pending.

The operation registry now shares task launch, deadlines, and interruption
handling between Action results and typed results. A separate operation
authorization component checks the current grant, scope, expiry, host, and lock
state. The registry still owns operation state and the journal owns durable
request identity and recovery. The focused integration run passed 164 tests,
and both project-generator checks and the native build passed. Cancellation
coverage includes queued and running work for both result kinds, with retries
that do not start work again. Installed acceptance for this refactoring remains
pending.

## Responsibility boundaries

| Boundary | Responsibility |
| --- | --- |
| `AgentContracts` | Operation vocabulary, schemas, permission rules, and shared tool definitions. |
| App service and editor registry | Library ownership, current editor projections, versions, Undo, and mutations. |
| Local host and connection registry | Local lifetime, grants, pairing, credentials, suspension, and revocation. |
| MCP and CLI adapters | Protocol framing and dispatch through the authenticated app service. |
| ChatGPT provider | Model authentication, streamed inference, and function-call continuation. |
| Apple model adapter | Native model inference and response-scoped tool callbacks through the same authorized service. |
| Chat tool session | The approved local session, exact library binding, current context checks, and duplicate-call rejection. |
| Native consent and effect review | The person's grant decision and any separate one-use effect approval. |

A model-provider account identifies the person to the model service. A Draftly
agent connection defines local authority. Signing in alone grants no draft
access. The console invokes the authenticated app service in process and shares
its tool definitions with MCP. It exposes no inbound HTTP server.

## Next work

1. Test other resource families and the remaining native-effect paths. Reuse
   the completed bounded editing, pending-review Stop Work, uncertain recovery,
   scope denial, expiry, and revocation evidence above.
2. Connect normal host startup only after lock behavior and default-off access
   have passed their checks. The QA adapter cannot satisfy this gate.
3. Reconcile and implement the missing operation contracts. Validate editor
   editing, Undo, concurrency, cancellation, and recovery through installed
   clients. Complete non-native effect result records and durability checks.
4. Complete model-account renewal/revocation acceptance, Apple Cloud acceptance,
   remaining model/provider restart paths, and chat reliability checks.
5. Complete full relevant CI, final signed/notarized packaging, update testing,
   and each named client's acceptance before publication.

## Next acceptance: editing and Stop Work

Use the glossary terms **Stop Work**, **Agent cancellation request**, and **Unknown agent
outcome**. A cancellation request is separate from its confirmed outcome. Stop
Work does not perform Undo or revoke a saved connection.

Keep the existing responsibility boundaries:

- The connection registry owns grants, scope, expiry, and revocation.
- The local host suspends access and invalidates pending reviews and sessions.
- The operation registry owns cancellation requests and operation outcomes.
- The editor owns edits, version checks, and native Undo history.
- The mutation receipt and operation journal retain the evidence for recovery.
- Native review presents the person's decision. It does not widen a grant.

CLI, MCP, and Chat Console must use these same rules. Do not add a separate edit
or cancellation rule for one client.

Test these cases in an installed signed QA with a limited editing grant:

1. Request an edit, then use Stop Work before the edit starts. Confirm that the
   text is unchanged and that no later callback applies the edit. Report confirmed
   cancellation only when the app has evidence that work stopped.
2. Complete an edit, then use Stop Work. Preserve the completed change and its
   native Undo entry. Confirm that a retry does not apply the edit again.
3. Use Stop Work while a native review is open. Confirm that the review cannot
   authorize a later effect, including after explicit resume.
4. Stop an operation after an external effect starts but before its result is
   confirmed. Retain an unknown outcome. Do not retry the effect automatically.
5. Change the draft manually while an agent edit waits. Reject a stale edit and
   preserve the person's change and Undo history.
6. Expire, revoke, or replace the grant before an edit is applied. Reject the old
   authority even when the replacement grant has the same scope.

The current registry can request cancellation and retain unknown outcomes for
running work. These scenarios still need installed acceptance. Do not equate a
cancelled task with a confirmed absence of effects. Do not add an automatic Undo
path to make a cancellation look complete.

## Action catalog component

`AgentActionAccess` owns agent catalog reads and action and group mutations.
`AgentCommandService` keeps session authorization, request dispatch, and action
execution admission. Both components use the existing version key, retry keys,
and read pages. Mutation validation, commit checks, receipt recovery, and page
scope checks keep their prior behavior. No operation or capability is added.
The focused integration run passed 164 tests in four suites. The two project
generator checks and the native Debug build passed. Installed acceptance and
full CI for this extraction remain pending.

## Connected operation availability

`AgentOperationAvailability` maps connected handlers to operations and derives
host capabilities from those operations. The service uses this result for
request admission, mutation preparation, schema availability, and connection
settings. Grant checks remain separate. Missing execution or operation-control
handlers do not expose `actions.run`. Preference writes can remain available
without an editor. Losing the draft writer withdraws the dependent mutations.
No handler, grant, or normal host startup is added by this refactor.
The focused run passed 169 tests in five suites, including partial-handler
configurations. The two generator checks and native Debug build passed. Full
CI and installed acceptance for this change remain pending.

## Stop Work in native review

Installed QA from `f6f6190` showed that the native effect review sheet blocked
Settings and had no Stop Work button. The sheet now calls the existing Stop Work
command directly. It closes only after that command succeeds. Failure leaves the
review open and shows the model error. No permission or cancellation rule changes.
The QA native build passed. Installed acceptance passed on signed `e9528d1`: Stop Work closed the review,
withdrew access, and cancelled the operation without native effects. Explicit
resume did not restore the review or replay the request.
[Installed editing acceptance](agent-editing-acceptance.md) records the CLI, MCP,
native Undo, concurrency, grant replacement, and actual prepared-write expiry
checks and their limits. The QA is closed, its test grant is revoked, and the
original shared preferences are restored. The corrected native review control,
unknown native-effect recovery through CLI and MCP, and denial of an unexpired
prepared write after revocation passed in the resumed signed QA. Real Chat Console editing passed on signed `13c3b1e`; the
connection was revoked after verification. Full CI
[41758319817](https://github.com/pobrespandas/draftly/actions/runs/41758319817)
passed for `882b945`, including the review correction.

## Validation references

- Full CI [41643931168](https://github.com/pobrespandas/draftly/actions/runs/41643931168)
  passed for installed QA source `2ea267b`.
- Typed-result source `ff7d42d` has focused integration and native build evidence
  above. Its own full CI remains pending. The installed permission QA used
  `2ea267b`; it did not test the later typed-result framework.


- Full CI [41598564068](https://github.com/pobrespandas/draftly/actions/runs/41598564068)
  passed for native consent commit `698c883`.
- QA isolation commit `e891051` has 30 focused tests, two generator checks, a
  native QA build, and the signed installed evidence above. Full CI [41608020603](https://github.com/pobrespandas/draftly/actions/runs/41608020603)
  passed for `33b8b41`, which includes that change. The 78-test consent/lifecycle run preceded that QA-only change.
- [Chat checkpoint](chat-console-checkpoint.md) records the source, native QA,
  local evidence location, and acceptance limits.
- [Operation checkpoint](agent-operation-checkpoint.md) retains earlier signed
  editing, Action, restart, and recovery evidence with its original limits.
- [Local development](agent-local-development.md) describes signed QA setup.

Implementation, integration, installed QA, and publication are separate gates.
None of the checks above establishes a published agents feature.

The [operation retention review](agent-operation-retention-review.md) records
the global-capacity reproduction and the requirements for a safe replacement.

Live admission now releases terminal durable cache entries and resolves retries
from the journal before applying capacity limits. Active jobs keep their slots.
The later indexed journal removes the persistent count limit. See the operation
retention review for current scope and remaining acceptance checks.

The live-cache correction passed the strict complete inventory: 1 consumer,
193 contract, 824 Core and 1,637 app tests (2,655 total). Native Debug build passed.
Full CI and installed acceptance of this correction remain open.

Indexed journal validation passed the strict inventory: 1 consumer, 193 contract,
824 Core and 1,640 app tests (2,658 total). After the final missing-marker guard,
39 focal tests and the final native Debug build passed. Full CI of the final
source and installed migration/update acceptance remain open. See the retention
review for exact validation scope and logs.

Direct editor preview passed strict complete Swift validation: 1 consumer,
193 contract, 824 Core and 1,645 app tests (2,663 total). The 49 focal tests and
native Debug build passed. Full CI and signed installed presentation remain open.

Source review also found fixed 128-entry host-lifetime receipt maps in
`AgentEditorWriting` and `AgentWorkspaceApplication`. Their saturation and
reclamation still need validation. The indexed journal fixes durable reservation
capacity; it does not change these separate receipt maps.

Direct navigation passed strict complete Swift validation: 1 consumer, 193 contract,
824 Core and 1,649 app tests (2,667 total). The focused 172 tests and final native
Debug build passed. Full CI, installed focus/navigation and signed-update client
acceptance remain open. See the navigation report for scope and logs.

The [authorized new-window adapter](agent-authorized-window-opening.md) now
provides app-owned scene creation with authority checks and protected cleanup.
The later `editor.open` integration connects both forms to the service, scope
policy and durable registry; see its opening report. The adapter alone did not
increase operation coverage or establish installed opening acceptance.

CI for navigation source `0f9c51f` ended without running native or tooling jobs.
GitHub reported unavailable macOS arm64 runner capacity. Plan and matrix passed;
the aggregate check failed on cancelled selected jobs. See
[41869494074](https://github.com/pobrespandas/draftly/actions/runs/41869494074).
This leaves full CI acceptance open; no check was relaxed.

The authorized scene adapter passed strict complete validation: 1 consumer,
193 contract, 824 Core and 1,654 app tests (2,672 total). The earlier focused
19 opening tests and final native Debug build passed. `editor.open` service
integration and installed acceptance remain open; operation coverage is unchanged.

Full CI for prior source `cee030e` passed in
[41877332833](https://github.com/pobrespandas/draftly/actions/runs/41877332833).
Native build/tests, tooling, matrix, plan and the aggregate check all succeeded.
The later direct theme selection source still needs its own CI acceptance.

## Direct file-theme reload

The preference effect host now connects `themes.reload`. It validates the current
file definition token and advances the native presentation revision without
changing selection or library definitions. See
[reload evidence](agent-theme-reload-acceptance.md). Installed acceptance is open.

## Direct theme deletion

The host now connects `themes.delete` only with the app-owned review store and
operation registry. Use the stored token from `themes.list`. The operation keeps
drafts and source files, commits its deletion receipt with the record, and then
removes the saved bookmark. See [deletion review](agent-theme-deletion-review.md)
for cross-store limits and installed acceptance still required.

## Scoped local import input

Backup validation and preview now use the bounded local input resolver for
inline text, owned transfers and authorized saved directory bookmarks. HTTPS
input remains gated on its reviewed route. This does not connect theme installation
or replacement. See [local input evidence](agent-local-import-reading.md).

## Local theme installation and replacement

The preference effect host connects `themes.install` and `themes.replace` with
inline, owned transfer, scoped bookmark and installation-link inputs. File mode
captures a checked file permission. HTTPS resolution still needs its reviewed
route. Durable results prevent automatic replay of cross-store effects. See
[installation evidence](agent-theme-installation-review.md). These two names
remain conditional on host components and source support, not release acceptance.

## File-theme permission versions

File-theme tokens now bind the saved permission without exposing permission bytes
or their hash. A same-content retarget invalidates stale local operations, including
pending destructive review. Installation result tokens match subsequent reads.
Strict 2,702 tests and native Debug passed. Installed retarget acceptance remains
open. See [installation evidence](agent-theme-installation-review.md).
