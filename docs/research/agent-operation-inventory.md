# Agent operation inventory

This table matches the 137 required operation names and records the owner,
capabilities, target kinds and gates from
[AgentOperationCatalog](../../Sources/AgentContracts/AgentOperationCatalog.swift).
`AgentOperationSchemas` provides a schema for each row. The complete-host
availability test checks all 137 names against the handler sets and schema
registry. A configured host can omit tools based on its connected handlers,
the connection's grant and the state of the app.

Installed evidence is separate from source coverage. See
[agents and AI readiness](../agents-ai-readiness.md#operation-coverage)
and the acceptance table below.

| Operation | Catalog owner | Capability names in code | Targets | Additional requirements |
| --- | --- | --- | --- | --- |
| server.status | AgentCommandService | connection only | none | none |
| server.capabilities | AgentCommandService | connection only | none | none |
| server.schemas | AgentCommandService | connection only | none | none |
| mutations.prepare | AgentCommandService | connection only | none | none |
| library.summary | LibraryStore | draftsRead | none | none |
| drafts.list | LibraryStore + DraftCommands | draftsRead | none | none |
| drafts.search | LibraryStore + DraftCommands | draftsRead | none | none |
| drafts.get | LibraryStore + DraftCommands | draftsRead | draft | none |
| drafts.versions | LibraryStore + DraftCommands | draftsRead | draft | none |
| drafts.create | LibraryStore + DraftCommands | draftsWrite | none | library |
| drafts.update | LibraryStore + DraftCommands | draftsWrite | draft | version |
| drafts.patch | LibraryStore + DraftCommands | draftsWrite | draft | version |
| drafts.duplicate | LibraryStore + DraftCommands | draftsWrite | draft | version, library |
| drafts.merge | LibraryStore + DraftCommands | draftsWrite | one or more draft | version, library |
| drafts.archive | LibraryStore + DraftCommands | draftsWrite | one or more draft | version |
| drafts.trash | LibraryStore + DraftCommands | draftsWrite | one or more draft | version |
| drafts.restore | LibraryStore + DraftCommands | draftsWrite | one or more draft | version |
| drafts.flag | LibraryStore + DraftCommands | draftsWrite | one or more draft | version |
| drafts.tags | LibraryStore + DraftCommands | draftsWrite | one or more draft | version |
| drafts.syntax | LibraryStore + DraftCommands | draftsWrite | one or more draft | version |
| drafts.restoreVersion | LibraryStore + DraftCommands | draftsWrite | draft + revision | version |
| drafts.purge | LibraryStore | draftsWrite, destructiveRequest | one or more draft | version, human |
| editor.windows | EditorSession + WindowModel | editorRead, draftsRead | none | none |
| editor.get | EditorSession + WindowModel | editorRead, draftsRead | window | none |
| editor.find | EditorSession + WindowModel | editorRead, draftsRead | window | none |
| editor.markers | EditorSession + WindowModel | editorRead, draftsRead | window | none |
| editor.links | EditorSession + WindowModel | editorRead, draftsRead | window | none |
| editor.replaceRange | EditorSession + WindowModel | editorWrite, draftsWrite | window | version |
| editor.setSelection | EditorSession + WindowModel | editorWrite, draftsWrite | window | version |
| editor.replaceAll | EditorSession + WindowModel | editorWrite, draftsWrite | window | version |
| editor.listTasks | SyntaxDefinition + EditorSession | editorRead, draftsRead | window | none |
| editor.tasks | EditorSession + WindowModel | editorWrite, draftsWrite | window | version |
| editor.undo | EditorSession + WindowModel | editorWrite, draftsWrite | window | version |
| editor.redo | EditorSession + WindowModel | editorWrite, draftsWrite | window | version |
| editor.open | WindowModel | presentUI, draftsRead | draft | none |
| editor.navigate | WindowModel | presentUI, draftsRead | window | version |
| editor.preview | WindowModel | presentUI, draftsRead | window | none |
| actions.list | ActionCatalog + ActionEditingCopy | actionsRead | none | none |
| actions.get | ActionCatalog + ActionEditingCopy | actionsRead | action | none |
| actions.stepSchemas | ActionCatalog + ActionEditingCopy | actionsRead | none | none |
| actions.groups | ActionCatalog + ActionEditingCopy | actionsRead | none | none |
| actions.create | LibraryStore + ActionEditingCopy | actionsManage | none | library |
| actions.update | LibraryStore + ActionEditingCopy | actionsManage | action | version |
| actions.duplicate | LibraryStore + ActionEditingCopy | actionsManage | action | version, library |
| actions.move | LibraryStore + ActionEditingCopy | actionsManage | action + actionGroup | version |
| actions.reorder | LibraryStore + ActionEditingCopy | actionsManage | one or more action | version, library |
| actions.validateShortcut | LibraryStore + ActionEditingCopy | actionsManage | none | library |
| actions.delete | LibraryStore | actionsManage, destructiveRequest | action | version, human |
| actionGroups.get | LibraryStore + ActionCatalog | actionsRead | actionGroup | none |
| actionGroups.create | LibraryStore + ActionCatalog | actionsManage | none | library |
| actionGroups.update | LibraryStore + ActionCatalog | actionsManage | actionGroup | version, library |
| actionGroups.duplicate | LibraryStore + ActionCatalog | actionsManage | actionGroup | version, library |
| actionGroups.reorder | LibraryStore + ActionCatalog | actionsManage | one or more actionGroup | version, library |
| actionGroups.delete | LibraryStore | actionsManage, destructiveRequest | actionGroup | version, human |
| actions.run | AutomationActionExecution + ActionRunner | actionsRun, draftsRead | action + draft | version |
| operations.get | AgentOperationRegistry | connection only | operation | none |
| operations.wait | AgentOperationRegistry | connection only | operation | none |
| operations.cancel | AgentOperationRegistry | connection only | operation | none |
| operations.answerPrompt | AgentOperationRegistry | connection only | operation | version |
| workspaces.list | Workspace + LibraryStore | workspacesRead | none | none |
| workspaces.get | Workspace + LibraryStore | workspacesRead | workspace | none |
| workspaces.query | Workspace + LibraryStore | workspacesRead, draftsRead | workspace | none |
| workspaces.create | LibraryStore | workspacesManage | none | library |
| workspaces.update | LibraryStore | workspacesManage | workspace | version |
| workspaces.duplicate | LibraryStore | workspacesManage | workspace | version, library |
| workspaces.reorder | LibraryStore | workspacesManage | one or more workspace | version, library |
| workspaces.delete | LibraryStore | workspacesManage, destructiveRequest | workspace | version, human |
| workspaces.apply | WindowModel.prepareWorkspace | workspacesApply, presentUI | workspace + window | version |
| themes.list | InstalledThemeCommands | appearanceRead | none | none |
| themes.get | InstalledThemeCommands | appearanceRead | theme | none |
| themes.export | InstalledThemeCommands | appearanceRead | theme | none |
| themes.create | InstalledThemeCommands | appearanceManage | none | library |
| themes.update | InstalledThemeCommands | appearanceManage | theme | version |
| themes.duplicate | InstalledThemeCommands | appearanceManage | theme | version, library |
| themes.select | InstalledThemeCommands | appearanceManage | theme | version |
| themes.selection | EditorThemePreferences | appearanceRead | none | none |
| themes.replace | ThemeFileAccess + InstalledThemeCommands | appearanceManage, filesRead | theme | version |
| themes.selectBuiltIn | EditorThemePreferences + ThemeCatalog | appearanceManage | none | version |
| themes.exportBuiltIn | ThemeInstallation | appearanceRead | none | none |
| themes.reload | InstalledThemeCommands | appearanceManage, filesRead | theme | version |
| themes.install | InstalledThemeCommands | appearanceManage, filesRead | none | none |
| themes.delete | InstalledThemeCommands | appearanceManage, destructiveRequest | theme | version, human |
| syntaxes.list | SyntaxDefinition + ScriptSyntax | appearanceRead | none | none |
| syntaxes.get | SyntaxDefinition + ScriptSyntax | appearanceRead | syntax | none |
| syntaxes.getBuiltIn | ScriptSyntax | appearanceRead | none | none |
| syntaxes.exportBuiltIn | ScriptSyntax | appearanceRead | none | none |
| syntaxes.reload | SyntaxFileAccess | appearanceManage, filesRead | syntax | version |
| syntaxes.export | SyntaxDefinition + ScriptSyntax | appearanceRead | syntax | none |
| syntaxes.install | SyntaxImportPreparation + ApplicationURLRouter | appearanceManage, filesRead | none | none |
| syntaxes.replace | SyntaxImportPreparation + ApplicationURLRouter | appearanceManage, filesRead | syntax | version |
| syntaxes.delete | SyntaxImportPreparation + ApplicationURLRouter | appearanceManage, destructiveRequest | syntax | version, human |
| preferences.schema | Typed preference commands | preferencesRead | none | none |
| preferences.get | Typed preference commands | preferencesRead | none | none |
| preferences.update | Typed preference commands | preferencesWrite | none | version |
| preferences.reset | Typed preference commands | preferencesWrite | none | version |
| bookmarks.list | BookmarkPreferences | preferencesRead | none | none |
| bookmarks.requestAdd | BookmarkPreferences | preferencesWrite | none | human |
| bookmarks.forget | BookmarkPreferences | preferencesWrite | bookmark | version, human |
| imports.validate | DraftFileCommands + importers | filesRead, draftsWrite | none | none |
| imports.preview | DraftFileCommands + importers | filesRead, draftsWrite | none | library |
| imports.commit | DraftFileCommands + importers | filesRead, draftsWrite | none | version, library, human |
| exports.drafts | DraftFileCommands | draftsRead, filesWrite | one or more draft | none |
| backups.export | LibraryStore.backupData | backupsExport, draftsRead, actionsRead, workspacesRead, appearanceRead, filesWrite | none | library |
| backups.validate | LibraryStore.restore | backupsRestore, filesRead | none | library |
| backups.previewRestore | LibraryStore.restore | backupsRestore, filesRead | none | library |
| backups.requestRestore | LibraryStore.restore | backupsRestore, filesRead | none | version, library, human |
| transfers.beginImport | AgentTransferStore | filesRead | none | none |
| transfers.appendChunk | AgentTransferStore | filesRead | operation | none |
| transfers.finishImport | AgentTransferStore | filesRead | operation | none |
| transfers.readChunk | AgentTransferStore | filesWrite | operation | none |
| transfers.cancel | AgentTransferStore | filesRead or filesWrite | operation | none |
| activity.list | AgentActivityStore | connection only | none | none |
| activity.changes | AgentActivityStore | connection only | none | none |
| native.http | NativeActionHost | nativeUse | none | human |
| native.xmlrpc | NativeActionHost | nativeUse | none | human |
| native.fileRead | AgentImportReading | nativeUse, filesRead | bookmark | human |
| native.fileWrite | AgentImportReading | nativeUse, filesWrite | bookmark | human |
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
| native.shell | NativeAutomationAdapter | nativeUse, scriptsUnrestricted | none | library, human |
| native.appleScript | NativeAutomationAdapter | nativeUse, scriptsUnrestricted | none | library, human |
| native.shortcut | NativeAutomationAdapter | nativeUse, scriptsUnrestricted | none | library, human |


| Scope | Evidence in the catalog branch |
| --- | --- |
| Every operation in the table | The complete-host test checks a registered handler and a schema for each required name. This is source evidence. |
| `activity.changes` | Signed build 26 returned the new event exactly once over CLI and MCP. |
| `operations.answerPrompt` | Signed build 30 rejected an unrelated retry key and accepted the valid answer over CLI and MCP. MCP also rejected a duplicate. |
| `syntaxes.install`, `syntaxes.replace`, `syntaxes.reload`, `syntaxes.delete`, `bookmarks.requestAdd`, `bookmarks.forget` | Signed build 26 passed CLI and MCP. See [PR #114](https://github.com/pobrespandas/draftly/pull/114). |
| `imports.validate`, `imports.preview`, `imports.commit`, `backups.previewRestore`, `backups.requestRestore` | Signed build 27 passed CLI and MCP and verified the pre-restore copy. See [PR #115](https://github.com/pobrespandas/draftly/pull/115). |
| Native operations added in the catalog branch | Signed build 30 passed model mode enumeration, HTML preview, XML-RPC, file read and write, Mail and Messages composition, and OCR of a selected PNG over CLI and MCP. Calendar and Reminders still need installed checks. See [post-update acceptance](../agent-codex-claude-acceptance.md#post-update-client-and-operation-checks). |

`version` requires an expected-version token. `human` requires a bound one-use
approval. `library` requires an explicit whole-library grant. Other target kinds
are always checked against the connection's allowed resources. Query handlers
must filter their results using the returned scope; an empty target list does
not authorize reading the whole library. Native effects and operation or transfer ownership have additional checks in
their handlers.

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


## Draft mutation contracts

Thirteen draft mutation operations now have schemas. Creation uses request-local
content, tag, flag, syntax and Inbox defaults that match Note. It does not invent
an identity, date or access history. Updates require a nonempty changes object;
IDs and accessedAt are not writable through it. Explicit null and unknown string
metadata remain unchanged. Unsupported fields fail instead of disappearing.

Patches use nonempty lists of original-snapshot UTF-16 offsets, lengths and text.
Validation rejects negative, fractional, overflowing, overlapping and duplicate
start ranges. It retains the request order. Future handlers must check content
bounds and Unicode scalar boundaries against the live version, reject editor
conflicts, then apply replacements from the end. Shape validation cannot prove
that a range exists in the current note.

Merge requires at least two distinct authorized targets in an explicit complete
order. The default destination is archive, matching LibraryStore.mergeNotes;
separator and blank-line defaults remain unchanged. Duplicate and merge results
must name a new resource. Batch receipts must cover every target exactly once.
Revision restoration returns the draft identity, not the revision identity.
A handler must also check that the revision belongs to that draft.

Restore accepts no organization override: the existing command clears trash
without clearing archive state. Purge accepts no self-approval field and still
requires human approval. Tags use explicit add/remove/replace modes. Syntax uses
exactly one name or identity. Runtime handlers must reuse shared TagRules,
syntax resolution, DraftOperations and persistence rather than copy these rules.
No actual note mutation, receipt transaction, pending-editor coordination or Undo
behavior is enabled by this contract work.

There are now 52 schemas for 128 planned operations; 76 still need schemas.
All executors, the local broker, pairing and clients remain to be implemented.
Arrays and objects export the same nonempty bounds used by validation. Batch
request targets, policy checks, order lists and receipts share a 10,000 target
limit. A regression demonstrated that larger requests were previously accepted
although their complete receipts could not fit the result shape.


## Editor contracts

Fifteen editor operations now have schemas. Added editor.listTasks as an explicit
read operation; editor.tasks remains a versioned mutation. Reading syntax task
marks does not require write authority. The catalog and independent fixture now
contain 129 operation names. There are 67 schemas; 62 operations still need them.
No editor handler is enabled.

Editor snapshots use explicit window and draft identities, opaque version tokens,
bounded UTF-16 content chunks and selection ranges. Empty editors cannot report
content, dirty state or match items. Find, markers, links and task marks use
paginated results. Syntax fields come from the existing shared definition;
internal rule indices are not public identities. Task mutations specify the
captured state and its range plus complete/reset/advance. Runtime code must
resolve the current task again after checking its editor version.

Opening requires either an explicit window with its expected window version or
an explicit newWindow request. It does not choose the active window. Focus is
false by default; the existing ui.present capability is still required. Window
and draft identities bind replies. Selection and preview replies must match the
requested change. Navigate uses previous/next; future handlers must retain the
existing visible-row order and clamp behavior without visiting unauthorized
notes. Open, navigate and preview require contextual effect review for resolved
windows, destination drafts and external resources.

AgentTextShapes shares UTF-16 range and content-chunk checks among draft reads,
patches and editor contracts. It checks integer bounds, overflow, chunk lengths
and continuation flags. It does not prove scalar boundaries in unseen content.
The existing literal/regex query and syntax task APIs are checked in contract
tests. Actual editor synchronization, query errors, pending text, storage errors,
Undo/Redo, cursor ownership, file effects and focus still need runtime and manual
acceptance. No windows, native permissions or personal data were used in tests.

A separate regression demonstrated that the schema gateway accepted mutation
requests without expectedVersion even though grant evaluation rejected them.
The gateway now enforces the catalog's required nonempty version header before
family-specific validation. This does not compare a version with live state;
that comparison remains a handler requirement.


## Appearance contracts

Twenty-three theme and syntax operations now have schemas. The inventory now
contains 136 names and 90 schemas; 46 operations still need schemas. Added
explicit built-in selection/read/export routes, theme selection state, targeted
theme replacement and syntax Reload. Built-ins use their existing names, not
invented persistent UUIDs. Installed definitions keep their existing UUIDs.
The independent fixture records these deliberate inventory additions.

Canonical themes retain unknown root fields, including imported Drafts source.
Canonical syntax records retain the exact source string and its unknown grammar
fields. Shape validation checks wire types; the existing theme validator, Drafts
importer and SyntaxDefinition parser must validate their semantics before any
save. No replacement parser or color rules were added. Creation leaves absent
constructor fields absent rather than writing inspector defaults.

Input sources distinguish inline UTF-8 text, a prepared transfer, a relative
path in an authorized bookmark, an installation link and an HTTPS source. The exported JSON Schema and validation share
the same exclusive alternatives and required fields. Exact source fields prevent
mixed destinations. Relative paths reject traversal and
absolute paths; live-file mode requires a bookmarked source. Installation links
are limited to the expected theme/syntax endpoint and unique supported query
keys. They cannot open Actions or callback URLs. These checks do not authorize
file roots, resolve symlinks, verify transfer ownership, authorize HTTP hosts or
redirects, fetch bytes or install anything. Contextual effect review remains
mandatory, including file-backed reads and reloads.

Installation fails on an existing identity/name unless the caller uses the
explicit targeted replacement route with a version check. A built-in link can
report its named built-in instead of inventing an installed resource. Replies
must report exactly one of those outcomes. Replacement retains the target ID;
duplication requires a different ID. Delete replies bind their target IDs.
Exports bind the resource or built-in name, chosen format, version and UTF-16
chunk. Native, Drafts-source and installation-link formats remain distinct;
unsupported conversions must return a real error, not synthetic data.

Theme selection reads the effective existing reference without rewriting stored
preferences. The reference is null if its definition cannot be disclosed under
the resource scope; the opaque local selection token contains no readable ID. Its version represents the local light/dark selection slot.
Selecting an installed definition also needs expectedThemeVersion; it does not
reuse the definition token as the local preference token. Installation selects
nothing unless selectAppearance and expectedSelectionVersion are both present.
Selection receipts are required only for that requested effect. Future handlers
must preserve the existing save/install-before-selection order and record any
completed effects if later selection fails. No rollback is claimed.

These remain unexposed contracts. Actual imports, storage failures, unknown-field
persistence, local bookmarks, shared definitions, syntax features, render changes,
selection and Undo still need handler tests and native acceptance. The habitual
app, identities, library and CloudKit container remain unchanged.


## Typed Settings and bookmark contracts

There are now 93 static schemas and four registry-bound preference forms for
136 planned operations. Thirty-nine operations still need contract definitions.
No handler is enabled. The production preference field catalog is not connected;
fixture fields do not prove coverage of actual Settings controls. See the
[preference source inventory](agent-preference-inventory.md) for audited owners
and the remaining application binding work.

AgentPreferenceRegistry accepts trusted field declarations from application code.
Requests cannot add fields or choose raw storage keys. Without a supplied registry,
preference operations return unavailable. Each field declares its value shape,
context, default source, writable state and approval requirements. Decimal number
validation preserves finite numeric values and rejects strings, booleans, NaN
and invalid bounds. Generated JSON Schema uses the same constraints.

Addresses distinguish device settings, syntax overrides, syntax features and
commands. Installed syntax IDs remain UUIDs; built-ins use known names. Duplicate
addresses cannot hide behind UUID case or canonically equivalent Unicode. Reads
retain stored/default/inherited/system/invalid origin without exposing raw data.
Resolved values must match their declared type, including inherited and system
values. Only a declared nullable value or an explicit invalid-store state can
return null. A regression caught untyped null replies before this correction.
Reading a default does not insert it into the request or write storage. Updates
and resets accept only selected known fields. Writer receipts contain addresses
and version tokens, not readable values. Replies must cover the requested set.

Command-specific and field-level approval requirements are separate from grant
evaluation. A global shortcut or login change can require protected human consent
while an ordinary local option does not. interactive only permits the app to ask;
it is not approval. Native adapters, conflicts, syntax-feature existence, reference
scope, storage failures and field-level reset behavior remain application work.
Descriptor output must match the trusted registry, including types and defaults.
A separate package-consumer module constructs fields and structured value shapes
without @testable access. It failed before explicit package constructors were
added. This proves the module interface can be consumed, not that application
Settings bindings are complete.

Bookmark list replies contain names, local IDs and versions, not paths or saved
permission data. Add requests preserve Unicode names and require a native human
folder choice; an arbitrary path or self-approval field is rejected. Adding a
bookmark does not grant the connection file authority. The app uses stable local
IDs for bookmark records and filters them by the grant. Forget requires review
and the current bookmark version. It removes the saved permission from Draftly
and leaves the folder on disk.


### Scoped file transfers

A transfer is a temporary byte exchange, not a library import or a saved file.
Transfers retain their authorized connection, exact grant and source resource
scope. A new CLI transport can resume a transfer under that same authorization.
A changed grant, expiry, connection invalidation or Stop Work prevents access. Transfer IDs are operation-kind handles, but do not identify
work in `operations.get`.

Uploads declare a byte count and SHA-256 digest. Chunks use byte offsets and
canonical Base64. Finish requires the complete bytes and a matching digest.
A repeated identical chunk is safe; an overlapping change is a conflict.
Finish does not install any content. The import handlers validate and preview
the completed transfer. Commit requires the preview version and app review.

Exports freeze the selected drafts, including pending editor content. The
`draftly` format uses the existing backup format with only selected drafts and
optional selected-draft versions. The `text` format requires exactly one draft
and excludes versions. Neither route flushes editors or writes a destination
file. The owning session reads exported bytes through `transfers.readChunk`.

Transfers expire after five minutes or at grant expiry, whichever occurs first.
The monotonic deadline also prevents clock rollback from extending access.
Each transfer holds at most 32 MiB. Each host reserves at most 64 MiB across
16 transfers. Chunks hold at most 64 KiB. Buffer cleanup checks ownership and either `files.read` or `files.write`.
Cancelling an upload does not require export permission. Plain draft readers
do not receive the cancellation tool.
It returns no content and changes no library resource.


### Backup validation, preview and restore

Backup export uses the existing backup model and projects pending text in saved drafts
without saving the editor. It requires whole-library scope, every declared
export capability, and connected editor tracking. The serialized backup uses
an owned export transfer and its existing byte and lifetime limits.

Backup validation applies incoming bytes to a disposable empty library. Restore
preview also applies them to a disposable copy of current storage. Both use
`LibraryStore.restore`; neither changes live storage. Preview rejects pending
editor byte changes. Its version token binds incoming bytes and stored library
state. Reports contain counts, not existing record content.

Validation, preview and restore accept inline data, completed transfers and
authorized bookmark sources. HTTPS input requires a separate download review.
Restore requires whole-library scope, the current preview version and app
review. It checks for pending editor changes and saves a recovery copy before
it applies the restore. The operation journal records the result and lets the
connection recover it without applying the restore again.
