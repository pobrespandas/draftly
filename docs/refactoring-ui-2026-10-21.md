# UI boundary refactoring — 21 October 2026

## Scope and reference

This is a behavior-preserving refactoring stage. It does not resume feature work.
The user prioritizes the action inspector, action organization, Workspaces,
Settings and personalization. Production, tests, scripts and documentation were
reviewed. Keep Note, public APIs, identities, unknown fields, library and backup
formats, action scripts, temporary editing, editor state and appearance choices.

Reference commit: 39ed835. Annotated tag: pre-refactor-settings-2026-10-21.
Cloning checkpoint branch: agent/cloning-ui-checkpoint-2026-10-21.
The working tree was clean. Earlier incomplete features were already committed;
the checkpoint retains them. No new functional sort correction had been edited.
No prior build, test or loopback server process was active at inspection.
The process search matched only its own inspection command. No process was killed.

## Baseline

The checked Swift runner verified 626 core and 524 app methods. All 57 Python
methods passed. Unsigned Xcode compilation passed. Logs and reports are in /tmp
under draftly-refactor-ui-baseline names. No automatic test opens or moves a
window, requests access, plays sound or reads personal data. These results do
not accept the pending native UI checks or claim Drafts compatibility.

## Accepted diagnosis

1. Shared Workspace sort writer. WorkspaceOptionsEditor.updateSortOptions and
   ActionRunner.workspaceValue repeat the entry merge, title/name mapping and
   direction mapping. Divergent writers make future contract work harder. Move
   only that pure write into Core. Keep each caller's inputs and optional flag
   policy. Risk: malformed shapes and unknown fields can change. Characterize
   those cases and run existing Workspace contract and application tests.
2. Inspector field policy. ActionEditor embeds hidden-key, multiline, tag-menu
   and editor-height decisions. The multiline-key list occurs twice. Extract
   pure field descriptors and render them in the same view. Risk: a field can
   disappear or move. Test exact keys, order, heights and nonmutation. Preserve
   generic fields, current defaults and imported payloads.
3. Test-only theme reader. WorkspaceThemeValues is in EditorPreferences but only
   three test files call it. Move it to test support and reuse Workspace.apiOptions.
   Risk: absent or invalid metadata can produce a different result. Retain the
   assertions and characterize those inputs. No theme selection change.
4. Preference fixture lifecycle. WorkspaceSortStateTests, ActionMoveNavigationTests
   and ApplicationAppearanceTests repeat temporary UserDefaults setup and cleanup.
   Use an app-test fixture with explicit cleanup. Keep suite prefixes, injection,
   reopen behavior, test identities and assertions. Risk: shared state or leaked
   defaults. Run the affected suites and complete checked test inventory.

ActionCatalogPresentation already separates catalog policy from rendering. No
additional organization layer is justified. No script rewrite or historical
document deletion is justified by this review. Keep all existing contract tests.

## Functional backlog retained separately

The effective per-view Workspace sort can disagree with model labels. Workspace
list-option fallbacks differ between editor and window. Unsaved Workspace list
options can be bypassed by panel getters. These remain functional follow-ups.
Platform metadata is preserved but not evaluated. Inspector Enabled Save/Cancel
and action-list option native checks remain pending. None is completed here.

## Stage results

1. Sort writer: complete. Workspace.updateSortOptions owns the existing merge
   operation. Both callers retain their original inputs. Characterization passed
   before extraction: five editor methods and two bridge methods. After extraction,
   eight app methods, four writer methods and 24 Core contract methods passed.
   Parameterized cases cover malformed shapes, all sort keys and both directions.
   Unsigned Xcode compilation and matrix structure passed. No native behavior or
   stored format changed. No Computer Use was needed for the pure extraction.
2. Inspector policy: complete. Pure ActionStepInspectorFields descriptors own
   field exclusion, order, multiline/tag policy and height. The existing view
   retains its bindings and layout. Four headless methods cover empty, mixed,
   unknown and unchanged step data, including nil/true/false enabled values.
   All five imported-action preservation methods also passed. Unsigned Xcode
   compilation passed after project generation registered the new app source.
   No new field, option, editor behavior or native acceptance is claimed.
3. Test-only theme reader: complete. WorkspaceThemeValues now belongs to app
   test support and reads through Workspace.apiOptions. The three existing
   consumer files are unchanged. Three characterization methods passed against
   the original helper, including malformed/type cases. After relocation all
   48 affected methods in four suites passed headlessly. Unsigned Xcode
   compilation and matrix structure passed. No production theme behavior changed.
4. Preference fixtures: complete. App-test TestPreferences owns the isolated
   suite name, defaults object and explicit cleanup. The three assigned files
   retain exact prefixes, preference injection and reopened-suite checks. All
   16 methods in the four affected suites passed with no parallel app execution.
   Function names, Test annotations and all 66 expectation lines are unchanged.
   Unsigned Xcode compilation passed. Complete final validation passed; see the closure below.

## Closure requirements

Close only this stage after all four accepted items are resolved or explicitly
justified, builds and relevant tests pass, and commits and references reach the
remote. Record automatic and real-use evidence separately. Resume cloning from
the retained backlog, with inspector and Workspaces first. Draftly remains open.


## Final validation and closure

All four accepted items are complete. No accepted item was deferred. The final
checked runner verified 630 core and 531 app methods. All 57 Python methods
passed. Unsigned Xcode builds passed after each source stage. The final source
state is the stage-four build. Baseline inventory has 1,150 methods; final has
1,161. No baseline identity is missing. The 11 additions characterize the sort
writer, inspector policy and relocated metadata reader. They do not duplicate
or replace existing execution or import acceptance methods.

Matrix structure has zero errors. Strict engine/global parity still reports
18/4,107 diagnostics. Those are the retained cloning backlog, not a new failure
introduced by this stage. The matrix and auditor files are unchanged. Original
JSON fixtures, scripts, bridge resources, Note model, coding rules, Configuration
and app resources have no diff from the reference tag. No library migration,
backup change, preference-key change or functionality was introduced.

No Computer Use was needed for these pure policy and test-support extractions.
No new real-use acceptance is claimed. Earlier inspector Enabled Save/Cancel,
action-list preferences and reference comparisons remain pending. This pass does
not claim to validate those earlier features. Logs and test reports stay in /tmp
under draftly-refactor-ui-final names, outside Git.

The status page and local handoff are updated. The existing local handoff remains
ignored by repository policy; this tracked record carries the durable resumption
state. No historical document, contract test or reference archive was deleted.
Scripts received no rewrite because this audit found no accepted script-boundary
problem. Atomic scoped commits and the reference tag/checkpoint branch are on
the remote. Check the final documentation commit for the closing revision.

## Resume cloning

Resume only after the user requests feature work. The latest cloning order is:
inspector, Workspaces, Settings and personalization; then visual comparison,
capture and search. Keep the engine/API backlog separate and open.

The first functional correction is the Workspace sort-state mismatch. Extend
WorkspaceSortStateTests with edit, save, reopen and apply. Assert both visible
order and model sort/direction. The current WorkspaceOptionsEditor writes per-view
_sort metadata, while WindowModel.applyResolvedWorkspace loads the top-level
sort before assigning that metadata. DraftListPanel labels use the model fields;
rows use Workspace.scriptSort. Correct this in its own fix commit. Then address
list-option fallback and unsaved Workspace presentation, also with their own
regressions. Do not mix those changes into this refactoring record.

Retain pending native inspector acceptance, platform semantics, original Drafts
group installation, visual measurements and capture/search checks. The complete
Mac cloning objective remains open.
