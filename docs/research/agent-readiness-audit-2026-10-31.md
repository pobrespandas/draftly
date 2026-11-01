# Agent readiness: architecture audit

Reviewed: 31 October 2026. Source baseline: `290d558`.
Scope: boundaries needed for the [agent plan](../plans/draftly-for-agents.md).
This is a targeted source audit, not a new functional acceptance of the app.
No production code changed during the audit.

## Prioritized findings

### A1 — Add one structured application boundary

Classification: justified refactoring and new agent interface. Priority: high.

[DraftlyIntents](../../Sources/Draftly/DraftlyIntents.swift) accesses the shared
controller and LibraryStore directly. SearchDraftsIntent returns tab-separated
IDs and titles. [ApplicationURLRouter](../../Sources/Draftly/ApplicationURLRouter.swift)
handles both data operations and native alerts. They are useful existing adapters,
not a complete data interface for agents.

Impact: a third caller could duplicate validation, window choice and result
handling. Proposed boundary: AgentCommandService plus shared application commands
where their behavior is actually equivalent. Preserve legacy return formats,
window behavior and confirmation rules. Do not route every legacy call through
agent-only permission prompts.

Risk: medium. Characterize old routes before extracting common commands. Test
identical data results through CLI/MCP, invalid targets, save failures, and
unchanged URL/Intent behavior. Implement contracts and reads in one stage;
mutations follow in a separate stage.

### A2 — Protect concurrent editor content at one mutation point

Classification: justified extraction plus new conflict contract. Priority: high.

[WindowModel.flush](../../Sources/Draftly/WindowModel.swift) owns pending autosave
and multi-window conflict policy. [AutomationActionExecution.run](../../Sources/Draftly/AutomationActionExecution.swift)
already checks unsaved content, execution exclusion and the target window's
lifetime. [ActionScriptCommands.perform](../../Sources/DraftlyCore/ActionScriptCommands.swift)
updates storage and synchronizes the editor for typed scripting commands.

Impact: a plain LibraryStore write can miss current editor content or fail to
preserve its Undo behavior. Proposed boundary: an application edit coordinator
for agent writes, using existing EditorSession mutation rules, explicit targets
and expected-version checks. Reuse rather than combine the deliberately distinct
updateNSView and synchronizeScriptEdit policies.

Risk: high. Test pending edits, divergent windows, immediate synchronization,
UTF-16 ranges, Undo/Redo, deletion during an operation, failed save, and a user
edit between read and write. Keep extraction separate from agent conflict rules.

### A3 — Execution identity is not authorization

Classification: new security contract, not a proven defect in current user flows.
Priority: release-blocking for agent execution.

[ActionBridgeRequestAuthority](../../Sources/DraftlyCore/ActionBridgeRequestAuthority.swift)
validates execution/step tokens, deadlines and single consumption. It does not
represent a user's grant. [ActionAsyncExecution](../../Sources/DraftlyCore/ActionAsyncExecution.swift)
handles HTTP/XML-RPC directly through httpTransport before native host dispatch.
[ActionScriptCommands](../../Sources/DraftlyCore/ActionScriptCommands.swift) can
query the library and enqueue Actions. [ActionHost](../../Sources/DraftlyCore/ActionHost.swift)
therefore cannot be the only permission boundary.

Impact: approving a named Action would otherwise allow effects outside a scoped
grant. Add explicit execution authority to the runner and check every read,
mutation, integration, include/queue and final effect. Keep legacy interactive
user authority explicit. Unknown agent operations fail closed. Do not claim
that arbitrary shell or AppleScript can be restricted to a set of draft IDs.

Risk: high. Test every dispatch route, including denied reads, HTTP, templates,
late callbacks and included/queued Actions. Use injected hosts, no real services.
Finish this stage before exposing Actions.run to normal agent connections.

### A4 — Add atomic mutation receipts without a second library writer

Classification: new retry/recovery contract. Priority: high.

