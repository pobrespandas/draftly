# Draftly architecture

## System overview

Draftly has two source modules. `DraftlyCore` contains the library models,
storage, templates, scripting, and action execution. `Draftly` connects those
operations to Mac windows, the editor, settings, and native services.

Start with the [development guide](development.md) to build the app and locate
files. The sections below explain component boundaries and the reasons for
past refactorings. Use [project progress](project-progress.md) for current work;
a completed refactoring does not mean a feature has complete Drafts parity.

## Continuation and records

Use [project progress](project-progress.md) for current work. The following
links preserve completed refactoring stages and their original diagnoses.

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


EditorThemePreferences reads each local theme slot independently. A write
patches the selected slot in the complete JSON object. Unknown sibling values
remain stored. Malformed JSON or an invalid storage type rejects the write
without advancing the theme revision. Reads retain their existing safe fallback
and do not write defaults. Theme commands retain their persistence ordering.


SyntaxFeaturePreferences keeps its nonthrowing API. Invalid JSON or a non-object
syntax slot returns unchanged data. SettingsOptionEditing converts invalid form
input into an explicit error, then delegates the patch to Core. The view stores
the result only after success. Syntax feature errors do not share theme error
state. Unknown values and other syntax slots retain their existing structure.


## Syntax font preferences

EditorSyntaxFontPreferences resolves optional local font and size overrides
against the existing global defaults. It patches one field or resets only
those two fields. Unknown fields and other syntax options remain stored.
Editor Settings reuses the font catalog for both defaults and syntax overrides.
EditorBody resolves the current draft syntax before it builds NativeEditor.
The existing native style and Undo rules remain unchanged. Shared syntax
records and backup formats do not contain these device font preferences.

## Syntax layout preferences

EditorSyntaxLayoutPreferences resolves five optional local layout fields against
Editing defaults. Each field can inherit independently. Zero line height keeps
the existing additive line-spacing rule. Zero maximum width stays unlimited.
Width remains in points. Typewriter scrolling stays global.

EditorSyntaxLayoutSettings writes one field only after validation. Reset removes
only known layout fields for the selected syntax. Malformed data rejects edits;
unknown fields and other syntaxes remain stored. EditorBody resolves the current
syntax before it passes layout to NativeEditor. Text mutation, native style
application and Undo rules do not change. The preference does not change shared
syntax records, library formats or backups.

The editor font catalog includes all faces returned by the installed font
families. Catalog construction is pure and accepts family members as input.
The view owns AppKit discovery. Stored PostScript names remain the identities;
labels do not determine selection. Common choices and unknown selected names
remain available through the existing picker rules.

## Syntax text input options

EditorTextInputPreferences owns four local options: continuous spelling,
grammar, smart quotes and smart dashes. Missing values keep Draftly's existing
native defaults. The resolver reads one syntax slot. Edits patch one known field;
reset retains unknown fields and other syntaxes. Invalid saved structures reject
writes. Editor Settings owns bindings and errors. EditorBody resolves the active
syntax and NativeEditor applies the configuration during creation and updates.
These changes do not call a text mutation or clear Undo. Automatic correction,
text replacement and Writing Tools are separate system options.

Autocorrection and Writing Tools use optional overrides in the same syntax
preference. A missing value means System Default. The coordinator captures the
native values once when it creates the text view. Reset or a syntax without an
override restores those values. Explicit Writing Tools enablement requests the
system default behavior; disablement requests none. This configures the editor,
not model installation, authorization or hardware availability.

## Monospace font selection

Editor Settings provides a local default monospace font and an optional override
per syntax. EditorSyntaxFontPreferences owns the syntax override and retains
unknown fields. EditorBody resolves the active choice. NativeEditor includes the
choice in its style identity. ThemeTextAttributes resolves the selected font for
syntax, theme and indentation metrics. A missing font falls back to the system
monospace font. The system default preserves the prior fixed-pitch behavior.
These settings do not change shared syntax records or backups.


## CI and release boundaries

