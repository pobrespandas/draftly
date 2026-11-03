import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Agent prepared preference writes") @MainActor
struct AgentPreferenceWritingTests {
    @MainActor private final class Fixture {
        let connection = UUID(), library = UUID(), wall = Date(timeIntervalSince1970: 1_700_000_000)
        var grant: AgentGrant?
        var values: [String: Any] = ["editor.fontSize": 17]
        var writes = 0
        var failAfterWrite = false
        var needsReview = false
        var changeDuringReceipt = false
        lazy var storage = AgentPreferenceStorage(read: { [unowned self] in values }, replace: { [unowned self] _, next in
            writes += 1; values = next
            if failAfterWrite { throw AgentErrorCode.storageError }
            return true
        })
        lazy var keys = AgentRetryKeys(now: { [unowned self] in wall }, uptime: { 1 },
            currentGrant: { [unowned self] id in id == connection ? grant : nil }, isLocked: { false })
        let preferences: AgentPreferenceRegistry
        lazy var writer = AgentPreferenceWriting(storage: storage, keys: keys, preferences: preferences,
            currentGrant: { [unowned self] id in id == connection ? grant : nil }, validateAdmission: {},
            plan: { [unowned self] request, _ in
                guard case .array(let items) = request.parameters["items"], case .object(let item) = items.first else {
                    throw AgentErrorCode.invalidInput
                }
                let value = request.operation == "preferences.reset" ? nil : item["value"]
                return AgentPreferenceBatch(storage: ["editor.fontSize": value.map { .scalar($0) } ?? .remove],
                    native: [], requiresHumanApproval: needsReview)
            }, readReceipt: { [unowned self] _, _ in
                if changeDuringReceipt && writes > 0 { values["editor.fontSize"] = 41 }
                let token = try storage.snapshot().version
                return ["items": .array([.object(["id": .string("editor.fontSize"), "versionToken": .string(token)])]),
                        "versionToken": .string(token)]
            })
        init() throws {
            preferences = try AgentPreferenceCatalog.make()
            grant = AgentGrant(connectionID: connection, libraryID: library, expiresAt: wall.addingTimeInterval(600),
                capabilities: [.preferencesWrite], scope: .library)
        }
        func request(value: Int64? = 23, id: UUID = UUID()) throws -> AgentRequest {
            var item: [String: AgentJSONValue] = ["id": .string("editor.fontSize")]
            if let value { item["value"] = .integer(value) }
            return AgentRequest(requestID: id, libraryID: library, operation: value == nil ? "preferences.reset" : "preferences.update",
                expectedVersion: try storage.snapshot().version, parameters: ["items": .array([.object(item)])])
        }
        func signed(_ request: AgentRequest, key: String) -> AgentRequest {
            AgentRequest(requestID: request.requestID, libraryID: request.libraryID, operation: request.operation,
                targets: request.targets, expectedVersion: request.expectedVersion, retryKey: key, parameters: request.parameters)
        }
    }

    @Test func repeatedSuccessCannotOverwriteLaterSettings() throws {
        let f = try Fixture(), request = try f.request()
        let ticket = try f.writer.prepare(request, connectionID: f.connection)
        #expect(f.writes == 0)
        let signed = f.signed(request, key: ticket.value)
        let result = try f.writer.update(signed, connectionID: f.connection)
        #expect(f.writes == 1 && f.values["editor.fontSize"] as? NSNumber == 23)
        f.values["editor.fontSize"] = 31
        #expect(try f.writer.update(signed, connectionID: f.connection) == result)
        let recovered = try f.writer.prepare(request, connectionID: f.connection)
        #expect(try f.writer.update(f.signed(request, key: recovered.value), connectionID: f.connection) == result)
        #expect(f.writes == 1 && f.values["editor.fontSize"] as? Int == 31)
    }

