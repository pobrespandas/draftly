import Foundation
import Testing
import AgentContracts
import AgentLocalTransport
@testable import DraftlyCore
@testable import Draftly

@Suite("Pairing over the private agent socket") @MainActor
struct AgentPairingTransportTests {
    @MainActor private final class Fixture {
        let library: LibraryStore
        let libraryID = UUID()
        @MainActor final class State {
            var metadata: Data?
            var credentials: [UUID: Data] = [:]
            var reads = 0
            var wall = Date()
            var elapsed: TimeInterval = 100
            var locked = false
            var failWrite = false
        }
        let state = State()
        lazy var registry: AgentConnectionRegistry = {
            let state = state
            return AgentConnectionRegistry(metadata: .init(read: { state.metadata }, replace: { value, expected in
                guard !state.failWrite else { throw AgentErrorCode.storageError }
                guard state.metadata == expected else { throw AgentErrorCode.versionConflict }
                state.metadata = value
            }), credentials: .init(read: { id in state.reads += 1; return state.credentials[id] },
                create: { state.credentials[$0] = $1 }, remove: { state.credentials.removeValue(forKey: $0) }),
                now: { state.wall }, authorityChanged: { _ in })
        }()
        lazy var pairing: AgentPairingCoordinator = {
            let state = state, library = library
            return AgentPairingCoordinator(registry: registry, libraryID: libraryID,
                now: { state.wall }, uptime: { state.elapsed }, validateHost: {}, isLocked: { state.locked }, resolveTargets: { targets in
                    Set(targets.filter { target in target.kind == .draft && library.notes.contains { $0.id == target.id } })
                })
        }()
        func service() throws -> AgentCommandService {
            let state = state
            return try AgentCommandService(library: library, libraryID: libraryID, connections: registry,
                appVersion: "Neutral QA", validateHost: {}, isLocked: { state.locked }, pendingEditorGeneration: { _ in "" })
        }
        init() throws { library = try LibraryStore(inMemory: true, seed: false); try registry.setEnabledFromUserInterface(true) }
        func broker(pairingEnabled: Bool = true) throws -> AgentSocketBroker {
            try AgentSocketBroker(service: try service(), parentDirectory: FileManager.default.temporaryDirectory,
                pairing: pairingEnabled ? pairing : nil, validateHelper: { _ in })
        }
        func client(_ broker: AgentSocketBroker) async throws -> AgentPairingClient {
            try await AgentPairingClient.connect(path: broker.path, name: "Neutral 🐼", validateServer: { _ in })
        }
        func approve(_ client: AgentPairingClient, scope: AgentResourceScope = .resources([])) async throws -> AgentConnectionRecord {
            let challenge = await client.challenge
            let id = try #require(challenge.pairingID), code = try #require(challenge.code)
            let review = try pairing.prepareReviewFromUserInterface(id, name: "My neutral client", scope: scope)
            return try pairing.approveFromUserInterface(id, reviewID: review.id, displayedChallenge: code)
        }
    }

