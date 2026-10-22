# Modularity and responsibility audit — 22 October 2026

## Base, method and limits

The reference is 1e399dd. The worktree was clean. No build or test process was
active at the initial check. The existing annotated reference tag is
pre-refactor-native-lifecycle-2026-10-22. This audit does not need another code
reference tag. No previous work was removed.

This is a repository-wide architectural audit, not a line-by-line correctness
review or a new compatibility acceptance. The inventory covers Sources, Tests,
scripts, Tools, Configuration and documentation. Detailed reads follow the
boundaries below and their callers and tests. Vendor provenance and its local
Markdown patch were checked as maintained inputs; upstream code was not audited.
The local signing configuration was not copied into the report.

The review applies modularity, cohesion, separation of concerns, concrete
abstractions and explicit dependencies. File size is not a finding. Similar
syntax is not proof that two caller policies are equivalent. Production, tests,
scripts, project files and configuration are unchanged in this delivery.

## Coverage and existing boundaries

| Area | Evidence reviewed | Assessment |
| --- | --- | --- |
| Domain and queries | Models, DraftQuery, WorkspaceAPI, ActionCatalog, SyntaxDefinition and value rules | Rules already have useful owners. Draft-list queries and editor find have distinct semantics. Do not merge them into one search engine. |
| Persistence and sync | LibraryStore, LibraryRecordPersistence, LibrarySyncCoordinator, CloudSyncState, import and backup tests | Storage operations and sync notifications are separate. LibraryStore coordinates a transaction across record kinds. Its length alone does not justify splitting it. |
| Execution and scripting | ActionRunner, async execution, ActionExecutionSession, ActionScriptWorker, request authority, ActionHost and Bridge.js | Sessions, token authority and worker cleanup have distinct contracts. Keep MainActor and worker boundaries explicit. Do not merge legacy and asynchronous lifetimes as a cosmetic refactor. |
| Native integrations | NativeActionHost, route classifier, sharing, printing, file, prompt, process and system adapters | Host dispatch is composition. Different resource and cancellation rules justify different implementations. The new SharingActionWait boundary is useful. |
| Window and editor | WindowModel, WindowDependencies, EditorBody, EditorView, completions, Touch Bar and AdvancedFindCommands | Completion data has an unnecessary dependency on the complete window model. Styling and text synchronization need narrower responsibilities. See R1–R3. |
| Inspector and organization | ActionEditingCopy, ActionEditor, creation defaults, field descriptors, ActionCatalogPresentation | The temporary editing copy already separates edits from saving. Shared order and visibility helpers exist. Do not add another editing or catalog service without a concrete new need. |
| Workspaces and personalization | WorkspacePresentationResolver, WindowThemePresentation, WorkspaceOptionsEditor, InstalledThemeCommands, ThemePickerOptions and Settings | Preparation is repeated at two entry points. Sort mutation and theme commands already have common owners. See R4. |
| Tests | Both target inventories, support fixtures, editor/Undo, theme, Workspace, persistence and native lifetime tests | Keep contract cases and different Undo policies separate. No exact duplicate Swift test files were found. This does not prove semantic uniqueness. |
| Scripts and tools | Build, QA preparation/refresh, signing verifier, test runner, auditor, fixture tests and benchmark entry point | QA preparation has an import-time write and no direct behavior tests. The existing refresh script has a callable boundary. See R5. |
| Documentation and inputs | README, architecture, status, local handoff, refactoring records, matrix, configuration templates and Vendor README | Current continuation must be distinguished from historical acceptance. Preserve reference archives, original scripts and vendor patch records. See D1. |

DraftlyCore contains shared Mac application code, including persistence and the
execution worker. It is not a framework-independent domain-only package. The
current dependency direction is Draftly to DraftlyCore. A package split needs
a demonstrated consumer or isolation need; none was established in this audit.

## Prioritized findings

### R1 — Completion data depends on the whole window

**Classification:** justified refactoring. **Priority:** high. **Size:** small.

Evidence: EditorView.swift, NativeEditor.updateNSView, lines 64–69, reads
touchBarModel.currentNote and touchBarModel.library.notes to build completion
requests. EditorBody.swift:26 supplies that model. EditorTouchBar.swift:6 also
uses the model, but for action subscriptions and execution availability.

