import Testing
import AgentContracts
@testable import Draftly

@Suite("Connected agent operation availability") @MainActor
struct AgentOperationAvailabilityTests {
    @Test(arguments: 0..<4)
    func themeDeletionNeedsReviewAndOperationControl(_ mask: Int) {
        var handlers = Set<AgentOperationAvailability.Handler>()
        if mask & 1 != 0 { handlers.insert(.themeDelete) }
        if mask & 2 != 0 { handlers.insert(.operationControl) }
        #expect(AgentOperationAvailability(handlers: handlers).operations.contains("themes.delete") == (mask == 3))
    }

    @Test func readOnlyHostDoesNotAdvertiseMutationOrExecution() throws {
        let available = AgentOperationAvailability(handlers: [])
        #expect(available.operations.contains("actions.get"))
        #expect(available.operations.contains("preferences.get"))
        #expect(available.operations.contains("workspaces.query"))
        #expect(available.capabilities.contains(.appearanceRead))
        #expect(!available.capabilities.contains(.appearanceManage))
        #expect(!available.capabilities.contains(.actionsRun))
        for name in available.operations {
            let descriptor = try #require(AgentOperationCatalog.operation(named: name))
            #expect(descriptor.capabilities.isSubset(of: available.capabilities))
            #expect(!name.hasPrefix("editor."))
        }
        #expect(!available.operations.contains(AgentMutationSchemas.name))
    }

    @Test(arguments: 0..<8)
    func actionExecutionNeedsBothComponentsAndActivityIsIndependent(_ mask: Int) {
        var handlers: Set<AgentOperationAvailability.Handler> = []
        if mask & 1 != 0 { handlers.insert(.operationControl) }
        if mask & 2 != 0 { handlers.insert(.actionExecution) }
        if mask & 4 != 0 { handlers.insert(.activityRead) }
        let available = AgentOperationAvailability(handlers: handlers)
        #expect(available.operations.contains("actions.run") == (mask & 3 == 3))
        #expect(available.capabilities.contains(.actionsRun) == (mask & 3 == 3))
        #expect(available.capabilities.contains(.nativeUse) == (mask & 3 == 3))
        #expect(available.operations.contains("operations.cancel") == (mask & 1 != 0))
        #expect(available.operations.contains("activity.list") == (mask & 4 != 0))
        #expect(!available.operations.contains("drafts.update"))
    }

    @Test func preferencesCanPrepareWithoutAnEditorButCannotExposeOtherWrites() {
        let available = AgentOperationAvailability(handlers: [.preferenceWrite])
        #expect(available.operations.contains(AgentMutationSchemas.name))
        #expect(available.operations.contains("preferences.update"))
        #expect(available.operations.contains("preferences.reset"))
        #expect(available.capabilities.contains(.appearanceManage))
        #expect(!available.operations.contains("drafts.update"))
        #expect(!available.operations.contains("actions.update"))
        #expect(!available.operations.contains("editor.replaceRange"))
    }

    @Test func losingDraftWriterWithdrawsWritesAndKeepsEditorReads() {
        let available = AgentOperationAvailability(handlers: [.editorRead, .editorWrite])
        #expect(available.operations.contains("editor.get"))
        #expect(!available.operations.contains("editor.replaceRange"))
        #expect(!available.operations.contains("actions.update"))
        #expect(!available.operations.contains(AgentMutationSchemas.name))
    }

    @Test(arguments: 0..<4)
    func workspaceDeletionNeedsReviewAndOperationControl(_ mask: Int) {
        var handlers: Set<AgentOperationAvailability.Handler> = []
        if mask & 1 != 0 { handlers.insert(.operationControl) }
        if mask & 2 != 0 { handlers.insert(.workspaceDelete) }
        let available = AgentOperationAvailability(handlers: handlers)
        #expect(available.operations.contains("workspaces.delete") == (mask == 3))
        #expect(available.operations.contains("mutations.prepare") == (mask == 3))
        #expect(available.capabilities.contains(.destructiveRequest) == (mask == 3))
        #expect(!available.operations.contains("drafts.update"))
        #expect(!available.operations.contains("actions.run"))
    }

