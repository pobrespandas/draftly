# Agent operation inventory

Status: contracts only. No endpoint or handler is enabled.

Snapshot date: 31 October 2026. The table records the first implementation unit.

The authoritative operation names, permission families, resource target rules,
and expected-version/approval requirements are in
[AgentOperationCatalog](../../Sources/AgentContracts/AgentOperationCatalog.swift).
The first contract tests validate message safety and baseline grants. Operation
parameter/result schemas, native destination grants, and per-member handler tests
remain required before execution. This inventory is not evidence of functionality.

| Operation | Existing owner or planned boundary | Capability names in code | Targets | Additional requirements |
| --- | --- | --- | --- | --- |
| server.status | AgentCommandService | connection only | none | none |
| server.capabilities | AgentCommandService | connection only | none | none |
| server.schemas | AgentCommandService | connection only | none | none |
| library.summary | LibraryStore | draftsRead | none | none |
| drafts.list | LibraryStore + DraftCommands | draftsRead | none | none |
| drafts.search | LibraryStore + DraftCommands | draftsRead | none | none |
| drafts.get | LibraryStore + DraftCommands | draftsRead | draft | none |
| drafts.versions | LibraryStore + DraftCommands | draftsRead | draft | none |
| drafts.create | LibraryStore + DraftCommands | draftsWrite | none | none |
| drafts.update | LibraryStore + DraftCommands | draftsWrite | draft | version |
| drafts.patch | LibraryStore + DraftCommands | draftsWrite | draft | version |
| drafts.duplicate | LibraryStore + DraftCommands | draftsWrite | draft | version |
| drafts.merge | LibraryStore + DraftCommands | draftsWrite | drafts | version |
| drafts.archive | LibraryStore + DraftCommands | draftsWrite | drafts | version |
| drafts.trash | LibraryStore + DraftCommands | draftsWrite | drafts | version |
| drafts.restore | LibraryStore + DraftCommands | draftsWrite | drafts | version |
| drafts.flag | LibraryStore + DraftCommands | draftsWrite | drafts | version |
| drafts.tags | LibraryStore + DraftCommands | draftsWrite | drafts | version |
| drafts.syntax | LibraryStore + DraftCommands | draftsWrite | drafts | version |
| drafts.restoreVersion | LibraryStore + DraftCommands | draftsWrite | draftAndRevision | version |
| drafts.purge | LibraryStore | draftsWrite,destructiveRequest | drafts | version,human |
| editor.windows | EditorSession + WindowModel | editorRead,draftsRead | none | none |
| editor.get | EditorSession + WindowModel | editorRead,draftsRead | window | none |
| editor.find | EditorSession + WindowModel | editorRead,draftsRead | window | none |
| editor.markers | EditorSession + WindowModel | editorRead,draftsRead | window | none |
| editor.links | EditorSession + WindowModel | editorRead,draftsRead | window | none |
| editor.replaceRange | EditorSession + WindowModel | editorWrite,draftsWrite | window | version |
| editor.setSelection | EditorSession + WindowModel | editorWrite,draftsWrite | window | version |
| editor.replaceAll | EditorSession + WindowModel | editorWrite,draftsWrite | window | version |
| editor.tasks | EditorSession + WindowModel | editorWrite,draftsWrite | window | version |
| editor.undo | EditorSession + WindowModel | editorWrite,draftsWrite | window | version |
| editor.redo | EditorSession + WindowModel | editorWrite,draftsWrite | window | version |
| editor.open | WindowModel | presentUI,draftsRead | draft | none |
| editor.navigate | WindowModel | presentUI,draftsRead | window | version |
| editor.preview | WindowModel | presentUI,draftsRead | window | none |
| actions.list | ActionCatalog + ActionEditingCopy | actionsRead | none | none |
| actions.get | ActionCatalog + ActionEditingCopy | actionsRead | action | none |
| actions.stepSchemas | ActionCatalog + ActionEditingCopy | actionsRead | none | none |
| actions.groups | ActionCatalog + ActionEditingCopy | actionsRead | none | none |
| actions.create | LibraryStore + ActionEditingCopy | actionsManage | none | none |
| actions.update | LibraryStore + ActionEditingCopy | actionsManage | action | version |
| actions.duplicate | LibraryStore + ActionEditingCopy | actionsManage | action | version |
| actions.move | LibraryStore + ActionEditingCopy | actionsManage | actionAndGroup | version |
| actions.reorder | LibraryStore + ActionEditingCopy | actionsManage | actions | version |
| actions.validateShortcut | LibraryStore + ActionEditingCopy | actionsManage | none | none |
| actions.delete | LibraryStore | actionsManage,destructiveRequest | action | version,human |
| actionGroups.get | LibraryStore + ActionCatalog | actionsRead | actionGroup | none |
| actionGroups.create | LibraryStore + ActionCatalog | actionsManage | none | none |
| actionGroups.update | LibraryStore + ActionCatalog | actionsManage | actionGroup | version |
| actionGroups.duplicate | LibraryStore + ActionCatalog | actionsManage | actionGroup | version |
| actionGroups.reorder | LibraryStore + ActionCatalog | actionsManage | actionGroups | version |
| actionGroups.delete | LibraryStore | actionsManage,destructiveRequest | actionGroup | version,human |
| actions.run | AutomationActionExecution + ActionRunner | actionsRun,draftsRead | actionAndDraft | version |
| operations.get | AgentOperationRegistry | connection only | operation | none |
| operations.wait | AgentOperationRegistry | connection only | operation | none |
| operations.cancel | AgentOperationRegistry | connection only | operation | none |
| operations.answerPrompt | AgentOperationRegistry | connection only | operation | version |
| workspaces.list | Workspace + LibraryStore | workspacesRead | none | none |
| workspaces.get | Workspace + LibraryStore | workspacesRead | workspace | none |
| workspaces.query | Workspace + LibraryStore | workspacesRead,draftsRead | workspace | none |
| workspaces.create | LibraryStore | workspacesManage | none | none |
| workspaces.update | LibraryStore | workspacesManage | workspace | version |
| workspaces.duplicate | LibraryStore | workspacesManage | workspace | version |
| workspaces.reorder | LibraryStore | workspacesManage | workspaces | version |
| workspaces.delete | LibraryStore | workspacesManage,destructiveRequest | workspace | version,human |
| workspaces.apply | WindowModel.prepareWorkspace | workspacesApply,presentUI | workspaceAndWindow | version |
| themes.list | InstalledThemeCommands | appearanceRead | none | none |
| themes.get | InstalledThemeCommands | appearanceRead | theme | none |
| themes.export | InstalledThemeCommands | appearanceRead | theme | none |
| themes.create | InstalledThemeCommands | appearanceManage | none | none |
| themes.update | InstalledThemeCommands | appearanceManage | theme | version |
| themes.duplicate | InstalledThemeCommands | appearanceManage | theme | version |
| themes.select | InstalledThemeCommands | appearanceManage | theme | version |
| themes.reload | InstalledThemeCommands | appearanceManage | theme | version |
| themes.install | InstalledThemeCommands | appearanceManage,filesRead | none | none |
| themes.delete | InstalledThemeCommands | appearanceManage,destructiveRequest | theme | version,human |
| syntaxes.list | SyntaxDefinition + ScriptSyntax | appearanceRead | none | none |
| syntaxes.get | SyntaxDefinition + ScriptSyntax | appearanceRead | syntax | none |
| syntaxes.export | SyntaxDefinition + ScriptSyntax | appearanceRead | syntax | none |
| syntaxes.install | SyntaxImportPreparation + ApplicationURLRouter | appearanceManage,filesRead | none | none |
| syntaxes.replace | SyntaxImportPreparation + ApplicationURLRouter | appearanceManage,filesRead | syntax | version |
| syntaxes.delete | SyntaxImportPreparation + ApplicationURLRouter | appearanceManage,destructiveRequest | syntax | version,human |
| preferences.schema | Typed preference commands | preferencesRead | none | none |
| preferences.get | Typed preference commands | preferencesRead | none | none |
| preferences.update | Typed preference commands | preferencesWrite | none | version |
| preferences.reset | Typed preference commands | preferencesWrite | none | version |
| bookmarks.list | BookmarkPreferences | preferencesRead | none | none |
| bookmarks.requestAdd | BookmarkPreferences | preferencesWrite | none | human |
| bookmarks.forget | BookmarkPreferences | preferencesWrite | bookmark | version,human |
| imports.validate | DraftFileCommands + importers | filesRead,draftsWrite | none | none |
| imports.preview | DraftFileCommands + importers | filesRead,draftsWrite | none | none |
| imports.commit | DraftFileCommands + importers | filesRead,draftsWrite | none | version |
| exports.drafts | DraftFileCommands | draftsRead,filesWrite | drafts | none |
| backups.export | LibraryStore.backupData | backupsExport,draftsRead,actionsRead,workspacesRead,appearanceRead,filesWrite | none | library |
| backups.validate | LibraryStore.restore | backupsRestore,filesRead | none | library |
| backups.previewRestore | LibraryStore.restore | backupsRestore,filesRead | none | library |
| backups.requestRestore | LibraryStore.restore | backupsRestore,filesRead | none | library,human,version |
| transfers.beginImport | AgentTransferStore | filesRead | none | none |
| transfers.appendChunk | AgentTransferStore | filesRead | operation | none |
| transfers.finishImport | AgentTransferStore | filesRead | operation | none |
| transfers.readChunk | AgentTransferStore | filesWrite | operation | none |
| transfers.cancel | AgentTransferStore | filesWrite | operation | none |
| activity.list | AgentActivityStore | connection only | none | none |
| activity.changes | AgentActivityStore | connection only | none | none |
| native.http | NativeActionHost | nativeUse | none | human |
| native.xmlrpc | NativeActionHost | nativeUse | none | human |
| native.fileRead | NativeActionHost | nativeUse | none | human |
| native.fileWrite | NativeActionHost | nativeUse | none | human |
| native.clipboardRead | NativeActionHost | nativeUse | none | human |
| native.clipboardWrite | NativeActionHost | nativeUse | none | human |
| native.htmlToMarkdown | NativeActionHost | nativeUse | none | human |
| native.htmlPreview | NativeActionHost | nativeUse | none | human |
| native.mail | NativeActionHost | nativeUse | none | human |
| native.messages | NativeActionHost | nativeUse | none | human |
| native.calendar | NativeActionHost | nativeUse | none | human |
| native.reminders | NativeActionHost | nativeUse | none | human |
| native.dictate | NativeActionHost | nativeUse | none | human |
| native.transcribe | NativeActionHost | nativeUse | none | human |
| native.scanDocument | NativeActionHost | nativeUse | none | human |
| native.location | NativeActionHost | nativeUse | none | human |
| native.models | NativeActionHost | nativeUse | none | human |
| native.share | NativeActionHost | nativeUse | none | human |
| native.print | NativeActionHost | nativeUse | none | human |
| native.speak | NativeActionHost | nativeUse | none | human |
| native.openURL | NativeActionHost | nativeUse | none | human |
| native.shell | NativeAutomationAdapter | nativeUse,scriptsUnrestricted | none | human |
| native.appleScript | NativeAutomationAdapter | nativeUse,scriptsUnrestricted | none | human |
| native.shortcut | NativeAutomationAdapter | nativeUse,scriptsUnrestricted | none | human |


