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