    @Test(arguments: 0..<16)
    func purgeNeedsEveryConnectedComponent(_ mask: Int) {
        let components: [AgentOperationAvailability.Handler] = [.editorRead, .draftWrite, .operationControl, .draftPurge]
        let handlers = Set(components.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil })
        #expect(AgentOperationAvailability(handlers: handlers).operations.contains("drafts.purge") == (mask == 15))
    }

    @Test func workspaceApplicationHasItsOwnConnectedComponent() {
        let available = AgentOperationAvailability(handlers: [.workspaceApply])
        #expect(available.operations.contains("workspaces.apply"))
        #expect(available.operations.contains("mutations.prepare"))
        #expect(available.capabilities.contains(.workspacesApply) && available.capabilities.contains(.presentUI))
        #expect(!available.operations.contains("workspaces.update") && !available.operations.contains("editor.replaceRange"))
        #expect(!AgentOperationAvailability(handlers: [.editorRead]).operations.contains("workspaces.apply"))
    }

    @Test func backupExportAndPreviewRequireEditorTracking() {
        let untracked = AgentOperationAvailability(handlers: [])
        #expect(untracked.operations.contains("backups.validate"))
        #expect(!untracked.operations.contains("backups.export"))
        #expect(!untracked.operations.contains("backups.previewRestore"))
        let tracked = AgentOperationAvailability(handlers: [.editorRead])
        #expect(tracked.operations.isSuperset(of: AgentBackupSchemas.operationNames))
        #expect(!tracked.operations.contains("backups.requestRestore"))
    }

    @Test(arguments: 0..<4)
    func actionDeletionNeedsReviewAndOperationControl(_ mask: Int) {
        var handlers: Set<AgentOperationAvailability.Handler> = []
        if mask & 1 != 0 { handlers.insert(.operationControl) }
        if mask & 2 != 0 { handlers.insert(.actionDelete) }
        let available = AgentOperationAvailability(handlers: handlers)
        #expect(available.operations.contains("actions.delete") == (mask == 3))
        #expect(available.operations.contains("actionGroups.delete") == (mask == 3))
    }

    @Test(arguments: 0..<4)
    func previewNeedsEditorMembershipAndOperationControl(_ mask: Int) {
        var handlers: Set<AgentOperationAvailability.Handler> = []
        if mask & 1 != 0 { handlers.insert(.editorRead) }
        if mask & 2 != 0 { handlers.insert(.operationControl) }
        #expect(AgentOperationAvailability(handlers: handlers).operations.contains("editor.preview") == (mask == 3))
        #expect(AgentOperationAvailability(handlers: handlers).operations.contains("editor.navigate") == (mask == 3))
    }

    @Test(arguments: 0..<8)
    func openingNeedsEditorMembershipFactoryAndOperationControl(_ mask: Int) {
        var handlers: Set<AgentOperationAvailability.Handler> = []
        if mask & 1 != 0 { handlers.insert(.editorRead) }
        if mask & 2 != 0 { handlers.insert(.editorOpen) }
        if mask & 4 != 0 { handlers.insert(.operationControl) }
        #expect(AgentOperationAvailability(handlers: handlers).operations.contains("editor.open") == (mask == 7))
    }

    @Test(arguments: 0..<4)
    func themePresentationNeedsPreferenceStorageAndOperationControl(_ mask: Int) {
        var handlers: Set<AgentOperationAvailability.Handler> = []
        if mask & 1 != 0 { handlers.insert(.themePresentation) }
        if mask & 2 != 0 { handlers.insert(.operationControl) }
        let operations = AgentOperationAvailability(handlers: handlers).operations
        #expect(AgentThemePresentation.operationNames.isSubset(of: operations) == (mask == 3))
    }

    @Test func completeHostUsesOnlyKnownContractsAndDoesNotAdvertiseMissingHandlers() {
        let available = AgentOperationAvailability(handlers: Set(AgentOperationAvailability.Handler.allCases))
        #expect(available.operations == AgentCommandService.implementedOperations.union([
            "themes.delete", "activity.list", "operations.get", "operations.cancel", "operations.wait", "actions.run", "workspaces.delete", "drafts.purge", "actions.delete", "actionGroups.delete", "editor.preview", "editor.navigate", "editor.open"]).union(AgentNativeSchemas.operationNames).union(AgentThemePresentation.operationNames))
        #expect(available.operations.allSatisfy { AgentOperationCatalog.operation(named: $0) != nil })
        #expect(!available.operations.contains("drafts.delete"))
        #expect(!available.operations.contains("backups.restore"))
    }
}
