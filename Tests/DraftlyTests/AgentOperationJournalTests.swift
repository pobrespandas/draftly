import Foundation
import Testing
import AgentContracts
import AgentLocalSecurity
import DraftlyCore
@testable import Draftly

@Suite("Device-local agent operation journal") @MainActor
struct AgentOperationJournalTests {
    private final class Host: ActionHost {
        var calls = 0
        func perform(_ operation: String, values: [String: Any]) throws -> Any? { throw AgentErrorCode.unavailable }
        func supportsAsync(_ operation: String) -> Bool { true }
        func performAsync(_ operation: String, payload: String) async throws -> String {
            calls += 1; return "{\"value\":true}"
        }
    }
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

    private func previewFixture() throws -> (Fixture, AgentGrant, AgentRequest, [String: AgentJSONValue]) {
        let f = try Fixture(), window = UUID(), draft = UUID()
        let targets: Set<AgentResourceReference> = [.init(kind: .window, id: window), .init(kind: .draft, id: draft)]
        let grant = AgentGrant(connectionID: f.grant.connectionID, libraryID: f.grant.libraryID,
            expiresAt: f.grant.expiresAt, capabilities: [.presentUI, .draftsRead], scope: .resources(targets))
        let request = AgentRequest(requestID: UUID(), libraryID: grant.libraryID, operation: "editor.preview",
            targets: [.init(kind: .window, id: window)], parameters: ["visible": .bool(true)])
        return (f, grant, request, ["windowID": .string(window.uuidString), "draftID": .string(draft.uuidString), "visible": .bool(true)])
    }

