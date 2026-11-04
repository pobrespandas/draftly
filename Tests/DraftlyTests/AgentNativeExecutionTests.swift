import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Native operation authority") @MainActor
struct AgentNativeExecutionTests {
    @Test(arguments: ["https://example.com/café", "draftly://create?text=neutral"])
    func applicationURLsNeedUnrestrictedCapabilityAndLibraryScope(url: String) throws {
        let connection = UUID(), library = UUID()
        let request = AgentRequest(requestID: UUID(), libraryID: library, operation: "native.openURL", parameters: ["url": .string(url)])
        let scoped = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(60),
            capabilities: [.nativeUse], scope: .resources([]))
        if url.hasPrefix("https:") {
            let value = try AgentNativeExecution.plan(request, grant: scoped)
            #expect(!value.effects.requiresLibraryScope && value.effects.capabilities == [.nativeUse])
        } else {
            #expect(throws: AgentErrorCode.permissionDenied) { try AgentNativeExecution.plan(request, grant: scoped) }
            let capable = AgentGrant(connectionID: connection, libraryID: library, expiresAt: scoped.expiresAt,
                capabilities: [.nativeUse, .scriptsUnrestricted], scope: .resources([]))
            #expect(throws: AgentErrorCode.permissionDenied) { try AgentNativeExecution.plan(request, grant: capable) }
            let libraryGrant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: scoped.expiresAt,
                capabilities: capable.capabilities, scope: .library)
            let value = try AgentNativeExecution.plan(request, grant: libraryGrant)
            #expect(value.effects.requiresLibraryScope && value.effects.capabilities == capable.capabilities)
        }
    }

    @Test(arguments: 0..<4)
    func availabilityNeedsBothNativeExecutionAndOperationControl(mask: Int) {
        var handlers: Set<AgentOperationAvailability.Handler> = []
        if mask & 1 != 0 { handlers.insert(.nativeExecution) }
        if mask & 2 != 0 { handlers.insert(.operationControl) }
        let available = AgentOperationAvailability(handlers: handlers)
        #expect(AgentNativeSchemas.operationNames.isSubset(of: available.operations) == (mask == 3))
        #expect(!available.operations.contains("native.shell"))
        #expect(available.capabilities.contains(.scriptsUnrestricted) == (mask == 3))
    }
}