Impact: syntax completion is coupled to a property named for an unrelated
presentation feature. A completion test needs window composition to exercise
the actual bridge. Future completion changes can accidentally affect Touch Bar
configuration or use a stale library snapshot.

Proposed boundary: supply a concrete completion context through an explicit,
lazy closure. It contains only the current draft and candidate drafts. Keep
Touch Bar configuration on its existing path. NativeEditor still owns session
text, selection and the active syntax. SyntaxDefinition remains the authority
for completion matching. No new protocol is needed.

Preserve current call-time data, the source-text override, the session note-ID
override and the fallback draft when no current draft exists. Preserve Unicode
ranges and the existing nil-session/nil-syntax behavior.

Risk and validation: low to medium. Test the actual NativeEditor bridge with a
neutral context, updated candidate drafts, a changed current draft, no context,
no session ID and Unicode. Existing completion, theme and Undo tests must pass.

### R2 — Styling is embedded in the text synchronization coordinator

**Classification:** justified refactoring. **Priority:** medium. **Size:** medium.

Evidence: EditorView.swift, Coordinator.highlight, lines 162–325, resets text
attributes, applies built-in visual rules, custom syntax scopes, active links
and indentation metrics. The same coordinator handles text notifications,
selection, script synchronization and Undo at lines 120–160.

Impact: changes to themes or syntax presentation require editing the component
that protects text and Undo coherence. Styling tests construct a coordinator
even when no synchronization behavior is under test.

Proposed boundary: extract a concrete AppKit styling component with the current
style inputs and explicit text-view/default-link-attribute inputs. Keep a thin
highlight wrapper for current callers. The coordinator retains event handling,
Undo, focus, invalidation and notification order. ThemeTextAttributes and
SyntaxDefinition remain existing rule owners.

Preserve the exact attribute application order, scope precedence, inherited
fonts, task colors, link defaults and indentation metrics. Built-in visual
fallback rules are not automatically duplicates of grammar rules. Do not remove
or consolidate them without separate equivalence evidence.

Risk and validation: medium to high. Characterize overlapping syntax/theme
styles, theme removal, link-mode changes, empty text, Unicode and selection/Undo
preservation before extraction. Keep existing ThemeRenderingTests names.

### R3 — Native text replacement is implemented in two update routes

**Classification:** justified refactoring with caller-policy limits.
**Priority:** medium. **Size:** small to medium.

Evidence: EditorView.swift:87–100 and Coordinator.synchronizeScriptEdit at
141–152 both detect a draft change, replace text and register Undo through
restore. They differ in parent updates, style invalidation, scrolling and focus.

Impact: fixing one replacement path can leave the other with different Undo or
selection behavior. Replacing both routes with one broad update method would
also erase intentional differences.

Proposed boundary: after R2, extract only the shared text-mutation operation
inside the coordinator. Keep route-specific notification, styling, scrolling
and focus sequences explicit. Do not add a generic editor command framework.

Risk and validation: medium. Use a route-by-route behavior table before edits.
Cover same-draft and changed-draft updates, no-op updates, shorter text, Unicode,
selection restoration and Undo/Redo. Different Undo grouping fixtures stay
separate unless equivalence is demonstrated.

### R4 — Workspace preparation is repeated before different effects

**Classification:** justified narrow refactoring. **Priority:** medium.
**Size:** small.

Evidence: WindowModel.applyScriptWorkspace at 357–361 and saveAndApplyWorkspace
at 364–370 each resolve groups/themes and validate external theme files. The
second route then saves and cancels an action before applying the result.
The apply wrapper cancels before its preparation call.

Impact: adding a preparation requirement could update only one entry point.
Moving all effects into a common service could change cancellation or save
ordering, so a broader extraction is not justified.

Proposed boundary: one private prepareWorkspace operation in WindowModel that
returns the resolved Workspace. Delegate to the current resolver and file
validator. Keep saving, action cancellation and published mutations in their
current callers. Do not introduce another resolver or Workspace state machine.

Risk and validation: medium despite the small edit. Invalid groups, missing
theme files and save failures must leave the same state and effects as before.
Run WorkspaceApplicationContractTests, WorkspaceSortStateTests and theme-file
tests. Preserve observers, unknown metadata, local options and per-folder order.

