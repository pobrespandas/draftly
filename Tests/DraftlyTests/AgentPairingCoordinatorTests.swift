import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Human-reviewed local agent pairing") @MainActor
struct AgentPairingCoordinatorTests {
    @MainActor private final class Fixture {
        let libraryID = UUID()
        var bytes: Data?
        var secrets: [UUID: Data] = [:]
        var wall = Date(timeIntervalSince1970: 1_700_000_000)
        var elapsed: TimeInterval = 50
        var locked = false
        var failWrite = false
        var failCleanup = false
        var targets: Set<AgentResourceReference> = []
        var createCount = 0
        lazy var registry = AgentConnectionRegistry(metadata: .init(read: { [unowned self] in self.bytes }, replace: { [unowned self] value, expected in
            guard !self.failWrite else { throw AgentErrorCode.storageError }
            guard self.bytes == expected else { throw AgentErrorCode.versionConflict }
            self.bytes = value
        }), credentials: .init(read: { [unowned self] in self.secrets[$0] }, create: { [unowned self] id, value in
            self.createCount += 1; self.secrets[id] = value
        }, remove: { [unowned self] id in
            guard !self.failCleanup else { throw AgentErrorCode.storageError }
            self.secrets.removeValue(forKey: id)
        }), now: { [unowned self] in self.wall }, authorityChanged: { _ in })
        func coordinator(capacity: Int = 32) -> AgentPairingCoordinator {
            AgentPairingCoordinator(registry: registry, libraryID: libraryID, capacity: capacity,
                now: { [unowned self] in self.wall }, uptime: { [unowned self] in self.elapsed },
                isLocked: { [unowned self] in self.locked }, resolveTargets: { [unowned self] in $0.intersection(self.targets) })
        }
        func enable() throws { try registry.setEnabledFromUserInterface(true) }
    }

