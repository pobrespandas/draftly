import Foundation
import Testing
@testable import AgentContracts

@Suite("Agent request contracts")
struct AgentRequestTests {
    @Test func roundTripRetainsUnicodeUnknownFieldsAndDistinctJSONTypes() throws {
        let input: [String: AgentJSONValue] = [
            "content": .string("café 🐼\r\nA"), "future": .object(["nested": .array([
                .null, .bool(false), .integer(0), .integer(Int64.max), .number(1.25), .string("0")])])
        ]
        let request = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "drafts.create", parameters: input)
        #expect(try AgentRequest.decode(JSONEncoder().encode(request)) == request)
    }

    @Test func decimalFieldsDoNotPassThroughBinaryFloatingPoint() throws {
        let decimal = try #require(Decimal(string: "1234567890.1234567890123456789", locale: Locale(identifier: "en_US_POSIX")))
        let input = AgentJSONValue.number(decimal)
        #expect(try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(input)) == input)
    }

    @Test(arguments: ["[]", "null", "{}", "{", "true"])
    func malformedEnvelopesAreTypedErrors(json: String) {
        #expect(throws: AgentErrorCode.invalidInput) { try AgentRequest.decode(Data(json.utf8)) }
    }

    @Test func unsupportedVersionEmptyTokensAndDuplicateTargetsAreRejected() throws {
        let target = AgentResourceReference(kind: .draft, id: UUID())
        let request = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "drafts.update",
            targets: [target], expectedVersion: "snapshot")
        let encoded = try JSONEncoder().encode(request)
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        root["apiVersion"] = 2
        #expect(throws: AgentErrorCode.invalidInput) { try AgentRequest.decode(JSONSerialization.data(withJSONObject: root)) }
        root["apiVersion"] = 1; root["expectedVersion"] = ""
        #expect(throws: AgentErrorCode.invalidInput) { try AgentRequest.decode(JSONSerialization.data(withJSONObject: root)) }
        let duplicate = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "drafts.update", targets: [target, target])
        #expect(throws: AgentErrorCode.invalidInput) { try AgentRequest.decode(JSONEncoder().encode(duplicate)) }
    }

    @Test func oversizedMessagesAndNonfiniteNumbersAreRejected() {
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentRequest.decode(Data(repeating: 0x20, count: AgentRequest.maximumBytes + 1))
        }
        #expect(throws: (any Error).self) { try JSONEncoder().encode(AgentJSONValue.number(.nan)) }
    }

    @Test func unknownOperationRemainsANameAndNeverBecomesAHandler() throws {
        let request = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "future.evaluate")
        let decoded = try AgentRequest.decode(JSONEncoder().encode(request))
        #expect(decoded.operation == request.operation)
        #expect(AgentOperationCatalog.operation(named: decoded.operation) == nil)
    }

    @Test func outcomeUnknownIsTerminalButWaitingForThePersonIsNotSuccess() {
        #expect(AgentOperationState.outcomeUnknown.isTerminal)
        #expect(AgentOperationState.cancelled.isTerminal)
        #expect(!AgentOperationState.waitingForUser.isTerminal)
        #expect(!AgentOperationState.running.isTerminal)
    }
    @Test func batchTargetsCannotExceedTheReceiptCapacity() throws {
        let targets = (0..<10_001).map { _ in AgentResourceReference(kind: .draft, id: UUID()) }
        let input = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "drafts.archive",
            targets: targets, expectedVersion: "snapshot")
        #expect(throws: AgentErrorCode.invalidInput) { try AgentRequest.decode(JSONEncoder().encode(input)) }
        let rejectsOversizedBatch = !AgentTargetRule.many(.draft).accepts(targets)
        #expect(rejectsOversizedBatch)
        let allowed = Array(targets.prefix(10_000))
        let boundary = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "drafts.archive",
            targets: allowed, expectedVersion: "snapshot")
        let decoded = try AgentRequest.decode(JSONEncoder().encode(boundary))
        let preservesTargets = decoded.targets == allowed
        #expect(preservesTargets)
        let acceptsBoundary = AgentTargetRule.many(.draft).accepts(allowed)
        #expect(acceptsBoundary)
    }

    @Test func retryKeySurvivesEnvelopeRoundTripAndOldRequestsStayCompatible() throws {
        let original = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "drafts.create")
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        #expect(root["retryKey"] == nil)
        root["retryKey"] = "opaque.signed-key"
        let decoded = try AgentRequest.decode(JSONSerialization.data(withJSONObject: root))
        let output = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        #expect(output["retryKey"] as? String == "opaque.signed-key")
    }

    @Test(arguments: ["", String(repeating: "x", count: 4097), String(repeating: "🐼", count: 1025)])
    func invalidRetryKeyBudgetsAreRejected(value: String) throws {
        let request = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "drafts.create")
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        root["retryKey"] = value
        #expect(throws: AgentErrorCode.invalidInput) { try AgentRequest.decode(JSONSerialization.data(withJSONObject: root)) }
    }

}
