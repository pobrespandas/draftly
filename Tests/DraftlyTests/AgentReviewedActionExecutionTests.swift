import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent reviewed Action execution") @MainActor
struct AgentReviewedActionExecutionTests {
    @Test func executionEditorSelectionCannotUseAnotherDraftWindow() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "First"), second = try library.createNote(content: "Second")
        let firstModel = WindowModel(library: library), secondModel = WindowModel(library: library)
        firstModel.select(first.id); secondModel.select(second.id)
        let registry = AgentEditorRegistry(library: library, models: { [firstModel, secondModel] })
        let snapshots = try registry.windowSnapshots()
        let secondWindow = try #require(snapshots.first { $0.draftID == second.id })
        let selected = try registry.executionModels(draftID: first.id)
        #expect(selected.count == 1 && selected.first === firstModel)
        #expect(throws: AgentErrorCode.notFound) {
            try registry.executionModels(draftID: first.id, windowID: secondWindow.id)
        }
        registry.invalidate()
        #expect(throws: AgentErrorCode.cancelled) { try registry.executionModels(draftID: first.id) }
    }
    @Test func executionIdentityCannotMoveAcrossConnectionsLibrariesOrDrafts() throws {
        let connection = UUID(), library = UUID(), draft = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead], scope: .library)
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {}, isLocked: { false },
            draftExists: { $0 == draft }, targetDraftID: draft)
        let request = AgentRequest(requestID: UUID(), libraryID: library, operation: "actions.run")
        try authority.validateRequestIdentity(request, connectionID: connection, draftID: draft)
        #expect(throws: AgentErrorCode.permissionDenied) {
            try authority.validateRequestIdentity(request, connectionID: UUID(), draftID: draft)
        }
        #expect(throws: AgentErrorCode.permissionDenied) {
            try authority.validateRequestIdentity(request, connectionID: connection, draftID: UUID())
        }
        let other = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "actions.run")
        #expect(throws: AgentErrorCode.permissionDenied) {
            try authority.validateRequestIdentity(other, connectionID: connection, draftID: draft)
        }
    }
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
            targets: [.init(kind: .action, id: action.id), .init(kind: .draft, id: note.id)], expectedVersion: "v1", parameters: ["interactive": .bool(true)])
        let host = Host()
        var waiting: [Bool] = []
        let operations = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false })
        let operationID = try operations.startIdentified(grant: grant, targets: Set(request.targets)) { id in
            try await AgentReviewedActionExecution.run(action: action, draftID: note.id, request: request,
                connectionID: connection, library: library, models: [model], host: host, authority: authority,
                approvals: approvals, currentSnapshot: { ["actionVersion": .string("v1"), "draftVersion": .string("d1")] },
                waitingForUser: { waiting.append($0); try operations.setWaitingForUser(id, waiting: $0) },
                resolveModel: { models, _ in models.first })
        }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        #expect(host.shares == 0 && review.effects.snapshot["nativeOperation"] == .string("share"))
        #expect(waiting == [true])
        #expect(try operations.snapshot(operationID, connectionID: connection).state == .waitingForUser)
        try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        for _ in 0..<1000 {
            if try operations.snapshot(operationID, connectionID: connection).state.isTerminal { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let snapshot = try operations.snapshot(operationID, connectionID: connection)
        let result = try #require(snapshot.output)
        #expect(snapshot.state == .succeeded)
        #expect(result.report.reason == .success && host.shares == 1 && !result.outcomeUnknown)
        #expect(waiting == [true, false])
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
            targets: [.init(kind: .action, id: action.id), .init(kind: .draft, id: note.id)], expectedVersion: "v1", parameters: ["interactive": .bool(true)])
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
