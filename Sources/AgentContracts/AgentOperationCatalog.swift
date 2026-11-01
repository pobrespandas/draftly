import Foundation

package enum AgentTargetRule: Sendable {
    case none
    case one(AgentResourceKind)
    case many(AgentResourceKind)
    case pair(AgentResourceKind, AgentResourceKind)

    func accepts(_ targets: [AgentResourceReference]) -> Bool {
        guard targets.count <= AgentRequest.maximumTargets, Set(targets).count == targets.count else { return false }
        switch self {
        case .none: return targets.isEmpty
        case .one(let kind): return targets.count == 1 && targets[0].kind == kind
        case .many(let kind): return !targets.isEmpty && targets.allSatisfy { $0.kind == kind }
        case .pair(let first, let second):
            return targets.count == 2 && Set(targets.map(\.kind)) == Set([first, second])
        }
    }
}

package struct AgentOperationDescriptor: Sendable {
    package let name: String
    package let owner: String
    package let capabilities: Set<AgentCapability>
    package let targets: AgentTargetRule
    package let requiresExpectedVersion: Bool
    package let requiresLibraryScope: Bool
    package let requiresHumanApproval: Bool
    package let isReadOnly: Bool

    package init(name: String, owner: String, capabilities: Set<AgentCapability>, targets: AgentTargetRule,
                 requiresExpectedVersion: Bool = false, requiresLibraryScope: Bool = false,
                 requiresHumanApproval: Bool = false, isReadOnly: Bool = false) {
        self.name = name
        self.owner = owner
        self.capabilities = capabilities
        self.targets = targets
        self.requiresExpectedVersion = requiresExpectedVersion
        self.requiresLibraryScope = requiresLibraryScope
        self.requiresHumanApproval = requiresHumanApproval
        self.isReadOnly = isReadOnly
    }

    package var requiresEffectAuthorization: Bool {
        name == "actions.run" || name.hasPrefix("native.")
            || name == "preferences.update" || name == "preferences.reset"
            || name == "imports.commit" || name == "workspaces.apply"
            || ["editor.open", "editor.navigate", "editor.preview", "themes.get", "themes.export",
                "themes.update", "themes.duplicate", "themes.select", "themes.selectBuiltIn", "themes.reload",
                "themes.install", "themes.replace", "syntaxes.get", "syntaxes.export", "syntaxes.install", "syntaxes.replace", "syntaxes.reload"].contains(name)
    }

    package func acceptsTargets(_ values: [AgentResourceReference]) -> Bool {
        targets.accepts(values)
    }
}