`version` requires an expected-version token. `human` requires a bound one-use
approval. `library` requires an explicit whole-library grant. Other target kinds
are always checked against the connection's allowed resources. Query handlers
must filter their results using the returned scope; an empty target list does
not authorize reading the whole library. Native grants and operation/transfer
ownership need additional validation in their future handlers.

Read/write capability names above are Swift case names. Their persisted names
are the dotted raw values in AgentCapability. Update this table when the catalog
changes; the test inventory freezes the required operation IDs separately so
removing an entry cannot silently narrow the scope.

## Existing characterization evidence reused

These cases characterize existing rules. They do not prove agent transport or
permission enforcement in the app. Keep their names and coverage.

| Rule | Existing case |
| --- | --- |
| Reads do not record access | AccessDateTests.queriesSortUnknownDatesLastAndDoNotRecordAccess |
| Unknown access dates survive old backups | AccessDateTests.oldNotesKeepUnknownDatesAndBackupsPreserveKnownDates |
| Save failure does not leak deletion | LibraryDeletionTransactionTests.failedDeletionCannotLeakIntoALaterSaveAndRetryPersists |
| Backup conflicts retain both drafts | LibraryTests.backupRoundTripAndConflictPreservesBothNotes |
| Cancel does not save Action edits | ActionEditingCopyTests.editsAndDiscardDoNotWriteTheLibraryAndSaveUsesTheSameActionIdentity |
| Busy execution does not flush pending text | AutomationEditorContextTests.busyReservationIsRejectedBeforeAnyPendingDraftIsSaved |
| Pending owner edits survive a clean duplicate editor | AutomationEditorContextTests.cleanDuplicateEditorCannotOverwritePendingOwnerText |
| Catalog order and visibility are shared | ActionCatalogTests.actionOrderUsesGroupPriorityThenExplicitOrDefaultPositionThenNameAndUUID |

