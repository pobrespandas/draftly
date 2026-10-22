# Draftly architecture

## Current continuation

Editor and scripting work continues in the [dated scope record](editor-scripting-2026-10-22.md).
The [Advanced Find refactoring stage](refactoring-find-2026-10-22.md) is complete.
The [option refactoring stage](refactoring-options-2026-10-22.md) is complete.
The [editing refactoring record](refactoring-editing-2026-10-21.md) describes the
previous completed stage. Current execution uses ActionRunner.runAsync and
ActionScriptWorker. The dated records below retain their original scope; they
do not describe the current engine or establish new compatibility acceptance.

## Action editing boundary

ActionEditingCopy owns the temporary action, selected step and step operations.
ActionEditor renders bindings and owns save, export, shortcut errors and dismissal.
The editing copy does not persist data. Cancel discards it.

## Step value boundary

ActionStepCreationDefaults owns values added to new steps. It does not fill
missing imported fields. ActionStepInspectorFields owns labels and control
layout. ActionStepValueRules in Core owns effective Prompt defaults, exact
Boolean reads and the configured-value type/default-key map. The app reads
these through the ActionEditing SPI in both SwiftPM and Xcode builds.
Existing public signatures and persisted dictionaries stay unchanged.

Unknown configuration types retain separate caller policies. Reading a value
uses the String default. The inspector offers no type-specific default control.
Initial configuration rejects the type. Displaying an effective default never
writes it. Explicit empty strings still take precedence over missing values.

## Installed theme command boundary

InstalledThemeCommands coordinates library writes, local theme preferences and
file bookmarks. It delegates to the existing preference and file-access types.
Settings owns panels, confirmations, temporary edits and error presentation.
Save and install precede selection. A later selection error retains prior effects.

## Theme picker boundary

ThemePickerOptions supplies ordered labels, identities and references without
persistence or UI effects. Editor Settings uses type-prefixed tags. Workspace
Settings keeps name or UUID tags. Resolution and missing references stay with
existing consumers. Picker tags are not a new storage format.

## Action catalog boundary

`ActionCatalog` is an internal value with actions and group records. It owns
group membership, identity lookup, visibility and presentation order without
persistence or UI dependencies. `LibraryStore` delegates its existing catalog
methods. Storage reload order remains separate.

## Workspace sort writer boundary

`Workspace.updateSortOptions` in Core owns the common sort-field mutation.
WorkspaceOptionsEditor and the scripting bridge keep their caller policies.
WindowModel retains its valid-object guard and silent encoding failure policy.
The options editor retains recovery, validation and sorted serialization.
The shared rule does not combine those different caller policies.

## Configuration default boundary

`ActionConfigurationField` owns raw key/type lookup and text-value selection.
Import, runtime and prompt callers keep their own validation and conversion
policies. The descriptor does not change imported values or confirmation state.

## Auditor reference boundary

`SwiftTestReferences` owns Swift source lookup and issue scanning for one
validation. The auditor owns evidence policy, reference archives and CLI
handling. A source cache ends with its validation. Compatibility wrappers
use the current root and do not share cached source across calls.

## Editing-bar boundary

`EditorBarTextCommands` calculates text and selection results without UI or
storage access. EditorActionBar supplies the safe selection and applies the
result before focus and save effects. Markdown marker rules and current line
behavior remain unchanged; syntax parity is a separate functional concern.

## Advanced Find command boundary

AdvancedFindCommands coordinates selection, navigation and replacement for the
current editor. It has no view state. AdvancedFindView keeps bindings, options,
query errors, result previews, focus and dismissal. EditorFindQuery remains the
matching and replacement engine. AdvancedFindRequest contains both texts and
matching options. AdvancedFindHistory stores complete requests in local
preferences. Library backups do not contain this history. Native find and preferAdvancedFind routes
remain separate and unchanged.

Navigation uses UTF-16 ranges and safeSelection. It excludes an identical
zero-length result before wrapping. Replace All updates content and safe
selection, synchronizes the native editor, reports the change and flushes.
A failed flush retains the changed text, error and unsaved state. The command
does not add rollback or present a new message. The view still disables
replacement when there are no results; the command retains its previous valid
query behavior when called directly.

