import Foundation

package struct AgentResponse: Equatable, Sendable, Codable {
    package enum Outcome: Equatable, Sendable {
        case result(AgentJSONValue)
        case accepted(operationID: UUID, state: AgentOperationState)
        case error(AgentErrorCode)
    }

    package let requestID: UUID
    package let outcome: Outcome

    package init(requestID: UUID, outcome: Outcome) throws {
        if case .accepted(_, let state) = outcome, state.isTerminal {
            throw AgentErrorCode.invalidInput
        }
        self.requestID = requestID
        self.outcome = outcome
    }

    private enum CodingKeys: String, CodingKey {
        case apiVersion, requestID, status, value, operationID, state, error
    }

    private enum Status: String, Codable { case result, accepted, error }

    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .apiVersion) == AgentRequest.version else {
            throw AgentErrorCode.invalidInput
        }
        let outcome: Outcome
        switch try values.decode(Status.self, forKey: .status) {
        case .result:
            guard !values.contains(.error), !values.contains(.operationID), !values.contains(.state) else {
                throw AgentErrorCode.invalidInput
            }
            outcome = .result(try values.decode(AgentJSONValue.self, forKey: .value))
        case .accepted:
            guard !values.contains(.error), !values.contains(.value) else { throw AgentErrorCode.invalidInput }
            outcome = .accepted(operationID: try values.decode(UUID.self, forKey: .operationID),
                state: try values.decode(AgentOperationState.self, forKey: .state))
        case .error:
            guard !values.contains(.value), !values.contains(.operationID), !values.contains(.state) else {
                throw AgentErrorCode.invalidInput
            }
            outcome = .error(try values.decode(AgentErrorCode.self, forKey: .error))
        }
        try self.init(requestID: values.decode(UUID.self, forKey: .requestID), outcome: outcome)
    }

    package func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(AgentRequest.version, forKey: .apiVersion)
        try values.encode(requestID, forKey: .requestID)
        switch outcome {
        case .result(let result):
            try values.encode(Status.result, forKey: .status)
            try values.encode(result, forKey: .value)
        case .accepted(let id, let state):
            try values.encode(Status.accepted, forKey: .status)
            try values.encode(id, forKey: .operationID)
            try values.encode(state, forKey: .state)
        case .error(let error):
            try values.encode(Status.error, forKey: .status)
            try values.encode(error, forKey: .error)
        }
    }
}