    @Test func changedSettingsAndChangedRequestsCannotReusePreparation() throws {
        let f = try Fixture(), request = try f.request()
        let ticket = try f.writer.prepare(request, connectionID: f.connection)
        f.values["editor.fontSize"] = 19
        #expect(throws: AgentErrorCode.versionConflict) { try f.writer.prepare(request, connectionID: f.connection) }
        #expect(throws: AgentErrorCode.versionConflict) {
            try f.writer.update(f.signed(request, key: ticket.value), connectionID: f.connection)
        }
        let changed = try f.request(value: 27, id: request.requestID)
        #expect(throws: AgentErrorCode.invalidInput) { try f.writer.prepare(changed, connectionID: f.connection) }
        #expect(f.writes == 0 && f.values["editor.fontSize"] as? Int == 19)
    }

    @Test func unknownWriteCannotExecuteAgain() throws {
        let f = try Fixture(), request = try f.request()
        let ticket = try f.writer.prepare(request, connectionID: f.connection)
        f.failAfterWrite = true
        let signed = f.signed(request, key: ticket.value)
        for _ in 0..<2 {
            #expect(throws: AgentErrorCode.outcomeUnknown) { try f.writer.update(signed, connectionID: f.connection) }
        }
        #expect(throws: AgentErrorCode.outcomeUnknown) { try f.writer.prepare(request, connectionID: f.connection) }
        #expect(f.writes == 1 && f.values["editor.fontSize"] as? NSNumber == 23)
    }

    @Test func changedGrantCannotRecoverAnEarlierResult() throws {
        let f = try Fixture(), request = try f.request()
        let ticket = try f.writer.prepare(request, connectionID: f.connection)
        _ = try f.writer.update(f.signed(request, key: ticket.value), connectionID: f.connection)
        f.grant = AgentGrant(connectionID: f.connection, libraryID: f.library, expiresAt: f.wall.addingTimeInterval(300),
            capabilities: [.preferencesWrite], scope: .library)
        #expect(throws: AgentErrorCode.permissionDenied) { try f.writer.prepare(request, connectionID: f.connection) }
        #expect(f.writes == 1)
    }

    @Test func humanReviewCannotBeReplacedByARetryKey() throws {
        let f = try Fixture(), request = try f.request()
        f.needsReview = true
        #expect(throws: AgentErrorCode.interactionRequired) { try f.writer.prepare(request, connectionID: f.connection) }
        #expect(f.writes == 0)
    }

    @Test func settingsChangeDuringReceiptKeepsTheNewValueAndBlocksReplay() throws {
        let f = try Fixture(), request = try f.request()
        let ticket = try f.writer.prepare(request, connectionID: f.connection)
        f.changeDuringReceipt = true
        let signed = f.signed(request, key: ticket.value)
        for _ in 0..<2 {
            #expect(throws: AgentErrorCode.outcomeUnknown) { try f.writer.update(signed, connectionID: f.connection) }
        }
        #expect(f.writes == 1 && f.values["editor.fontSize"] as? Int == 41)
    }

    @Test func capacityCannotDiscardAnExistingRequestIdentity() throws {
        let f = try Fixture(), first = try f.request()
        let ticket = try f.writer.prepare(first, connectionID: f.connection)
        for _ in 1..<128 { _ = try f.writer.prepare(f.request(), connectionID: f.connection) }
        let extra = try f.request()
        #expect(throws: AgentErrorCode.busy) { try f.writer.prepare(extra, connectionID: f.connection) }
        #expect(f.writes == 0)
        let signed = f.signed(first, key: ticket.value)
        let result = try f.writer.update(signed, connectionID: f.connection)
        #expect(try f.writer.update(signed, connectionID: f.connection) == result && f.writes == 1)
    }

    @Test func resetUsesTheSamePreparationAndReceiptPath() throws {
        let f = try Fixture(), request = try f.request(value: nil)
        let ticket = try f.writer.prepare(request, connectionID: f.connection)
        let signed = f.signed(request, key: ticket.value)
        let result = try f.writer.update(signed, connectionID: f.connection)
        #expect(f.values["editor.fontSize"] == nil && f.writes == 1)
        #expect(try f.writer.update(signed, connectionID: f.connection) == result && f.writes == 1)
    }
}
