import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent native effect review") @MainActor
struct AgentNativeEffectApprovalTests {
    private final class Host: ActionHost {
        var calls = 0
        func supportsAsync(_ operation: String) -> Bool { true }
        func perform(_ operation: String, values: [String: Any]) throws -> Any? { calls += 1; return nil }
        func performAsync(_ operation: String, payload: String) async throws -> String { calls += 1; return "done" }
    }

    @Test func approvedEffectRunsOnceWithConcreteDetails() async throws {
        let connection = UUID(), library = UUID(), action = UUID(), draft = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead, .nativeUse], scope: .library)
        let store = AgentApprovalStore(currentGrant: { $0 == connection ? grant : nil }, isLocked: { false })
        let request = AgentRequest(requestID: UUID(), libraryID: library, operation: "actions.run",
            targets: [.init(kind: .action, id: action), .init(kind: .draft, id: draft)], expectedVersion: "v1")
        let host = Host()
        let guarded = AgentAuthorizedActionHost(host: host, approve: { operation, values in
            try await AgentNativeEffectApproval.wait(store: store, request: request, connectionID: connection,
                operation: operation, values: values, currentSnapshot: { ["actionVersion": .string("v1")] })
        }, authorize: { _, _ in })
        let task = Task { @MainActor in try await guarded.performAsync("share", payload: "{\"text\":\"neutral\"}") }
        for _ in 0..<100 where store.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(store.pendingFromUserInterface().first)
        #expect(review.effects.snapshot["nativeOperation"] == .string("share"))
        #expect(review.effects.snapshot["nativeParameters"] == .object(["text": .string("neutral")]))
        #expect(host.calls == 0)
        try store.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        #expect(try await task.value == "done")
        #expect(host.calls == 1)
        #expect(try store.statusForConnection(review.id, connectionID: connection) == .consumed)
    }

    @Test func unclassifiedEffectNeverCreatesAReview() async throws {
        let connection = UUID(), library = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead, .nativeUse], scope: .library)
        let store = AgentApprovalStore(currentGrant: { _ in grant }, isLocked: { false })
        let request = AgentRequest(requestID: UUID(), libraryID: library, operation: "actions.run")
        await #expect(throws: AgentErrorCode.unavailable) {
            try await AgentNativeEffectApproval.wait(store: store, request: request, connectionID: connection,
                operation: "unknown", values: [:], currentSnapshot: { [:] })
        }
        #expect(store.pendingFromUserInterface().isEmpty)
    }

    @Test func unrestrictedEffectNeedsItsOwnCapability() async throws {
        let connection = UUID(), library = UUID(), action = UUID(), draft = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead, .nativeUse], scope: .library)
        let store = AgentApprovalStore(currentGrant: { _ in grant }, isLocked: { false })
        let request = AgentRequest(requestID: UUID(), libraryID: library, operation: "actions.run",
            targets: [.init(kind: .action, id: action), .init(kind: .draft, id: draft)], expectedVersion: "v1")
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await AgentNativeEffectApproval.wait(store: store, request: request, connectionID: connection,
                operation: "appleScript", values: ["source": "return 1"], currentSnapshot: { [:] })
        }
        #expect(store.pendingFromUserInterface().isEmpty)
    }
}
