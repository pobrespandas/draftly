# Draftly architecture

## Current continuation

The [modularity audit](modularity-audit-2026-10-22.md) records the current
refactoring diagnosis. [Editor completion context](refactoring-completion-context-2026-10-22.md)
implements its first stage. [Workspace preparation](refactoring-workspace-preparation-2026-10-22.md)
is also implemented. [Cloud QA preparation](refactoring-cloud-qa-preparation-2026-10-22.md)
is complete. [Editor styling](refactoring-editor-styling-2026-10-22.md)
is implemented. [Shared text mutation](refactoring-editor-text-mutation-2026-10-22.md)
completes R3. All five bounded audit stages are integrated into main.
The [integration record](refactoring-integration-2026-10-22.md) records validation
and history preservation.
See [status](status.md) for
functional work. The [dated editor/scripting record](editor-scripting-2026-10-22.md)
retains its original scope. The audit does not implement its proposed changes.
The [Advanced Find refactoring stage](refactoring-find-2026-10-22.md) is complete.
The [option refactoring stage](refactoring-options-2026-10-22.md) is complete.
The [editing refactoring record](refactoring-editing-2026-10-21.md) describes the
previous completed stage. Current execution uses ActionRunner.runAsync and
ActionScriptWorker. The dated records below retain their original scope; they
do not describe the current engine or establish new compatibility acceptance.

## Action editing boundary

ActionEditingCopy owns the temporary action, selected step and step operations.
ActionEditor renders bindings and owns save, export, shortcut errors and dismissal.
The editing copy saves through the existing atomic saveActions operation.
The view dismisses only after success. A failed save retains the copy. Cancel
discards temporary edits. Imported shortcut conflicts have a separate preservation
check; assigning a new shortcut still uses the shared validator.

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

## Editor styling boundary

EditorSyntaxStyler applies base attributes, visual syntax rules, custom scopes,
active links and indentation metrics to an NSTextView. Its value inputs contain
only style settings and the syntax definition. It receives native link defaults
explicitly. It does not read NativeEditor, EditorSession or WindowModel.

Coordinator.highlight captures link defaults once and delegates styling. The
coordinator retains text events, synchronization, selection, Undo, focus and
invalidation. ThemeTextAttributes and SyntaxDefinition retain their rules.
Attribute order and the built-in visual fallback rules remain unchanged.

## Editor text mutation boundary

Coordinator.replaceSessionText owns the shared history reset, identity update,
Undo registration and session-content assignment. It returns whether text changed.
Each route supplies its own draft-change decision and retains its update guard,
style and display invalidation, selection, scrolling and focus policies.
updateNSView also treats an empty style cache as a draft change. Script
synchronization does not. restore remains the shared Undo/Redo inverse operation.

## Action catalog boundary

`ActionCatalog` is an internal value with actions and group records. It owns
group membership, identity lookup, visibility and presentation order without
persistence or UI dependencies. `LibraryStore` delegates its existing catalog
methods. Storage reload order remains separate.

## Workspace preparation boundary

WindowModel.prepareWorkspace resolves presentation references and validates
external theme files through the existing components. Both application entry
points use it. Callers retain saving, cancellation and published state changes.
The script route prepares and applies. Save-and-apply prepares, saves, cancels
and applies. The window apply wrapper cancels before preparation and keeps its
existing error wrapper. File checks retain their current bookmark effects.

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

## Cloud QA metadata boundary

prepare-cloud-qa.py separates metadata transformation, filesystem preparation
and CLI entry. cloud_qa_metadata owns the metadata and backup decision without
I/O. prepare reads the current files, generates the ID and writes the backup
before the destination. main preserves the existing arguments and working
location. Importing the module does not run preparation. Build identities and
signing remain with the existing build wrapper and configuration.

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

## Editor completion data boundary

EditorBody supplies a lazy completion-context provider to NativeEditor. The
provider reads the current draft and candidates when invoked. The text-view
callback does not obtain completion data from the Touch Bar model.
EditorCompletionContext builds the current draft with the callback source and
session identity, then delegates matching to SyntaxDefinition. Without a
provider, standalone editors retain an empty candidate list and fallback draft.
Touch Bar configuration, completion invalidation, text synchronization, selection
and Undo retain their existing owners.

## Advanced Find command boundary

AdvancedFindCommands coordinates selection, navigation and replacement for the
current editor. It has no view state. WindowModel retains the current complete
AdvancedFindRequest for its source window. AdvancedFindView keeps bindings,
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

## Sharing lifetime boundary

SharingActionWait owns the continuation, timer and single result of one sharing
request. It clears the continuation and cancels the timer before presentation
cleanup. It resumes the caller after that cleanup. Cancellation keeps its
existing MainActor dispatch.

SharingSession owns discovery, deadline decisions, service events and resource
retention. A selected service can still use its attachment after the caller
receives cancellation or timeout. That session stays retained until a terminal
service callback releases its file and driver. Prepared data and the system
picker remain separate. Printing keeps its own wait because its cancellation
and sheet rules differ. See [the refactoring record](refactoring-native-lifecycle-2026-10-22.md).

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


### Syntax completion boundary

SyntaxDefinition calculates completion requests and preserves separate labels,
values and draft identities. NativeEditor supplies the current text and library
snapshot. EditorSyntaxCompletions owns selection and the transient child panel.
It checks source, selection and draft identity before an insertion. DraftTextView
keeps text input and native Undo ownership. Hidden editors cannot show the panel.

### Syntax import choices

SyntaxImportPreparation resolves replacement or copy identity without saving.
SyntaxImportReview presents the conflict choices and checks for catalog changes.
DraftFileCommands and ApplicationURLRouter use this review before persistence.
File syntax installation retains its bookmark ordering in SyntaxFileAccess.

Find commands from the interface preserve that window's current request when no
query is supplied. Script requests retain their existing query initialization.
Explicit script query text, including an empty string, replaces the current query.
Closing the Find window does not clear the source window request. Process restart
and cross-window sharing of defaults are separate contracts.

FindWindow handles Command-Return before multiline text input. It calls the same
AdvancedFindCommands.find operation as the button. Ordinary Return stays with the
text editor. The callback retains no source model and ignores a closed Find state.

EditorSyntaxPresentation resolves the assigned grammar with window preferences.
It returns a definition or a visible error without mutating editor content.
EditorBody retains its editor view while the notice appears or disappears.
SyntaxFileAccess keeps bookmark lookup separate from shared syntax records.


## Settings option writes

SettingsOptionEditing patches stored Markdown and shortcut JSON. It preserves
unknown fields and does not fill missing display defaults. Invalid JSON reports
an edit error and remains unchanged. MarkdownPreferences reads Boolean fields
without discarding valid siblings when another field has a future value type.
CommandShortcuts validates each stored override independently. An empty editable
binding disables that command; Reset removes the override. Fixed commands keep
their existing defaults. Local and global forms retain their distinct validators.


## Editor Settings navigation

SettingsView retains Settings routing. EditorSettingsView owns the existing
font and layout controls and the syntax sidebar. EditorSettingsNavigation owns
local section and syntax selection. It builds a stable syntax catalog without
writing preferences. EditorLayoutPreferences renders the selected section and
retains theme commands, sheets and errors. Font and layout preferences remain
global. Syntax indentation and feature options retain their existing keys.
