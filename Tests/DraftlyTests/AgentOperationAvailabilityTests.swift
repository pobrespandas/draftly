import Testing
import AgentContracts
@testable import Draftly

@Suite("Connected agent operation availability") @MainActor
struct AgentOperationAvailabilityTests {
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

    @Test func completeHostUsesOnlyKnownContractsAndDoesNotAdvertiseMissingHandlers() {
        let available = AgentOperationAvailability(handlers: Set(AgentOperationAvailability.Handler.allCases))
        #expect(available.operations == AgentCommandService.implementedOperations.union([
            "activity.list", "operations.get", "operations.cancel", "actions.run"]))
        #expect(available.operations.allSatisfy { AgentOperationCatalog.operation(named: $0) != nil })
        #expect(!available.operations.contains("drafts.delete"))
        #expect(!available.operations.contains("backups.restore"))
    }
}