`ci-change-scope.py` selects checks and verifies the combined result. Native
execution remains in its workflow job. Script and website tests use separate
jobs. Selection has no signing credentials and does not publish.

`release-changes.py` compares package inputs before native runner allocation.
Version and history validation remain in the existing preflight components.
Candidate creation, signed appcast preparation, GitHub staging, public asset
verification, and site promotion keep their existing separate commands. The
writer lock and operation journals cover the publication sequence. See
[CI/CD](ci-cd.md) and [release operations](releasing.md).


## Local connection metadata and authentication

AgentConnectionRegistry owns human-only connection management and credential
validation. A new configuration disables access. New grants default to selected
resources and draft reads for one hour. Grant replacement rotates authorization
identity while retaining the connection credential. The renewable choice is
stored; authentication does not silently extend an expired grant.

AgentConnectionFile stores metadata under a trusted application-owned parent.
It opens a private Agents directory by descriptor, checks ownership, modes and
extended ACLs, and rejects symbolic links, hard links and non-regular files.
The directory uses mode 0700 and files use 0600. Replacement compares the expected
bytes under a nonblocking lock, writes a private temporary file, synchronizes it,
renames it and synchronizes the directory. A failure after rename can return
outcome_unknown. This file is not part of the library, CloudKit or user backups.