### R5 — Cloud QA preparation cannot be imported safely for direct tests

**Classification:** justified refactoring. **Priority:** medium. **Size:** small.

Evidence: scripts/prepare-cloud-qa.py:8–21 reads sys.argv and writes a plist at
module scope. scripts/build-app.sh:20 invokes it as a command.
test_build_app.py:125 checks that invocation, not the resulting metadata.
refresh-engine-qa.py:12 exposes a callable operation and has a main guard.

Impact: direct unit tests cannot import the preparation code without executing
file operations. QA metadata changes are harder to validate independently of
the shell build wrapper.

Proposed boundary: a pure metadata transformation plus an explicit prepare
command and main guard. Preserve CLI arguments, working-directory behavior,
container identity, UUID reuse and Info.previous.plist behavior. Do not combine
Cloud QA with Engine QA; they have different identities and purposes.

Risk and validation: low to medium. Use temporary plists and a controlled UUID
factory. Check absent destination, matching container, changed container,
preserved prior library ID, previous-plist output and import without writes.
Do not invoke signing, LaunchServices, a VM or CloudKit from these tests.

### D1 — Current orientation competes with dated continuation records

**Classification:** justified documentation correction. **Priority:** medium.
**Size:** small. **Implemented in this audit.**

Evidence: architecture.md:5 directed current work to the editor/scripting scope,
while status and the newest local handoff recorded native-engine work and then
this audit. Older records remain valid historical evidence.

Change: link current orientation to this audit and status. Keep dated scope and
refactoring records available as history. Do not rewrite past acceptance or
treat a successful test total as compatibility evidence. No archive was removed.

## Candidates that do not justify implementation now

| Candidate | Classification | Decision and missing evidence |
| --- | --- | --- |
| Splitting LibraryStore by file size or record kind | Insufficient evidence | Restore at 337, collision recovery and imported-record commit at 392 coordinate one graph transaction. LibraryRecordPersistence already owns record access. No new repository hierarchy or transaction framework is proposed. First measure a concrete change that crosses this boundary. |
| Shared generic native-request framework | Adequate separate structures | Printing has a cancellation flag and owned sheet; sharing retains attachments after action termination; EventKit, speech and file operations have other contracts. Similar continuation syntax does not establish interchangeable lifetimes. |
| Inspector editing, theme commands and catalog ordering | Adequate structures | ActionEditingCopy, InstalledThemeCommands, ThemePickerOptions, ActionCatalog and ActionCatalogPresentation already isolate useful rules. Keep Save/Cancel and partial-effect policies. No extra layer is proposed. |
| TestPreferences in two test targets | Adequate local duplication | App tests use Testing requirements and a required prefix. Core tests use a local setup error and a default prefix. Sharing ten lines would add cross-target support structure without demonstrated benefit. |
| Undo fixtures with similar setup | Insufficient evidence for consolidation | ScriptUndoEditorFixture disables event grouping and disconnects callbacks. Other suites exercise different grouping and notification policies. Similar construction is not equivalent contract coverage. |
| Removal of redundant tests | Insufficient evidence | SHA256 comparison found no identical Swift test files. Semantic redundancy needs a condition/result comparison and proof that no matrix reference or error path is lost. No test is marked for deletion. |
| Original action fixtures and bundled/vendor resources | Adequate preserved inputs | First-party fixtures, Bridge.js and vendor sources are compatibility inputs. Keep originals, provenance and the documented footnote patch. No generic cleanup is proposed. |

## Independent functional risk

The prior native-lifetime baseline recorded a Core XML-RPC timeout before the
transport started. Its focused serial check and the prior final run passed.
The complete run in this audit also passed. This is an observed earlier failure,
not a proven production root cause. Keep it as an independent timing/test-design
investigation. Do not change timeouts, serial execution policy or retry rules
inside any of R1–R5. No new functional defect was reproduced by this audit.

## Follow-up — R1 implementation

R1 is implemented in the separate [completion-context refactoring record](refactoring-completion-context-2026-10-22.md).
Its verification does not change the original audit results or implement R2–R5.
The implementation adds the explicit provider and migrates the model-supplying
constructors. The later R4 follow-up below records Workspace preparation.