AdvancedFindWindow presents a native window from LibraryView. WindowModel only
stores presentation state; scripting tests do not create native windows. An
explicit presentation identity controls raising and initial focus. Query and
content changes update the existing view without raising its window. The bridge
closes Find when the source closes and rejects delayed focus work for old windows.
Multiline fields and result previews stay in AdvancedFindView.

## Native asynchronous route boundary

`NativeAsyncRoute` classifies support and dispatch for NativeActionHost.
NativePromptAdapter retains its own operation inventory. Classification does
not invoke capabilities. A missing asynchronous route retains synchronous
fallback; it does not mean that a direct asynchronous call must fail.

## Window-submission boundary

`WindowModel.submitWindowAction` owns reservation and the stored task for
single and batch launches. Callers pass a body that receives the model; they
do not capture it before startup. Direct async entry points keep their caller
lifetime. Execution sessions, source-window observers, worker waits and native
continuations retain separate owners because their cleanup contracts differ.

## Historical refactoring baseline — 19 October 2026

The annotated tag `pre-refactor-2026-10-19` points to `2fba5bd`.
It is published on origin. The baseline passed 170 app and 266 core tests.
This refactoring preserves behavior. Mac parity and async engine work stay open.

## Dependency direction

The app composes services. Window state owns the current editor and observable
presentation state. Window adapters translate scripting operations. Resolvers
validate values before the window changes. The library remains shared.

The domain glossary defines drafts, capture, workspaces, action sessions, and
execution history. Technical components are described here, not in the glossary.

## Stage 1: window boundaries

`WindowDependencies` supplies navigation and preferences. AppController composes
production routes. Tests can provide separate defaults and routes without
starting the application singleton. Existing mutable callback seams remain.

`WindowActionAdapter` translates the existing scripting dictionaries.
WindowModel keeps its published state and editor lifecycle. The workspace
presentation resolver validates group and theme references without window
mutation. Existing return values and errors remain unchanged.

Validation: all 436 existing Swift tests passed after extraction. Two additional
tests check independent windows and injected scripting routes. Native acceptance
has not been repeated. No visual parity status changed.

## Stage 2: preferences and Settings

Settings pages are separate view components. General, HTML, bookmark, theme,
and window preference access has no dependency on SettingsView. Existing keys,
formats, defaults, and AppStorage bindings remain. Local preferences do not
move into the library. The related preference and workspace tests passed.

## Historical stage 3: action execution before the worker

ActionRunner coordinates sessions, queues, and final effects. ActionStepExpansion
resolves included steps. ActionStepExecutor performs one step. ActionScriptValues
maps draft values against explicit library snapshots. EditorSession and execution
results have separate definitions with their existing public names.

ActionScriptRuntime owns the context, bridge closures, and host-call lifetime.
It stops accepting host and module calls after close. JavaScriptCore stays on
MainActor. Existing synchronous APIs and RunLoop waits remain. No runAsync or
worker was added. All 266 core tests and four script-editor Undo tests passed.
A new runtime lifetime test passed. The normal matrix check has zero errors.

## Stage 4: storage and synchronization

LibraryRecordPersistence owns container setup, the record cache, payload mapping,
and commit/rollback mechanics. LibrarySyncCoordinator receives remote changes,
CloudKit events, and account checks. It reports through callbacks. LibraryStore
keeps its public container, published collections, and domain operations.

The Record schema, store URL, history settings, merge policy, backup contract,
and operation boundaries remain unchanged. All 267 core tests passed, including
reopen, rollback, backup, and cloud-state cases. This is not new two-client
CloudKit acceptance. That acceptance remains separate.

## Background test policy

The user requested tests that do not interrupt normal Mac use. Three visible
animation tests and their fixture were removed. OffscreenTestWindow rejects
window ordering and activation. Hidden layout, responder, rendering, storage,
Undo, and scripting tests remain. Visible animation acceptance now requires a
separate manual session. Do not claim that offscreen tests prove visible motion.

