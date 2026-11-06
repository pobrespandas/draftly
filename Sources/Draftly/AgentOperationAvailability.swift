import AgentContracts

// Availability describes connected handlers. It does not grant permission.
@MainActor struct AgentOperationAvailability {
    enum Handler: CaseIterable {
        case editorRead, editorOpen, draftWrite, editorWrite, preferenceWrite
        case activityRead, operationControl, actionExecution, workspaceApply, workspaceDelete, draftPurge, themeWrite, themeImport, themeDelete, themePresentation, actionDelete, nativeExecution
    }

    private struct Rule {
        let operations: Set<String>
        let handlers: Set<Handler>
        var optionalHostFeature = false
    }

    private static let rules: [Rule] = [
        .init(operations: ["server.status", "server.capabilities", "server.schemas",
            "library.summary", "drafts.list", "drafts.search", "drafts.get", "drafts.versions",
            "preferences.schema", "preferences.get", "syntaxes.list", "syntaxes.get", "syntaxes.export",
            "syntaxes.getBuiltIn", "syntaxes.exportBuiltIn", "actions.list", "actions.get",
            "actions.stepSchemas", "actions.groups", "actionGroups.get",
            "workspaces.list", "workspaces.get", "workspaces.query"], handlers: []),
        .init(operations: AgentBookmarkReading.operationNames, handlers: []),
        .init(operations: AgentTransferSchemas.operationNames, handlers: []),
        .init(operations: ["backups.validate"], handlers: []),
        .init(operations: ["backups.export", "backups.previewRestore"], handlers: [.editorRead]),
        .init(operations: AgentThemeReading.operationNames, handlers: []),
        .init(operations: ["themes.delete"], handlers: [.themeDelete, .operationControl], optionalHostFeature: true),
        .init(operations: AgentThemeInstallation.operationNames, handlers: [.themeImport, .operationControl], optionalHostFeature: true),
        .init(operations: AgentThemePresentation.operationNames, handlers: [.themePresentation, .operationControl], optionalHostFeature: true),
        .init(operations: AgentThemeWriting.operationNames.union([AgentMutationSchemas.name]), handlers: [.themeWrite]),
        .init(operations: ["editor.windows", "editor.get", "editor.find", "editor.markers",
            "editor.links", "editor.listTasks"], handlers: [.editorRead]),
        .init(operations: ["editor.open"], handlers: [.editorRead, .editorOpen, .operationControl], optionalHostFeature: true),
        .init(operations: ["editor.preview", "editor.navigate"], handlers: [.editorRead, .operationControl], optionalHostFeature: true),
        .init(operations: AgentDraftWriting.operationNames, handlers: [.editorRead, .draftWrite]),
        .init(operations: AgentEditorWriting.operationNames, handlers: [.editorRead, .draftWrite, .editorWrite]),
        .init(operations: ["workspaces.create", "workspaces.update", "workspaces.duplicate", "workspaces.reorder", "actions.create", "actions.update", "actions.duplicate",
            "actions.move", "actions.reorder", "actions.validateShortcut", "actionGroups.create",
            "actionGroups.update", "actionGroups.duplicate", "actionGroups.reorder", AgentMutationSchemas.name],
            handlers: [.editorRead, .draftWrite]),
        .init(operations: AgentPreferenceWriting.operationNames.union([AgentMutationSchemas.name]),
            handlers: [.preferenceWrite]),
        .init(operations: AgentWorkspaceApplication.operationNames.union([AgentMutationSchemas.name]), handlers: [.workspaceApply]),
        .init(operations: ["drafts.purge", AgentMutationSchemas.name],
            handlers: [.editorRead, .draftWrite, .operationControl, .draftPurge], optionalHostFeature: true),
        .init(operations: ["actions.delete", "actionGroups.delete", AgentMutationSchemas.name],
            handlers: [.operationControl, .actionDelete], optionalHostFeature: true),
        .init(operations: ["workspaces.delete", AgentMutationSchemas.name],
            handlers: [.operationControl, .workspaceDelete], optionalHostFeature: true),
        .init(operations: AgentActivitySchemas.operationNames, handlers: [.activityRead], optionalHostFeature: true),
        .init(operations: ["operations.get", "operations.cancel", "operations.wait"], handlers: [.operationControl], optionalHostFeature: true),
        .init(operations: ["operations.answerPrompt"], handlers: [.operationControl, .actionExecution], optionalHostFeature: true),
        .init(operations: AgentNativeSchemas.operationNames, handlers: [.nativeExecution, .operationControl], optionalHostFeature: true),
        .init(operations: ["actions.run"], handlers: [.operationControl, .actionExecution], optionalHostFeature: true)
    ]

    static var implementedOperations: Set<String> {
        rules.filter { !$0.optionalHostFeature }.reduce(into: []) { $0.formUnion($1.operations) }
    }

    let operations: Set<String>

    init(handlers: Set<Handler>) {
        operations = Self.rules.filter { $0.handlers.isSubset(of: handlers) }
            .reduce(into: []) { $0.formUnion($1.operations) }
    }

    var capabilities: Set<AgentCapability> {
        operations.reduce(into: []) { result, name in
            if let operation = AgentOperationCatalog.operation(named: name) {
                result.formUnion(operation.capabilities)
            }
            switch name {
            case "preferences.get": result.insert(.appearanceRead)
            case "preferences.update": result.insert(.appearanceManage)
            case "themes.get", "themes.export": result.insert(.filesRead)
            case "native.openURL": result.insert(.scriptsUnrestricted)
            case "actions.run": result.formUnion([.draftsWrite, .editorWrite, .nativeUse])
            default: break
            }
        }
    }
}
