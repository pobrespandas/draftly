import Foundation
import CryptoKit
import Testing
import AgentContracts
@testable import Draftly

@Suite("Signed agent retry keys") @MainActor
struct AgentRetryKeysTests {
    @MainActor private final class Fixture {
        let connection = UUID(), library = UUID(), epoch = UUID()
        var wall = Date(timeIntervalSince1970: 1_700_000_000)
        var ticks: TimeInterval = 100
        var locked = false
        var grant: AgentGrant?
        lazy var keys = makeKeys()
        init() {
            grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: wall.addingTimeInterval(40 * 86400),
                capabilities: [.draftsRead, .draftsWrite, .preferencesWrite], scope: .library)
        }
        func makeKeys() -> AgentRetryKeys {
            AgentRetryKeys(epoch: epoch, now: { [unowned self] in self.wall }, uptime: { [unowned self] in self.ticks },
                currentGrant: { [unowned self] id in id == self.connection ? self.grant : nil }, isLocked: { [unowned self] in self.locked })
        }
        func request(id: UUID = UUID(), content: String = "Neutral café 🐼", defaults: Bool = false) -> AgentRequest {
            var parameters: [String: AgentJSONValue] = ["content": .string(content)]
            if defaults { parameters["tags"] = .array([]); parameters["syntax"] = .string("Markdown"); parameters["flag"] = .integer(0); parameters["folder"] = .string("inbox") }
            return AgentRequest(requestID: id, libraryID: library, operation: "drafts.create", parameters: parameters)
        }
    }

    @Test func matchingRetriesKeepHashesWithoutRetainingContentOrNeedingAReceipt() throws {
        let f = Fixture(), request = f.request(), ticket = try f.keys.issue(request, connectionID: f.connection)
        let checked = try f.keys.verify(ticket.value, request: request, connectionID: f.connection)
        #expect(checked.requestHash == ticket.requestHash && checked.connectionHash == ticket.connectionHash)
        #expect(ticket.requestHash.count == 64 && ticket.connectionHash.count == 64)
        #expect(ticket.expiresAt == f.wall.addingTimeInterval(30 * 86400))
        let payload = try #require(Data(base64Encoded: String(ticket.value.split(separator: ".")[0])))
        #expect(!String(decoding: payload, as: UTF8.self).contains("Neutral"))
        f.wall += 30 * 86400 - 1; f.ticks += 30 * 86400 - 1
        _ = try f.keys.verify(ticket.value, request: request, connectionID: f.connection)
    }

    @Test func defaultsNormalizeButUnicodeScalarChangesAndRequestIDsDoNot() throws {
        let f = Fixture(), id = UUID(), request = f.request(id: id, content: "Café")
        let ticket = try f.keys.issue(request, connectionID: f.connection)
        _ = try f.keys.verify(ticket.value, request: f.request(id: id, content: "Café", defaults: true), connectionID: f.connection)
        #expect(throws: AgentErrorCode.invalidInput) {
            try f.keys.verify(ticket.value, request: f.request(id: id, content: "Cafe\u{0301}"), connectionID: f.connection)
        }
        #expect(throws: AgentErrorCode.invalidInput) {
            try f.keys.verify(ticket.value, request: f.request(content: "Café"), connectionID: f.connection)
        }
    }

    @Test func thirtyDayDeadlineAndBothClockDirectionsFailClosed() throws {
        for clock in ["wall", "monotonic", "wallRollback", "monotonicRollback"] {
            let f = Fixture(), request = f.request(), ticket = try f.keys.issue(request, connectionID: f.connection)
            if clock == "wall" { f.wall += 30 * 86400 }
            if clock == "monotonic" { f.ticks += 30 * 86400 }
            if clock == "wallRollback" { f.wall -= 1 }
            if clock == "monotonicRollback" { f.ticks -= 1 }
            #expect(throws: AgentErrorCode.retryWindowExpired) {
                try f.keys.verify(ticket.value, request: request, connectionID: f.connection)
            }
        }
    }

    @Test func missingRevokedExpiredOrChangedGrantsCannotUseAnOldKey() throws {
        for change in ["missing", "revoked", "expired", "replaced", "capabilities", "scope"] {
            let f = Fixture(), request = f.request(), ticket = try f.keys.issue(request, connectionID: f.connection)
            let original = try #require(f.grant)
            if change == "missing" { f.grant = nil }
            else {
                f.grant = AgentGrant(connectionID: f.connection, libraryID: f.library,
                    expiresAt: change == "expired" ? f.wall : original.expiresAt, revoked: change == "revoked",
                    capabilities: change == "capabilities" ? [.draftsWrite] : original.capabilities,
                    scope: change == "scope" ? .resources([]) : .library,
                    grantID: change == "replaced" ? UUID() : original.grantID)
            }
            #expect(throws: AgentErrorCode.permissionDenied) {
                try f.keys.verify(ticket.value, request: request, connectionID: f.connection)
            }
        }
    }

    @Test func tamperingForeignConnectionRestartAndClosureCannotReuseAKey() throws {
        let f = Fixture(), request = f.request(), ticket = try f.keys.issue(request, connectionID: f.connection)
        #expect(throws: AgentErrorCode.invalidInput) {
            try f.keys.verify(ticket.value + "x", request: request, connectionID: f.connection)
        }
        #expect(throws: AgentErrorCode.permissionDenied) {
            try f.keys.verify(ticket.value, request: request, connectionID: UUID())
        }
        #expect(throws: AgentErrorCode.invalidInput) {
            try f.makeKeys().verify(ticket.value, request: request, connectionID: f.connection)
        }
        f.keys.close()
        #expect(throws: AgentErrorCode.cancelled) { try f.keys.issue(request, connectionID: f.connection) }
        #expect(throws: AgentErrorCode.cancelled) { try f.keys.verify(ticket.value, request: request, connectionID: f.connection) }
    }

    @Test func lockedHostAndInvalidRequestsNeverIssueKeys() throws {
        let f = Fixture()
        f.locked = true
        #expect(throws: AgentErrorCode.interactionRequired) { try f.keys.issue(f.request(), connectionID: f.connection) }
        f.locked = false
        let invalid = AgentRequest(requestID: UUID(), libraryID: f.library, operation: "drafts.create", parameters: ["content": .bool(true)])
        #expect(throws: AgentErrorCode.invalidInput) { try f.keys.issue(invalid, connectionID: f.connection) }
        let read = AgentRequest(requestID: UUID(), libraryID: f.library, operation: "drafts.get", targets: [.init(kind: .draft, id: UUID())])
        #expect(throws: AgentErrorCode.invalidInput) { try f.keys.issue(read, connectionID: f.connection) }
    }
    @Test func expectedVersionTargetOrderAndLibraryAreBound() throws {
        let f = Fixture(), ids = [UUID(), UUID()], requestID = UUID()
        func merge(version: String = "v1", reversed: Bool = false, library: UUID? = nil) -> AgentRequest {
            let order = reversed ? Array(ids.reversed()) : ids
            return AgentRequest(requestID: requestID, libraryID: library ?? f.library, operation: "drafts.merge",
                targets: order.map { .init(kind: .draft, id: $0) }, expectedVersion: version,
                parameters: ["order": .array(order.map { .string($0.uuidString) })])
        }
        let ticket = try f.keys.issue(merge(), connectionID: f.connection)
        for changed in [merge(version: "v2"), merge(reversed: true)] {
            #expect(throws: AgentErrorCode.invalidInput) {
                try f.keys.verify(ticket.value, request: changed, connectionID: f.connection)
            }
        }
        #expect(throws: AgentErrorCode.permissionDenied) {
            try f.keys.verify(ticket.value, request: merge(library: UUID()), connectionID: f.connection)
        }
        f.locked = true
        #expect(throws: AgentErrorCode.interactionRequired) {
            try f.keys.verify(ticket.value, request: merge(), connectionID: f.connection)
        }
    }

    @Test func shortGrantAndInvalidClocksCannotExtendRetryAuthority() throws {
        let f = Fixture(), request = f.request()
        f.grant = AgentGrant(connectionID: f.connection, libraryID: f.library, expiresAt: f.wall.addingTimeInterval(60),
            capabilities: [.draftsWrite], scope: .library)
        let ticket = try f.keys.issue(request, connectionID: f.connection)
        f.wall += 60; f.ticks += 60
        #expect(throws: AgentErrorCode.permissionDenied) {
            try f.keys.verify(ticket.value, request: request, connectionID: f.connection)
        }
        let invalid = Fixture(); invalid.ticks = .nan
        #expect(throws: AgentErrorCode.unavailable) {
            try invalid.keys.issue(invalid.request(), connectionID: invalid.connection)
        }
    }

    @Test func aRecreatedVerifierNeedsBothTheSameSecretAndTheSameEpoch() throws {
        let f = Fixture(), request = f.request(), secret = SymmetricKey(data: Data(repeating: 0x5a, count: 32))
        func manager(epoch: UUID) -> AgentRetryKeys {
            AgentRetryKeys(epoch: epoch, key: secret, now: { f.wall }, uptime: { f.ticks },
                currentGrant: { $0 == f.connection ? f.grant : nil }, isLocked: { f.locked })
        }
        let ticket = try manager(epoch: f.epoch).issue(request, connectionID: f.connection)
        _ = try manager(epoch: f.epoch).verify(ticket.value, request: request, connectionID: f.connection)
        #expect(throws: AgentErrorCode.invalidInput) {
            try manager(epoch: UUID()).verify(ticket.value, request: request, connectionID: f.connection)
        }
        let original = try #require(Data(base64Encoded: String(ticket.value.split(separator: ".")[0])))
        var payload = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        payload["padding"] = String(repeating: "x", count: 4096)
        let oversized = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let proof = Data(HMAC<SHA256>.authenticationCode(for: oversized, using: secret))
        let oversizedKey = oversized.base64EncodedString() + "." + proof.base64EncodedString()
        #expect(oversizedKey.utf8.count > 4096)
        #expect(throws: AgentErrorCode.invalidInput) {
            try manager(epoch: f.epoch).verify(oversizedKey, request: request, connectionID: f.connection)
        }
    }

}
