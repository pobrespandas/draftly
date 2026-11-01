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
| workspaces.query | Workspace + LibraryStore | workspacesRead | workspace | none |
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