    @Test func requestCreatesNoGrantAndDefaultsRemainSelectedReadOnly() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator()
        let challenge = try c.request(clientName: "Client 🐼")
        #expect(challenge.expiresAt == f.wall.addingTimeInterval(300))
        #expect(!challenge.code.isEmpty && c.pendingFromUserInterface() == [challenge])
        #expect(f.secrets.isEmpty && f.createCount == 0)
        #expect(try f.registry.configurationForUserInterface().connections.isEmpty)
        let review = try c.prepareReviewFromUserInterface(challenge.id, name: "My client")
        #expect(review.capabilities == [.draftsRead] && review.scope == .resources([]))
        #expect(!review.renewable && review.grantExpiresAt == f.wall.addingTimeInterval(3600))
        #expect(f.createCount == 0)
        let record = try c.approveFromUserInterface(challenge.id, reviewID: review.id, displayedChallenge: challenge.code)
        #expect(record.libraryID == f.libraryID && record.name == "My client")
        #expect(record.grant.capabilities == [.draftsRead] && record.grant.scope == .resources([]))
        #expect(try c.state(challenge.id) == .approved(connectionID: record.id))
        #expect(f.createCount == 1 && f.secrets[record.id]?.count == 32)
        #expect(c.pendingFromUserInterface().isEmpty)
        #expect(throws: AgentErrorCode.permissionDenied) {
            try c.approveFromUserInterface(challenge.id, reviewID: review.id, displayedChallenge: challenge.code)
        }
        #expect(f.createCount == 1)
    }

    @Test func userCanReviewExplicitCapabilitiesAndFrozenIDs() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator()
        let target = AgentResourceReference(kind: .draft, id: UUID()); f.targets = [target]
        let q = try c.request(clientName: "External label")
        let review = try c.prepareReviewFromUserInterface(q.id, name: "Trusted label", capabilities: [.draftsRead, .draftsWrite],
            scope: .resources([target]), grantExpiresAt: f.wall.addingTimeInterval(90), renewable: true)
        let record = try c.approveFromUserInterface(q.id, reviewID: review.id, displayedChallenge: q.code)
        #expect(record.grant.scope == .resources([target]) && record.renewable)
        #expect(record.grant.capabilities == [.draftsRead, .draftsWrite])
        #expect(record.expiresAt == f.wall.addingTimeInterval(90))
        f.targets.insert(.init(kind: .draft, id: UUID()))
        #expect(record.grant.scope == .resources([target]))
    }

    @Test func replacedReviewOrWrongChallengeCannotApprove() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator(), q = try c.request(clientName: "client")
        let first = try c.prepareReviewFromUserInterface(q.id, name: "First", scope: .library)
        let second = try c.prepareReviewFromUserInterface(q.id, name: "Second")
        #expect(throws: AgentErrorCode.versionConflict) {
            try c.approveFromUserInterface(q.id, reviewID: first.id, displayedChallenge: q.code)
        }
        #expect(throws: AgentErrorCode.versionConflict) {
            try c.approveFromUserInterface(q.id, reviewID: second.id, displayedChallenge: "wrong")
        }
        #expect(f.createCount == 0)
        #expect(try c.state(q.id) == .pending)
        let record = try c.approveFromUserInterface(q.id, reviewID: second.id, displayedChallenge: q.code)
        #expect(record.grant.scope == .resources([]))
    }

    @Test func targetsMustResolveAtReviewAndAgainAtApproval() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator(), q = try c.request(clientName: "client")
        let target = AgentResourceReference(kind: .draft, id: UUID())
        #expect(throws: AgentErrorCode.notFound) { try c.prepareReviewFromUserInterface(q.id, name: "Client", scope: .resources([target])) }
        f.targets = [target]
        let review = try c.prepareReviewFromUserInterface(q.id, name: "Client", scope: .resources([target]))
        f.targets = []
        #expect(throws: AgentErrorCode.notFound) { try c.approveFromUserInterface(q.id, reviewID: review.id, displayedChallenge: q.code) }
        #expect(try c.state(q.id) == .invalidated)
        #expect(f.createCount == 0)
    }

    @Test func disabledLockedAndRestartedCoordinatorsCannotAuthorizePendingWork() throws {
        let f = Fixture(), c = f.coordinator()
        #expect(throws: AgentErrorCode.permissionDenied) { try c.request(clientName: "client") }
        try f.enable(); let q = try c.request(clientName: "client")
        f.locked = true
        #expect(c.pendingFromUserInterface().isEmpty)
        f.locked = false
        #expect(try c.state(q.id) == .invalidated)
        let second = try c.request(clientName: "second")
        try f.registry.setEnabledFromUserInterface(false)
        #expect(try c.state(second.id) == .invalidated)
        try f.enable()
        #expect(throws: AgentErrorCode.permissionDenied) { try c.prepareReviewFromUserInterface(second.id, name: "Client") }
        #expect(throws: AgentErrorCode.notFound) { try f.coordinator().state(q.id) }
        #expect(f.createCount == 0)
    }

    @Test func monotonicExpiryAndClockRollbackCannotExtendAChallenge() throws {
        for change in [0, 1, 2, 3] {
            let f = Fixture(); try f.enable(); let c = f.coordinator(), q = try c.request(clientName: "client")
            if change == 0 { f.elapsed += 300 }
            if change == 1 { f.wall += 300 }
            if change == 2 { f.wall -= 1 }
            if change == 3 { f.elapsed -= 1 }
            #expect(try c.state(q.id) == .expired)
            #expect(throws: AgentErrorCode.permissionDenied) { try c.prepareReviewFromUserInterface(q.id, name: "Client") }
        }
    }

    @Test func denialAndCancellationAreStableAndNeverCreateCredentials() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator()
        let a = try c.request(clientName: "deny"), b = try c.request(clientName: "cancel")
        try c.denyFromUserInterface(a.id); try c.cancel(a.id)
        try c.cancel(b.id); try c.cancel(b.id)
        #expect(try c.state(a.id) == .denied && c.state(b.id) == .cancelled)
        #expect(f.createCount == 0)
        #expect(throws: AgentErrorCode.notFound) { try c.cancel(UUID()) }
    }

    @Test func failedPersistenceIsTerminalAndCannotBeRetriedByDoubleClick() throws {
        for cleanupFails in [false, true] {
            let f = Fixture(); try f.enable(); let c = f.coordinator(), q = try c.request(clientName: "client")
            let review = try c.prepareReviewFromUserInterface(q.id, name: "Client")
            f.failWrite = true; f.failCleanup = cleanupFails
            let code: AgentErrorCode = cleanupFails ? .outcomeUnknown : .storageError
            #expect(throws: code) { try c.approveFromUserInterface(q.id, reviewID: review.id, displayedChallenge: q.code) }
            #expect(try c.state(q.id) == .failed(code))
            f.failWrite = false; f.failCleanup = false
            #expect(throws: AgentErrorCode.permissionDenied) { try c.approveFromUserInterface(q.id, reviewID: review.id, displayedChallenge: q.code) }
            #expect(f.createCount == 1)
            #expect(try f.registry.configurationForUserInterface().connections.isEmpty)
        }
    }

    @Test func revocationInvalidatesAnApprovedPairingResultWithoutReturningItsSecret() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator(), q = try c.request(clientName: "client")
        let r = try c.prepareReviewFromUserInterface(q.id, name: "Client")
        let record = try c.approveFromUserInterface(q.id, reviewID: r.id, displayedChallenge: q.code)
        _ = try f.registry.revokeFromUserInterface(record.id)
        #expect(try c.state(q.id) == .invalidated)
        #expect(f.secrets.isEmpty)
    }

    @Test func capacityAndNamesAreBoundedAndExpiredEntriesCanBeReplaced() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator(capacity: 1)
        #expect(throws: AgentErrorCode.invalidInput) { try c.request(clientName: "\n") }
        #expect(throws: AgentErrorCode.invalidInput) { try c.request(clientName: String(repeating: "x", count: 257)) }
        let q = try c.request(clientName: "client")
        #expect(throws: AgentErrorCode.busy) { try c.request(clientName: "another") }
        try c.cancel(q.id)
        #expect(throws: AgentErrorCode.busy) { try c.request(clientName: "another") }
        f.wall += 300; f.elapsed += 300
        let next = try c.request(clientName: "another")
        #expect(next.id != q.id && next.code != q.code)
        #expect(throws: AgentErrorCode.notFound) { try c.state(q.id) }
    }

    @Test func invalidReviewKeepsPendingStateAndNeverWritesDefaults() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator(), q = try c.request(clientName: "client")
        let before = f.bytes
        #expect(throws: AgentErrorCode.invalidInput) { try c.prepareReviewFromUserInterface(q.id, name: " ") }
        #expect(throws: AgentErrorCode.invalidInput) { try c.prepareReviewFromUserInterface(q.id, name: "Client", grantExpiresAt: f.wall) }
        #expect(f.bytes == before && f.secrets.isEmpty)
        #expect(try c.state(q.id) == .pending)
        c.invalidatePending()
        #expect(try c.state(q.id) == .invalidated)
    }

    @Test func approvalUsesOnlyTheReviewedLibraryScopeAndRejectsAnotherRequestReview() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator()
        let a = try c.request(clientName: "A"), b = try c.request(clientName: "B")
        let review = try c.prepareReviewFromUserInterface(a.id, name: "A", capabilities: [], scope: .library)
        #expect(throws: AgentErrorCode.versionConflict) {
            try c.approveFromUserInterface(b.id, reviewID: review.id, displayedChallenge: b.code)
        }
        #expect(f.createCount == 0)
        let record = try c.approveFromUserInterface(a.id, reviewID: review.id, displayedChallenge: a.code)
        #expect(record.grant.scope == .library && record.grant.capabilities.isEmpty)
    }

    @Test func grantExpiryBeforeApprovalRequiresANewReview() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator(), q = try c.request(clientName: "client")
        let review = try c.prepareReviewFromUserInterface(q.id, name: "Client", grantExpiresAt: f.wall.addingTimeInterval(1))
        f.wall += 1; f.elapsed += 1
        #expect(throws: AgentErrorCode.invalidInput) {
            try c.approveFromUserInterface(q.id, reviewID: review.id, displayedChallenge: q.code)
        }
        #expect(f.createCount == 0 && c.pendingFromUserInterface() == [q])
        let next = try c.prepareReviewFromUserInterface(q.id, name: "Client")
        let record = try c.approveFromUserInterface(q.id, reviewID: next.id, displayedChallenge: q.code)
        #expect(record.expiresAt == f.wall.addingTimeInterval(3600))
    }

    @Test func unreadableConfigurationInvalidatesPendingWorkAndCannotCreateCredentials() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator(), q = try c.request(clientName: "client")
        let r = try c.prepareReviewFromUserInterface(q.id, name: "Client")
        f.bytes = Data("not metadata".utf8)
        #expect(try c.state(q.id) == .invalidated)
        #expect(throws: AgentErrorCode.storageError) {
            try c.approveFromUserInterface(q.id, reviewID: r.id, displayedChallenge: q.code)
        }
        #expect(f.createCount == 0)
    }


    @Test func failedAvailabilityCheckInvalidatesOlderPendingReviews() throws {
        let f = Fixture(); try f.enable(); let c = f.coordinator(), q = try c.request(clientName: "client")
        let review = try c.prepareReviewFromUserInterface(q.id, name: "Client")
        let previous = f.bytes
        f.bytes = Data("invalid metadata".utf8)
        #expect(throws: AgentErrorCode.storageError) { try c.request(clientName: "another") }
        f.bytes = previous
        #expect(try c.state(q.id) == .invalidated)
        #expect(throws: AgentErrorCode.permissionDenied) {
            try c.approveFromUserInterface(q.id, reviewID: review.id, displayedChallenge: q.code)
        }
        #expect(f.createCount == 0)
    }

}
