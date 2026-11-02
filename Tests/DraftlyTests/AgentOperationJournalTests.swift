import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Device-local agent operation journal") @MainActor
struct AgentOperationJournalTests {
    private struct Fixture {
        let root: URL
        let grant: AgentGrant
        let request: AgentRequest

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Journal-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: Date().addingTimeInterval(600),
                capabilities: [.actionsRun, .draftsRead], scope: .library)
            request = AgentRequest(requestID: UUID(), libraryID: grant.libraryID, operation: "actions.run",
                targets: [.init(kind: .action, id: UUID()), .init(kind: .draft, id: UUID())],
                expectedVersion: "PRIVATE-REQUEST-SENTINEL")
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func reservationSurvivesReopenWithoutStoringRequestParameters() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let original = UUID(), journal = try AgentOperationJournal(parentDirectory: f.root)
        #expect(try journal.reserve(f.request, grant: f.grant, operationID: original).isNew)
        let reopened = try AgentOperationJournal(parentDirectory: f.root)
        let reservation = try reopened.reserve(f.request, grant: f.grant, operationID: UUID())
        #expect(!reservation.isNew && reservation.record.operationID == original)
        let stored = try Data(contentsOf: f.root.appendingPathComponent("Agents/operations.json"))
        #expect(!String(decoding: stored, as: UTF8.self).contains("PRIVATE-REQUEST-SENTINEL"))
        let changed = AgentRequest(requestID: f.request.requestID, libraryID: f.grant.libraryID, operation: "actions.run",
            targets: f.request.targets, expectedVersion: "changed")
        #expect(throws: AgentErrorCode.versionConflict) {
            try reopened.reserve(changed, grant: f.grant, operationID: UUID())
        }
        #expect(try Data(contentsOf: f.root.appendingPathComponent("Agents/operations.json")) == stored)
    }

    @Test func savedEffectsAndUncertainOutcomeSurviveReopenWithOriginalGrantOnly() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root), operation = UUID()
        _ = try journal.reserve(f.request, grant: f.grant, operationID: operation)
        let snapshot = try AgentOperationRegistry.Snapshot(id: operation, state: .outcomeUnknown, updatedAt: Date(),
            output: nil, error: .outcomeUnknown,
            effects: [.init(id: UUID(), kind: "share", outcome: "completed", resources: Set(f.request.targets))]).wireValue()
        try journal.save(snapshot, operationID: operation, grant: f.grant)
        let reopened = try AgentOperationJournal(parentDirectory: f.root)
        #expect(try reopened.record(operation, grant: f.grant)?.snapshot == snapshot)
        let changed = AgentGrant(connectionID: f.grant.connectionID, libraryID: f.grant.libraryID,
            expiresAt: f.grant.expiresAt, capabilities: f.grant.capabilities, scope: f.grant.scope)
        #expect(throws: AgentErrorCode.permissionDenied) { try reopened.record(operation, grant: changed) }
        #expect(throws: AgentErrorCode.permissionDenied) {
            try reopened.reserve(f.request, grant: changed, operationID: UUID())
        }
    }

    @Test func corruptJournalIsRejectedWithoutRepair() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root)
        _ = try journal.reserve(f.request, grant: f.grant, operationID: UUID())
        let path = f.root.appendingPathComponent("Agents/operations.json"), corrupt = Data("broken".utf8)
        try corrupt.write(to: path)
        #expect(throws: AgentErrorCode.storageError) { try AgentOperationJournal(parentDirectory: f.root) }
        #expect(try Data(contentsOf: path) == corrupt)
    }

    @Test func registryReopenReturnsCompletedResultWithoutExecutingAgain() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root)
        let registry = AgentOperationRegistry(currentGrant: { _ in f.grant }, validateHost: {}, isLocked: { false }, journal: journal)
        var starts = 0
        let id = try registry.startRequest(f.request, grant: f.grant) { id in
            starts += 1
            let effect = UUID()
            try registry.recordEffect(id, effectID: effect, kind: "share", outcome: "submitted")
            try registry.recordEffect(id, effectID: effect, kind: "share", outcome: "completed")
            return .init(report: .notStarted(actionID: f.request.targets[0].id, reason: .cancelled, message: "Later cancellation"),
                noteID: nil, message: "Later cancellation")
        }
        for _ in 0..<1000 where try !registry.snapshot(id, connectionID: f.grant.connectionID).state.isTerminal { await Task.yield() }
        let original = try registry.snapshot(id, connectionID: f.grant.connectionID).wireValue()
        let reopened = AgentOperationRegistry(currentGrant: { _ in f.grant }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: f.root))
        let recovered = try reopened.snapshot(id, connectionID: f.grant.connectionID)
        #expect(recovered.state == .cancelled && recovered.effects.map(\.outcome) == ["completed"])
        #expect(try recovered.wireValue() == original)
        #expect(try reopened.existingRequest(f.request, grant: f.grant) == id)
        #expect(try reopened.startRequest(f.request, grant: f.grant) { _ in fatalError("Must not replay") } == id)
        #expect(starts == 1)
        #expect(throws: AgentErrorCode.permissionDenied) { try reopened.snapshot(id, connectionID: UUID()) }
    }

    @Test func interruptedHandoffRecoversAsUnknownAndKeepsEarlierEffects() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root), id = UUID()
        _ = try journal.reserve(f.request, grant: f.grant, operationID: id)
        let effects: [AgentOperationRegistry.Effect] = ["completed", "submitted"].map {
            .init(id: UUID(), kind: "share", outcome: $0, resources: Set(f.request.targets))
        }
        try journal.save(AgentOperationRegistry.Snapshot(id: id, state: .running, updatedAt: Date(), output: nil,
            error: nil, effects: effects).wireValue(), operationID: id, grant: f.grant)
        let registry = AgentOperationRegistry(currentGrant: { _ in f.grant }, validateHost: {}, isLocked: { false }, journal: journal)
        let result = try registry.snapshot(id, connectionID: f.grant.connectionID)
        #expect(result.state == .outcomeUnknown && result.effects.map(\.outcome) == ["completed", "unknown"])
        #expect(try registry.startRequest(f.request, grant: f.grant) { _ in fatalError("Must not replay") } == id)
        #expect(try journal.record(id, grant: f.grant)?.snapshot == result.wireValue())
        #expect(throws: AgentErrorCode.versionConflict) {
            try journal.save(AgentOperationRegistry.Snapshot(id: id, state: .running, updatedAt: Date(), output: nil,
                error: nil, effects: effects).wireValue(), operationID: id, grant: f.grant)
        }
    }
}
