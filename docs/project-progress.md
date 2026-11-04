# Project progress

Updated: 4 November 2026. This is the maintained continuation summary.
Historical test reports describe only the versions they tested.

## Scoped transfers and draft exports — 4 November

The service now connects the five transfer contracts and `exports.drafts`.
Uploads prepare bounded bytes and verify their digest. They do not apply imports.
Exports freeze only selected authorized drafts and optional versions. Pending
editor content is included without flushing the editor. Text export accepts one
draft; the native format uses the existing backup model. No destination file is
written. Ownership binds the exact session, grant and source scope. Buffers have
size, count and expiry limits, including a monotonic deadline. Cancelling owned
bytes returns no content and does not require export permission.

Coverage is 85 connected or conditional names of 137. The remaining 52 names
still need direct handlers. Validation passed: 142 app tests across three suites,
180 contract tests across 26 suites, one consumer test, two project checks and
the normal native Debug build. Installed acceptance and full CI remain open.
Full CI for the earlier admission diagnostics, `fdc05d2`,
passed in [41813362305](https://github.com/pobrespandas/draftly/actions/runs/41813362305).
The retained installed QA is still that source, with access off and no new grant.

## Installed syntax export — 4 November

`syntaxes.export` now returns source text or a `draftly://syntax` installation
URL for the exact granted resource. Export preserves source data and supports
UTF-16 chunks. File exports require `files.read`, read the current bookmarked
file, and reject oversized files and non-regular files. A missing file returns
`unavailable`. Export does not change the library or select a syntax.

The source inventory now connects 79 of the 137 required names. The remaining
58 names still need direct handlers. The final focused run passed 134 app tests
across two suites, 30 Core syntax tests and 13 appearance contract tests. The native
Debug build passed. Installed acceptance for this handler remains open.

## Installed client preparation — 4 November

Full CI [41808994708](https://github.com/pobrespandas/draftly/actions/runs/41808994708)
passed for `abd4e2d`. This includes the routine inventory correction. A Developer
ID app and helper were built from that source, signed, verified and installed
in the retained isolated QA. The normal library was not opened. Cloud and
updates remain disabled. A fresh shared-preference backup is retained.

Startup showed access off. Signed helper discovery returned no endpoints.
Codex CLI 0.166.0 and Claude Code 2.1.316 both returned `QA_READY` through their
own existing logins, with no Draftly tools attached. The temporary client
workspace does not change global MCP configuration. Claude's bare mode skips
OAuth and Keychain reads; the successful probe instead used restricted mode
with memory, hooks and unrelated MCP servers excluded.

The user approved a new 15-minute connection for reading and editing only the
neutral draft and its editor. Enabling access failed before pairing or
credential creation. The host stayed off. The standalone AppKit sample showed
protected data unavailable, but an unlaunched CLI sample does not establish the
GUI app state. Read-only admission diagnostics were added only to the isolated
QA build. They do not bypass or change the gate. Both the normal native build
and the QA-flag native build passed. The signed GUI values and full client
calls remain to be checked. No new grant has started.

## Durable theme mutations — 4 November

Connected theme creation, custom-theme update and duplication. A theme definition
and its receipt save in one storage transaction. Creation and duplication need
library scope. Scoped custom-theme updates need the exact resource and current
version. File duplication reads the current bounded file with `files.read` and
creates a portable custom definition. Native file themes use Reload or targeted
replacement; direct update returns an interaction requirement. These operations
do not change the configured theme selection.

The commit rechecks the active session, grant, retry key, source version and
cancellation after source resolution. Recreating the service can prepare the
same intent and recover its original receipt without another write or replacing
later user changes. Imported fields use the native theme validator and Drafts
color updates. Duplicate identities and names fail before save.

A late-cancellation regression first reproduced the wrong `storage_error` result
with unchanged data. The handler now reports `cancelled`, keeps the old theme,
and permits a clean retry. The final focused run passed 163 app tests across
six suites, 26 Core tests across two suites and 16 contract tests across two
suites. The normal native build and two project-generator checks passed.

Source coverage is 78 connected or conditional names out of 137; 59 direct
handlers remain missing. Six theme mutation contracts remain. Installed theme
mutation acceptance and full CI remain open. Next, let the complete CI validate
the inventory fix and this source. Keep full installed Codex/Claude Code,
lifecycle, provider and distribution acceptance in scope before publication.

## Live Apple probe inventory — 4 November

CI [41804761088](https://github.com/pobrespandas/draftly/actions/runs/41804761088)
ran all 1,575 app tests with a successful process exit. The revised Apple schema
assertion passed. Strict verification then rejected the XML: the runtime-disabled
live probe appeared as a skipped case, and its suite count excluded that case.
The verifier correctly rejects selected tests that do not pass.

The live probe now requires the `DRAFTLY_APPLE_LIVE_QA` compile flag. Routine
builds do not register it in their inventory. Explicit QA still requires an
available model and an actual authorized fixture read. No verifier check was
relaxed and no live success was substituted. Eight routine Apple tests passed.
The existing strict verifier accepted their XML against the discovered inventory
and confirmed that the live probe was absent. Full CI remains pending.

## Apple schema CI check — 4 November

Full CI [41802527118](https://github.com/pobrespandas/draftly/actions/runs/41802527118)
failed for `4585453`. Its app test log reports one failure in the native Apple
tool-schema assertion. That assertion required a direct `enum` field in encoded
`GenerationSchema`. The test now reads equivalent finite string choices through
local definitions, constant alternatives and nullable alternatives. It rejects
unconstrained string alternatives and reference cycles. It compares the exact
name set with the authorized catalog. An unsupported encoding reports its
neutral schema for diagnosis. No production permission check was removed.

The local Apple and Chat Console run passed 19 tests in two suites. The opt-in
live inference probe was disabled. Full CI on the failing runner remains
required; local success does not prove that compatibility gate.

## Theme read contracts — 4 November

Connected the five theme read contracts: list, get, export, selection and
built-in export. Catalog pages filter by theme scope and reuse opaque cursors.
Selection hides an installed reference outside the grant. Definitions and
exports use version tokens. Native and installation exports preserve portable
custom definitions. Drafts export retains imported fields and applies current
editor colors before encoding. Built-in exports use the app installation URL.

File-backed definitions require `files.read` in addition to appearance access
and the exact theme scope. The app resolves its existing bookmark; a request
cannot supply a path. The agent read is bounded to the wire-size limit and
accepts only a regular opened file. It does not return a cached definition when
file permission, access, parsing or size checks fail. Native callers keep their
existing read behavior unless they request a byte limit.

The final focused run passed 150 app tests across five suites, 26 Core tests
across five suites and three shared-tool contract tests. Native and imported
exports round-trip. File reads detect current content, enforce the exact byte
limit and deny missing file authority. The normal native build and two project
generator checks passed. Source coverage is 75 connected or conditional names
out of 137; 62 direct handlers remain missing.

The nine theme mutation contracts remain unconnected. Installed read acceptance
and full CI for this increment remain open. Broader readiness is unchanged.

## Reviewed draft purge handler — 4 November

Connected `drafts.purge` to native review, prepared mutations, editor coordination
and atomic storage receipts. The handler is available only with all required
components. It requires destructive authority for the exact targets and version
set. It never expands a scoped deletion to all Trash. Native review explains
that versions are removed, action history remains and Undo is not available.
Denial, cancellation, an ended session and changed stored or pending content
prevent commit. A completed retry returns its result. A matching storage receipt
can resolve an uncertain journal after service restart without another effect.
The recovery path also retains its existing Workspace deletion checks.

The final focused run passed 256 tests across ten app suites and three tests
in one contract suite. It includes six reviewed purge outcomes, all availability
component combinations, durable recovery, Workspace regressions, MCP and host
checks. The normal native build passed.

Source coverage is 70 connected or conditional names out of 137, with 67 direct
handlers still missing. Installed purge acceptance and full CI for this
increment remain open. All broader client, lifecycle, provider and distribution
gates remain open.

## Deleted-draft editor coordination — 4 November

The editor registry can coordinate a reviewed deletion with its storage commit.
It checks current draft generations, conflicting pending text, running actions
and native editor interaction. The caller receives a validation callback for
the transaction boundary. A failed commit leaves pending editor text in place.
After commit, every matching tracked window cancels autosave and switches to a
new empty scratch draft without flushing the deleted text. Its native Undo
history is cleared by the draft transition. Cleanup remains synchronous if a
storage publication ends authority. Unrelated drafts stay open.

The first deletion test exposed an Undo fixture exception: the native draft
transition clears groups, so the fixture must not close a removed group. The
fixture now checks the group level before closing it. This change does not
alter the production Undo path. The handler still needs native review, exact
version binding, durable operation reconciliation and installed acceptance.
`drafts.purge` remains unavailable. Coverage remains 69 connected or conditional
operations and 68 missing direct handlers.

The final focused run passed 46 tests across five suites: editor mutation,
draft writing, native Trash, script Undo and range Undo. The normal native build
passed. These are source-level checks; installed deletion acceptance is open.

## Targeted Trash transaction — 4 November

A package-only storage operation can delete an exact nonempty set of trashed
drafts and save its mutation receipt in the same transaction. It removes the
selected drafts, their revisions and access records. It preserves unrelated
Trash, active drafts and action history. Empty Trash uses the same staging rule.
A completed request returns its receipt without another delete, including after
reopening the store. Live, missing and duplicate targets fail before commit.
This is storage groundwork for `drafts.purge`, not a connected agent handler.
Native review, editor coordination and installed acceptance remain open. The
operation coverage count stays at 69 connected or conditional and 68 missing.

The focused run passed 20 receipt tests and three native Trash-command tests.
A follow-up passed seven Draft operations tests and four resource-choice tests.
The normal native build passed. Full CI for this increment remains pending.

Before connecting the handler, bind review to the exact draft versions and
pending editor generations. Recheck scope, expiry and the active session at
commit. Detach deleted drafts from all tracked editors so later autosave cannot
recreate them. Record the submitted effect before commit. Reconcile an uncertain
journal only with its matching storage receipt. Verify denial, cancellation,
concurrent changes and service restart through the shared CLI/MCP route.

## Apple chat through authorized tools — 4 November

Apple chat modes now attach the same authenticated local tool session as ChatGPT.
The native adapter discovers only the current grant's tool names. It generates
common request fields natively and carries operation parameters as exact JSON
text. The app service still validates each complete request. Legacy script-model
callbacks are not connected to this chat path. Each response has a bounded tool
budget and a monotonic deadline. Cancellation or response completion closes its
callbacks. Checks also run across asynchronous catalog reads.

The permission dialog and activity connection name identify the selected
provider and data destination. A provider or Apple mode change disconnects the old tools. Apple
chat needs no ChatGPT account. Cloud choices require the real signed PCC
entitlement and runtime availability; no entitlement was added to this project.

Real on-device inference read the neutral allowed draft through the gateway.
The opt-in test passed in 7.384 seconds on macOS 27.2. It required an actual
`drafts.get` call and the expected Unicode content. It used only an isolated
in-memory library. No installed QA grant or user-library access was created.
Early probes exposed a wrong catalog name and an 8,192-token context limit.
Constrained tool names and native request fields resolved the successful probe.

The routine run reported 222 tests across nine app suites and three tests in
one contract suite. Its opt-in live test was disabled; the live result above
came from a separate explicit run. Tests cover scoped reads, typed native-tool
write preparation, receipt recovery, later editor text, cancellation during
catalog lookup, late callbacks, budgets, and model changes. Two generator checks
and the normal native build passed. The prior full CI for `1378c36` passed in
[41793052970](https://github.com/pobrespandas/draftly/actions/runs/41793052970).
Full CI for this increment is pending.

Installed Apple read/write, real-model edit decisions, and live inference
cancellation remain open. Cloud eligibility, compatible distribution, and Cloud
inference are not accepted. The 69 connected or conditional operation names and
68 missing direct handlers are unchanged. All broader readiness gates remain.

## Atomic draft merge — 4 November

Connected `drafts.merge`. It requires library scope, all source draft versions,
and an explicit order that names every target once. The native merge engine
builds the new Inbox draft. The handler commits it with the source changes and
one receipt. Archive, Trash, and Keep use the app's destination rules. Pending
source text is saved with revision protection. Existing editors keep their
current draft. Unrelated drafts remain unchanged.

Tests cover all destinations and separator modes, pending Unicode text, tags,
syntax, source revisions, scope denial, and failed commits. Storage failure,
changed sources, lost grants, ended sessions, and new editor text leave no
partial merge. A recreated command service returns the stored result without
another merge or overwriting a later user edit. This does not establish a
process-restart or installed-client acceptance result.

The final run passed 270 tests across 13 suites. The normal native build passed.
This run also validates the new-draft receipt version correction below.
Source-set coverage is 69 connected or conditional names out of 137, with 68
missing direct handlers. Full CI and installed acceptance remain pending.
Keep the broader lifecycle, provider, client, and distribution gates open.

## New draft receipt versions — 4 November

A regression test showed that Create and Duplicate returned a version token
that changed on the first read of the new draft. Receipt creation now uses the
same editor generation as the draft reader. The new token matches that first
read. Both failing cases now pass, and all 25 draft-writing tests passed.
This fixes the receipt path that Merge also uses. The Merge increment above
supplies integration and native build evidence. Installed acceptance remains
pending.

## Draft creation scope — 4 November

Create and Duplicate now require library scope. Their new draft identity cannot
belong to a grant that names only existing drafts. The Merge contract adopted the same rule before its handler was connected. Editing approved existing drafts
keeps its resource scope. No grant is expanded by this change.

The shared tool catalog now filters all operations that require library scope
when the connection has only resource scope. Direct preparation and execution
still enforce the permission policy. Tests check both routes and the catalog,
including rejection with an otherwise valid draft-write capability. Library
scope still permits creation and duplication.

The final run passed 238 tests across ten suites. The normal native build passed.
Full CI and installed acceptance remain pending. Operation coverage stays at 68
connected or conditional names, with 69 missing direct handlers. Keep all broader
client, provider, lifecycle, and distribution gates open.

## Draft request session at commit — 4 November

Draft preparation, storage commits, and receipt responses now check the exact
active request session as well as its persisted grant. Invalidating a session
before the storage commit rolls back the change. This closes a gap where the
grant could remain valid after the original service session had ended.

Seven cases cover creation, update, patch, duplication, version restoration,
flags, and syntax. They invalidate the service session at the commit boundary,
check stored drafts and revisions, and retry from a fresh session. The run
passed 234 tests across ten suites. The normal native build passed. Installed
lifecycle acceptance and full CI remain separate pending gates. Coverage stays
at 68 connected or conditional names and 69 missing direct handlers.

## Draft syntax mutation — 4 November

Connected `drafts.syntax` through the atomic metadata path. Built-in syntax names
need no installed-resource read. An installed name or ID requires
`appearance.read` and access to that syntax resource. Name lookup follows the
app's Unicode comparison rules. Before the storage commit, the handler checks
the selected stored definition's name, source, type, and identity again.
A completed receipt remains recoverable after a later definition rename.

The run passed 265 tests across 13 suites. Tests cover scoped installed lookup,
built-in batches, Unicode names, changes during commit, rollback, and retries.
The normal native build passed. Source-set coverage is 68 connected or
conditional names out of 137, with 69 missing direct handlers. Installed syntax
acceptance and full CI remain pending. The active-session increment above
adds a check at the draft storage boundary. Keep PR #105 in draft.

## Atomic draft metadata batches — 4 November

Connected `drafts.archive`, `drafts.trash`, `drafts.restore`, `drafts.flag`, and
`drafts.tags`. Requests support all authorized targets in one atomic transaction.
They use current per-draft state, including pending editor text, and durable
receipts. Shared editor synchronization now reserves every affected draft before
the storage commit. Failed grants, stale drafts, conflicting editors, and storage
errors leave no partial metadata batch. A recovered receipt does not repeat an
edit over later changes.

Nonempty draft list, search, and Workspace query pages provide `batchVersion`
for exactly their returned IDs. A subset or changed target set cannot use that
token. Single drafts keep their existing version tokens. The public combination
rule and an independent SHA-256 test vector are in the local development guide.
Trash and restore preserve archive state. Archive clears trash state. Tags use
the native normalization rules.

The final run passed 266 tests across 16 suites. It includes service, scope,
editor, storage-failure, receipt, MCP, and contract checks. The normal native
build passed. Source-set coverage is 67 connected or conditional operation names
out of 137, with 70 missing direct handlers. Full CI for this increment and
installed batch acceptance remain pending. Keep PR #105 in draft and preserve
all broader readiness gates.

## Workspace deletion service and recovery — 4 November

Connected `workspaces.delete` through explicit reviewed-mutation host wiring.
Normal startup connects the handler but keeps access off by default. Hosts that
do not connect both review and operation control do not advertise deletion.
The service returns `accepted` only for nonterminal work. Repeated completed
requests return the typed result or the recorded error. No editor permission
or library-wide scope is required for one authorized Workspace.

An atomic storage receipt can resolve an interrupted deletion journal entry.
Recovery checks the original request, connection, grant, target, and canonical
request hash. It records the completed result without deleting again. Ordinary
terminal journal results remain immutable. Missing storage proof leaves an
unknown result. The result contract rejects empty, foreign, duplicate, or extra
Workspace IDs. Stop Work removes the pending review and preserves the Workspace.

The final run passed 258 tests across 12 suites, including service, host, MCP,
review, journal, and Workspace contracts. The normal native build passed.
Source-set coverage is 62 connected or conditional names out of 137, with 75
missing direct handlers. Full CI for this increment and installed acceptance
remain pending. The broader readiness gates remain open. PR #105 stays in draft.

## Reviewed Workspace deletion flow — 4 November

Added the app-owned deletion flow to `AgentWorkspaceAccess`. Preparation binds
one Workspace, its version, and the current grant to a retry key. Review uses
a fresh Workspace name and version. The handler waits for an app decision,
checks the active session again, and records submission at the storage commit
boundary. A completed storage receipt can return without another deletion.
The review sheet names the Workspace, states that drafts remain, and uses a
destructive button without the default Return shortcut.

Tests cover approval, denial, cancellation, a changed Workspace, a lost session,
a revoked grant, storage rollback, and receipt recovery after reopening the
library. The combined run passed 160 tests in five suites. The normal native
build passed. This flow is not connected to service admission or host feature
availability yet. Reconciliation between a committed storage receipt and an
unknown operation journal still needs implementation and tests before exposure.
The missing-handler count stays at 76. Installed review acceptance is pending.

## Review cancellation groundwork — 4 November

Added an internal failure path for app-owned handlers that have not submitted
an effect. The operation registry records a known failure only when its effect
list is empty. If an effect was submitted, the same report remains
`outcome_unknown`. Ordinary cancellation after work starts keeps its existing
conservative result. All nine operation-lifetime tests passed, including both
new cases and request identity checks. The reviewed Workspace deletion handler
is not connected yet.

## Workspace deletion storage — 4 November

Added an app-owned storage transaction that deletes one saved Workspace and
stores its mutation receipt in the same commit. Failed final authorization
rolls back both records. A repeat after reopening returns the saved receipt
without another delete. Other Workspaces and drafts remain unchanged. Invalid
resource IDs and missing targets do not store a receipt. All 18 mutation-receipt
tests passed. This is storage groundwork only. It does not advertise or enable
`workspaces.delete`; review, service admission, and installed acceptance remain
pending. The missing-handler count remains 76.

## Agent Workspace window application — 4 November

Connected `workspaces.apply` through the native window route. It checks the
specific active session, grant, Workspace version, and live window before the
first view effect. Both resource references and presentation permission are
required. Tests preserve pending editor state and stored library data. They do
not grant implicit draft or editor reads. Empty windows are supported. Running
Actions are not cancelled. Stale or closed targets fail.

Presentation errors before submission can retry. Results use host-lifetime
receipts. Successful retries do not replace a later view change. Losing the
session or window after submission leaves an unknown result that reconnection
does not replay. The effect gate does not bypass required human approval.

The final run passed 243 tests. The normal native build and two project-generator
checks passed. Source-set coverage is now 61 connected or conditional names out
of 137, with 76 missing direct handlers. Full CI passed for the prior `01635d5`
order increment. Full CI for window application passed in
[41784775217](https://github.com/pobrespandas/draftly/actions/runs/41784775217)
for `f32f9d9`. Installed acceptance remains pending. Direct Workspace deletion
still needs its review handler.

## Agent Workspace order snapshots — 4 November

Connected `workspaces.reorder`. Library-scoped list pages carry an opaque order
snapshot. Selected-resource pages do not disclose it. Reorder requires every
current Workspace and rejects stale metadata, changed membership, and partial
resource sets. Atomic commit and durable receipts preserve the old order on
failure and prevent another reorder after a lost reply or service restart.

The focused run passed 146 tests. The normal native build passed without the
QA flag. Source-set coverage is now 60 connected or conditional names out of
137, with 77 direct handlers missing. Full CI [41781501330](https://github.com/pobrespandas/draftly/actions/runs/41781501330)
passed for `01635d5`. Installed acceptance remains pending. Later increments
below their own headings record additional handlers.

## Agent Workspace creation and duplication — 4 November

Connected `workspaces.create` and `workspaces.duplicate` through a shared
Workspace access component. Creation inherits app defaults and accepts explicit
overrides. Duplication preserves metadata. Both require library scope and use
prepared mutations, current authority checks, and durable receipts. Repeating
a completed request or recovering after service restart does not create another
copy. Existing selected-resource updates keep their prior behavior.

The focused run passed 130 tests. These include source conflicts, storage
failure, scope denial, and revocation, expiry, and lock before commit. The normal
native build passed without the QA flag. Project-generator tests passed two
checks. Source-set coverage is now 59 connected or conditional names out of
137, with 78 direct handlers still missing. Installed acceptance and full CI for
this change remain pending. Read [readiness](agents-ai-readiness.md) for limits.

## Normal agent startup follow-up — 4 November

Builds with the bundled helper now construct an idle host at normal startup.
Isolated QA uses the same path. Missing or inactive console sessions and
unavailable protected data deny admission. Suspension notifications invalidate
access synchronously. Host construction never restores listening access.
The final focused run passed 54 application-host and local-host tests. The
native QA build passed. Installed startup and real lock/sleep acceptance remain
pending. Public session properties do not prove graphical unlock. Read
[readiness](agents-ai-readiness.md#normal-startup-follow-up) for the limits.

## Agents and AI development — 4 November

[PR #105](https://github.com/pobrespandas/draftly/pull/105) stays in draft. The
bounded installed editing and Stop Work QA block is complete. Read
[agents and AI readiness](agents-ai-readiness.md) for the broader remaining work
and [installed editing acceptance](agent-editing-acceptance.md) for source-specific
evidence and limits.

Signed isolated QA checked scoped CLI/MCP edits, native Undo/Redo, replay
protection, manual conflicts, grant replacement, actual expiry, and unexpired
revocation. A missing Stop Work control in native review was added and accepted.
Interrupting a submitted Share effect retained an unknown result across restart;
CLI and MCP did not replay it. No share destination was selected.

Signed `13c3b1e` completed a real GPT-6.1-Sol editor change after fixing finalized
stream-item handling. The editor preserved the prior Unicode text and appended
one exact test line. Activity showed one write followed by a verification read.
Full CI [41765000703](https://github.com/pobrespandas/draftly/actions/runs/41765000703)
passed for that source. The QA is closed, test grants are revoked, local access
is off, and the original shared preferences are restored.

Normal host startup, real screen-lock/sleep handling, remaining contracts,
provider renewal and other model paths, named-client acceptance, and final
signed/notarized distribution remain open. No agents feature was published.
Older release and test sections below retain their original scope.

## Signed helper smoke check — 2 November

An isolated Developer ID app contained the signed universal agent helper.
The app and nested helper passed strict signature and profile checks. The helper
ran `discover` against a new temporary directory and returned an empty list.
This command validates the helper identity before discovery. The same binary
also completed an MCP initialize exchange over standard input and output with
protocol version 2025-11-25. No app host was connected during this exchange.
The check does not prove pairing, Keychain exchange with the installed app,
screen-lock handling, or notarization of the combined app.

## Public 0.1.7 — 2 November

[0.1.7/build8](https://github.com/pobrespandas/draftly/releases/tag/v0.1.7)
is public from e86a125. Release workflow41468484366 passed. Its seven public
assets matched the candidate; the public appcast matched the signed feed. Both
site download buttons point to the0.1.7 DMG. Site promotion completed and the
writer lock was released. The candidate passed signature, notarization and
Gatekeeper checks; it contains no agent helper or test tracing library.

Isolated local package replacement produced110 actions and five groups while
preserving drafts. Two separate libraries on one Mac synchronized through the
CloudKit Development container. This does not establish a Sparkle update or
CloudKit Production acceptance. The habitual installation was not changed.
During catalog stabilization, installation and updates replace all actions and
groups, including custom entries, once per installation. Agents remain disabled.

## Public 0.1.6 — 2 November

[0.1.6/build7](https://github.com/pobrespandas/draftly/releases/tag/v0.1.6)
is public from70a5d4f. PR86 and PR88 passed protected CI before integration.
Release run41385382234 completed rehearsal, signing, notarization, staging,
publication and public verification. Seven assets downloaded without credentials
matched their expected sizes and SHA256 hashes. The public feed matched the
signed asset and selected0.1.6/build7. Both site buttons point to its DMG.
Firebase promotion8c01f5bc03ff34f8 completed and the writer lock was released.

The original candidate passed local signature, ticket and Gatekeeper checks.
The ZIP contains neither an agent helper nor the test tracing library. Normal
agent startup remains disabled. The habitual installation and library were not
changed. Existing catalogs require Settings > Maintenance > Replace Default
Actions to receive the new defaults. Native isolated QA checked Cancel, Replace,
the110-action result and visible icon colors; the closed QA store had110 actions
and five groups. This does not establish live CloudKit catalog acceptance.

Earlier native test interruptions remain unexplained. The subsequent complete
reports establish those runs, not a root-cause correction.

## Stage zero complete — 2 November

Baseline inventory:98f9529. Version0.1.6/build7 was published from70a5d4f.
Public verification is complete; main is available for subsequent integration.

| Work | Current evidence | Next action |
| --- | --- | --- |
| Catalog replacement, PR86 | Merged433a7b4 after protected CI41383794456 passed. PR88 merged70a5d4f after CI41384674328 passed; v0.1.6/build7 tagged. | Release run41385382234 passed. Seven public assets and signed feed matched; site links point to0.1.6. Writer lock released. |
| Test performance, PR85 | Protected CI41379668319 passed all required checks. Local timing and coverage are recorded in testing.md on its branch. | Merged as f24de0b after publication. Final protected CI41387879161 passed. Local combined merge a761a71 passed23 runner tests and full Swift inventory1/166/793/1265. |
| Settings background, PR78 | Patch targets the earlier SwiftUI TabView. Main now uses a native controller. | Closed as superseded on2November; branch preserved. Retain the visual acceptance requirement for the current controller. |
| Revision restoration, PR80 | Focused evidence exists; hosted native report is incomplete. | Preserve branch. Revalidate against the current base before integration in the agents stage. |
| Editor reads, at/editor-syntax-reads-20261101 | a591d2d, 97741bd, b4b98ab and 40228d8 are outside main. | Preserve commits; integrate snapshots/search/syntax reads with their dependencies in the agents stage. |
| Earlier editor projection | 5ff376b is an ancestor of main. | Already integrated; do not duplicate it. |
| Product documents | e0cf84d was carried into PR82 and merged as6340434. | Already integrated; do not cherry-pick again. |

Two earlier Settings worktrees retain uncommitted SwiftUI background/transaction
experiments. Recovery patches were saved outside Git; their source was left
intact. They target the superseded selector, not the current native controller.
The original workspace also retains independent user edits and website work.

This inventory does not claim native parity or agent activation. The active
release keeps agents disabled. PR87 integrated the reconciliation as2f67629. PR85 integrated the test refactor
asf24de0b after its final protected CI passed. Stage zero is complete. Parity,
agent activation and the other later stages remain separate work.

## Catalog release CI interruption — 2 November

PR #86 run `41380539924` passed tooling and the matrix check. Native execution
returned CLI status zero with an incomplete app XML. The strict inventory
verifier rejected it. Artifact `13113232443` retains the failed reports.
The last logged test was
`URLActionInstallationTests.draftlyGroupLinkInstallsGroupAndOrderedActionsAtomically`.
The Typewriter suite had completed. This log position does not establish the
cause. No assertion failure or matching crash report was captured.

The crash collector now also accepts the actual `DraftlyPackageTests` executable
name. Its bounded file checks and CI-only restriction remain unchanged.
All 21 runner unit tests pass. This improves diagnostics; it does not prove that
the interruption is fixed. A targeted hosted Typewriter diagnostic is separate
from release acceptance. No merge, release tag, or publication has occurred.

Run `41381660136` also stopped with CLI status zero and an incomplete XML.
Its last log was a parameter case in the Typewriter native editor test.
The expanded crash collector found no report. The isolated Typewriter run
`41381508965` passed all three method identities. These results do not establish
the cause of the complete-suite interruption.

CI now loads a test-process-only exit tracer. It records `exit` and `_exit`
call stacks and preserves their status. It does not change report validation,
test selection, deadlines, or retries. The dylib is a CI diagnostic and is not
bundled in the app. Local smoke checks preserved exit statuses 73 and 74 and
captured their stacks. All 22 runner unit tests passed.

Run `41382985447` stopped before the first target test. The trace dylib had only
an arm64 slice. The hosted SDK lookup process required arm64e and rejected it.
The tracer now includes both slices. Local SDK lookup and exit-status smoke
checks passed with that universal dylib. This diagnostic failure is separate
from the earlier incomplete test reports.

Isolated native QA accepted Maintenance replacement and cancellation. The dialog
explained replacement, restoration, and preservation of other actions. Replace
reported 110 installed actions in the five canonical groups. Basic showed the
reviewed blue, green, gray, orange, and red symbols; the editor bar also showed
its colors. The Agents tab was absent. The QA app used a separate identity and
library with CloudKit disabled, then quit. The usual app remained unchanged.
This is local visual acceptance, not live CloudKit or final package acceptance.

## Default catalog replacement — 1 November

Settings > Maintenance now replaces the canonical default actions by ID.
It restores deleted defaults and overwrites edited defaults. Other action IDs
remain unchanged. Default symbols, bar labels, and colors are stored in the
catalog data. The list and bar share these appearance rules. Repeated
replacement does not add duplicate groups. A failed write rolls back all changes.

Automatic catalog updates that preserve edits and deletions are deferred to
2.0.0. Existing libraries remain unchanged at launch. Independent copies from
previous installations remain independent. See [catalog behavior](default-actions-parity.md).

Focused catalog, presentation, and window selection tests passed (36 methods).
The full Swift runner verified 2,226 method identities against fresh reports.
The API matrix audit and local signed app build passed. Visible Settings and
live CloudKit acceptance have not run.
The usual app and its library remain unchanged.

## Public 0.1.5 — 1 November

[0.1.5/build 6](https://github.com/pobrespandas/draftly/releases/tag/v0.1.5)
is public from `b03c86b`. PR #81 integrated the parity corrections and the
120-minute native CI and release rehearsal limits. PR #83 prepared the final
version after a documentation merge advanced main. Tag v0.1.4 remains fixed;
its attempt stopped before candidate signing and publication.

Protected CI `41372526306` passed. The app correction code also passed 2,224
local Swift cases, a local build, and isolated native QA. Candidate run
`41373367140` passed signing, notarization and staging. Recovery run
`41374988451` restored that original candidate, verified the public assets,
promoted the site and released the writer lock. Both live download buttons
point to the 0.1.5 DMG.

The exact ZIP passed isolated installation and automatic relaunch. The habitual
app then updated from 0.1.3 through the public signed feed and relaunched as
0.1.5/build 6. Its executable matches the original candidate. Strict signature
and Gatekeeper checks passed. The three existing drafts remained visible with
their original text and dates. Settings uses the native toolbar and has no
Agents tab. Normal agent startup remains disabled; no helper is bundled.

These checks do not establish complete visual parity, VM or offline acceptance,
or a new CloudKit synchronization matrix. Existing cloud action catalogs remain
unchanged. Explicit default installation remains available in Settings.
## Editor syntax reads — 1 November

The isolated syntax-read branch adds editor.markers, editor.links and
editor.listTasks. It uses SyntaxDefinition and each window's injected local
preferences. It reads pending text without changing selection or storage.
Task states remain those of the grammar. Internal rule indexes are excluded.
Missing definitions return unavailable. Both resource scopes are required.
Cursors reject changes to text, syntax source or local feature state.

The first custom-grammar regression failed while handlers were unavailable.
Final focused results passed 46 app and 6 contract tests. The official SDK suite
passed 12 tests, including a new case for all three syntax reads. Coverage includes
Unicode ranges, intermediate task states, pagination, missing scope, changed
syntax, missing syntax and feature changes. The local app build and structural
audit passed. All 303 Python checks passed. The complete Swift run passed the contract and
Core stages, then the app command exited 1 without an XML report. The last log
was a parameterized TypewriterScrollingTests case and included an XML parser
message. There was no assertion that explains the interruption. Isolated
Typewriter checks passed both with default execution and with the exact serial
runner and XML inventory verification. The two adjacent suites also passed together: all 18 methods matched the XML
inventory. This does not explain the full-run interruption. Integration is not
accepted. No installed app, native permission or release changed.

## Editor find reads — 1 November

The isolated editor-find branch adds editor.find to the local dispatcher.
It uses EditorFindQuery on pending editor text. It does not select, focus or
save. Both window and draft scope are required. Cursors bind to the editor
version, query, session and grant. Changed text rejects an old cursor.

The initial regression failed because the handler was unavailable. After the
implementation, an older exact handler-count expectation needed an update.
The final focused run passed 44 application and 6 contract tests. Cases include
UTF-16 ranges, case-insensitive defaults, invalid regex, empty results, zero-length
matches, missing draft scope and stale cursors. Local app compilation and the structural audit passed. The official SDK/socket
case passed with all 11 MCP tests. Its first fixture used an invalid top-level
query; moving that input into parameters corrected the fixture. The case checks
read-only metadata, UTF-16 ranges and preservation of selection and storage.
The complete runner verified 1 consumer, 166 contract, 786 Core and 1272 app
tests. All 303 Python tests passed. Integration remains pending behind PR80. No installed app or release changed.

The isolated ThemeRenderingTests CI diagnostic 41343722483 passed. This does
not explain or replace the rejected incomplete full report in PR80.

## Authorized editor reads — 1 November

The local service adds editor.windows and editor.get with an explicit registry.
Window IDs belong to tracked models and change after removal and registration.
Both the window and its current draft must be in scope. Reads preserve pending
text, selection, dirty state and storage. Pagination uses existing session-bound
cursors. Text chunks share scalar-boundary rules with draft reads. Window versions
use a distinct generation for selection and content changes, including reverts;
draft versions retain their existing selection-independent behavior.

Initial two service tests failed four issues while handlers were absent. A new
selection-revert test caught a repeated token, then passed with window generations.
MCP coverage caught missing read-only catalog metadata; the two new read handlers
now declare it. The SDK fixture also required explicit optional-note unwrapping.
Final focused53 app and9 contract checks passed. Complete final results verified
1/166/786/1270 (2223) Swift. Python303 and the structural audit passed. Helper
and local app compilation passed. The SDK test verifies
that another window's text is excluded without saving either pending editor.
No visible window, permission or personal data was used by automated tests.
Normal installed host activation and editor mutations remain unfinished.

## Restoration CI interruption — 1 November

PR80 CI41342870313 failed at0c4b10a. Artifact13097984150 is retained locally in
.build/agent-revision-ci-results. process.json reports Swift CLI0 and rejected
incomplete XML, with no collected native crash report. The last logged start was
ThemeRenderingTests.linkThemeChangesAndLinkModeRestoreNativeAttributesWithoutChangingText.
That is not a proven crash location or cause. No acceptance bypass or deadline
change occurred. Diagnostic run41343722483 targets ThemeRenderingTests on the
same head; it is not a retry of the complete acceptance and cannot replace it.
PR80 remains unmerged. Earlier incomplete reports remain unresolved observations.


## Patch integration and final restoration checks — 1 November

PR79 passed every actual check at333e642 in CI41341691455. Native results
verified1/166/786/1260 and BUILD SUCCEEDED. Guarded merge317b5f0 preserves both
histories. The restoration branch took that ancestry via c463ab2 with no source
tree difference. A final complete run verified1/166/786/1265 (2218), Python303
and the structural audit passed. Prior local app/helper builds use unchanged
production sources.

A later regression injects a revision change through admission before mutation
staging. It avoids a nested Core Data commit. The final validation rejects the
old resolved source with version_conflict, retains the original draft and keeps
the concurrent revision change. All19 writer methods passed. This added test
is covered by that focused run, not the earlier full inventory. No native UI,
permissions, installed app or release changed. Settings remains independent.

## Revision authority regression — 1 November

An additional writer test removes revision scope or deletes the revision between
preparation and execution. Both paths return not_found and leave the current
note unchanged. All18 writer methods passed. The prior complete2216Swift run
predates this one added test; this focused run validates the added regression.
No production code changed in this follow-up.

## Agent revision restoration — 1 November

A separate branch adds drafts.restoreVersion through the existing-draft writer
and local dispatcher. Target order does not choose the draft; both targets need
granted scope and the revision must belong to the draft. Only content is restored.
Expected versions, editor synchronization, Undo and atomic receipts remain shared.
No catalog or library format changed. The configured service has13 handlers.

Initial two methods failed against the unavailable handler. Focused65 checks
passed for target order, explicit scope, wrong parent, Unicode, Undo, receipt
recovery and storage-failure retry. Full strict Swift verified1/166/786/1263
(2216). A later66-test run included a new official SDK/real-socket restoration
case with hidden-note preservation. Python303 and the structural audit passed.
Local app/helper builds also passed. Normal startup remains inactive. No
installed application, native permission, personal data or release changed.


## Patch branch combined validation — 1 November

Merge9bc3472 preserves local-route headd2ac2c6 and native diagnostics. The only
conflict was the progress document; both records remain. The missing-registry
test also checks the patch route. Complete combined results verified
1/166/786/1260 (2213) Swift tests. Python303 and the structural audit passed.
This result does not explain the earlier interrupted runs. Normal app startup
remains inactive. Local app/helper builds passed. PR acceptance remains a
separate check.

## Agent UTF-16 patch handler — 1 November

The separate patch branch adds drafts.patch to the prepared existing-draft writer
and command service. Every range refers to the original projected UTF-16 text.
Preparation and execution validate bounds and scalar boundaries. Replacements run
in descending offset order. The existing admission, grant, version, editor and
atomic receipt checks remain shared with drafts.update. Metadata is retained;
the text change uses the existing Undo synchronization. Chunk reads reuse the
same pure scalar-boundary check. The catalog remains137 operations; the configured
service now has12 handlers. Normal app startup remains inactive.

Initial patch characterization failed five issues against the unavailable handler.
After implementation, 61 app tests and12 schema tests passed. They cover unordered
edits on one snapshot, combining Unicode, supplementary scalars, empty documents,
end insertion, split/out-of-bounds rejection during preparation and execution,
Undo and repeat receipt recovery. The real-socket CLI test also performs a patch
and verifies that an unauthorized note is unchanged. Complete Swift verified
1/166/786/1259 (2212). Python294, the structural audit and local app/helper builds passed. All data is neutral and isolated.

PR76 later merged after the diagnostic head passed; see the integration entry.
This branch does not change Actions, native permissions, the installed app, iCloud or releases.

## PR76 CI interruption — 1 November

Exact-head CI41337022036 failed on e09e790. Plan, tooling and matrix passed;
the native job124938932238 returned an incomplete app XML report. The strict
verifier rejected it. Artifact13095643499 contains the test output and reports.
The app XML contains only its opening root. The last reported case started was
URLActionInstallationTests.draftlyGroupLinkInstallsGroupAndOrderedActionsAtomically.
TypewriterScrollingTests reported all its cases complete before that point.
This is the last log position, not proof of the cause or crash location.

A separate local diagnostic verified all17 tests in those two suites. It does
not fix or explain the interruption. The Swift CLI returned zero to the runner;
the child process outcome is not available in the uploaded artifact. No CI retry,
deadline increase or acceptance bypass was made. PR76 remains unmerged. Preserve
the failure and collect better process/crash diagnostics before another CI attempt.
Independent patch work is kept on agent/draft-patch-20261101.

## Local route validation follow-up — 1 November

The combined run agent-routes-main-accepted returned CLI code1 with an incomplete
app report. Its last log starts a toolbar separator test; no recorded assertion
establishes the cause. A separate strict diagnostic verified all5 toolbar methods.
Preserve the failed report. A passing isolated suite is not a root-cause fix.

A new service contract test confirms that a missing editor registry leaves both
mutation preparation and update unavailable, even with write capability. Its first
fixture used the real clock with an expired synthetic grant; after injecting the
fixture clock, all40 service tests passed. This corrected only the test setup.
The final complete run verified 1/166/786/1257 (2210) Swift tests. The earlier
interruption remains unresolved. Python303, the structural audit and local
app/helper builds passed.
Normal app activation remains pending.

## Draft update integration accepted — 1 November

PR76 passed every actual check at 3d2425f in CI41339030094, including the required
macOS summary. Its native log verified 1/164/786/1252 Swift results and a successful
app build. Guarded merge a6c1eb0 preserves both histories. The prior interrupted
run remains unexplained; the passing diagnostic head is not a root-cause fix.

The local-route branch took the accepted main ancestry via7632969. Its earlier
run agent-routes-with-diagnostics stopped during the user pause and has no complete
app report. It is not acceptance. A fresh combined check is recorded separately.
No installed app, native permission or release changed.

## Local-route combined validation — 1 November

Merge cc7ba82 preserves the update branch and theme catalog ancestry. Complete
combined Swift results verified 1/166/786/1256 (2209). Python294, the structural
audit and local app/helper builds passed. A later focused run passed47 after adding service-recreation checks:
a key from the old service is rejected, and an explicit new preparation recovers
the committed receipt with the original response. This is a service fixture check,
not an installed-app restart or native acceptance. No application data was changed.

## Local mutation routes — 1 November

The configured command service now exposes mutations.prepare and drafts.update.
Preparation validates a typed unsigned request, current scope and expected version.
It returns a signed key without changing notes. Update uses the existing writer,
editor coordination and atomic receipt. CLI and the official MCP SDK use these
same routes through the real private local socket. They do not renew keys silently.
The service requires an explicit editor registry before it enables write handlers.

New tests cover preparation without mutation, selected-note updates, Unicode,
lost replies through MCP, CLI named calls, insufficient capability, excluded notes,
wrong libraries, existing keys and stale versions. Complete Swift results verified
one consumer, 166 contract, 786 Core and 1256 app tests (2209 total). A later
focused run passed 47 tests after assertions were tightened to exact error codes.
Python 294, the structural audit and local app/helper builds passed. Explicit
preparation after a committed update also recovered the original response in a
final 47-test focused run. No visible windows, native permissions or personal data were used.

This branch remains separate from PR76 until its main integration is validated.
Normal app startup, native activation, remaining write operations and full agent
acceptance remain pending. No installed application or release changed.
## Native Settings toolbar candidate — 1 November

Settings now embeds an NSTabViewController with the preference toolbar style.
Each tab uses an NSImage system symbol. No symbol is rasterized or stretched.
AppKit owns the toolbar items and selection. Child pages remain SwiftUI views.
The controller disables crossfade transitions and retains the selected-tab
preference. The toolbar background remains explicitly visible.

Local Debug build and strict QA signature verification passed. Isolated QA
opened Settings, switched between General and Bookmarks, restored the selected
tab after restart, and opened Editor through the General page button. A ten-second
press returned to an intact native symbol. This checks the state after release;
it does not establish the appearance throughout the press or first hover.
Exact interaction parity remains unverified. The installed app is unchanged.
The candidate remains in the Settings worktree and separate QA app.

### Earlier toolbar experiment

A separate visual fix gives Settings an explicit window-background color and
keeps the native toolbar background visible. Tab buttons remain native. This
removes dependence on automatic background visibility across tab content changes.
Tab changes also disable their SwiftUI transaction animation. This prevents the
toolbar from returning to the centered capsule presentation during a tab change.
Only SettingsView changed.

Local app build and strict package signature verification passed. Manual isolated
QA compared Drafts and Draftly Settings in the same session. Draftly first showed
one centered capsule around all tab items. The combined change removed the capsule
and retained a continuous toolbar background with one native selection frame, as
in Drafts. The result remained stable when QA changed from Markdown to General.
This accepts top-toolbar presentation only. It does not establish full Settings
layout parity or diagnose macOS compositing. No preference control or personal
note changed. The installed app was not replaced. QA used a separate preference
domain and library.

The first hover lifted a symbol. A tab click also moved the other symbols.
The template-image experiment changed symbol shapes and was rejected. Source
now uses native SF Symbols again. The QA app has been rebuilt and refreshed.
Earlier static acceptance does not establish interaction parity.


## Native test interruption diagnostics — 1 November

CI41337022036 rejected the incomplete app XML on PR76 e09e790. The last logged
case was URLActionInstallationTests.draftlyGroupLinkInstallsGroupAndOrderedActionsAtomically;
Typewriter had already reported completion. A local17-test diagnostic of both
suites passed. This does not establish the interruption cause. Preserve artifact
13095643499 and the failed run; do not describe the failure as fixed.

A separate infrastructure change records each Swift CLI invocation and report
verification. It retains a zero exit even when XML is rejected and distinguishes
signal exits. It records no environment variables. CI can collect bounded fresh
crash reports for known test processes, then collect delayed reports before
artifact upload. Local runs do not read system crash logs. Tests cover old files,
symlinks, unrelated reports, size/count limits, local refusal and delayed capture
without executing tests. Incomplete reports still fail; no retries or deadline
changes were added.

Initial diagnostic tests failed because no process records existed. Final20
focused checks and303 Python tests passed. The complete enhanced runner verified
1/164/786/1252 (2203) Swift and four passed CLI/verification records. No local
system crash directory was read. Structural checks and local app/helper builds passed. The next exact-head CI
result remains separate evidence; the prior interruption is still unexplained.

The route branch f92f5b0 and patch branch f4543bc remain preserved independently.
Normal app activation and the full local-agent objective remain unfinished.

## Theme ancestry integration — 1 November

The draft-update branch merged main at de5a851 after PR66 completed. Merge
 df0fc9a preserves both histories and the 14-theme public catalog. No conflict
resolution changed either implementation. The combined local tree passed complete
Swift checks: one consumer, 164 contract, 786 Core and 1252 app tests (2203 total).
Python294 and the structural audit passed. Helper and local app compilation passed. New exact-head PR checks must also
pass before integration.

The separate local-route branch remains pushed at 1d47518. Its newer operation
catalog and CLI/MCP tests are not part of this PR. The site was not deployed.

## Existing-draft update receipts — 1 November

AgentDraftWriting now joins current admission and signed-key checks, read-version
validation, editor coordination and atomic note/receipt storage. It implements
all fields in the existing drafts.update schema, including explicit dates and
nullable metadata. Existing-draft scope can cover one selected note; it does not
require whole-library authority. Missing metadata remains unchanged.

The same pure version encoding serves reads and receipt resources. Receipt
versions use normalized stored data and the reserved editor generation. Before
the final database commit, the writer checks admission, current key/grant, action
exclusion and editor generation again. Recovery checks authority before looking
up or returning a prior receipt. It does not repeat edits, revisions or Undo and
does not replace later human text. The writer and reader must share one library
and editor registry; requests must match the configured local library ID.

The package-only commit boundary accepts date preservation and a final validation
closure. Existing callers keep their defaults. Public APIs, record formats and
backup exclusions are unchanged. The project change registers one app source.

Six initial methods failed against an unavailable stub with eight issues. Final
focused checks passed 71 tests across writer, editor, read and receipt suites.
The writer has 11 methods covering every field, scope, nullable fields, reply
loss, failed-save retry, revoked authority, commit-time revocation/editing, stale
versions, admission failure and altered request/library/connection values.
Complete results verified one consumer, 164 contract, 786 Core and 1252 app tests
(2203 total). Python 294 and the structural audit passed. Local app and helper
compilation passed.

No external handler or key-issuance route is enabled yet. Native activation,
creation/task-owned scope and remaining resource operations are still pending.
Tests used neutral isolated libraries and offscreen text fixtures. No installed
application, native permission, personal data or release changed. The earlier
Typewriter interruption remains an unresolved observation; it was not fixed here.

## Editor coordination integrated — 1 November

PR75 exact head a3d7ebc passed CI41331687422, including the required macOS
summary. Native results verified1/164/786/1241 and BUILD SUCCEEDED. Guarded
merge 1b510422f6a9e275f763dddc5cc9c3d9b257b3ef preserves both histories.
The draft-update branch took that main ancestry without changing its validated
source tree. This does not resolve the earlier unexplained test interruption.

## Editor mutation coordination — 1 November

AgentEditorRegistry now coordinates a synchronous stored mutation across matching
editors. It protects pending projections during library publication, then uses
the existing Undo callback. Selection is clamped safely and focus stays unchanged.
Clean tag fields refresh; unconfirmed tag input remains editable. The caller owns
authorization, expected versions, durable storage and an atomic receipt. No
external write handler is enabled by this component.

The registry reserves one generation for the mutation. Its own synchronization
does not invalidate that generation. Real callback edits or navigation do. A
failed save restores the prior generation only if no outside state changed.
Failed storage retains prior text and Undo. A conflict after a completed commit
does not roll back stored data; recovery must consult the durable receipt.

Eight new methods cover two-editor Undo, selection/focus, publication ordering,
pending and clean save failures, reentry, invalidation, callback edits/navigation
and unconfirmed tags. Initial stub tests failed. Additional failing cases caught
generation loss after a clean failure and tag input replacement. Final focused
checks passed 54 tests. Python 294, structural audit and app/helper builds passed.

One full run ended during TypewriterScrollingTests without a final app XML or a
recorded assertion failure. Its cause is not established. An isolated diagnostic
passed all three methods. A new complete check, with no code, deadline or retry
changes between runs, verified one consumer, 164 contract, 786 Core and 1241 app
tests (2192 total). Keep the original interruption as an unresolved reliability
observation. The earlier similar signature does not prove this one pre-existing.

All checks used neutral isolated data and offscreen text fixtures. No native
permission, installed app or release changed. Receipt integration, service key
issuance, guarded handlers and native activation remain pending.

## Unicode correction integrated — 1 November

PR74 exact head a1f29f1 passed CI41329568126, including the required macOS
summary. Native results verified1/164/786/1233 and BUILD SUCCEEDED. Guarded
merge 129be2c1a99aacc949135d1ce3ce4b3f8480ae6c preserves both histories.
The editor mutation branch took that ancestry with no change to its validated
source tree. The installed application and release remain unchanged.

## Exact Unicode content correction — 1 November

Canonically equivalent strings can contain different code units. The editor
could skip such a replacement, omit Undo, leave the draft clean and skip saving
the new spelling. The library could also skip its revision and persisted value.

DraftOperations.sameText now supplies one package-only content comparison.
Editor synchronization, dirty detection, flush, saved baselines and library
content/revision checks use exact UTF-8 bytes. Existing agent generation tracking
uses the same rule. Note equality, public APIs and library formats are unchanged.
This is a functional correction, separate from the agent version-check feature.

All four new methods failed before the fix, with nine issues across app and Core
results. Final focused checks passed 19 tests. Full results verified one consumer,
164 contract, 786 Core and 1233 app tests (2184 total). All 294 Python tests, the
structural matrix and local app/helper builds passed. The offscreen Undo fixture
created no window. Persistence tests reopened a neutral temporary library.
No personal data, native permission, installation or release was involved.

## Retry transport integrated — 1 November

PR72 exact head67b1b7c passed CI41327756363, including the required macOS
summary. Native results verified1/164/785/1224 and BUILD SUCCEEDED. Guarded
merge b23b7d3d7645c00f3f54e5e605b746cd8b57f5e3 preserves both histories.
The draft-version branch took that ancestry with no change to its validated
source tree. This is source integration, not installed agent activation.

## Draft version check integrated — 1 November

PR73 exact head ff797f6 passed CI41328646515, including its required macOS
summary. Native results verified1/164/785/1230 and BUILD SUCCEEDED. Guarded
merge a153539ea3927527ba82e6729c75db06031faf74 preserves both histories.
The separate Unicode correction took that main ancestry with no change to its
validated source tree. External mutation handlers remain unavailable.

## Draft expected-version check — 1 November

Draft reads and the internal checkedSnapshot boundary now use one version
calculation. The check compares stored and projected draft state and returns
that snapshot without saving, selecting or synchronizing an editor. It preserves
access-date exclusion and editor generation changes after edit-and-revert.
It distinguishes invalid input, missing drafts, stale versions and divergent
pending editors. It is not authorization or a reservation across an await.

The first fixture build needed the actual clock arguments for AgentReadPages.
After that fixture correction, five methods failed with six issues against an
unavailable stub. Final focused46 passed across the new checks and existing read
and editor membership suites. Complete results verified1consumer/164contracts/
785Core/1230app (2180 total). Python294, matrix and local app/helper builds passed.
All tests used neutral temporary preferences and in-memory libraries, without
windows or native permission requests. No mutation handler was enabled.

Service key issuance, permission rechecks, atomic receipt writes, editor
synchronization/Undo and restart recovery remain before external writes.
The installed app and release are unchanged.

## Combined agent transport validation — 1 November

The retry-envelope branch now preserves the merged default action catalog and
the signed Keychain probe branch. Only continuation documentation conflicted;
both records remain. No runtime rules changed during this integration.
Complete results verified1consumer/164contracts/785Core/1224app (2174 total).
Python294, structural matrix, local app build and helper build passed.
The integrated tree is committed separately from its original feature commit.

PR71 exact head dbe732f passed CI41327181686, including its required summary.
It merged as2311dd822f654aa74c2174c6edeab3c5d6b38c89. The envelope branch
took that main ancestry without changing its validated tree and can enter review. Normal agent activation,
key issuance and guarded writes remain pending. This check did not install or
release the app, exercise personal data or repeat microphone acceptance.

## Retry key transport envelope — 1 November

The optional retryKey field now survives request decoding, named CLI/MCP tool
input and local-client library binding. Empty keys and keys over 4096 UTF-8 bytes
are rejected. The same limit applies to signed key verification. Old requests
without this field retain their representation. Canonical request fingerprints
exclude the key that authenticates them. This does not enable a write handler.

Three contract methods first failed with five issues. Final focused58 passed,
including real socket propagation and verification of a request carrying its own
signed key. Complete results verified1consumer/164contracts/774Core/1221app
(2160 total). Python294 and the structural matrix passed. App and helper
compilation passed. No UI or native permission
checks were invoked. Service issuance and guarded mutation dispatch remain next.

## Default action integration completed — 1 November

PR64 exact head5a5e7ec passed CI41326158201, including the required macOS
summary. Native results verified1/161/785/1222 and BUILD SUCCEEDED. Merged with
an exact-head guard as81ec89a377e23876a82c66e2ea62a93a6aa1758b. This is source
integration only. Native panel binding, automatic empty-cloud initialization,
installation and release remain separate checks.

## Signed adapter Keychain acceptance — 1 November

A manual probe compiled the production AgentCredentialKeychain adapter into two
isolated app-like packages. One used the principal application identity and its
existing profile. The other used the helper identity and new helper profile.
Both used Developer ID, hardened runtime and the dedicated agent access group.
The application created a random neutral item, read it, passed its expected
bytes through a pipe to the helper and checked a matching result. It removed the
item and confirmed absence. The unsigned probe failed permission_denied before
creation. No existing connection or personal credential was queried.

The build script only compiles. Signing and native execution remain explicit
manual steps; automatic tests never invoke them. This acceptance covers adapter
sharing on this Mac. App embedding, helper replacement, graphical lock behavior
and notarization remain pending. No installed application or release changed.

## Default action initial selection — 1 November

A new-window regression reproduced two failures: General stayed selected while
only the new Basic catalog was present, so the list had no actions. WindowModel
now reconciles selection with list-visible groups. The panel uses that same rule
on first appearance and later catalog changes. All Actions and valid selections
remain unchanged. Empty catalogs fall back to All Actions.

Three focused methods passed, including three selection variants. Full results
verified1consumer/161contracts/785Core/1222app (2169 total). Python294, the
structural matrix and local app/helper builds passed. No visible windows,
permissions or personal data were used. Native panel binding acceptance remains pending. The app was not installed or published.

## Default action integration review — 1 November

The integration branch preserves PR64 and main through merge commits6f5a8da
and3d22b0b. A new local cache no longer triggers default action installation when
CloudKit is requested. This prevents local initialization before cloud actions
arrive. Explicit installation preserves existing identities and unknown fields.
Automatic installation after a confirmed empty CloudKit import remains pending.

The configuration regression failed with two issues before the guard. All13
catalog tests then passed. Full Swift results verified1consumer/161contracts/
785Core/1219app (2166 total). Python294, structural matrix, helper build and
local app build passed. Tests used isolated data and did not access CloudKit.
No native synchronization, installed app change or release is claimed.

Review also found an initial group mismatch: WindowModel starts with General,
but the new catalog starts with Basic. Reproduce and correct that issue in a
separate change before updating PR64. The initial-selection section records that fix.

## Signed retry-key engine — 1 November

AgentRetryKeys binds a normalized request hash, connection hash, complete grant
fingerprint, host epoch and issuance clocks under an HMAC signature. Keys contain
no request content or credential. They expire after thirty days and reject clock
rollback, changed or expired authority, tampering and a closed manager. Verification
is stateless, so receipt cleanup cannot make an expired key executable again.

AgentRequestBinding now supplies the common normalization and grant snapshot for
approvals and keys. Existing approval behavior remains covered. Six initial key
methods failed against the unavailable stub; the existing sixteen approval
methods passed after extraction. Final focused25 passed (nine new key methods).
Fixtures were corrected to use the actual create defaults and required merge
order; no contract was changed to fit them. Complete results verified1consumer/
161contracts/774Core/1219app (2155 total). Python294, matrix0 and helper/local app
builds passed. The project change only registers the two new application files.

Key issuance is not exposed through CLI/MCP yet. Envelope integration, guarded
mutation dispatch, task-owned target grants, editor CAS, restart recovery and
pruning remain pending. This engine does not replace permission or effect approval
checks and does not enable installed agent access. The installed app is unchanged.

## Atomic note mutation receipts — 1 November

The package-only LibraryStore boundary stages notes and an agent mutation receipt
in one existing Core Data transaction. Public note saves share the same staging
rules. A matching committed request returns its receipt without repeating edits.
Different request hashes or targets are rejected. Receipt reads reject pending
context changes, and the write boundary preserves pre-existing uncommitted work.
Receipts omit raw requests and credentials and are excluded from backups.

Nine new Core test methods cover reopening/reply loss, failures before and after
receipt staging, conflicts, invalid metadata, thirty-day expiry, clock rollback,
backup exclusion, pending changes, malformed records and unknown record kinds.
The pending-state regression failed before its guard and passed afterwards.
All20 focused methods passed. Complete results verified1consumer/161contracts/
774Core/1210app (2146 total). Python294, matrix0, helper and local app builds passed.
Tests used neutral temporary or in-memory libraries. No personal data was used.

This is a storage primitive, not an exposed write handler. Signed retry keys,
request normalization, authorization/CAS/editor integration, receipt pruning and
restore-epoch invalidation remain before writes can be enabled. The installed
app and release are unchanged. No action defaults or theme catalog was edited.

## Read cursor lifetime contract — 1 November

Read cursors now use the accepted ten-minute maximum, bounded by the grant
expiry and both wall and monotonic clocks. The previous implementation used five
minutes. Pairing challenges and human approvals retain their five-minute limits.
This changes the cursor contract, not a test wait or execution timeout.

The new 599-second read failed before the correction. All37 focused service
methods then passed, including exact 600-second expiry, a shorter grant and
monotonic rollback. Full Swift results verified1consumer/161contracts/765Core/
1210app (2137 total). Python294, matrix0 and the helper build passed. Local app
compilation passed. Exact-head CI remains pending for this correction. No installed access was enabled.

## Authenticated preference discovery — 1 November

preferences.schema now serves the authoritative typed preference descriptors.
It checks preferences.read, validates selected IDs and binds opaque page cursors
to the normalized query, session and grant. Descriptor discovery reads no stored
settings or credentials. Preference values and mutations remain separate work.

Three behavioral cases first failed because the operation was unavailable.
Final focused49 passed, including complete descriptor coverage, permission and
ID rejection, cross-session/filter cursor rejection and expiry. Complete Swift
results verified1consumer/161contracts/765Core/1207app (2134 total). Python294,
matrix0, helper build and local app build passed. No native activation is claimed.

## Isolated agent helper packaging — 1 November

The new packaging command builds an app-like wrapper for draftly-agent in a new
output directory. It checks the helper profile identity, team, expiry, Keychain
group and certificates before signing. It verifies the signed Apple requirement,
exact required entitlements and the permitted leaf certificate. Existing output
is preserved. Errors propagate and leave only the isolated candidate.

All294 Python tests passed, including eight new packaging cases. The structural
matrix passed. A real negative invocation rejected the installed principal-app
profile before creating output or requesting a signature. No helper profile is
installed yet. Positive signed packaging, embedding, runtime Keychain sharing,
lock behavior and notarization remain pending. No installed app or release changed.
The prior Swift2130 inventory and app/helper builds apply to client configuration;
this scripts-only stage did not repeat them or claim new native acceptance.

### Signed helper check

Apple registered Draftly Agent and generated its Developer ID profile after
explicit user confirmations. The isolated helper package passed real signing,
exact code requirement, entitlements and profile certificate checks. Its discover
command passed self-identity validation and returned an empty isolated catalog,
without creating state, a credential or a grant. Actual Keychain sharing and
notarization are still pending.

The first real run found two codesign argument defects. Literal requirements
need the equals prefix, and the certificate extraction option needs its optional
value attached with equals. Both now have failing-then-passing regression
assertions. All294 Python tests passed again. This correction changes packaging
only. It does not replace or enable the installed application.

## Copyable MCP client configuration — 1 November

The helper configuration command prints a stdio mcpServers object with its own
absolute executable path, connection UUID and stable library route. An optional
state parent supports isolated libraries. It reuses AgentHostDestination rules.
It reads no credential or library, changes no client file and grants no access.
Export from the final bundled helper when provisioning is accepted.

Three new headless contract methods cover exact arguments, JSON structure,
Unicode paths and malformed input. All5 focused methods passed. Complete Swift
results verified1consumer/161contracts/764Core/1204app (2130 total). Python286,
matrix0, helper compilation and positive/negative CLI smoke checks passed.
Local app compilation passed. Exact-head CI remains pending at this checkpoint.
Normal startup, signed sharing and native lock acceptance remain unfinished.

## Application-owned host lifecycle — 1 November

AppController can adopt a prepared host for its exact library and editor registry.
It closes the host before a library change, on owner release and after successful
Quit saves. A save failure retains pending text and active sessions. Adoption
alone starts no listener and creates no Settings model or permission.

Five headless methods cover lifecycle ordering, retained hosts, save success and
failure, idempotent adoption and rejection of foreign, closed or untracked hosts.
The initial behavioral cases failed before the wiring. Final focused42 passed.
Complete results verified consumer1, contracts158, Core764 and app1204 (2127).
Python286 and matrix0 passed. Helper and local app compilations passed. Exact-head CI and native acceptance
are still pending at this checkpoint.

Normal startup remains disconnected. Signed helper provisioning, real Keychain
sharing, native lock/session acceptance, mutations, receipts and the remaining
agent operations still need implementation or acceptance. No installed app,
website, release or user data changed.

## Application-owned editor membership — 1 November

AppController now lazily supplies one AgentEditorRegistry for its current
library. Both registration paths and window removal refresh membership. A
library change or controller release invalidates the old registry. Retained
references cannot read snapshots or reattach after invalidation. Another library
is rejected. This adds no listener, grant, settings model or startup activation.

Three headless cases first failed before the wiring: normal/requested windows
between reads, library replacement/cache identity and owner release. They passed
afterwards. All68 focused cases passed. The complete inventory passed:
consumer1, contracts158, Core764, app1199 (2122 total). Python286, matrix0 and
final helper/local app builds passed. Tests used temporary preferences and
in-memory libraries; no visible window was created.

PR #59 passed exact-head CI 41310392387 and merged as 97cd64f. The native
job verified inventory2119 and BUILD SUCCEEDED. Merge5ff376b brought main into
this branch without changing the validated49436f7 tree. After resumption, the
complete2122 inventory, Python286, matrix0 and both builds passed again. Native lifecycle acceptance, host shutdown
on context change, system-lock handling and signed helper provisioning remain.
Registry invalidation does not substitute for invalidating all host authority.
The website, installed app and release are unchanged.

## Pending editor read projection — 1 November

AgentEditorRegistry projects current text for one bound library. Reads use that
text for content, titles, previews, search and order after scope filtering.
Divergent pending code units return editor_conflict. Clean stale views and other
libraries cannot override pending text. The host and service reject a registry
for another library before private host state is created.

EditorSession supplies a package-only hasUnpersistedText check against its
acknowledged baseline. The projection uses it as well as the window dirty flag.
This catches Unicode changes before that flag changes. Normal save and scripting
rules are unchanged. The registry keeps weak window references and records
per-draft generations. Selection, focus and unrelated drafts do not change them.

The caller must invoke refreshMembership at window registration and removal.
Lazy reads alone cannot observe a window opened, edited and closed between two
requests. Focused reproductions failed before their respective changes: stale reads and
conflicts, missed membership, code-unit-only text, and a stored-content change
hidden by pending text. Version material now includes both stored and projected
Notes. Access dates are excluded from both.

All63 focused cases passed (58 app, 5 Core). Complete inventories passed:
consumer1, contracts158, Core764, app1196 (2119 total). Python286, matrix0 and
final helper/local app builds passed. The socket case returned pending text
without saving it. Other cases cover Unicode conflicts, edit/revert, weak
lifetime, scope, selection, callbacks and wrong-library refusal.
No public API, Note identity, library or backup format changed.

CI41308744548 passed at178e2a8 before the stored-version reproduction. Its
completed result could not be canceled and does not validate the later fix.
The corrected head ea46474 then passed all required checks in CI41310392387
and merged through PR #59. The earlier CI41307619354 was canceled as obsolete
for membership and Unicode corrections. These are
headless, injected-host tests, not native UI or signed acceptance. Host wiring,
native lifecycle acceptance, system-lock handling, helper provisioning and
editor mutations remain unfinished. No installed-app access is enabled.

## Stable library destinations — 1 November

The helper accepts --library UUID, with an optional absolute --state-parent,
where explicit --socket access was accepted. AgentHostDestination owns argument
parsing and formatting. Its transport adapter resolves that exact local library
and supplies the expectation during pairing and authentication. Each physical
connection reads the current publication. Failed requests are not replayed.
A later explicit request can use a reopened host. No fallback selects a different
library or removes stale state. Corrupt and unsafe catalogs retain their errors.

Focused results passed: 70 app cases and 16 contract cases. Cases cover missing
state without writes, two libraries, misleading hints, refusal before credential
reads, reopened hosts, no replay and legacy explicit sockets without a catalog.
The helper and local app builds passed. Six executable smoke checks passed,
including refusal of unprovisioned identity without creating state directories.
These are isolated, injected-signature tests, not signed-helper acceptance.
The full branch inventory passed: 1 consumer, 152 contracts, 763 Core and
1183 app cases (2099 total). All 286 Python tests and the structural matrix
passed. After merging the validated CLI refactor from main, complete Swift
inventories passed: 1 consumer, 158 contracts, 763 Core and 1183 app (2105
total). Python286, matrix0 and both final builds passed. Three executable checks
kept stdin open and proved status/capabilities and invalid calls do not read it.
PR #58 passed exact-head CI 41306169094, including native build and required
summary, and merged as 50cc5c9. Normal app startup, helper provisioning, configuration export and the
remaining handlers are unfinished.

## Local host test fixture lifetime — 1 November

The new routing tests exposed an unowned fixture capture during late broker
pairing cleanup. The test process aborted after the fixture went away. Host
callbacks now retain their injected test state. The fixture does not retain the
host, so this adds no ownership cycle. A focused case drops the caller's fixture
reference while a host can still pair and cancel. It passed. Routing and transport
focused tests also passed (61 app, 2 contracts) after this test-only correction.
Production cancellation, timeouts and cleanup rules are unchanged.

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
The stable CLI adapter above now uses this handshake binding.

## CLI request preparation refactor — 1 November

The helper entry point mixed request preparation with stream and connection
management. AgentCLIRequest now owns preparation for json, call, status and
capabilities. AgentRequest and AgentToolInput remain the validation authorities.
The executable keeps framing, identity checks, transport, cleanup and output.
The input closure preserves the previous read order and error types.

The base is a56334f. The reference tag is
pre-refactor-cli-requests-2026-11-01. Before editing, 14 focused tests and the
helper build passed. Main's complete CI results remain recorded below.
After extraction, 20 focused tests, 286 Python tests and the structural matrix
passed. The complete Swift inventory passed: 1 consumer, 152 contracts,
763 Core and 1169 app cases (2085 total). Final helper and local app builds
passed. Five helper smoke checks passed, including stderr-only MCP errors.
These counts describe execution, not compatibility. No native UI check was
needed for this internal extraction. Signed-helper acceptance is still pending.
No existing test was removed. No UI or native permission path changed.

Expected-library binding and routing were developed separately, as recorded
above. Neither belongs to this behavior-preserving refactor. The extra recovery
stash remains preserved. PR #57 passed exact-head CI 41305076276 and merged
as 33c91df. Its checks included the native build and the required summary.
Local agent access remains unfinished.

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
