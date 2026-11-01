import Foundation

// Prepare requests without owning input streams or the connection lifetime.
package enum AgentCLIRequest {
    package static func make(mode: String, operationName: String? = nil,
                             readInput: () throws -> Data) throws -> AgentRequest {
        switch mode {
        case "json":
            return try AgentRequest.decode(readInput())
        case "call":
            guard let operationName,
                  let operation = AgentOperationCatalog.operation(named: operationName),
                  case .object(let arguments) = try JSONDecoder().decode(AgentJSONValue.self, from: readInput()) else {
                throw AgentErrorCode.invalidInput
            }
            return try AgentToolInput.request(operation: operation, arguments: arguments)
        case "status", "capabilities":
            return AgentRequest(requestID: UUID(), libraryID: nil,
                                operation: mode == "status" ? "server.status" : "server.capabilities")
        default:
            throw AgentErrorCode.invalidInput
        }
    }
}
