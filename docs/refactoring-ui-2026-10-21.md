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

1. Sort writer: in progress.
2. Inspector policy: pending.
3. Test-only theme reader: pending.
4. Preference fixtures: pending.

## Closure requirements

Close only this stage after all four accepted items are resolved or explicitly
justified, builds and relevant tests pass, and commits and references reach the
remote. Record automatic and real-use evidence separately. Resume cloning from
the retained backlog, with inspector and Workspaces first. Draftly remains open.
