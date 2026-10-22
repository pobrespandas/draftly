# Action editing refactoring — 22 October 2026

## Reference and baseline

Cloning is paused for this behavior-preserving stage. The clean reference is
65cfc4b, with annotated tag pre-refactor-options-2026-10-22. Main matched
origin/main. No earlier work was discarded. Existing branches remain unchanged.
No build, test or QA process was active at the start. The installed app stays
unchanged.

The initial serial run passed 646 Core and 650 app methods. All 68 Python tests
and the local Xcode build passed. Separate target reports match all 1,296 discovered
method identities. Raw reports and logs stay in /tmp, outside Git.
Earlier concurrent worker timeouts and the window-opening deadline fragility
remain known risks. This stage does not add retries or change deadlines.

## Accepted diagnosis

1. ActionEditingCopy reads creation defaults from ActionStepInspectorFields.
   This makes step creation depend on a presentation descriptor. Move creation
   choices to ActionStepCreationDefaults. Preserve every value and selection
   rule. Risk: imported steps could acquire defaults. Existing copy and field
   tests must retain missing fields, identities and unknown data.
2. Inspector and execution repeat Prompt Boolean and default rules, the Create
   Draft destination rule, and configured-value type/default-key rules. Share
   these pure rules in Core. Keep creation choices, labels and controls in the
   app. Preserve distinct unknown-type and missing-value policies. Risk: a
   general Boolean conversion could change imported values. Characterize exact
   accepted strings before replacing reads.
3. Prompt and Create Draft editing tests repeat the same headless library,
   Unicode source, selection and runner setup. Share only that setup. Keep each
   suite's actions, host, assertions and test names. Other fixtures prove
   different contracts. No test deletion is justified.
4. Architecture mixes current boundaries with historical engine statements.
   Mark the history and put current guidance first. Keep prior evidence and
   acceptance limits. Risk: historical results could appear current. Check the
   descriptions against the source and current test commands.

## Boundaries retained by the wider audit

ActionCatalog, InstalledThemeCommands, ThemePickerOptions and Workspace
presentation preflight already have useful responsibilities. Workspace sort
mutation is shared while caller error policies stay separate. SyntaxDefinition
already serves editor and scripting. File size alone does not justify another
layer. Scripts already separate test discovery, execution and result checks;
QA refresh scripts retain identity and Services safeguards.

Syntax selectors currently differ in sorting and duplicate removal. Treat that
as a functional follow-up, not a refactoring correction. Keep Action.find
duplicate-name behavior and other contract gaps in the functional backlog.
No new native or Drafts compatibility acceptance is implied by this stage.

## Invariants and validation

Keep public contracts, Note, identities, unknown fields, scripts, library and
backup formats, preferences, selection, Undo, fonts and preview behavior.
Missing fields and explicit empty strings remain distinct. Only an edit writes
a displayed default. Save and Cancel keep their existing behavior.

Run affected suites and local compilation for each production change. At the
end, check complete serial target reports against inventory, Python tests and
matrix structure. Automatic tests stay headless and use temporary data. Native
binding checks, if needed, use a separate temporary QA session. Never replace
the installed app as part of this refactoring.

## Stage results

1. Creation defaults: implemented. ActionEditingCopy now depends on
   ActionStepCreationDefaults rather than the inspector. Presentation reads
   Prompt defaults from the same app-owned definition. All 27 affected editing
   methods passed, including defaults, imported data, identity, Save and Cancel.
   The local Xcode build passed. Existing assertions remain unchanged.

2. Shared value rules: implemented. ActionStepValueRules owns the existing
   Prompt defaults, exact Boolean reads and configuration type/default-key map.
   Inspector and runtime keep their own unknown-type policies. Three new methods
   with 17 parameter cases passed against the previous implementation before
   substitution. After substitution, 27 app methods and 27 Core methods passed.
   SwiftPM and the local Xcode build passed. Independent review found no change
   in rendering order, errors, imported data or Boolean interpretation.

The app and Core are separate modules in the Xcode build. The small
ActionEditing SPI shares these rules without adding an ordinary public API.
It adds exported SPI symbols; existing public signatures stay unchanged.
Package-only access would not serve both build modes without extra build
configuration. No model, storage representation or generic registry was added.

The test fixture extraction is in progress. No manual check is credited yet.
