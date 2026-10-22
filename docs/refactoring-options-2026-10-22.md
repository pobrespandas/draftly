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
remain known risks. This stage does not add retries or change production deadlines.

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
as a functional follow-up, not a refactoring correction. The previously accepted
Action.find duplicate-name correction stays unchanged. Keep other contract gaps
in the functional backlog.
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
   with 17 cases passed against the previous implementation before
   substitution. After substitution, 27 app methods and 27 Core methods passed.
   SwiftPM and the local Xcode build passed. Independent review found no change
   in rendering order, errors, imported data or Boolean interpretation.

The configured-value picker also derives its four choices from the shared type
list. Its labels and order stay String, Text, Boolean, Number. After this last
app-only change, all 650 app methods and local compilation passed. A fresh QA
launch recovered the saved Boolean value and displayed those four options in
order. The check did not save another edit.

The app and Core are separate modules in the Xcode build. The small
ActionEditing SPI shares these rules without adding an ordinary public API.
It adds exported SPI symbols; existing public signatures stay unchanged.
Package-only access would not serve both build modes without extra build
configuration. No model, storage representation or generic registry was added.

3. Editing fixture: implemented. ActionEditingExecutionFixture shares only
   in-memory setup, the Unicode source and selection, optional host lifetime and
   runner entry selection. Prompt-specific hosts, actions and assertions remain
   local. All 650 app methods passed after extraction. No test was removed or
   renamed. The preceding local build used the same production sources.

## Independent test-infrastructure defect

The integrated Core run stopped making progress in
XMLRPCLocalServerTests.realHTTPPreservesXMLBodyUnicodeFaultsAndInvalidResponseErrors.
A process sample showed NSConcreteTask.waitUntilExit at line52 on a cooperative
thread. The Python child was already absent. The fixture and XML-RPC runtime
were unchanged by this stage. The earlier baseline passed; this observation
must not be hidden by a retry. The confirmed stuck test helper was terminated;
that incomplete run does not count as acceptance.

Independent test correction: both XML-RPC process waits now use an exit event
registered before launch. A two-second diagnostic bound matches the existing
HTTP fixture. It is not a production deadline. A missing event throws instead
of waiting without a bound. A deterministic test covers an event before the
wait, a repeated wait, and a deadline without an exit. All three XML-RPC methods
passed, including real body/fault/error and disconnect checks. No retry was
added. Complete Core integration then passed all 650 methods; its earlier incomplete
run remains recorded. Manual results are separate below.


## Manual regression results

Computer Use ran separately after automatic tests. A fresh local QA bundle used
an isolated preferences domain and library. It published no Services, URL scheme
or document types. CloudKit and global capture shortcuts were disabled. The
habitual app was neither launched by the check nor replaced.

Verified in use:

- Add Prompt, Create Draft and Configured Value steps. Prompt starts with Text
  Field off and Cancel on. Create Draft starts with Open in Editor on.
- Set Prompt text/buttons/title and a Unicode default. Select Boolean, set its
  default and turn required configuration off. Move the selected step up/down.
- Save and reopen all four steps. The saved options retain their values.
- Change Prompt Cancel, delete the Configured Value step in the temporary copy,
  then cancel editing. Reopening retains the saved step. The runtime still
  offers the saved Cancel button.
- Runtime Cancel leaves one draft and the source Unicode selection. Retry and
  Second produce exactly `Second: café 🐼` as a second draft in the background.
  The source text and selection stay current. Undo removes a typed tail; Redo
  restores it.

This checks refactoring bindings and existing behavior. It does not accept all
Prompt options, import variants, integrations, visual parity or Drafts contracts.
No personal data, permissions, messages or sounds were used.

QA quit normally and its process was absent. Its exact Launch Services record
was retired. The bundle, exported preferences and closed library were kept
together in recoverable Trash. Raw screenshots and logs were not added to Git.


## Integrated acceptance

Implemented: all four accepted responsibility changes. The separate XML-RPC
fixture correction preserves the protocol assertions. Workspaces, themes,
syntax selectors and scripts received no speculative structural changes.

Automatic: 650 Core methods in 124 suites and 650 app methods in 117 suites
passed. Each target's fresh report matches discovery. All 1,296 baseline method
identities remain; four characterization/regression methods were added. All
68 Python tests passed. The matrix structure check has zero errors. Local Xcode
compilation passed after the final production change. No build overlapped a
Swift test run. The initial incomplete Core integration remains a failed gate,
not a passing result obtained by retrying unchanged code.

The five original action snapshots, manual action fixtures, compatibility
classifications, package targets, signing configuration and storage/backup
formats have no diff from the reference. This is not new signed-distribution,
CloudKit, integration-capability or Drafts compatibility acceptance.

Manual: the binding and runtime subset above passed. A final QA restart also
retained both neutral drafts, all four steps and the configured Boolean value.
The generated type picker preserved labels and order. QA quit normally again;
its exact registration was retired. Package, preferences and closed library
are in recoverable Trash. The habitual installation was not replaced.

Final QA identity: `com.pobrespandas.draftly.refactor-qa-0f153075`.
Final debug implementation SHA-256:
`46d6231da356422cd841129dd834c4f0113d6629639f6aafbd3e5ac29120ff8f`.
Temporary session metadata: /tmp/draftly-refactor-20261022-qa.json. These paths
can disappear after restart; conclusions above are the versioned record.

## Closure and resume point

Each implementation and the independent test correction has a scoped atomic
commit. The reference tag and validated commits are published. This record,
architecture, test guidance, glossary, status and local handoff identify the
current boundaries and preserve historical evidence. No earlier branch or work
was discarded. No new regression remains unresolved in this stage's checks.

Retain the earlier concurrent worker timeouts and window-opening timing risk.
This stage does not change their deadlines or claim parallel acceptance. The
ActionEditing SPI is an internal cross-module dependency; both build modes must
continue to be checked when these rules change.

Cloning remains paused. When feature work is requested, resume Editor and
scripting: syntax-defined tasks, markers, links, custom grammars and advanced
find acceptance. The existing inspector option and native capability backlog
remains separate. Review the different syntax-selector order/duplicate policies
before proposing a functional change. Do not reopen the accepted Action.find
fix as an unresolved duplicate-name defect. Pro-only comparisons and the broader
Mac acceptance remain pending. This refactoring does not complete Draftly.
