import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Agent protected operation approvals") @MainActor
struct AgentApprovalStoreTests {
    @MainActor private final class Fixture {
        let connection = UUID()
        let library = UUID()
        var wall = Date(timeIntervalSince1970: 1_700_000_000)
        var ticks: TimeInterval = 100
        var locked = false
        var grant: AgentGrant?
        lazy var store = makeStore()
        init() {
            grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: wall.addingTimeInterval(3600),
                capabilities: [.preferencesRead, .preferencesWrite, .nativeUse], scope: .library)
        }
        func makeStore(capacity: Int = 256) -> AgentApprovalStore {
            AgentApprovalStore(capacity: capacity, now: { [unowned self] in self.wall }, uptime: { [unowned self] in self.ticks },
                currentGrant: { [unowned self] id in id == self.connection ? self.grant : nil },
                isLocked: { [unowned self] in self.locked })
        }
        func request(id: UUID = UUID(), field: String = SpotlightPreferences.enabledKey,
                     value: AgentJSONValue = .bool(true), version: String = "preferences-generation-1",
                     interactive: Bool? = nil) -> AgentRequest {
            var parameters: [String: AgentJSONValue] = ["items": .array([.object(["id": .string(field), "value": value])])]
            if let interactive { parameters["interactive"] = .bool(interactive) }
            return AgentRequest(requestID: id, libraryID: library, operation: "preferences.update", expectedVersion: version, parameters: parameters)
        }
        func effects(version: String = "index-generation-1", targets: Set<AgentResourceReference> = [],
                     fullLibrary: Bool = true, capabilities: Set<AgentCapability> = [.nativeUse]) -> AgentApprovalStore.Effects {
            .init(capabilities: capabilities, targets: targets, requiresLibraryScope: fullLibrary,
                snapshot: ["version": .string(version)])
        }
        func review(_ request: AgentRequest, effects: AgentApprovalStore.Effects? = nil) throws -> AgentApprovalStore.Review {
            try store.requestReview(request, connectionID: connection, effects: effects ?? self.effects())
        }
        func approve(_ review: AgentApprovalStore.Review) throws {
            try store.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        }
    }

    @Test func onlyHumanDecisionAllowsOneConsumption() throws {
        let fixture = Fixture()
        let ownRequest = fixture.request()
        let review = try fixture.review(ownRequest)
        #expect(try fixture.store.statusForConnection(review.id, connectionID: fixture.connection) == .pending)
        #expect(throws: AgentErrorCode.interactionRequired) {
            try fixture.store.consume(review.id, request: ownRequest, connectionID: fixture.connection, effects: fixture.effects())
        }
        try fixture.approve(review)
        try fixture.store.consume(review.id, request: ownRequest, connectionID: fixture.connection, effects: fixture.effects())
        #expect(try fixture.store.statusForConnection(review.id, connectionID: fixture.connection) == .consumed)
        #expect(throws: AgentErrorCode.permissionDenied) {
            try fixture.store.consume(review.id, request: ownRequest, connectionID: fixture.connection, effects: fixture.effects())
        }
        #expect(!AgentOperationCatalog.operations.contains { $0.name.lowercased().contains("approve") })
    }

    @Test func defaultNormalizationDoesNotMintAnotherReviewOrExtendExpiry() throws {
        let fixture = Fixture(), id = UUID()
        let review = try fixture.review(fixture.request(id: id))
        fixture.wall = fixture.wall.addingTimeInterval(20); fixture.ticks += 20
        let repeated = try fixture.review(fixture.request(id: id, interactive: false))
        #expect(repeated.id == review.id && repeated.expiresAt == review.expiresAt)
        try fixture.approve(review)
        let alreadyApproved = try fixture.review(fixture.request(id: id))
        #expect(alreadyApproved.id == review.id)
    }

    @Test func parameterVersionAndEffectEditsInvalidateTheApproval() throws {
        for changed in 0..<3 {
            let fixture = Fixture(), id = UUID()
            let original = fixture.request(id: id), review = try fixture.review(original)
            try fixture.approve(review)
            let request = changed == 0 ? fixture.request(id: id, value: .bool(false))
                : changed == 1 ? fixture.request(id: id, version: "new-generation") : original
            let effects = changed == 2 ? fixture.effects(version: "index-generation-2") : fixture.effects()
            #expect(throws: AgentErrorCode.versionConflict) {
                try fixture.store.consume(review.id, request: request, connectionID: fixture.connection, effects: effects)
            }
            #expect(try fixture.store.statusForConnection(review.id, connectionID: fixture.connection) == .invalidated)
        }
    }

    @Test func unicodeScalarChangesAreNotSilentlyNormalized() throws {
        let fixture = Fixture(), id = UUID()
        let original = fixture.request(id: id, field: "editor.fontName", value: .string("Café"))
        let review = try fixture.review(original); try fixture.approve(review)
        let differentScalars = fixture.request(id: id, field: "editor.fontName", value: .string("Cafe\u{301}"))
        #expect(throws: AgentErrorCode.versionConflict) {
            try fixture.store.consume(review.id, request: differentScalars, connectionID: fixture.connection, effects: fixture.effects())
        }
    }

    @Test func anotherConnectionCannotReadConsumeOrCancelTheReview() throws {
        let fixture = Fixture(), requestID = UUID()
        let request = fixture.request(id: requestID), review = try fixture.review(request)
        try fixture.approve(review)
        let other = UUID()
        #expect(throws: AgentErrorCode.notFound) { try fixture.store.statusForConnection(review.id, connectionID: other) }
        #expect(throws: AgentErrorCode.notFound) { try fixture.store.cancelFromConnection(review.id, connectionID: other) }
        #expect(throws: AgentErrorCode.notFound) {
            try fixture.store.consume(review.id, request: request, connectionID: other, effects: fixture.effects())
        }
        #expect(try fixture.store.statusForConnection(review.id, connectionID: fixture.connection) == .approved)
    }

    @Test func deniedCancelledAndExpiredStatesRemainDistinct() throws {
        for terminal in 0..<3 {
            let fixture = Fixture()
            let own = fixture.request(), review = try fixture.review(own)
            if terminal == 0 { try fixture.store.denyFromUserInterface(review.id) }
            if terminal == 1 { try fixture.store.cancelFromConnection(review.id, connectionID: fixture.connection) }
            if terminal == 2 { fixture.wall = fixture.wall.addingTimeInterval(300) }
            let expected: AgentErrorCode = terminal == 0 ? .permissionDenied : terminal == 1 ? .cancelled : .timeout
            #expect(throws: expected) {
                try fixture.store.consume(review.id, request: own, connectionID: fixture.connection, effects: fixture.effects())
            }
            let state = try fixture.store.statusForConnection(review.id, connectionID: fixture.connection)
            #expect(state == (terminal == 0 ? .denied : terminal == 1 ? .cancelled : .expired))
        }
    }

    @Test func monotonicExpiryAndClockRollbackCannotExtendConsent() throws {
        for clock in 0..<3 {
            let fixture = Fixture()
            let own = fixture.request(), review = try fixture.review(own)
            try fixture.approve(review)
            if clock == 0 { fixture.ticks += 300 }
            if clock == 1 { fixture.wall = fixture.wall.addingTimeInterval(-1) }
            if clock == 2 { fixture.ticks -= 1 }
            #expect(throws: clock == 0 ? AgentErrorCode.timeout : .versionConflict) {
                try fixture.store.consume(review.id, request: own, connectionID: fixture.connection, effects: fixture.effects())
            }
        }
    }

    @Test func replacingAnIdenticalGrantStillInvalidatesItsApprovals() throws {
        let fixture = Fixture()
        let own = fixture.request(), review = try fixture.review(own)
        try fixture.approve(review)
        let old = try #require(fixture.grant)
        fixture.grant = AgentGrant(connectionID: old.connectionID, libraryID: old.libraryID, expiresAt: old.expiresAt,
            capabilities: old.capabilities, scope: old.scope)
        #expect(fixture.grant?.grantID != old.grantID)
        #expect(throws: AgentErrorCode.permissionDenied) {
            try fixture.store.consume(review.id, request: own, connectionID: fixture.connection, effects: fixture.effects())
        }
    }

    @Test func revocationAndGrantEditsDenyUseEvenIfTheIDWasRetained() throws {
        for edit in 0..<5 {
            let fixture = Fixture()
            let own = fixture.request(), review = try fixture.review(own)
            try fixture.approve(review)
            let old = try #require(fixture.grant)
            fixture.grant = AgentGrant(connectionID: old.connectionID, libraryID: edit == 4 ? UUID() : old.libraryID,
                expiresAt: edit == 2 ? old.expiresAt.addingTimeInterval(60) : old.expiresAt,
                revoked: edit == 0, capabilities: edit == 1 ? [.preferencesRead] : old.capabilities,
                scope: edit == 3 ? .resources([]) : old.scope, grantID: old.grantID)
            #expect(throws: AgentErrorCode.permissionDenied) {
                try fixture.store.consume(review.id, request: own, connectionID: fixture.connection, effects: fixture.effects())
            }
        }
    }

    @Test func declaredEffectsCannotWidenCapabilityOrTargetScope() throws {
        let fixture = Fixture()
        let request = fixture.request()
        #expect(throws: AgentErrorCode.permissionDenied) {
            try fixture.review(request, effects: fixture.effects(capabilities: [.scriptsUnrestricted]))
        }
        let old = try #require(fixture.grant), allowed = AgentResourceReference(kind: .draft, id: UUID())
        fixture.grant = AgentGrant(connectionID: old.connectionID, libraryID: old.libraryID,
            expiresAt: old.expiresAt, capabilities: old.capabilities, scope: .resources([allowed]))
        #expect(throws: AgentErrorCode.permissionDenied) { try fixture.review(request) }
        #expect(throws: AgentErrorCode.permissionDenied) {
            try fixture.review(request, effects: fixture.effects(targets: [.init(kind: .workspace, id: allowed.id)], fullLibrary: false))
        }
        _ = try fixture.review(request, effects: fixture.effects(targets: [allowed], fullLibrary: false))
    }

    @Test func lockedOrRestartedServiceCannotReuseConsent() throws {
        let fixture = Fixture()
        let request = fixture.request(), review = try fixture.review(request)
        try fixture.approve(review)
        fixture.locked = true
        #expect(throws: AgentErrorCode.interactionRequired) {
            try fixture.store.consume(review.id, request: request, connectionID: fixture.connection, effects: fixture.effects())
        }
        fixture.locked = false
        #expect(throws: AgentErrorCode.versionConflict) {
            try fixture.store.consume(review.id, request: request, connectionID: fixture.connection, effects: fixture.effects())
        }
        let nextRequest = fixture.request(), nextReview = try fixture.review(nextRequest)
        try fixture.approve(nextReview)
        fixture.store.invalidateForScreenLock()
        #expect(throws: AgentErrorCode.versionConflict) {
            try fixture.store.consume(nextReview.id, request: nextRequest, connectionID: fixture.connection, effects: fixture.effects())
        }
        let restarted = fixture.makeStore()
        #expect(throws: AgentErrorCode.notFound) {
            try restarted.consume(review.id, request: request, connectionID: fixture.connection, effects: fixture.effects())
        }
    }

    @Test func staleHumanReviewAndExplicitRevocationCannotBeReapproved() throws {
        let fixture = Fixture()
        let request = fixture.request(), review = try fixture.review(request)
        #expect(throws: AgentErrorCode.versionConflict) {
            try fixture.store.approveFromUserInterface(review.id, reviewedFingerprint: "old visible review")
        }
        #expect(throws: AgentErrorCode.versionConflict) { try fixture.approve(review) }
        let other = try fixture.review(fixture.request())
        fixture.store.invalidateConnection(fixture.connection)
        #expect(throws: AgentErrorCode.versionConflict) { try fixture.approve(other) }
    }

    @Test func capacityRejectsActiveOverflowAndCanReclaimTerminalReviews() throws {
        let fixture = Fixture()
        let store = fixture.makeStore(capacity: 1)
        let request = fixture.request()
        let review = try store.requestReview(request, connectionID: fixture.connection, effects: fixture.effects())
        #expect(throws: AgentErrorCode.busy) {
            try store.requestReview(fixture.request(), connectionID: fixture.connection, effects: fixture.effects())
        }
        try store.denyFromUserInterface(review.id)
        let next = try store.requestReview(fixture.request(), connectionID: fixture.connection, effects: fixture.effects())
        #expect(next.id != review.id)
        #expect(throws: AgentErrorCode.notFound) { try store.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint) }
    }
    @Test func requestParametersCannotSupplyApprovalOrEffectAuthority() throws {
        let fixture = Fixture(), request = fixture.request()
        for key in ["approved", "effects", "grant"] {
            var parameters = request.parameters
            parameters[key] = .bool(true)
            let forged = AgentRequest(requestID: request.requestID, libraryID: request.libraryID,
                operation: request.operation, expectedVersion: request.expectedVersion, parameters: parameters)
            #expect(throws: (any Error).self) { try fixture.review(forged) }
        }
        let review = try fixture.review(request)
        #expect(try fixture.store.statusForConnection(review.id, connectionID: fixture.connection) == .pending)
    }

    @Test func defaultsDoNotReduceTheAcceptedWireFrameLimit() throws {
        let fixture = Fixture(), id = UUID()
        let empty = fixture.request(id: id, field: "editor.fontName", value: .string(""))
        let overhead = try JSONEncoder().encode(empty).count
        let text = String(repeating: "x", count: AgentRequest.maximumBytes - overhead - 1)
        let request = fixture.request(id: id, field: "editor.fontName", value: .string(text))
        #expect(try JSONEncoder().encode(request).count < AgentRequest.maximumBytes)
        let review = try fixture.review(request)
        #expect(try fixture.store.statusForConnection(review.id, connectionID: fixture.connection) == .pending)
    }

    @Test func anApprovalCannotBeMovedToDifferentRequestTargets() throws {
        let fixture = Fixture()
        let old = try #require(fixture.grant)
        fixture.grant = AgentGrant(connectionID: old.connectionID, libraryID: old.libraryID, expiresAt: old.expiresAt,
            capabilities: [.draftsWrite, .destructiveRequest], scope: .library)
        let id = UUID(), originalTarget = AgentResourceReference(kind: .draft, id: UUID())
        let original = AgentRequest(requestID: id, libraryID: fixture.library, operation: "drafts.purge",
            targets: [originalTarget], expectedVersion: "draft-version-1")
        let effects = fixture.effects(fullLibrary: false, capabilities: [])
        let review = try fixture.review(original, effects: effects)
        try fixture.approve(review)
        let other = AgentRequest(requestID: id, libraryID: fixture.library, operation: "drafts.purge",
            targets: [.init(kind: .draft, id: UUID())], expectedVersion: "draft-version-1")
        #expect(throws: AgentErrorCode.versionConflict) {
            try fixture.store.consume(review.id, request: other, connectionID: fixture.connection, effects: effects)
        }
    }

}