## Follow-up — R4 implementation

R4 is implemented in the separate [Workspace preparation record](refactoring-workspace-preparation-2026-10-22.md).
A common private operation prepares the resolved Workspace. Each caller keeps
its existing save, cancel and apply order. R1 and R4 are complete as refactoring
stages. Cloud QA preparation is next; R2, R3 and R5 remain unimplemented.

## Recommended implementation sequence

1. R1: explicit completion context. This is the next small implementation stage.
2. R4: shared Workspace preparation, retaining caller effect order.
3. R5: callable Cloud QA preparation and direct temporary-file tests.
4. R2: styling extraction after its attribute-order characterization.
5. R3: shared text mutation after the styling boundary is stable.

Each stage needs a separate scoped commit with related tests and documentation.
Recheck the worktree and active processes first. Create a reference tag on the
validated implementation base before source changes. Do not reuse the previous
stage's test totals as validation for the next stage. Functional fixes are
separate work. None of R1–R5 is implemented by this audit.

### First stage: R1 implementation handoff

Production ownership is limited to EditorView.swift, EditorBody.swift and a new
EditorCompletionContext.swift. Completion tests belong in
EditorSyntaxCompletionTests.swift. Update the two model-supplying constructors in EditorTouchBarTests.swift to pass the same
explicit context. Keep their test names and Touch Bar assertions.
Keep project.pbxproj generation as a separate, reviewed derived-file step.

Use an internal EditorCompletionContext value with currentDraft: Note? and
drafts: [Note]. NativeEditor receives an optional MainActor context-provider
closure with a nil default. EditorBody supplies a weak-model provider that
reads currentNote and library.notes when called, not when the view is built.
When the provider is absent, use no current draft and an empty candidate list,
as existing standalone callers do. Migrate all three current model-supplying
constructors, including the two Touch Bar test constructors, to the explicit
context. NativeEditor must no longer read touchBarModel for completion data.
Retain that model only for the existing Touch Bar behavior.

Build the completion request at the current callback using the existing syntax,
source and selection. Preserve the current early return if the session is gone.
Use currentDraft or a new Note(content: source), then replace its content with
source and override its ID only when the session has a note ID. Pass the current
candidate drafts unchanged to SyntaxDefinition.completion. Keep completion
invalidation, view updates and Touch Bar behavior unchanged.

Characterize the existing callback first. Then prove that the explicit provider
sees updated data on consecutive calls and works without a Touch Bar model.
A different Touch Bar model must not change the supplied completion context.
Check empty context, nil note ID, custom syntax, Unicode and library changes. Exercise the installed text-view callback, not only
a pure context helper. Preserve all existing test names and Undo grouping.

Run focused completion, theme and Undo tests, then both complete Swift suites,
Python, local Debug build and matrix checks without overlapping Swift commands.
Do not deploy the build. A new native manual session is needed only if the change
affects presentation bindings that the headless bridge tests cannot verify.
Completion criteria: exact prior completion outputs and lifetimes remain,
new context tests pass, project derivatives agree, no new unresolved regression,
and status/handoff record automatic and native evidence separately.

## Audit validation and delivery

Implemented: this diagnostic, prioritized sequence, current orientation and
handoff. Production, tests, scripts and configuration are unchanged. The glossary
terms remain suitable; no new domain concept or irreversible decision needs an
ADR. No abstraction or package boundary was added.

Automatic results on the unchanged base:

- Complete Swift: 674 Core methods and 767 app methods. XML reports match
  discovered identities. No retries or longer limits were added.
- Python: all 68 tests passed.
- Local Debug compilation passed after Swift testing finished.
- Structural API matrix: zero errors. These results do not prove API parity.

Raw output is in /tmp/draftly-modularity-audit*. It is not tracked. No new
Computer Use session, app deployment, permission request, audible output or
personal-data check was needed. Existing headless tests use neutral fixtures;
OffscreenTestWindow rejects attempts to show or activate its windows.

The strict engine check and native capability checklist remain separate from
this audit. Their pending work is not reclassified. Resume refactoring at R1,
or resume cloning from status and engine-native-checklist after that stage.
