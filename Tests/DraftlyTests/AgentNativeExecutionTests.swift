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

    @Test(arguments: ["native.shell", "native.appleScript", "native.shortcut"])
    func unrestrictedAutomationCannotRunUnderAResourceGrant(operation: String) throws {
        let connection = UUID(), library = UUID()
        let parameters: [String: AgentJSONValue] = operation == "native.shortcut" ? ["name": .string("QA")] : ["source": .string("neutral")]
        let request = AgentRequest(requestID: UUID(), libraryID: library, operation: operation, parameters: parameters)
        let nativeOnly = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(60),
            capabilities: [.nativeUse], scope: .library)
        #expect(throws: AgentErrorCode.permissionDenied) { try AgentNativeExecution.plan(request, grant: nativeOnly) }
        let scoped = AgentGrant(connectionID: connection, libraryID: library, expiresAt: nativeOnly.expiresAt,
            capabilities: [.nativeUse, .scriptsUnrestricted], scope: .resources([]))
        #expect(throws: AgentErrorCode.permissionDenied) { try AgentNativeExecution.plan(request, grant: scoped) }
        let all = AgentGrant(connectionID: connection, libraryID: library, expiresAt: scoped.expiresAt, capabilities: scoped.capabilities, scope: .library)
        let plan = try AgentNativeExecution.plan(request, grant: all)
        #expect(plan.effects.requiresLibraryScope && plan.effects.capabilities == all.capabilities)
        if operation == "native.shortcut" { #expect(plan.values["waitForResponse"] == .bool(true)) }
    }

    @Test func appleScriptResultKeepsDateMetadataAndRejectsInvalidPaths() throws {
        let raw = #"{"value":{"when":1700000000123.125,"record":{"$date":"literal"}},"appleScriptDatePaths":["/when"]}"#
        #expect(try AgentNativeExecution.decodedResult(raw, for: "native.appleScript") == ["valueJSON": .string(raw), "resultAvailable": .bool(true)])
        #expect(throws: (any Error).self) {
            try AgentNativeExecution.decodedResult(#"{"value":{"when":"not a date"},"appleScriptDatePaths":["/when"]}"#, for: "native.appleScript")
        }
        #expect(throws: (any Error).self) {
            try AgentNativeExecution.decodedResult(#"{"value":1,"appleScriptDatePaths":["/absent"]}"#, for: "native.appleScript")
        }
    }

    @Test(arguments: 0..<4)
    func availabilityNeedsBothNativeExecutionAndOperationControl(mask: Int) {
        var handlers: Set<AgentOperationAvailability.Handler> = []
        if mask & 1 != 0 { handlers.insert(.nativeExecution) }
        if mask & 2 != 0 { handlers.insert(.operationControl) }
        let available = AgentOperationAvailability(handlers: handlers)
        #expect(AgentNativeSchemas.operationNames.isSubset(of: available.operations) == (mask == 3))
        #expect(available.operations.contains("native.shell") == (mask == 3))
        #expect(available.capabilities.contains(.scriptsUnrestricted) == (mask == 3))
    }
}