The updated background suite passed 169 app and 267 core tests. No visible
Computer Use session will run as part of this refactoring acceptance.

## Stage 5: native and application adapters

NativeActionHost routes operations to prompt, file, preview, automation, message,
and system adapters. HTML conversion has a separate component. Legacy host
methods delegate to those components. Existing operation names and results stay.
Notification errors use an injected error callback. Production hosts are created
by AppController; tests do not require its global instance.

AppController composes capture, quick search, and window routes. ApplicationURLRouter
handles existing URL endpoints. StatusMenuController owns the status menu and
its update policy. Capture and search controllers receive library and navigation
providers. The normal matrix check and all 436 background Swift tests passed.
Prompt implementation paths were updated without changing compatibility status.

## Stage 6: view components

The library root keeps selection, tag-search visibility, and the window model.
Filters and editor presentation receive explicit values and bindings. Native
list helpers stay with the draft list. Action list, editor bar, command palette,
and each dialog have separate components. Shared measures remain unchanged.

The app scene injects its controller into library views, Settings, and commands.
WindowModel no longer imports SwiftUI; focus bridging has its own component.
Two unused library-view helpers were removed. All 169 app and 267 core tests
passed after extraction. Visible use was not repeated under the background test
policy. The change does not claim new visual or CloudKit acceptance.

## Historical final acceptance — 19 October 2026

File dialogs now live in DraftFileCommands. Tag operations receive the peer-window
provider. Toolbar search and shortcut Settings use explicit routes or owners.
AppController.shared remains at app lifecycle and App Intent entry points.
ActionHost has its own boundary definition. TestMainQueue centralizes fixture
synchronization. Offscreen fixtures retain responder and layout coverage.

Final checks passed on 19 October 2026: 170 app tests, 267 core tests, 24 Python
tests, local Xcode build with signing disabled, whitespace validation, and the
normal matrix check with zero errors. The five original action fixture files
are unchanged. Every API compatibility classification matches the baseline tag.

No package target, stored schema, backup format, or public scripting API changed.
No worker or runAsync was added. Visible UI, two-client CloudKit, and signed
installation were not repeated. Those checks retain their previous pending
status. Historical test totals elsewhere are not the current test inventory.

## Historical test refactoring

The scripting API tests now have eleven suites by API area. Shared setup, script
builders, isolated preferences, and native Undo text views have test-only owners.
Specialized hosts retain their own failure and callback policies. Three duplicate
version cases were removed. The retained contract cases cover their assertions.
See [test structure](testing.md) for the replacement map and background policy.
Production code and package targets are unchanged.

## Historical typed core scripting commands

ScriptCommand decodes the 24 core wire operations into typed cases. It owns
text defaults, identifiers, query options, and ranges. ActionScriptCommands
executes those cases. ActionRunner keeps the run lifecycle and delegates core
command execution. The public JavaScript and host interfaces stay unchanged.

ScriptNoteInput retains note payloads until execution. Loading first saves the
editor, then resolves the note against the current library. ScriptWorkspaceInput
also delays resolution so a missing window keeps its existing error priority.
ScriptTextRange checks UTF-16 bounds for reads and replacements. Selection still
uses the editor's clamping policy. Successful mutations save before they notify
the native editor.

This is the first typed boundary. Other API operations still use dispatchAPI,
and native capabilities still use ActionHost dictionaries. Unknown core names
delegate to those existing routes. No async worker, new public API, storage
format, or compatibility claim was added.

## Current async execution boundary

ActionRunner.runAsync owns the public async lifecycle. ActionScriptWorker owns
JavaScriptCore and its scheduled timers on one serial queue. The bridge moves
JSON strings and execution and step identities. MainActor retains library and UI
ownership. Shared configuration and success effects keep the legacy adapters
compatible. ScriptHTTP supplies an async transport; native adapters retain their
remaining acceptance work.

Window actions reserve scheduling, cancel on user edits or navigation, and retain
scripted Undo and navigation. Stored-editor synchronization uses the same rule.
Headless writes reject concurrent stored-content changes and deleted drafts.
See [Actions execution](actions-engine.md) for implementation and native limits.
