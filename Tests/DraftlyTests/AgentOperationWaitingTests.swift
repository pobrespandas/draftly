import Foundation
import Testing
import AgentContracts
import AgentLocalTransport
@testable import Draftly

@Suite("Authorized operation waiting") @MainActor
struct AgentOperationWaitingTests {
    @MainActor private final class Fixture {
        let connection = UUID(), library = UUID(), window = UUID(), draft = UUID()
        let gate = AsyncStream<Void>.makeStream()
        var current: AgentGrant?
        var locked = false
        var starts = 0
        let maximumWaiters: Int
        lazy var original = AgentGrant(connectionID: connection, libraryID: library,
            expiresAt: Date().addingTimeInterval(600), capabilities: [.presentUI, .draftsRead],
            scope: .resources([.init(kind: .window, id: window), .init(kind: .draft, id: draft)]))
        lazy var registry = AgentOperationRegistry(maximumWaiters: maximumWaiters,
            currentGrant: { [unowned self] id in id == self.connection ? self.current : nil },
            validateHost: {}, isLocked: { [unowned self] in self.locked })
        init(maximumWaiters: Int = 16) { self.maximumWaiters = maximumWaiters }
        func start() throws -> UUID {
            current = original
            let request = AgentRequest(requestID: UUID(), libraryID: library, operation: "editor.preview",
                targets: [.init(kind: .window, id: window)], parameters: ["visible": .bool(true)])
            return try registry.startValueRequest(request, grant: original) { [self] _ in
                starts += 1
                for await _ in gate.stream { break }
                try Task.checkCancellation()
                return ["windowID": .string(window.uuidString), "draftID": .string(draft.uuidString), "visible": .bool(true)]
            }
        }
        func request(_ id: UUID, seconds: Int64 = 1) -> AgentRequest {
            AgentRequest(requestID: UUID(), libraryID: library, operation: "operations.wait",
                targets: [.init(kind: .operation, id: id)], parameters: ["timeoutSeconds": .integer(seconds)])
        }
        func cleanup() { registry.cancelAll(); gate.continuation.finish() }
    }

    @Test func waitObservesCompletionAndReturnsACompletedResultWithoutReplaying() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let id = try f.start()
        let result = try await f.registry.wait(f.request(id), connectionID: f.connection,
            validateSession: {}, uptime: { 0 }, sleep: {
                f.gate.continuation.yield()
                try await Task.sleep(for: .milliseconds(1))
            })
        #expect(result.snapshot.state == .succeeded && !result.waitExpired && f.starts == 1)
        let repeated = try await f.registry.wait(f.request(id), connectionID: f.connection,
            validateSession: {}, sleep: { Issue.record("A completed operation must not sleep") })
        #expect(try repeated.snapshot.wireValue() == result.snapshot.wireValue())
        #expect(!repeated.waitExpired && f.starts == 1 && f.registry.activeWaitCount == 0)
    }

    @Test func reviewAttentionReturnsWithoutApprovingOrCancellingWork() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let id = try f.start()
        for _ in 0..<1000 where try f.registry.snapshot(id, connectionID: f.connection).state == .queued { await Task.yield() }
        try f.registry.setWaitingForUser(id, waiting: true)
        let result = try await f.registry.wait(f.request(id), connectionID: f.connection,
            validateSession: {}, sleep: { Issue.record("A pending review must be reported immediately") })
        #expect(result.snapshot.state == .waitingForUser && !result.waitExpired)
        #expect(try f.registry.snapshot(id, connectionID: f.connection).state == .waitingForUser)
    }

    @Test func waitExpiryDoesNotTimeOutTheOperation() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let id = try f.start()
        var tick: TimeInterval = 100
        let result = try await f.registry.wait(f.request(id), connectionID: f.connection,
            validateSession: {}, uptime: { tick }, sleep: { tick += 1; await Task.yield() })
        #expect(result.waitExpired && !result.snapshot.state.isTerminal && result.snapshot.error == nil)
        #expect(f.registry.activeWaitCount == 0)
        f.gate.continuation.yield()
        let completed = try await f.registry.wait(f.request(id), connectionID: f.connection, validateSession: {})
        #expect(completed.snapshot.state == .succeeded && !completed.waitExpired)
    }

    @Test func cancellationAndCapacityLimitOnlyAffectTheObserver() async throws {
        let f = Fixture(maximumWaiters: 1); defer { f.cleanup() }
        let id = try f.start()
        let waiter = Task { try await f.registry.wait(f.request(id), connectionID: f.connection, validateSession: {}) }
        for _ in 0..<1000 where f.registry.activeWaitCount == 0 { await Task.yield() }
        #expect(f.registry.activeWaitCount == 1)
        await #expect(throws: AgentErrorCode.busy) {
            try await f.registry.wait(f.request(id), connectionID: f.connection, validateSession: {})
        }
        waiter.cancel()
        await #expect(throws: AgentErrorCode.cancelled) { try await waiter.value }
        #expect(f.registry.activeWaitCount == 0)
        #expect(try !f.registry.snapshot(id, connectionID: f.connection).state.isTerminal)
    }

    @Test(arguments: ["revoked", "replaced", "scope", "lock"])
    func waitRechecksLiveAuthorityAfterSuspension(interruption: String) async throws {
        let f = Fixture(); defer { f.cleanup() }
        let id = try f.start()
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await f.registry.wait(f.request(id), connectionID: f.connection, validateSession: {}, sleep: {
                switch interruption {
                case "revoked": f.current = nil
                case "lock": f.locked = true
                default:
                    f.current = AgentGrant(connectionID: f.connection, libraryID: f.library,
                        expiresAt: f.original.expiresAt, capabilities: f.original.capabilities,
                        scope: interruption == "scope" ? .resources([]) : f.original.scope,
                        grantID: interruption == "replaced" ? UUID() : f.original.grantID)
                }
                await Task.yield()
            })
        }
        #expect(f.registry.activeWaitCount == 0)
    }

    @Test func monotonicRollbackCannotExtendAnObserverWait() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let id = try f.start()
        var tick: TimeInterval = 100
        await #expect(throws: AgentErrorCode.timeout) {
            try await f.registry.wait(f.request(id), connectionID: f.connection, validateSession: {},
                uptime: { tick }, sleep: { tick = 99; await Task.yield() })
        }
        #expect(f.registry.activeWaitCount == 0)
    }

    @Test func transportBudgetIncludesTheMaximumWaitAndKeepsTheNormalBaseline() {
        let f = Fixture(), id = UUID()
        #expect(AgentLocalClient.responseTimeout(for: f.request(id, seconds: 30)) == 35)
        #expect(AgentLocalClient.responseTimeout(for: f.request(id, seconds: 1)) == 30)
        #expect(AgentLocalClient.responseTimeout(for: f.request(id, seconds: 31)) == 30)
        let status = AgentRequest(requestID: UUID(), libraryID: f.library, operation: "server.status")
        #expect(AgentLocalClient.responseTimeout(for: status) == 30)
    }
}