    @Test func pendingPollingAndCancellationNeverCreateOrReadCredentials() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let client = try await f.client(broker)
        let challenge = await client.challenge
        #expect(challenge.code != nil && challenge.state == nil)
        #expect(f.pairing.pendingFromUserInterface().count == 1)
        #expect(try await client.poll().state == .pending)
        #expect(f.state.credentials.isEmpty && f.state.reads == 0)
        #expect(try f.registry.configurationForUserInterface().connections.isEmpty)
        #expect(try await client.cancel().state == .cancelled)
        #expect(try await client.poll().state == .cancelled)
        #expect(f.pairing.pendingFromUserInterface().isEmpty)
    }

    @Test func approvalReturnsOnlyTheConnectionIDAndThenNormalAuthenticationWorks() async throws {
        let f = try Fixture(), note = try f.library.createNote(content: "Neutral allowed 🐼")
        _ = try f.library.createNote(content: "Neutral hidden")
        let broker = try f.broker(); defer { broker.stop() }
        let client = try await f.client(broker)
        let record = try await f.approve(client, scope: .resources([.init(kind: .draft, id: note.id)]))
        let reply = try await client.poll()
        #expect(reply.state == .approved && reply.connectionID == record.id)
        #expect(f.state.reads == 0)
        let bytes = try AgentPairingHandshake.encode(reply), secret = try #require(f.state.credentials[record.id])
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains(secret.base64EncodedString()) && !text.contains("credential"))
        let authenticated = try await AgentLocalClient.connect(path: broker.path, connectionID: record.id,
            credential: secret, validateServer: { _ in })
        let request = AgentRequest(requestID: UUID(), libraryID: nil, operation: "library.summary")
        let result = try JSONDecoder().decode(AgentResponse.self, from: await authenticated.request(JSONEncoder().encode(request)))
        #expect(result.outcome == .result(.object(["draftCount": .integer(1)])))
        await authenticated.close()
    }

    @Test func denialExpiryAndLockReturnDistinctTerminalStates() async throws {
        for expected in [AgentPairingHandshake.State.denied, .expired, .invalidated] {
            let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
            let client = try await f.client(broker), id = try #require(await client.challenge.pairingID)
            switch expected {
            case .denied: try f.pairing.denyFromUserInterface(id)
            case .expired: f.state.wall += 300; f.state.elapsed += 300
            default: f.state.locked = true
            }
            #expect(try await client.poll().state == expected)
            #expect(f.state.credentials.isEmpty && f.state.reads == 0)
        }
    }

    @Test func failedHumanApprovalIsReportedWithoutRetryingPersistence() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let client = try await f.client(broker)
        f.state.failWrite = true
        await #expect(throws: AgentErrorCode.storageError) { try await f.approve(client) }
        let reply = try await client.poll()
        #expect(reply.state == .failed && reply.error == .storageError && reply.connectionID == nil)
        f.state.failWrite = false
        #expect(try await client.poll().state == .failed)
        #expect(f.state.credentials.isEmpty)
    }

    @Test func absentPairingSupportFailsExplicitlyWithoutChangingAuthentication() async throws {
        let f = try Fixture(), broker = try f.broker(pairingEnabled: false); defer { broker.stop() }
        await #expect(throws: AgentErrorCode.unavailable) { try await f.client(broker) }
        #expect(f.pairing.pendingFromUserInterface().isEmpty && f.state.credentials.isEmpty)
    }

    @Test func helperIdentityRejectionHappensBeforeAChallengeExists() async throws {
        let f = try Fixture()
        let broker = try AgentSocketBroker(service: try f.service(), parentDirectory: FileManager.default.temporaryDirectory,
            pairing: f.pairing, validateHelper: { _ in throw AgentErrorCode.permissionDenied })
        defer { broker.stop() }
        await #expect(throws: (any Error).self) { try await f.client(broker) }
        #expect(f.pairing.pendingFromUserInterface().isEmpty && f.state.credentials.isEmpty && f.state.reads == 0)
    }

    @Test func anotherPairingIDCannotBeInspectedOrCancelled() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let channel = try await AgentUnixChannel.connect(path: broker.path, validatePeer: { _ in })
        defer { channel.close() }
        try await channel.writeFrame(AgentPairingHandshake.encode(AgentPairingHandshake.Start(clientName: "First")))
        let a = try AgentPairingHandshake.Reply.decode(await channel.readFrame())
        let other = try await f.client(broker)
        let b = await other.challenge
        try await channel.writeFrame(AgentPairingHandshake.encode(AgentPairingHandshake.Control(pairingID: #require(b.pairingID), command: .cancel)))
        let error = try AgentPairingHandshake.Reply.decode(await channel.readFrame())
        #expect(error.error == .invalidInput && error.state == nil)
        #expect(try f.pairing.state(#require(a.pairingID)) == .cancelled)
        #expect(try await other.poll().state == .pending)
        _ = try await other.cancel()
    }

    @Test func pairingCapacityLeavesRoomForAnAuthenticatedClient() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let first = try await f.client(broker), second = try await f.client(broker)
        await #expect(throws: AgentErrorCode.busy) { try await f.client(broker) }
        let record = try f.registry.connectFromUserInterface(name: "Existing", libraryID: f.libraryID)
        let client = try await AgentLocalClient.connect(path: broker.path, connectionID: record.id,
            credential: #require(f.state.credentials[record.id]), validateServer: { _ in })
        let request = AgentRequest(requestID: UUID(), libraryID: nil, operation: "server.status")
        let response = try JSONDecoder().decode(AgentResponse.self, from: await client.request(JSONEncoder().encode(request)))
        if case .error = response.outcome { Issue.record("Pairing occupied the operation slots") }
        await client.close(); _ = try await first.cancel(); _ = try await second.cancel()
    }

    @Test func cancellationAfterApprovalDoesNotClaimToRevokeCompletedEffects() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let client = try await f.client(broker), record = try await f.approve(client)
        let reply = try await client.cancel()
        #expect(reply.state == .approved && reply.connectionID == record.id)
        #expect(try f.registry.grantForAuthenticatedConnection(record.id)?.grantID == record.grantID)
    }

    @Test func disconnectAndBrokerDestructionCancelPendingChallenges() async throws {
        let f = try Fixture()
        var broker: AgentSocketBroker? = try f.broker()
        let client = try await f.client(#require(broker)), id = try #require(await client.challenge.pairingID)
        await client.close()
        for _ in 0..<50 {
            if try f.pairing.state(id) == .cancelled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try f.pairing.state(id) == .cancelled)
        let second = try await f.client(#require(broker)), secondID = try #require(await second.challenge.pairingID)
        weak var weakBroker = broker
        broker = nil
        #expect(weakBroker == nil)
        for _ in 0..<50 {
            if try f.pairing.state(secondID) == .cancelled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try f.pairing.state(secondID) == .cancelled)
        await second.close()
    }

    @Test func clientRejectsAStatusForAnotherChallenge() async throws {
        let listener = try AgentUnixListener(parentDirectory: FileManager.default.temporaryDirectory)
        defer { listener.close() }
        let id = UUID()
        let server = Task {
            let channel = try await listener.accept(); defer { channel.close() }
            _ = try await channel.readFrame()
            try await channel.writeFrame(AgentPairingHandshake.encode(AgentPairingHandshake.Reply(pairingID: id, code: UUID().uuidString, expiresAt: Date().addingTimeInterval(300))))
            _ = try await channel.readFrame()
            try await channel.writeFrame(AgentPairingHandshake.encode(AgentPairingHandshake.Reply(pairingID: UUID(), state: .pending)))
        }
        let client = try await AgentPairingClient.connect(path: listener.path, name: "Neutral", validateServer: { _ in })
        await #expect(throws: AgentErrorCode.invalidInput) { try await client.poll() }
        try await server.value
        await client.close()
    }

    @Test func disabledAccessAndExplicitStopInvalidatePendingPairing() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let client = try await f.client(broker), id = try #require(await client.challenge.pairingID)
        try f.registry.setEnabledFromUserInterface(false)
        #expect(try await client.poll().state == .invalidated)
        await #expect(throws: AgentErrorCode.permissionDenied) { try await f.client(broker) }
        try f.registry.setEnabledFromUserInterface(true)
        let next = try await f.client(broker), nextID = try #require(await next.challenge.pairingID)
        broker.stop()
        #expect(try f.pairing.state(nextID) == .invalidated)
        #expect(try f.pairing.state(id) == .invalidated)
        #expect(f.state.credentials.isEmpty)
        await next.close()
    }


    @Test func deadlineCancellationReportsTimeoutOnlyWhenTheRequestWasStillPending() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let pending = try await f.client(broker)
        await #expect(throws: AgentErrorCode.timeout) { try await pending.waitForDecision(timeout: 0) }
        #expect(try await pending.poll().state == .cancelled)
        #expect(f.state.credentials.isEmpty)
        let approved = try await f.client(broker), record = try await f.approve(approved)
        let result = try await approved.waitForDecision(timeout: 0)
        #expect(result.state == .approved && result.connectionID == record.id)
    }

    @Test func invalidWaitBudgetDoesNotCancelOrChangeThePendingRequest() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let client = try await f.client(broker)
        for budget in [-1.0, 301.0, Double.infinity, Double.nan] {
            await #expect(throws: AgentErrorCode.invalidInput) { try await client.waitForDecision(timeout: budget) }
        }
        #expect(try await client.poll().state == .pending)
        #expect(f.state.credentials.isEmpty)
        _ = try await client.cancel()
    }


    @Test func decisionWaitReturnsTheHumanDecisionThroughThePollingRoute() async throws {
        for approve in [false, true] {
            let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
            let client = try await f.client(broker)
            let waiting = Task { try await client.waitForDecision() }
            await Task.yield()
            if approve { _ = try await f.approve(client) }
            else { try f.pairing.denyFromUserInterface(#require(await client.challenge.pairingID)) }
            let result = try await waiting.value
            #expect(result.state == (approve ? .approved : .denied))
            #expect(f.state.credentials.count == (approve ? 1 : 0))
        }
    }

    @Test func taskCancellationInterruptsTheDecisionWaitAndReleasesTheChallenge() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let client = try await f.client(broker), id = try #require(await client.challenge.pairingID)
        let waiting = Task { try await client.waitForDecision() }
        await Task.yield()
        waiting.cancel()
        await #expect(throws: (any Error).self) { try await waiting.value }
        for _ in 0..<50 {
            if try f.pairing.state(id) == .cancelled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try f.pairing.state(id) == .cancelled)
        #expect(f.state.credentials.isEmpty)
        await client.close()
    }

    @Test func libraryBoundPairingEchoesTheActualLibraryBeforeHumanApproval() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let channel = try await AgentUnixChannel.connect(path: broker.path, validatePeer: { _ in })
        let start: AgentJSONValue = .object(["apiVersion": .integer(1), "mode": .string("pair"),
            "clientName": .string("Neutral bound client"), "expectedLibraryID": .string(f.libraryID.uuidString)])
        try await channel.writeFrame(JSONEncoder().encode(start))
        let data = try await channel.readFrame(maximumBytes: AgentPairingHandshake.maximumBytes, timeout: 15)
        guard case .object(let fields) = try JSONDecoder().decode(AgentJSONValue.self, from: data),
              case .string(let rawID) = fields["pairingID"], let id = UUID(uuidString: rawID) else {
            Issue.record("Expected a bound pairing challenge"); channel.close(); return
        }
        #expect(fields["libraryID"] == .string(f.libraryID.uuidString))
        #expect(f.pairing.pendingFromUserInterface().count == 1 && f.state.credentials.isEmpty && f.state.reads == 0)
        try await channel.writeFrame(AgentPairingHandshake.encode(AgentPairingHandshake.Control(pairingID: id, command: .cancel)))
        _ = try await channel.readFrame(maximumBytes: AgentPairingHandshake.maximumBytes, timeout: 15)
        channel.close()
    }

    @Test func aDifferentExpectedPairingLibraryCreatesNoReviewOrCredential() async throws {
        let f = try Fixture(), broker = try f.broker(); defer { broker.stop() }
        let channel = try await AgentUnixChannel.connect(path: broker.path, validatePeer: { _ in })
        defer { channel.close() }
        let start: AgentJSONValue = .object(["apiVersion": .integer(1), "mode": .string("pair"),
            "clientName": .string("Neutral bound client"), "expectedLibraryID": .string(UUID().uuidString)])
        try await channel.writeFrame(JSONEncoder().encode(start))
        let reply = try AgentPairingHandshake.Reply.decode(await channel.readFrame(maximumBytes: AgentPairingHandshake.maximumBytes, timeout: 15))
        #expect(reply.error == .permissionDenied && reply.pairingID == nil)
        #expect(f.pairing.pendingFromUserInterface().isEmpty && f.state.credentials.isEmpty && f.state.reads == 0)
    }

    @Test(arguments: [0, 1, 2])
    func boundClientRequiresTheActualLibraryAcknowledgementBeforeShowingAChallenge(replyKind: Int) async throws {
        let expected = UUID(), listener = try AgentUnixListener(parentDirectory: FileManager.default.temporaryDirectory)
        let server = Task { @MainActor in
            let channel = try await listener.accept(); defer { channel.close() }
            let start = try AgentPairingHandshake.Start.decode(await channel.readFrame(maximumBytes: AgentPairingHandshake.maximumBytes, timeout: 15))
            #expect(start.expectedLibraryID == expected)
            let actual: UUID? = replyKind == 0 ? expected : replyKind == 1 ? UUID() : nil
            try await channel.writeFrame(AgentPairingHandshake.encode(AgentPairingHandshake.Reply(
                pairingID: UUID(), code: UUID().uuidString, expiresAt: Date().addingTimeInterval(300), libraryID: actual)))
            do { _ = try await channel.readFrame(); return false } catch { return true }
        }
        defer { server.cancel(); listener.close() }
        if replyKind == 0 {
            let client = try await AgentPairingClient.connect(path: listener.path, name: "Neutral", expectedLibraryID: expected, validateServer: { _ in })
            #expect(await client.challenge.libraryID == expected)
            await client.close()
        } else {
            await #expect(throws: AgentErrorCode.permissionDenied) {
                try await AgentPairingClient.connect(path: listener.path, name: "Neutral", expectedLibraryID: expected, validateServer: { _ in })
            }
        }
        #expect(try await server.value)
    }

}