## Remaining stage 1 work

- Bind each parameter/result schema to existing model and step definitions.
- Map all 25 step types and all script/native effects to exact grant checks.
- Add missing characterization cases only where existing cases do not cover the rule.
- Add real executors in later stages. The static catalog is not an execution registry.

## Existing Action step effect boundaries

This is a source-review map, not runtime authorization. Templates can request
additional draft, clipboard, file or network data. Check those reads at runtime
for every step, not only for scripts. Unknown enabled steps fail explicitly;
disabled imported steps remain preserved and are not executed.

| Existing step | Effects that the future agent runner must check |
| --- | --- |
| script | Every bridge query, mutation, native request, timer and included/queued execution. |
| clipboard | Clipboard read for append/prepend and clipboard write. |
| url | External URL launch and destination. |
| callbackUrl | External launch, callbacks, final outcome and destination. |
| insertText | Editor mutation, version, selection, persistence and Undo. |
| createDraft | Library create, tags/folder/syntax and optional editor opening. |
| file | Resolved file root, path, write mode and bytes written. |
| share | Native sharing presentation and selected destination. |
| runShortcut | Unrestricted automation approval and external process result. |
| runAppleScript | Unrestricted automation approval and native execution. |
| htmlpreview | Presentation, loaded resources, interactive callbacks and returned data. |
| configurationKey | Initial configuration values and human input where required. |
| includeAction | Included Action identity/version, cycle checks and inherited grant. |
| reminder | Reminders permission, destination and created data. |
| event | Calendar permission, destination and created data. |
| prompt | Human/agent answer policy, secure input and cancellation. |
| defineTemplateTag | Execution-local template data; subsequent template reads still need checks. |
| configureWindow | Explicit window, presentation authority and unsaved state. |
| mail | Recipient/content approval, native permission and send/composition result. |
| message | Recipient/content approval, native permission and send/composition result. |
| listInReminders | Reminders list destination and each created item. |
| export | File data, native save destination and file authority. |
| openIn | File creation and external application launch. |
| print | Native print presentation and output destination. |
| speak | Audio presentation and cancellation; never start in background tests. |

