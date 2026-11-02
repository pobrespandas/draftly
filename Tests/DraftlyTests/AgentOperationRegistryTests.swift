import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent operation lifetime") @MainActor
struct AgentOperationRegistryTests {
    @Test func removingCompletedOperationDoesNotReplayItsRequest() async throws {
        let connection = UUID(), library = UUID(), action = UUID(), draft = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead], scope: .library)
        let registry = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false })
        let request = AgentRequest(requestID: UUID(), libraryID: library, operation: "actions.run",
            targets: [.init(kind: .action, id: action), .init(kind: .draft, id: draft)], expectedVersion: "v1")
        let id = try registry.startRequest(request, grant: grant) { _ in
            .init(report: .notStarted(actionID: action, reason: .cancelled, message: "Cancelled"), noteID: draft, message: "Cancelled")
        }
        for _ in 0..<1000 where try !registry.snapshot(id, connectionID: connection).state.isTerminal { await Task.yield() }
        try registry.removeCompleted(id, connectionID: connection)
        #expect(throws: AgentErrorCode.notFound) {
            try registry.startRequest(request, grant: grant) { _ in fatalError("Must not replay") }
        }
    }
    @Test func repeatedRequestReturnsTheSameOperationWithoutStartingWorkAgain() async throws {
        let connection = UUID(), library = UUID(), action = UUID(), draft = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead], scope: .library)
        let registry = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false })
        defer { registry.cancelAll() }
        let request = AgentRequest(requestID: UUID(), libraryID: library, operation: "actions.run",
            targets: [.init(kind: .action, id: action), .init(kind: .draft, id: draft)], expectedVersion: "v1")
        let id = try registry.startRequest(request, grant: grant) { _ in fatalError("Cancelled before starting") }
        let repeated = try registry.startRequest(request, grant: grant) { _ in fatalError("Must not start again") }
        #expect(repeated == id)
        let changed = AgentRequest(requestID: request.requestID, libraryID: library, operation: "actions.run",
            targets: request.targets, expectedVersion: "v2")
        #expect(throws: AgentErrorCode.versionConflict) {
            try registry.startRequest(changed, grant: grant) { _ in fatalError("Must not start") }
        }
        #expect(try registry.cancel(id, connectionID: connection))
        for _ in 0..<1000 where try !registry.snapshot(id, connectionID: connection).state.isTerminal { await Task.yield() }
        let snapshot = try registry.snapshot(id, connectionID: connection)
        #expect(snapshot.state == .cancelled)
        _ = try snapshot.wireValue()
    }
    @Test func cancellationWaitsForWorkAndKeepsOwnership() async throws {
        let connection = UUID(), library = UUID(), action = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead], scope: .library)
        var clock = Date()
        let registry = AgentOperationRegistry(capacity: 1, currentGrant: { _ in grant }, validateHost: {}, isLocked: { false }, now: { clock })
        var observedID: UUID?
        let id = try registry.startIdentified(grant: grant, targets: []) { operationID in
            observedID = operationID
            do { try await Task.sleep(for: .seconds(30)) } catch {}
            let report = ActionExecutionReport.notStarted(actionID: action, reason: .cancelled, message: "Cancelled")
            return .init(report: report, noteID: nil, message: "Cancelled")
        }
        for _ in 0..<100 where try registry.snapshot(id, connectionID: connection).state == .queued { await Task.yield() }
        #expect(observedID == id)
        let control = AgentRequest(requestID: UUID(), libraryID: library, operation: "operations.get",
            targets: [.init(kind: .operation, id: id)])
        #expect(try registry.control(control, connectionID: connection).snapshot.id == id)
        let foreign = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "operations.cancel",
            targets: [.init(kind: .operation, id: id)])
        #expect(throws: AgentErrorCode.permissionDenied) { try registry.control(foreign, connectionID: connection) }
        #expect(throws: AgentErrorCode.notFound) { try registry.snapshot(id, connectionID: UUID()) }
        #expect(throws: AgentErrorCode.busy) { try registry.start(grant: grant, targets: []) { fatalError() } }
        clock = clock.addingTimeInterval(1)
        try registry.setWaitingForUser(id, waiting: true)
        #expect(try registry.snapshot(id, connectionID: connection).updatedAt == clock)
        #expect(try registry.snapshot(id, connectionID: connection).state == .waitingForUser)
        _ = try registry.snapshot(id, connectionID: connection).wireValue()
        try registry.setWaitingForUser(id, waiting: false)
        #expect(try registry.cancel(id, connectionID: connection))
        #expect(try !registry.cancel(id, connectionID: connection))
        #expect(try registry.snapshot(id, connectionID: connection).state == .running)
        for _ in 0..<1000 where try registry.snapshot(id, connectionID: connection).state == .running { await Task.yield() }
        #expect(try registry.snapshot(id, connectionID: connection).state == .cancelled)
        _ = try registry.snapshot(id, connectionID: connection).wireValue()
        try registry.removeCompleted(id, connectionID: connection)
        #expect(throws: AgentErrorCode.notFound) { try registry.snapshot(id, connectionID: connection) }
    }

    @Test func unexpectedCancellationAfterStartIsUncertain() async throws {
        let connection = UUID(), library = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead], scope: .library)
        let registry = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false })
        let id = try registry.start(grant: grant, targets: []) { try await Task.sleep(for: .seconds(30)); fatalError() }
        for _ in 0..<100 where try registry.snapshot(id, connectionID: connection).state == .queued { await Task.yield() }
        #expect(try registry.cancel(id, connectionID: connection))
        for _ in 0..<1000 where try registry.snapshot(id, connectionID: connection).state == .running { await Task.yield() }
        let result = try registry.snapshot(id, connectionID: connection)
        #expect(result.state == .outcomeUnknown && result.error == .outcomeUnknown && result.output == nil)
        _ = try result.wireValue()
    }

    @Test func revokedGrantCannotReadOrCancelAnOperation() async throws {
        let connection = UUID(), library = UUID()
        let original = AgentGrant(connectionID: connection, libraryID: library, expiresAt: Date().addingTimeInterval(600),
            capabilities: [.actionsRun, .draftsRead], scope: .library)
        var grant: AgentGrant? = original
        let registry = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false })
        let id = try registry.start(grant: original, targets: []) { try await Task.sleep(for: .seconds(30)); fatalError() }
        grant = nil
        #expect(throws: AgentErrorCode.permissionDenied) { try registry.snapshot(id, connectionID: connection) }
        #expect(throws: AgentErrorCode.permissionDenied) { try registry.cancel(id, connectionID: connection) }
        registry.cancelAll()
        await Task.yield()
    }
}