package enum AgentOperationCatalog {
    package static func operation(named name: String) -> AgentOperationDescriptor? {
        byName[name]
    }

    private static let byName = Dictionary(uniqueKeysWithValues: operations.map { ($0.name, $0) })

    package static let operations: [AgentOperationDescriptor] = [
        .init(name: "server.status", owner: "AgentCommandService", capabilities: [], targets: .none, isReadOnly: true),
        .init(name: "server.capabilities", owner: "AgentCommandService", capabilities: [], targets: .none, isReadOnly: true),
        .init(name: "server.schemas", owner: "AgentCommandService", capabilities: [], targets: .none, isReadOnly: true),
        .init(name: "library.summary", owner: "LibraryStore", capabilities: [.draftsRead], targets: .none, isReadOnly: true),
        .init(name: "drafts.list", owner: "LibraryStore + DraftCommands", capabilities: [.draftsRead], targets: .none, isReadOnly: true),
        .init(name: "drafts.search", owner: "LibraryStore + DraftCommands", capabilities: [.draftsRead], targets: .none, isReadOnly: true),
        .init(name: "drafts.get", owner: "LibraryStore + DraftCommands", capabilities: [.draftsRead], targets: .one(.draft), isReadOnly: true),
        .init(name: "drafts.versions", owner: "LibraryStore + DraftCommands", capabilities: [.draftsRead], targets: .one(.draft), isReadOnly: true),
        .init(name: "drafts.create", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .none),
        .init(name: "drafts.update", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .one(.draft), requiresExpectedVersion: true),
        .init(name: "drafts.patch", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .one(.draft), requiresExpectedVersion: true),
        .init(name: "drafts.duplicate", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .one(.draft), requiresExpectedVersion: true),
        .init(name: "drafts.merge", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .many(.draft), requiresExpectedVersion: true),
        .init(name: "drafts.archive", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .many(.draft), requiresExpectedVersion: true),
        .init(name: "drafts.trash", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .many(.draft), requiresExpectedVersion: true),
        .init(name: "drafts.restore", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .many(.draft), requiresExpectedVersion: true),
        .init(name: "drafts.flag", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .many(.draft), requiresExpectedVersion: true),
        .init(name: "drafts.tags", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .many(.draft), requiresExpectedVersion: true),
        .init(name: "drafts.syntax", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .many(.draft), requiresExpectedVersion: true),
        .init(name: "drafts.restoreVersion", owner: "LibraryStore + DraftCommands", capabilities: [.draftsWrite], targets: .pair(.draft, .revision), requiresExpectedVersion: true),
        .init(name: "drafts.purge", owner: "LibraryStore", capabilities: [.draftsWrite, .destructiveRequest], targets: .many(.draft), requiresExpectedVersion: true, requiresHumanApproval: true),
        .init(name: "editor.windows", owner: "EditorSession + WindowModel", capabilities: [.editorRead, .draftsRead], targets: .none),
        .init(name: "editor.get", owner: "EditorSession + WindowModel", capabilities: [.editorRead, .draftsRead], targets: .one(.window)),
        .init(name: "editor.find", owner: "EditorSession + WindowModel", capabilities: [.editorRead, .draftsRead], targets: .one(.window)),
        .init(name: "editor.markers", owner: "EditorSession + WindowModel", capabilities: [.editorRead, .draftsRead], targets: .one(.window)),
        .init(name: "editor.links", owner: "EditorSession + WindowModel", capabilities: [.editorRead, .draftsRead], targets: .one(.window)),
        .init(name: "editor.replaceRange", owner: "EditorSession + WindowModel", capabilities: [.editorWrite, .draftsWrite], targets: .one(.window), requiresExpectedVersion: true),
        .init(name: "editor.setSelection", owner: "EditorSession + WindowModel", capabilities: [.editorWrite, .draftsWrite], targets: .one(.window), requiresExpectedVersion: true),
        .init(name: "editor.replaceAll", owner: "EditorSession + WindowModel", capabilities: [.editorWrite, .draftsWrite], targets: .one(.window), requiresExpectedVersion: true),
        .init(name: "editor.listTasks", owner: "SyntaxDefinition + EditorSession", capabilities: [.editorRead, .draftsRead], targets: .one(.window)),
        .init(name: "editor.tasks", owner: "EditorSession + WindowModel", capabilities: [.editorWrite, .draftsWrite], targets: .one(.window), requiresExpectedVersion: true),
        .init(name: "editor.undo", owner: "EditorSession + WindowModel", capabilities: [.editorWrite, .draftsWrite], targets: .one(.window), requiresExpectedVersion: true),
        .init(name: "editor.redo", owner: "EditorSession + WindowModel", capabilities: [.editorWrite, .draftsWrite], targets: .one(.window), requiresExpectedVersion: true),
        .init(name: "editor.open", owner: "WindowModel", capabilities: [.presentUI, .draftsRead], targets: .one(.draft)),
        .init(name: "editor.navigate", owner: "WindowModel", capabilities: [.presentUI, .draftsRead], targets: .one(.window), requiresExpectedVersion: true),
        .init(name: "editor.preview", owner: "WindowModel", capabilities: [.presentUI, .draftsRead], targets: .one(.window)),
        .init(name: "actions.list", owner: "ActionCatalog + ActionEditingCopy", capabilities: [.actionsRead], targets: .none),
        .init(name: "actions.get", owner: "ActionCatalog + ActionEditingCopy", capabilities: [.actionsRead], targets: .one(.action)),
        .init(name: "actions.stepSchemas", owner: "ActionCatalog + ActionEditingCopy", capabilities: [.actionsRead], targets: .none),
        .init(name: "actions.groups", owner: "ActionCatalog + ActionEditingCopy", capabilities: [.actionsRead], targets: .none),
        .init(name: "actions.create", owner: "LibraryStore + ActionEditingCopy", capabilities: [.actionsManage], targets: .none),
        .init(name: "actions.update", owner: "LibraryStore + ActionEditingCopy", capabilities: [.actionsManage], targets: .one(.action), requiresExpectedVersion: true),
        .init(name: "actions.duplicate", owner: "LibraryStore + ActionEditingCopy", capabilities: [.actionsManage], targets: .one(.action), requiresExpectedVersion: true),
        .init(name: "actions.move", owner: "LibraryStore + ActionEditingCopy", capabilities: [.actionsManage], targets: .pair(.action, .actionGroup), requiresExpectedVersion: true),
        .init(name: "actions.reorder", owner: "LibraryStore + ActionEditingCopy", capabilities: [.actionsManage], targets: .many(.action), requiresExpectedVersion: true),
        .init(name: "actions.validateShortcut", owner: "LibraryStore + ActionEditingCopy", capabilities: [.actionsManage], targets: .none),
        .init(name: "actions.delete", owner: "LibraryStore", capabilities: [.actionsManage, .destructiveRequest], targets: .one(.action), requiresExpectedVersion: true, requiresHumanApproval: true),
        .init(name: "actionGroups.get", owner: "LibraryStore + ActionCatalog", capabilities: [.actionsRead], targets: .one(.actionGroup)),
        .init(name: "actionGroups.create", owner: "LibraryStore + ActionCatalog", capabilities: [.actionsManage], targets: .none),
        .init(name: "actionGroups.update", owner: "LibraryStore + ActionCatalog", capabilities: [.actionsManage], targets: .one(.actionGroup), requiresExpectedVersion: true),
        .init(name: "actionGroups.duplicate", owner: "LibraryStore + ActionCatalog", capabilities: [.actionsManage], targets: .one(.actionGroup), requiresExpectedVersion: true),
        .init(name: "actionGroups.reorder", owner: "LibraryStore + ActionCatalog", capabilities: [.actionsManage], targets: .many(.actionGroup), requiresExpectedVersion: true),
        .init(name: "actionGroups.delete", owner: "LibraryStore", capabilities: [.actionsManage, .destructiveRequest], targets: .one(.actionGroup), requiresExpectedVersion: true, requiresHumanApproval: true),
        .init(name: "actions.run", owner: "AutomationActionExecution + ActionRunner", capabilities: [.actionsRun, .draftsRead], targets: .pair(.action, .draft), requiresExpectedVersion: true),
        .init(name: "operations.get", owner: "AgentOperationRegistry", capabilities: [], targets: .one(.operation)),
        .init(name: "operations.wait", owner: "AgentOperationRegistry", capabilities: [], targets: .one(.operation)),
        .init(name: "operations.cancel", owner: "AgentOperationRegistry", capabilities: [], targets: .one(.operation)),
        .init(name: "operations.answerPrompt", owner: "AgentOperationRegistry", capabilities: [], targets: .one(.operation), requiresExpectedVersion: true),
        .init(name: "workspaces.list", owner: "Workspace + LibraryStore", capabilities: [.workspacesRead], targets: .none),
        .init(name: "workspaces.get", owner: "Workspace + LibraryStore", capabilities: [.workspacesRead], targets: .one(.workspace)),
        .init(name: "workspaces.query", owner: "Workspace + LibraryStore", capabilities: [.workspacesRead, .draftsRead], targets: .one(.workspace)),
        .init(name: "workspaces.create", owner: "LibraryStore", capabilities: [.workspacesManage], targets: .none),
        .init(name: "workspaces.update", owner: "LibraryStore", capabilities: [.workspacesManage], targets: .one(.workspace), requiresExpectedVersion: true),
        .init(name: "workspaces.duplicate", owner: "LibraryStore", capabilities: [.workspacesManage], targets: .one(.workspace), requiresExpectedVersion: true),
        .init(name: "workspaces.reorder", owner: "LibraryStore", capabilities: [.workspacesManage], targets: .many(.workspace), requiresExpectedVersion: true),
        .init(name: "workspaces.delete", owner: "LibraryStore", capabilities: [.workspacesManage, .destructiveRequest], targets: .one(.workspace), requiresExpectedVersion: true, requiresHumanApproval: true),
        .init(name: "workspaces.apply", owner: "WindowModel.prepareWorkspace", capabilities: [.workspacesApply, .presentUI], targets: .pair(.workspace, .window), requiresExpectedVersion: true),
        .init(name: "themes.list", owner: "InstalledThemeCommands", capabilities: [.appearanceRead], targets: .none),
        .init(name: "themes.get", owner: "InstalledThemeCommands", capabilities: [.appearanceRead], targets: .one(.theme)),
        .init(name: "themes.export", owner: "InstalledThemeCommands", capabilities: [.appearanceRead], targets: .one(.theme)),
        .init(name: "themes.create", owner: "InstalledThemeCommands", capabilities: [.appearanceManage], targets: .none),
        .init(name: "themes.update", owner: "InstalledThemeCommands", capabilities: [.appearanceManage], targets: .one(.theme), requiresExpectedVersion: true),
        .init(name: "themes.duplicate", owner: "InstalledThemeCommands", capabilities: [.appearanceManage], targets: .one(.theme), requiresExpectedVersion: true),
        .init(name: "themes.select", owner: "InstalledThemeCommands", capabilities: [.appearanceManage], targets: .one(.theme), requiresExpectedVersion: true),
        .init(name: "themes.selection", owner: "EditorThemePreferences", capabilities: [.appearanceRead], targets: .none),
        .init(name: "themes.replace", owner: "ThemeFileAccess + InstalledThemeCommands", capabilities: [.appearanceManage, .filesRead], targets: .one(.theme), requiresExpectedVersion: true),
        .init(name: "themes.selectBuiltIn", owner: "EditorThemePreferences + ThemeCatalog", capabilities: [.appearanceManage], targets: .none, requiresExpectedVersion: true),
        .init(name: "themes.exportBuiltIn", owner: "ThemeInstallation", capabilities: [.appearanceRead], targets: .none),
        .init(name: "themes.reload", owner: "InstalledThemeCommands", capabilities: [.appearanceManage, .filesRead], targets: .one(.theme), requiresExpectedVersion: true),
        .init(name: "themes.install", owner: "InstalledThemeCommands", capabilities: [.appearanceManage, .filesRead], targets: .none),
        .init(name: "themes.delete", owner: "InstalledThemeCommands", capabilities: [.appearanceManage, .destructiveRequest], targets: .one(.theme), requiresExpectedVersion: true, requiresHumanApproval: true),
        .init(name: "syntaxes.list", owner: "SyntaxDefinition + ScriptSyntax", capabilities: [.appearanceRead], targets: .none),
        .init(name: "syntaxes.get", owner: "SyntaxDefinition + ScriptSyntax", capabilities: [.appearanceRead], targets: .one(.syntax)),
        .init(name: "syntaxes.getBuiltIn", owner: "ScriptSyntax", capabilities: [.appearanceRead], targets: .none),
        .init(name: "syntaxes.exportBuiltIn", owner: "ScriptSyntax", capabilities: [.appearanceRead], targets: .none),
        .init(name: "syntaxes.reload", owner: "SyntaxFileAccess", capabilities: [.appearanceManage, .filesRead], targets: .one(.syntax), requiresExpectedVersion: true),
        .init(name: "syntaxes.export", owner: "SyntaxDefinition + ScriptSyntax", capabilities: [.appearanceRead], targets: .one(.syntax)),
        .init(name: "syntaxes.install", owner: "SyntaxImportPreparation + ApplicationURLRouter", capabilities: [.appearanceManage, .filesRead], targets: .none),
        .init(name: "syntaxes.replace", owner: "SyntaxImportPreparation + ApplicationURLRouter", capabilities: [.appearanceManage, .filesRead], targets: .one(.syntax), requiresExpectedVersion: true),
        .init(name: "syntaxes.delete", owner: "SyntaxImportPreparation + ApplicationURLRouter", capabilities: [.appearanceManage, .destructiveRequest], targets: .one(.syntax), requiresExpectedVersion: true, requiresHumanApproval: true),
        .init(name: "preferences.schema", owner: "Typed preference commands", capabilities: [.preferencesRead], targets: .none),
        .init(name: "preferences.get", owner: "Typed preference commands", capabilities: [.preferencesRead], targets: .none),
        .init(name: "preferences.update", owner: "Typed preference commands", capabilities: [.preferencesWrite], targets: .none, requiresExpectedVersion: true),
        .init(name: "preferences.reset", owner: "Typed preference commands", capabilities: [.preferencesWrite], targets: .none, requiresExpectedVersion: true),
        .init(name: "bookmarks.list", owner: "BookmarkPreferences", capabilities: [.preferencesRead], targets: .none),
        .init(name: "bookmarks.requestAdd", owner: "BookmarkPreferences", capabilities: [.preferencesWrite], targets: .none, requiresHumanApproval: true),
        .init(name: "bookmarks.forget", owner: "BookmarkPreferences", capabilities: [.preferencesWrite], targets: .one(.bookmark), requiresExpectedVersion: true, requiresHumanApproval: true),
        .init(name: "imports.validate", owner: "DraftFileCommands + importers", capabilities: [.filesRead, .draftsWrite], targets: .none),
        .init(name: "imports.preview", owner: "DraftFileCommands + importers", capabilities: [.filesRead, .draftsWrite], targets: .none),
        .init(name: "imports.commit", owner: "DraftFileCommands + importers", capabilities: [.filesRead, .draftsWrite], targets: .none, requiresExpectedVersion: true),
        .init(name: "exports.drafts", owner: "DraftFileCommands", capabilities: [.draftsRead, .filesWrite], targets: .many(.draft)),
        .init(name: "backups.export", owner: "LibraryStore.backupData", capabilities: [.backupsExport, .draftsRead, .actionsRead, .workspacesRead, .appearanceRead, .filesWrite], targets: .none, requiresLibraryScope: true),
        .init(name: "backups.validate", owner: "LibraryStore.restore", capabilities: [.backupsRestore, .filesRead], targets: .none, requiresLibraryScope: true),
        .init(name: "backups.previewRestore", owner: "LibraryStore.restore", capabilities: [.backupsRestore, .filesRead], targets: .none, requiresLibraryScope: true),
        .init(name: "backups.requestRestore", owner: "LibraryStore.restore", capabilities: [.backupsRestore, .filesRead], targets: .none, requiresExpectedVersion: true, requiresLibraryScope: true, requiresHumanApproval: true),
        .init(name: "transfers.beginImport", owner: "AgentTransferStore", capabilities: [.filesRead], targets: .none),
        .init(name: "transfers.appendChunk", owner: "AgentTransferStore", capabilities: [.filesRead], targets: .one(.operation)),
        .init(name: "transfers.finishImport", owner: "AgentTransferStore", capabilities: [.filesRead], targets: .one(.operation)),
        .init(name: "transfers.readChunk", owner: "AgentTransferStore", capabilities: [.filesWrite], targets: .one(.operation)),
        .init(name: "transfers.cancel", owner: "AgentTransferStore", capabilities: [.filesWrite], targets: .one(.operation)),
        .init(name: "activity.list", owner: "AgentActivityStore", capabilities: [], targets: .none),
        .init(name: "activity.changes", owner: "AgentActivityStore", capabilities: [], targets: .none),
        .init(name: "native.http", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.xmlrpc", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.fileRead", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.fileWrite", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.clipboardRead", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.clipboardWrite", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.htmlToMarkdown", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.htmlPreview", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.mail", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.messages", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.calendar", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.reminders", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.dictate", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.transcribe", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.scanDocument", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.location", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.models", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.share", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.print", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.speak", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.openURL", owner: "NativeActionHost", capabilities: [.nativeUse], targets: .none, requiresHumanApproval: true),
        .init(name: "native.shell", owner: "NativeAutomationAdapter", capabilities: [.nativeUse, .scriptsUnrestricted], targets: .none, requiresHumanApproval: true),
        .init(name: "native.appleScript", owner: "NativeAutomationAdapter", capabilities: [.nativeUse, .scriptsUnrestricted], targets: .none, requiresHumanApproval: true),
        .init(name: "native.shortcut", owner: "NativeAutomationAdapter", capabilities: [.nativeUse, .scriptsUnrestricted], targets: .none, requiresHumanApproval: true),
    ]
}
