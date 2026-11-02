import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent reviewed Action execution") @MainActor
struct AgentReviewedActionExecutionTests {
    private final class Host: ActionHost {
        var shares = 0
        func supportsAsync(_ operation: String) -> Bool { operation == "share" }
        func perform(_ operation: String, values: [String: Any]) throws -> Any? {
            if operation == "device" { return ["systemName": "macOS", "model": "Mac", "systemVersion": "test"] }
            throw AgentErrorCode.unavailable
        }
        func performAsync(_ operation: String, payload: String) async throws -> String {
            guard operation == "share" else { throw AgentErrorCode.unavailable }
            shares += 1
            return "{\"value\":true}"
        }
    }

    @Test func actionWaitsForReviewedShareBeforeNativeEffect() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let action = DraftAction(name: "Share", steps: [ActionStep("share", ["template": "[[draft]]"])])
        try library.saveAction(action)
        let model = WindowModel(library: library); model.select(note.id)
        let connection = UUID(), libraryID = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: libraryID, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead, .draftsWrite, .nativeUse], scope: .library)
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {}, isLocked: { false },
            draftExists: { $0 == note.id }, targetDraftID: note.id, editorDraftID: { model.editor.noteID },
            approvedActions: [action.id: action], currentAction: { id in library.actions.first { $0.id == id } },
            reviewedNativeEffects: true)
        let approvals = AgentApprovalStore(currentGrant: { $0 == connection ? grant : nil }, isLocked: { false })
        let request = AgentRequest(requestID: UUID(), libraryID: libraryID, operation: "actions.run",
            targets: [.init(kind: .action, id: action.id), .init(kind: .draft, id: note.id)], expectedVersion: "v1")
        let host = Host()
        let task = Task { @MainActor in
            try await AgentReviewedActionExecution.run(action: action, draftID: note.id, request: request,
                connectionID: connection, library: library, models: [model], host: host, authority: authority,
                approvals: approvals, currentSnapshot: { ["actionVersion": .string("v1"), "draftVersion": .string("d1")] },
                resolveModel: { models, _ in models.first })
        }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        #expect(host.shares == 0 && review.effects.snapshot["nativeOperation"] == .string("share"))
        try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        let result = try await task.value
        #expect(result.report.reason == .success && host.shares == 1 && !result.outcomeUnknown)
        #expect(try approvals.statusForConnection(review.id, connectionID: connection) == .consumed)
    }

    @Test func changedDraftVersionStopsReviewedEffect() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let action = DraftAction(name: "Share", steps: [ActionStep("share", ["template": "[[draft]]"])])
        try library.saveAction(action)
        let model = WindowModel(library: library); model.select(note.id)
        let connection = UUID(), libraryID = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: libraryID, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead, .draftsWrite, .nativeUse], scope: .library)
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {}, isLocked: { false },
            draftExists: { $0 == note.id }, targetDraftID: note.id, editorDraftID: { model.editor.noteID },
            approvedActions: [action.id: action], currentAction: { id in library.actions.first { $0.id == id } },
            reviewedNativeEffects: true)
        let approvals = AgentApprovalStore(currentGrant: { _ in grant }, isLocked: { false })
        let request = AgentRequest(requestID: UUID(), libraryID: libraryID, operation: "actions.run",
            targets: [.init(kind: .action, id: action.id), .init(kind: .draft, id: note.id)], expectedVersion: "v1")
        let host = Host()
        var draftVersion = "d1"
        let task = Task { @MainActor in
            try await AgentReviewedActionExecution.run(action: action, draftID: note.id, request: request,
                connectionID: connection, library: library, models: [model], host: host, authority: authority,
                approvals: approvals, currentSnapshot: { ["actionVersion": .string("v1"), "draftVersion": .string(draftVersion)] },
                resolveModel: { models, _ in models.first })
        }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        draftVersion = "d2"
        let result = try await task.value
        #expect(result.report.reason == .error && host.shares == 0 && !result.outcomeUnknown)
        #expect(try approvals.statusForConnection(review.id, connectionID: connection) == .invalidated)
    }
}
