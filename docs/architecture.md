# Draftly architecture

## Refactoring baseline

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

## Stage 3: action execution

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

## Final acceptance

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

## Test refactoring

The scripting API tests now have eleven suites by API area. Shared setup, script
builders, isolated preferences, and native Undo text views have test-only owners.
Specialized hosts retain their own failure and callback policies. Three duplicate
version cases were removed. The retained contract cases cover their assertions.
See [test structure](testing.md) for the replacement map and background policy.
Production code and package targets are unchanged.

## Typed core scripting commands

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