All execution routes also need checks for final tags, flag and folder effects.
Review source in ActionStepExecutor, ActionAsyncExecution, ActionScriptCommands
and native adapters. A static step classification cannot authorize dynamic
script behavior. All new agent execution handlers remain unavailable.

## Discovery and read schema increment

Eight operations now have parameter and result shapes: server.status,
server.capabilities, server.schemas, library.summary, drafts.list, drafts.search,
drafts.get and drafts.versions. AgentReadSchemas owns these definitions and
exports JSON Schema from the same rules used for validation. This does not add
an executor or make any operation available.

Query defaults are request-local: all non-trash drafts, modified order, descending,
50 results. Explicit folder=trash uses the existing Workspace meaning. Search
requires a nonempty query; list allows an empty query. Folder and sort raw names
match NoteFolder and NoteSort. Advanced date filters and Workspace evaluation
remain handler/schema work; unknown parameters fail instead of being ignored.

List results contain summaries, never full content. library.summary returns
only draftCount, not counts of Actions or other library objects. The count
means authorized saved drafts, including those in Trash. Full-content
reads use UTF-16 offset and length, with a maximum chunk of 65,536 code units.
Chunk results must match the text length, total length and hasMore state. A future
handler must also verify the requested target, range boundaries and grant scope.
Dates require UTC and UUID fields require valid identities. Pagination defaults
and integer bounds are exported; string lengths use Unicode code points.

At this checkpoint, no schema existed for the other 119 operations. Later
increments are recorded below. All catalog entries remain planned without a handler. Native destination checks, authentication, snapshots,
cursors and library/editor reads are not implemented by these shapes.