[LibraryStore.saveNotes](../../Sources/DraftlyCore/LibraryStore.swift) batches note
and revision writes and rolls back on error. Its generic records can carry
additional internal data. No agent idempotency receipt currently exists.

Impact: a timed-out create followed by a retry can duplicate content. Extend the
existing transaction with a generic receipt record. Keep credentials and local
audit data separate. Use the same pattern for other atomic data mutations;
external side effects need outcome_unknown rather than a false rollback claim.

Risk: high. Characterize each existing writer's rollback behavior first; do not
assume saveAction and saveNotes have identical failure handling. Test commit
failure before/after receipt staging, reply loss, repeated keys, mismatched
payloads, retention, restore epochs and older backups. Any existing persistence
fault found during characterization gets its own reproduction and fix commit.

### A5 — Preserve the useful domain and editing boundaries

Classification: structure adequate; reuse. Priority: medium.

[ActionCatalog](../../Sources/DraftlyCore/ActionCatalog.swift) centralizes identity,
visibility and order. [ActionEditingCopy](../../Sources/Draftly/ActionEditingCopy.swift)
keeps edits temporary and preserves original shortcut behavior.
[InstalledThemeCommands](../../Sources/Draftly/InstalledThemeCommands.swift)
coordinates theme persistence and local selection. Workspace preparation in
WindowModel resolves references before application. TagRules and EditorFindQuery
already hold shared domain calculations.

Impact: implementing replacements for these components would produce drift.
Expose existing calculations and commands through narrow handlers. Extract
Workspace preparation only as far as a headless query/application needs it;
retain current save and cancellation order.

Risk: medium. Preserve imported unknown fields, identities, Cancel, sort order,
missing-reference failure, local/shared preferences and save failure effects.
Do not add a protocol for each class simply to mirror existing types.

### A6 — Review destinations and local-only data explicitly

Classification: new agent configuration and integration contracts. Priority: high.

[NativeFileAdapter](../../Sources/Draftly/NativeFileAdapter.swift) resolves bookmarks
and file API roots. [NativeAutomationAdapter](../../Sources/Draftly/NativeAutomationAdapter.swift)
executes Shortcuts, shell and AppleScript. Current user operations are not an
agent-scoped resource model. LibraryStore.backupData exports existing library
objects, not device permissions.

Impact: an agent settings or file tool must not expose Keychain data, broaden a
bookmark, approve a native permission, or export a partial library as a full
backup. Add a typed preference allowlist and effect-specific grants. Keep local
grants, credentials and audit records out of normal backups and synchronization.

Risk: high. Test path escapes, secure settings, export authority, malformed
imports, restore review, and cancellation with hosts and temporary roots.

## Tests, scripts and documentation

The existing Swift targets separate Core and app tests. Add headless service and
protocol suites, use current temporary stores and editor fixtures, and keep UI
acceptance separate. Preserve tests referenced by the Actions matrix. Similar
names are not evidence of duplicate coverage.

Build/release scripts currently package the app and Sparkle. Plan to include and
sign the helper and its dependencies, verify both architectures when supported,
and test an actual installed helper after an update. Do not register QA Services
or introduce visible-window tests through agent protocol tests.

The development guide currently lists MCP as outside its version. Keep that
statement tied to the shipped release; describe this work as proposed until it
ships. Update setup docs, client compatibility evidence, glossary and architecture
with each implemented stage. The plan is not marketing evidence of availability.

## Audit limits and next step

No complete field-by-field agent operation inventory exists yet. Stage 1 must
produce it from the model, views, 25 step descriptors and native dispatch paths.
The new security boundary, token storage, socket implementation and transaction
receipts have not been compiled or tested because they are not implemented.
SDK documentation was inspected; client interoperability remains untested.

First implementation unit: characterize shared query and edit behavior, define
AgentContracts and the complete registry, then implement disabled-by-default
local connection and scoped reads. Keep Actions.run unavailable until A3 passes.