The parent path is resolved physically before opening it with O_NOFOLLOW_ANY;
Foundation can abbreviate the system /private/var alias back to /var. The child
directory and files are not resolved through links. Extended ACL allow entries
fail closed; no ACL and deny-only ACLs remain valid. See Apple's
[secure file guidance](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/Articles/RaceConditions.html)
and [ACL implementation](https://github.com/apple-oss-distributions/Libc/blob/main/posix1e/acl_file.c).

The versioned metadata decoder rejects unsupported security fields rather than
dropping restrictions. Credentials are separate injected operations and never
appear in metadata or management results. Authentication uses a cryptographic
comparison and rechecks metadata before accepting the grant. This is internal
validation, not a connected transport or complete Keychain integration.

Management verifies stored bytes. Failed changes block the connection in this
process and notify authority listeners. Revocation persists denial before removing
the credential; a failed cleanup is reported separately. If storage and credential
cleanup both fail, report outcome_unknown and retain the runtime block. Do not
claim durable revocation in that case. Native Keychain restrictions for the signed
app/helper, pairing UI, listener ownership and per-request service checks remain
required before enabling access. Agent file handlers must also reject writes to
this control metadata and other control stores, even when a broader bookmark
contains them. A data-file grant must not become permission to edit grants.
This does not sandbox unrelated software already running as the same OS user.

## Protected approval state

AgentApprovalStore is an application-owned, in-memory state machine. It uses
existing request and schema validators, then binds one approval to the normalized
request, declared effect snapshot, grant identity and complete grant state, and
service epoch. A private, per-store HMAC key keeps request content out of stored
review metadata. Request text keeps its exact Unicode scalars and UTF-16 meaning.

Reviews expire after at most five minutes and no later than the grant. Elapsed
time also limits consent; backward or invalid clock readings invalidate it.
Consumption is synchronous on MainActor and changes approved to consumed once.
Decline, cancellation, expiry and invalidation remain distinct. The bounded store
can reclaim terminal reviews. It is not an operation journal or a mutation receipt.

Only trusted UI code can call the human-decision methods. No agent operation
registers them. The service must check interaction rules before requesting or
presenting a review. Future prompt-answer dispatch must not map an approval to an
ordinary agent-answerable prompt. The future UI must display the trusted prepared
operation and effects paired with the review fingerprint before allowing consent.

The service must supply current grants and lock state, call invalidation on lock
and revocation, and resolve effects again before consumption. A declared effect
snapshot is not authority for an undeclared service or destination. Authentication,
fine-grained native authorization, UI wiring and execution remain separate work.
Grant replacement creates a new grant identity; reading stored grants must keep
that identity stable rather than generate it again.

## Agent contract boundary — local stage 1

AgentContracts is a package-internal target. It contains serialized request and
result envelopes, JSON values, stable errors, the planned operation catalog,
and pure baseline grant evaluation. It depends on Foundation only. No app
route, socket, network listener, or MCP server uses it yet.

AgentTextShapes owns wire-level UTF-16 ranges and content chunks for draft reads,
patches and editor contracts. It checks integer bounds, overflow, text lengths
and continuation flags. Handlers must still check live content and scalar
boundaries. It does not own text replacement, selection or Undo.

AgentImportSource describes inline text, prepared transfers, bookmarked relative
paths, installation links and HTTPS inputs. Validation and exported JSON Schema
share exclusive input alternatives. The application must still authorize roots,
resolve symlinks, check transfer ownership and authorize every HTTP destination.
The contract target performs none of those effects.

AgentPreferenceRegistry is an explicit application-supplied field allowlist.
It defines typed addresses, defaults, schemas and approval requirements. It has
no storage reader or writer. Field and object-shape constructors use package
access. A separate consumer test target imports the module without @testable;
it checks the same construction boundary used by application code. Requests
cannot register fields; a missing registry returns unavailable.

AgentPreferenceCatalog builds the application metadata from existing option
enums and shared defaults. It does not read UserDefaults, invoke native services
or enable an endpoint. Its reviewed field IDs are frozen in application tests.
The Swift package and standalone Xcode app both link AgentContracts. The Xcode
target uses the same package identity for package-only declarations; this is a
build boundary, not an authorization mechanism. Typed readers, writers and native
bindings remain separate application work. When wiring Settings consumers, use the
[preference source inventory](research/agent-preference-inventory.md).

AgentEncodedPreferenceAccess prepares known syntax, Markdown and shortcut JSON
edits and reads their typed values. It uses existing option setters and command
conflict rules. Reset removes the selected known override and retains imported
additional fields. Its output is a prepared change, not a persistence receipt.
It has no storage or native-service dependency. Callers must still enforce grants,
versions, human approval and commit rules before applying it.

AgentDevicePreferenceAccess handles reviewed scalar keys from an explicit
preference domain. AgentListPreferenceAccess prepares the known list object and
its legacy mirror changes. AgentPreferenceReading gives these adapters a shared
typed result. None commits a mutation, registers an OS service or applies a
Workspace. The future command service owns those effects and their authorization.

AgentNativePreferenceAccess coordinates existing native preference models. It
reports native effect completion separately from the verified local reset and operation record.
Human approval is required for both settings; Spotlight changes require full
library scope. The adapter does not issue approvals. Its availability and failure
tests use injected service closures, not the real OS services.

AgentWorkspacePreferenceAccess checks capabilities and target scope before
resolving a default Workspace. AgentResourceScope.permits is the common membership
rule used by this adapter and baseline request policy. The command service must
still validate session lifetime, connection and library before calling adapters.

Syntax preference storage uses existing syntax names. Checking the resolved UUID
does not establish that a name is unique. The future handler must check aliases
and name collisions before a scoped change. This adapter does not grant access
to every definition with the same name.

The catalog records ownership, target shape, expected-version and human approval
requirements. The catalog contains no executable handlers. The application
service owns runtime availability. Execution and native effects
require an additional authorization result, even when the connection has the
baseline capability. Query decisions retain the explicit allowed scope for a
future handler to filter results. These decisions do not authenticate callers,
consume approvals, validate destinations, or apply edits.

The independent required-operation fixture prevents accidental scope removal.
The existing Swift inventory runner discovers the new test target without an
alternate test command. See the [agent operation inventory](research/agent-operation-inventory.md)
for current boundaries, reused characterization cases and remaining work.


### Agent read schemas

AgentReadSchemas defines parameters and results for the first eight discovery
and draft-read operations. AgentValueShape covers only the JSON Schema types
used by those contracts. Validation and schema export use the same field rules;
this is not a general-purpose JSON Schema interpreter. Defaults stay in request
values, not preferences or imported objects. Shape validation does not check
library scope or read data. Future handlers must perform those checks.


### Agent effect review

AgentStepEffectCatalog records potential effects for the existing Action step
types. Its result is either skipped, unsupported, or a requirement for runtime
checks. It never grants permission. Tests compare its keys with the executor's
supported types. The production contract target remains independent of Core;
only its tests import Core for this compatibility check.

Action execution still needs authority at each real bridge and native effect.
Preference and import mutations also need contextual checks after the baseline
grant check. This work changes only unexposed contracts, not existing user routes.


### Agent definition and execution contracts

AgentOperationSchemas composes the read, Action and execution schema families.
It checks target binding without reading the library or granting authority.
AgentActionSchemas follows the canonical model fields and preserves unknown
Action, step and presentation fields. Typed string maps stay distinct from
arbitrary imported JSON metadata. Mutation results expose receipts rather than
full definitions.

AgentExecutionSchemas checks state/report consistency and keeps polling expiry
separate from operation timeout. A terminal Action result must have a matching
report; an ambiguous effect does not become success. Ownership checks, durable
operation state, approvals and native execution remain application-service work.

### Authenticated agent reads

AgentCommandService accepts bounded serialized requests under an internal session
handle. Only credential authentication can create a handle. Requests cannot choose
one. Each dispatch checks the current registry, host library, grant identity,
capabilities, targets, expiry and lock state. It checks authority again before
returning data. A required injected host validator runs before transport start,
before and after credential authentication, and at both read-authority checks.
A lost owner clears sessions and cursors. Temporary lock contention denies only
that attempt. Normal startup still needs to supply the real lease validator.
Closing a session, explicit invalidation or observing a locked
screen removes its cursors. Unlocking does not restore that session.

The service owns an explicit set of eight read handlers. server.schemas reports
that set independently of the contract inventory. New catalog or schema entries
do not become executable by registration. Other operations return a real error.
No permission-management or approval method becomes an agent tool.

AgentDraftReading uses LibraryStore and the existing Workspace evaluator. It
filters authorized drafts before search, sorting, previews or counts. Summary
counts include authorized drafts in Trash. A revision read requires permission
for its parent draft; a revision ID alone does not grant that permission. Reads
never open an editor, save a draft, create a revision or update an access date.
Previews use the existing row presentation and are bounded to 1024 characters.
Search previews use its literal-query snippet behavior; compound-query snippets
can fall back to a normal preview, as in the existing row presentation.

AgentReadPages retains only resource IDs and order. Values remain current on
each page; deleted members are skipped and new members are not added. Signed,
opaque cursors bind the normalized query, targets, session and grant. They expire
after at most five minutes or the grant deadline. Monotonic time bounds their
lifetime. A replay reads the same membership position, not a cached content copy.
There are at most 64 snapshots and one million retained IDs per service.

Draft text uses UTF-16 offsets. A chunk cannot split a Unicode scalar. An offset
inside a surrogate pair or a length too small to return its first scalar is an
invalid request. An empty draft returns a valid empty terminal chunk. Read version
tokens are opaque per-service HMACs of the draft and a trusted editor generation.
Access dates are excluded. The future live-editor adapter must supply a generation
that changes for every pending edit. No mutation handler relies on these tokens yet.

The eight-MiB frame limit also applies to responses. Oversized full revision content
or metadata returns unavailable, without truncating its meaning or reporting
success. Use metadata-only revision reads when content is too large. Chunked
revision-content access remains a contract gap. Large schemas and JSON parsing
still need rate/latency review before transport activation.

This service is not connected to the installed app. The real Keychain adapter,
protected pairing/management UI, lock notifications, stable host library identity,
live-editor generation adapter, Unix socket and CLI/MCP remain pending. Tests use
an in-memory library and fake credentials. They do not prove signed-helper access,
real pairing, native approval, remote access or synchronization.

### Agent credential integration

AgentLocalSecurity depends only on AgentContracts and Apple Foundation, Security
and LocalAuthentication. It is package-internal. The helper can use it without
linking the application or Core Data. AgentCredentialKeychainAccess is the small
application adapter that maps its operations into AgentConnectionRegistry.

The system backend uses SecItem with the data protection keychain, an exact
access group, a connection UUID account, no synchronization and
WhenUnlockedThisDeviceOnly protection. A fresh noninteractive LAContext goes into
every query. Create never updates an existing item. Read never returns partial,
malformed or unexpected-size data. Remove is limited to that one connection item.
Only a genuine item-not-found status becomes absence or successful repeated
removal. Errors do not include raw native messages or credential bytes.

Before each call, AgentCredentialIdentity checks the current running code's Apple
signature, fixed team and role identifier. SecTask supplies current entitlements;
the adapter checks the exact group and rejects debug/injection permissions. The
helper cannot select the application role to bypass the running-code check.
These checks supplement the OS profile/access-group enforcement. They do not
sandbox software running as the same macOS user or deliberately signed by the
team's signing authority.

No existing entitlements, profiles or credentials change in this unit. It cannot
operate from the unsigned test runner or a QA identity. Real app/helper profiles
and signed replacement checks remain required before activation. The shared group
and helper wrapper choice are recorded in
[the credential decision](adr/0001-agent-device-keychain.md).

### Local agent socket boundary

AgentLocalTransport depends on AgentContracts and AgentLocalSecurity, not Core
Data or application models. AgentPrivateFilePolicy is the common owner/mode/ACL
rule for connection files and socket directories. AgentUnixListener owns one new
private temporary endpoint. Cleanup checks its captured inode; it does not search
for or delete other endpoints. Locator publication and one broker per library
still need a coordinator before normal app activation.

AgentUnixChannel uses length-prefixed bounded Data frames. Each connection has a
serial worker queue. Descriptor borrowing keeps close/cancellation from reusing a
file descriptor under pending I/O. Polling uses monotonic deadlines on those worker
queues; MainActor does not poll or block on the socket. The broker admits at most
eight clients. See [local development](agent-local-development.md) for limits.

AgentPeerIdentity validates kernel audit tokens with public SecCode APIs. Both
ends also check peer UID. This avoids trusting a claimed PID, name, path or
connection UUID as process identity. The production helper checks the app before
sending a credential; the production broker checks the helper before reading it.
Injected peer validators exist for isolated tests, not as client configuration.

AgentSocketBroker owns live application sessions. Hello authenticates a connection;
Welcome returns the host library ID, never the private session handle. Every
subsequent frame reaches AgentCommandService under that handle. The client binds
an omitted library ID to the authenticated host and checks response request IDs.
Framing or connection errors close the session. The JSON CLI returns error status
for setup/transport and operation errors; accepted work is not completion.

The executable imports contracts, local security, transport and AgentMCP. It has no
library writer, raw credential flag, global installation, background daemon or
remote socket. Signed helper wrapping/provisioning, pairing UI and normal
app startup are pending. No app route starts this broker in the installed app.


AgentMCP owns protocol presentation, not application authority. It uses the pinned
MCP SDK with a bounded pipe transport. AgentToolInput shares tool names and request
binding with the named CLI command. The application validates every request.
Exact JSON text avoids lossy protocol numbers. The app target does not link MCP.
See [ADR 0002](adr/0002-mcp-exact-bounded-stdio.md) for the limits and trade-offs.


AgentPairingCoordinator owns short-lived requests before a connection exists.
The caller supplies an untrusted client label after signed-helper verification.
Only human-interface methods prepare and approve a grant. Review IDs bind the
shown choices; exact target IDs are resolved again before persistence. Polling
returns lifecycle state and, after approval, a connection UUID, never a credential.
The registry remains the sole owner of persistent grants and credential creation.
A failed commit terminates the pairing attempt rather than retrying a write.
Clock, lock and host-ownership dependencies are explicit for headless tests.
Request and review admission require a live owner. Scope resolution is followed
by another ownership check before a review or credential is created. Host loss
invalidates pending and approved pairing results without deleting saved grants.
Temporary contention preserves the review and its original deadline. Runtime lock,
disable and shutdown events must invalidate pending decisions before activation.


The pairing introduction is a separate, bounded conversation on the same private
socket. AgentPairingHandshake owns wire shapes; AgentConnectionName owns the
shared name rule. AgentPairingClient owns one channel and caches terminal pairing
history. It cannot read or create credentials. The broker verifies process identity
before choosing either the normal credential route or the pairing route. Only
poll and cancel controls exist in the latter route. Human decisions remain in
AgentPairingCoordinator. Pending waits reserve at most two client slots.
The async pairing session does not retain the broker; destruction closes its
channels and cancels pending work. Normal authenticated requests still recheck
current grants, so a pairing result cannot substitute for live authorization.


AgentConnectionsSettingsModel coordinates human commands, not transport startup.
It uses the same registry/library binding as its pairing coordinator. The view
owns bindings and presentation; AgentGrantEditingCopy retains unsaved choices.
Existing edits check the grant ID that was reviewed. Pairing copy changes discard
the prepared review. The registry remains the source for live, paused, revoked
and blocked display states. Resource labels include stable IDs and do not grant
access by title or by future Workspace membership.

AppController can receive this Settings model through explicit host setup.
Settings adds the Agents tab only when it exists. Normal startup still supplies
none until signed helper, Keychain, locator and lifecycle integration are ready.
The separate Tools/AgentSettingsPreview host uses memory fixtures and never opens
an agent endpoint. Its build script does not launch it; manual Computer Use is a
separate step. See [connection UI](agent-connections-ui.md) for verified cases.


AgentStateDirectory owns bounded local metadata I/O and file-lock lifetimes.
AgentPrivateFilePolicy remains the common owner, mode, ACL and link rule.
AgentConnectionFile selects the existing connection filenames and budget; it no
longer contains another atomic-write implementation. A held AgentStateFileLock
keeps its descriptor and directory alive. Release leaves the lock inode in place.
Long-lived host owners can also validate the current path and inode before work.


AgentLibraryLocation reads the loaded SQLite store's UUID and retains a read-only
file descriptor. It uses the filesystem path, volume and file identity to check
that the loaded store still names that instance. It does not change Core Data
metadata, Note or the database. In-memory or ambiguous stores are not adopted by
this persistent host path.

AgentHostLease owns the stable local library ID and both location and physical
file locks. Its private identity record lives in Agents beside SQLite, outside
record backups and synchronization. Corrupt or foreign records fail without
repair. Copy or replacement creates a different binding. Release keeps lock
inodes in place. Ownership validation is required before every admitted request;
a non-contention failure remains invalid until a new host epoch. The app factory
and broker still need to consume this lease before normal activation. See
[the binding decision](adr/0003-local-agent-library-binding.md).


AgentLocalHost assembles one loaded library, AgentHostLease, private connection
file, registry, command service, pairing coordinator and optional socket broker.
It derives the library ID from the lease. Both admission paths and every metadata
access use that same owner. Application identity must pass before state creation;
tests inject an isolated backend explicitly.

Construction does not listen or write an enabled preference. Human Settings
commands can enable the broker. Explicit resume rechecks ownership, application
identity and lock state. Suspension closes the broker and invalidates sessions
and pending reviews. Close does that before releasing the lease. A discarded host
has a MainActor-isolated deinitializer as a fallback; shutdown and library changes
must call close explicitly rather than depend on deinitializer timing. See
[Swift SE-0371](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0371-isolated-synchronous-deinit.md).

A failed first enable compensates its new enabled preference. If that write also
fails, it reports outcomeUnknown. Unreadable metadata is not repaired. Temporary
ownership contention does not tear down a live broker. Normal AppController
startup, locator publication, editor/lock adapters and signed helper provisioning
remain separate, unfinished wiring; the assembly alone does not activate access.