Sources: JSON Schema official [object reference](https://json-schema.org/understanding-json-schema/reference/object)
and [string reference](https://json-schema.org/understanding-json-schema/reference/string),
consulted 31 October 2026. Format annotations require format checking in an external
validator; the Swift validator checks UUID and UTC date values directly.

## Effect classification increment

AgentStepEffectCatalog now describes potential effects for all 25 existing step
types. A test compares its keys with DraftAction.supportedSteps. Enabled known
steps return requiresRuntimeChecks; enabled unknown steps return unsupported;
disabled steps return skipped. No result authorizes execution.

The classification is conservative. A clipboard step can potentially read and
write; a create step can potentially open a window. Actual parameters and
runtime calls determine which grants are needed. Do not demand every potential
capability in advance or use the classification to bypass runtime checks.
Templates, initial configuration, final disposition and queued Actions have
separate review requirements. Script runtime authority remains unfinished.

Baseline permission evaluation also returns needsEffectAuthorization for
preferences.update, preferences.reset and imports.commit. A general write grant
cannot decide which setting or imported resource is safe. Field allowlists,
resource classification and any required human approval remain handler work.
No existing execution or preference route was changed.

## Action definitions and lifecycle increment

AgentActionSchemas adds 18 schemas for Action definitions, groups and execution
requests. AgentExecutionSchemas adds four schemas for inspect/wait/cancel/prompt
reply operations. Together with the original eight reads, 30 operations now have
schemas; none has an executor or an enabled endpoint.

Added actionGroups.get to close an inventory gap: reading an entire group,
including imported metadata, needs an explicit targeted read. The catalog and
independent required-operation fixture now contain 128 entries. This is an
inventory expansion, not a compatibility percentage. All 98 remaining operations
still need schemas.

Definitions use DraftAction's canonical Codable format, not the external
.draftsAction import format. Steps keep their own IDs, include destinations in
values, optional enabled state and unknown fields. values/configuredValues and
scriptMetadata remain string maps. Imported presentation values and unknown
fields are retained, including unsupported values that must not be normalized
just to edit another field. Creating a definition does not fill absent nested
options with inspector defaults. New definitions can omit constructor fields;
future handlers must obtain their defaults from the existing models.

Update payload IDs must match their typed targets. Reorder payloads must name
every target exactly once. Mutation results are identity/version receipts, not
readable Action definitions. A management grant therefore does not implicitly
return scripts or unknown metadata. Reading definitions remains a separate
capability. Validation does not save or execute the definition.

Lifecycle replies separate wait expiration from execution timeout, preserve
completed-effect metadata, and reject success reports in pending/ambiguous
states. Cancel cannot claim acceptance after a successful committed result.
Failure reports cannot contain success parameters. execution_error represents
an unclassified Action execution failure; storage_error remains distinct.
Request-bound result validation checks operation/resource identities. A busy
termination reason must use the busy error code. Other failures cannot use that
code. A focused regression detected a busy report labelled storage_error.

Prompt answers require operation, step and prompt identities and a version
check. They do not grant permissions. A future handler must validate fields
against the live prompt, reject secure fields, check ownership and consume the
proper token. No operation registry, prompt UI or permission grant is implemented
by these schemas.

## UTC validation regression

A focused test demonstrated that ISO8601DateFormatter accepted 31 February and
trailing text after a timestamp. AgentValueShape now checks the exact UTC syntax
and verifies calendar components without rounding the fractional second.
The exported schema uses the same syntax pattern. The regression fails before
the fix and passes afterward; valid leap days and high fractional precision
remain accepted. This is a separate contract fix, not a change to existing app
or scripting date behavior.


## Workspace contracts

Nine Workspace operations now have schemas. Canonical definitions match the
existing Workspace Codable format. Updates preserve list options, optional
fields and string metadata, including the existing API JSON string. Unknown
canonical top-level fields fail explicitly because the current model cannot
retain them. Unknown data inside scriptMetadata stays intact. Imported integers
are not restricted to a view's picker range. Creation does not fill defaults;
the future application handler must use WorkspaceDefaults.

Queries accept pagination only. They use the saved Workspace evaluator, not a
second query grammar or a replacement filter from the request. Their result
schema is the same draft page used by drafts.list. Queries require both
workspacesRead and draftsRead; a Workspace is not an access-control container.
The handler must still filter each draft by the connection's resource scope.
Applying a Workspace needs effect review before theme/file references can load.
The permission regression failed before these catalog changes.

Updates bind the definition ID to the target. Reorders cover all targets once.
Apply results bind both the window and Workspace IDs. Write receipts contain
identities and versions, not readable definitions. Action and Workspace contracts
share these receipt and target-binding rules. There are now 39 schemas for 128
planned operations. None has an executor. Persistence, cancellation, invalid
reference handling, editor preservation and actual window application remain
runtime acceptance work; schema tests do not prove these effects.