    @Test func nonActionResultSurvivesRestartWithoutActionPermissionOrReplay() async throws {
        let (f, grant, request, result) = try previewFixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root)
        let first = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false }, journal: journal)
        var starts = 0
        let id = try first.startValueRequest(request, grant: grant) { _ in starts += 1; return result }
        for _ in 0..<1000 where try !first.snapshot(id, connectionID: grant.connectionID).state.isTerminal { await Task.yield() }
        let original = try first.snapshot(id, connectionID: grant.connectionID)
        #expect(original.state == .succeeded && original.name == "editor.preview" && original.result == .object(result))
        guard case .object(let fields) = try original.wireValue() else { Issue.record("Missing operation"); return }
        #expect(fields["actionReport"] == .null)
        let second = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: f.root))
        #expect(try second.startValueRequest(request, grant: grant) { _ in starts += 1; return result } == id)
        let restored = try second.snapshot(id, connectionID: grant.connectionID)
        #expect(restored.name == "editor.preview" && restored.result == .object(result))
        #expect(try restored.wireValue() == original.wireValue())
        #expect(starts == 1)
    }

    @Test func interruptedNonActionReservationRecoversAsUnknownWithoutStarting() throws {
        let (f, grant, request, result) = try previewFixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root), id = UUID()
        _ = try journal.reserve(request, grant: grant, operationID: id)
        let reopened = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: f.root))
        #expect(try reopened.startValueRequest(request, grant: grant) { _ in Issue.record("Unexpected replay"); return result } == id)
        let snapshot = try reopened.snapshot(id, connectionID: grant.connectionID)
        #expect(snapshot.state == .outcomeUnknown && snapshot.name == "editor.preview" && snapshot.result == nil)
        _ = try snapshot.wireValue()
    }

    @Test func genericResultCannotChangeItsReservedOperationName() throws {
        let (f, grant, request, _) = try previewFixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root), id = UUID()
        _ = try journal.reserve(request, grant: grant, operationID: id)
        let path = f.root.appendingPathComponent("Agents/operations.json"), original = try Data(contentsOf: path)
        let wrong = try AgentOperationRegistry.Snapshot(id: id, state: .outcomeUnknown, updatedAt: Date(),
            output: nil, error: .outcomeUnknown, effects: [], name: "themes.reload").wireValue()
        #expect(throws: AgentErrorCode.invalidInput) { try journal.save(wrong, operationID: id, grant: grant) }
        #expect(try Data(contentsOf: path) == original)
    }

    @Test func malformedNonActionResultCannotBeSavedAsSuccess() throws {
        let (f, grant, request, _) = try previewFixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root), id = UUID()
        _ = try journal.reserve(request, grant: grant, operationID: id)
        let path = f.root.appendingPathComponent("Agents/operations.json"), original = try Data(contentsOf: path)
        let malformed = try AgentOperationRegistry.Snapshot(id: id, state: .succeeded, updatedAt: Date(),
            output: nil, error: nil, effects: [], name: "editor.preview", result: .object([:])).wireValue()
        #expect(throws: (any Error).self) { try journal.save(malformed, operationID: id, grant: grant) }
        #expect(try Data(contentsOf: path) == original)
    }

    @Test func legacyActionReservationWithoutNameRemainsReadable() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let id = UUID(), journal = try AgentOperationJournal(parentDirectory: f.root)
        _ = try journal.reserve(f.request, grant: f.grant, operationID: id)
        let path = f.root.appendingPathComponent("Agents/operations.json")
        var records = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [[String: Any]])
        records[0].removeValue(forKey: "operationName")
        try JSONSerialization.data(withJSONObject: records).write(to: path)
        let registry = AgentOperationRegistry(currentGrant: { _ in f.grant }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: f.root))
        let value = try registry.snapshot(id, connectionID: f.grant.connectionID)
        #expect(value.name == "actions.run" && value.state == .outcomeUnknown)
        _ = try value.wireValue()
    }

    @Test func stopWorkPreservesCompletedNonActionEffectsAndDoesNotReplay() async throws {
        let (f, grant, request, result) = try previewFixture(); defer { f.cleanup() }
        let registry = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: f.root))
        var starts = 0
        let id = try registry.startValueRequest(request, grant: grant) { id in
            starts += 1
            let effect = UUID()
            try registry.recordEffect(id, effectID: effect, kind: "preview", outcome: "submitted")
            try registry.recordEffect(id, effectID: effect, kind: "preview", outcome: "completed")
            while !Task.isCancelled { await Task.yield() }
            throw CancellationError()
        }
        for _ in 0..<1000 where try registry.snapshot(id, connectionID: grant.connectionID).effects.isEmpty { await Task.yield() }
        registry.cancelAll()
        for _ in 0..<1000 where try !registry.snapshot(id, connectionID: grant.connectionID).state.isTerminal { await Task.yield() }
        let snapshot = try registry.snapshot(id, connectionID: grant.connectionID)
        #expect(snapshot.state == .outcomeUnknown && snapshot.result == nil)
        #expect(snapshot.effects.map(\.outcome) == ["completed"])
        #expect(try registry.startValueRequest(request, grant: grant) { _ in starts += 1; return result } == id)
        #expect(starts == 1)
    }

    @Test func queuedNonActionCancellationDoesNotStartWorkOrCreateAnActionReport() async throws {
        let (f, grant, request, result) = try previewFixture(); defer { f.cleanup() }
        let registry = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: f.root))
        var starts = 0
        let id = try registry.startValueRequest(request, grant: grant) { _ in starts += 1; return result }
        registry.cancelAll()
        for _ in 0..<1000 where try !registry.snapshot(id, connectionID: grant.connectionID).state.isTerminal { await Task.yield() }
        let snapshot = try registry.snapshot(id, connectionID: grant.connectionID)
        #expect(starts == 0 && snapshot.state == .cancelled)
        guard case .object(let fields) = try snapshot.wireValue() else { Issue.record("Missing snapshot"); return }
        #expect(fields["actionReport"] == .null && fields["result"] == .null)
    }

    @Test func revokedValueGrantCannotReadItsRecoveredResult() async throws {
        let (f, grant, request, result) = try previewFixture(); defer { f.cleanup() }
        var current: AgentGrant? = grant
        let registry = AgentOperationRegistry(currentGrant: { _ in current }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: f.root))
        let id = try registry.startValueRequest(request, grant: grant) { _ in result }
        for _ in 0..<1000 where try !registry.snapshot(id, connectionID: grant.connectionID).state.isTerminal { await Task.yield() }
        current = nil
        #expect(throws: AgentErrorCode.permissionDenied) { try registry.snapshot(id, connectionID: grant.connectionID) }
        let recovered = AgentOperationRegistry(currentGrant: { _ in current }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: f.root))
        #expect(throws: AgentErrorCode.permissionDenied) { try recovered.snapshot(id, connectionID: grant.connectionID) }
    }

    @Test func missingPermissionRejectsGenericWorkBeforeReservation() throws {
        let (f, approved, request, result) = try previewFixture(); defer { f.cleanup() }
        let grant = AgentGrant(connectionID: approved.connectionID, libraryID: approved.libraryID,
            expiresAt: approved.expiresAt, capabilities: [.draftsRead], scope: approved.scope)
        let registry = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: f.root))
        #expect(throws: AgentErrorCode.permissionDenied) {
            try registry.startValueRequest(request, grant: grant) { _ in Issue.record("Unexpected work"); return result }
        }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Agents/operations.json").path))
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

    @Test func unavailableReservationStoragePreventsExecution() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root)
        let directory = try AgentStateDirectory(parentDirectory: f.root)
        let obstruction = try directory.acquireLock("operations.lock")
        let registry = AgentOperationRegistry(currentGrant: { _ in f.grant }, validateHost: {}, isLocked: { false }, journal: journal)
        #expect(throws: AgentErrorCode.busy) {
            try registry.startRequest(f.request, grant: f.grant) { _ in fatalError("Must not execute") }
        }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Agents/operations.json").path))
        withExtendedLifetime(obstruction) {}
    }

    @Test func fullJournalRejectsNewWorkWithoutDroppingOldRequestIdentities() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root)
        var first: (request: AgentRequest, operation: UUID)?
        for _ in 0..<128 {
            let request = AgentRequest(requestID: UUID(), libraryID: f.grant.libraryID, operation: "actions.run",
                targets: f.request.targets, expectedVersion: f.request.expectedVersion)
            let operation = UUID()
            _ = try journal.reserve(request, grant: f.grant, operationID: operation)
            if first == nil { first = (request, operation) }
        }
        let path = f.root.appendingPathComponent("Agents/operations.json"), before = try Data(contentsOf: path)
        #expect(throws: AgentErrorCode.busy) { try journal.reserve(f.request, grant: f.grant, operationID: UUID()) }
        #expect(try Data(contentsOf: path) == before)
        let original = try #require(first), reopened = try AgentOperationJournal(parentDirectory: f.root)
        let recovered = try reopened.reserve(original.request, grant: f.grant, operationID: UUID())
        #expect(!recovered.isNew && recovered.record.operationID == original.operation)
        #expect(try Data(contentsOf: path) == before)
    }

    @Test func journalCapacityIsGlobalAndSurvivesConnectionReplacement() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root)
        var first: (request: AgentRequest, operation: UUID)?
        for _ in 0..<128 {
            let request = AgentRequest(requestID: UUID(), libraryID: f.grant.libraryID,
                operation: "actions.run", targets: f.request.targets,
                expectedVersion: f.request.expectedVersion)
            let operation = UUID()
            _ = try journal.reserve(request, grant: f.grant, operationID: operation)
            if first == nil { first = (request, operation) }
        }
        let replacement = AgentGrant(connectionID: UUID(), libraryID: f.grant.libraryID,
            expiresAt: f.grant.expiresAt, capabilities: f.grant.capabilities, scope: f.grant.scope)
        let request = AgentRequest(requestID: UUID(), libraryID: replacement.libraryID,
            operation: "actions.run", targets: f.request.targets,
            expectedVersion: f.request.expectedVersion)
        let reopened = try AgentOperationJournal(parentDirectory: f.root)
        let registry = AgentOperationRegistry(currentGrant: { id in
            id == replacement.connectionID ? replacement : nil
        }, validateHost: {}, isLocked: { false }, journal: reopened)
        #expect(throws: AgentErrorCode.busy) {
            try registry.startRequest(request, grant: replacement) { _ in
                Issue.record("Full journal must not submit an effect")
                throw AgentErrorCode.unavailable
            }
        }
        let original = try #require(first)
        let recovered = try reopened.reserve(original.request, grant: f.grant, operationID: UUID())
        #expect(!recovered.isNew && recovered.record.operationID == original.operation)
    }

    @Test(arguments: [false, true])
    func storageFailureAroundNativeHandoffCannotReplayAfterReopen(afterHandoff: Bool) async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let journal = try AgentOperationJournal(parentDirectory: f.root)
        let directory = try AgentStateDirectory(parentDirectory: f.root)
        var obstruction: AgentStateFileLock?
        let registry = AgentOperationRegistry(currentGrant: { _ in f.grant }, validateHost: {}, isLocked: { false }, journal: journal)
        let host = Host()
        let id = try registry.startRequest(f.request, grant: f.grant) { id in
            if !afterHandoff { obstruction = try directory.acquireLock("operations.lock") }
            let guarded = AgentAuthorizedActionHost(host: host,
                recordEffect: { try registry.recordEffect(id, effectID: $0, kind: $1, outcome: $2) }, authorize: { _, _ in })
            if afterHandoff {
                _ = try await guarded.performAsync("share", payload: "{}")
                obstruction = try directory.acquireLock("operations.lock")
            } else {
                await #expect(throws: AgentErrorCode.busy) { try await guarded.performAsync("share", payload: "{}") }
            }
            return .init(report: .notStarted(actionID: f.request.targets[0].id, reason: .cancelled, message: "Cancelled"),
                noteID: nil, message: "Cancelled")
        }
        for _ in 0..<1000 where try !registry.snapshot(id, connectionID: f.grant.connectionID).state.isTerminal { await Task.yield() }
        #expect(try registry.snapshot(id, connectionID: f.grant.connectionID).state == .outcomeUnknown)
        #expect(host.calls == (afterHandoff ? 1 : 0))
        #expect(obstruction != nil)
        obstruction = nil
        let reopened = AgentOperationRegistry(currentGrant: { _ in f.grant }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: f.root))
        let recovered = try reopened.snapshot(id, connectionID: f.grant.connectionID)
        #expect(recovered.state == .outcomeUnknown)
        #expect(recovered.effects.map(\.outcome) == (afterHandoff ? ["completed"] : []))
        #expect(try reopened.startRequest(f.request, grant: f.grant) { _ in fatalError("Must not replay") } == id)
        #expect(host.calls == (afterHandoff ? 1 : 0))
    }
}
