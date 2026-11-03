# Agents and AI readiness

Updated: 3 November 2026. Work is on [PR #105](https://github.com/pobrespandas/draftly/pull/105).
Agents and AI are not complete or ready for an agents release.

This is the current status summary. The operation and chat checkpoints retain
historical evidence. A passed test applies to its recorded source and path.

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
| Chat Console tools | Shared MCP tool definitions, completed function calls, bounded continuation, and native consent are connected to the QA host. | GPT-6.1-Sol used `drafts.list` and `drafts.get`. It returned the exact approved Unicode draft text. Native activity confirmed both calls. | Real editing, Undo, cancellation, concurrency, result recovery, and the remaining operation families. |
| Consent and grants | The chat creates a separate connection for the current draft and editor. Reading and editing are separate choices. The grant expires after 15 minutes. | The user approved reading. A fresh native pairing on signed `2ea267b` granted exactly `drafts.read` and `editor.read` for one draft and window. Another draft returned `not_found`; draft/editor writes returned `permission_denied` without text changes. The existing MCP process and a new CLI request were denied after the actual deadline. | Other resource families, editing grants, and their installed negative cases. |
| Keychain and helper | The app creates the connection credential. The signed helper uses it to authenticate. | The installed helper returned the same limited capabilities. This proves sharing for that QA connection. | Broader client setup and failure-path acceptance. |
| Installed MCP | The bundled helper exposes the local service through bounded stdio MCP. | A fresh native helper pairing negotiated `2025-11-25`, listed read tools, omitted write tools, and read the approved draft. It denied another draft and remained open through pause, resume, and actual expiry. | A full session for each named client. No Codex or Claude Code compatibility claim follows from this probe. |
| Revocation | Disconnect closes the chat session, revokes its connection, and removes its credential and revoked metadata. | An existing MCP process denied its next read. A new CLI request returned `permission_denied`. No draft text returned after revocation. | Revocation during writes and native effects, plus installed storage-failure cases. |
| Stop Work | The host suspends transport, reviews, and operations. | On signed `2ea267b`, Stop Work set access off, withdrew publication, and denied the existing authorized MCP reader. Explicit resume let that same process read again without changing grant or expiry. | Stop Work during an active operation with effects or a pending review. The installed check covered an open read session. |
| Restart | Account and conversation persistence are connected. A new host does not start a listener automatically. | The signed QA retained account and conversation after process exit. Access remained off. | A follow-up signed QA from `2ea267b` retained the selected ChatGPT model after verified process exit. Tools stayed disconnected and access stayed off. Other model/provider restart paths remain pending. Test permission and result recovery for the remaining operations. |
| Normal startup and lock | Host creation is still gated to isolated agent QA. | Fresh QA access started off. The QA lock adapter does not detect screen lock. | Normal startup with access off, verified initial lock state, lock/sleep transitions, and explicit resume. |
| Distribution | App and helper profiles and signatures are checked. | Both ran installed with matching Developer ID identities. | Combined notarization, final release packaging, architecture checks, signed updates, and post-update CLI/MCP sessions. |
| Apple Intelligence | Available on-device and Cloud choices are connected through the native model adapter. | Both choices appeared in this QA. An earlier isolated QA checked an on-device reply. | Availability is separate from inference. Cloud inference and tool integration need their own acceptance. |

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

## Operation coverage

The required-operation manifest contains 137 names. A source-set review found
57 names in implemented or conditional handler sets. The other 80 names have
no direct handler in those sets. These counts do not prove that 57 operations
are complete, always available, or accepted in an installed app.

The review used `AgentCommandService.implementedOperations`, its conditional
availability, the draft/editor/preference writer sets, and the required
manifest. `server.schemas` remains authoritative for a configured connection.
Some native effects already run through reviewed Actions; that does not supply
a direct handler for every `native.*` contract.

| Family | Direct contracts still outside those handler sets |
| --- | --- |
| Drafts | `drafts.archive`, `drafts.flag`, `drafts.merge`, `drafts.purge`, `drafts.restore`, `drafts.syntax`, `drafts.tags`, `drafts.trash` |
| Editor | `editor.navigate`, `editor.open`, `editor.preview` |
| Actions and groups | `actions.delete`, `actionGroups.delete` |
| Workspaces | `workspaces.apply`, `workspaces.create`, `workspaces.delete`, `workspaces.duplicate`, `workspaces.reorder` |
| Themes | All 14 declared `themes.*` contracts. |
| Syntax | `syntaxes.delete`, `syntaxes.export`, `syntaxes.install`, `syntaxes.reload`, `syntaxes.replace` |
| Bookmarks | `bookmarks.forget`, `bookmarks.list`, `bookmarks.requestAdd` |
| Imports and exports | `imports.commit`, `imports.preview`, `imports.validate`, `exports.drafts` |
| Backups | `backups.export`, `backups.previewRestore`, `backups.requestRestore`, `backups.validate` |
| Transfers | All five declared `transfers.*` contracts. |
| Native operations | All 24 direct `native.*` contracts. Existing reviewed Action effects are a separate path. |
| Operation control and activity | `operations.answerPrompt`, `operations.wait`, `activity.changes` |

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

## Responsibility boundaries

| Boundary | Responsibility |
| --- | --- |
| `AgentContracts` | Operation vocabulary, schemas, permission rules, and shared tool definitions. |
| App service and editor registry | Library ownership, current editor projections, versions, Undo, and mutations. |
| Local host and connection registry | Local lifetime, grants, pairing, credentials, suspension, and revocation. |
| MCP and CLI adapters | Protocol framing and dispatch through the authenticated app service. |
| ChatGPT provider | Model authentication, streamed inference, and function-call continuation. |
| Chat tool session | The approved local session, exact library binding, current context checks, and duplicate-call rejection. |
| Native consent and effect review | The person's grant decision and any separate one-use effect approval. |

A model-provider account identifies the person to the model service. A Draftly
agent connection defines local authority. Signing in alone grants no draft
access. The console invokes the authenticated app service in process and shares
its tool definitions with MCP. It exposes no inbound HTTP server.

## Next work

1. Test editing grants, other resource families, and Stop Work during active
   effects or pending review. Reuse the accepted fresh pairing, read-only
   negatives, active read-session pause/resume, expiry, and revocation evidence.
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
