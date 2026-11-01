import Foundation
import Testing
@testable import AgentContracts

@Suite("Agent result envelopes")
struct AgentResponseTests {
    @Test func roundTripDistinguishesDataPendingWorkAndFailure() throws {
        for outcome in [AgentResponse.Outcome.result(.object(["content": .string("café 🐼")])),
                        .accepted(operationID: UUID(), state: .waitingForUser), .error(.storageError)] {
            let response = try AgentResponse(requestID: UUID(), outcome: outcome)
            #expect(try JSONDecoder().decode(AgentResponse.self, from: JSONEncoder().encode(response)) == response)
        }
    }

    @Test func anAcceptedHandleCannotHideACompletedOrUnknownOutcome() {
        for state in AgentOperationState.allCases where state.isTerminal {
            #expect(throws: AgentErrorCode.invalidInput) {
                try AgentResponse(requestID: UUID(), outcome: .accepted(operationID: UUID(), state: state))
            }
        }
    }

    @Test func conflictingSuccessAndErrorFieldsAreRejected() throws {
        let response = try AgentResponse(requestID: UUID(), outcome: .result(.null))
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])
        root["error"] = "storage_error"
        #expect(throws: AgentErrorCode.invalidInput) {
            try JSONDecoder().decode(AgentResponse.self, from: JSONSerialization.data(withJSONObject: root))
        }
    }
}
