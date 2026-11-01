import Foundation
import Testing
import AgentContracts

@Suite("Mutation key preparation contracts")
struct AgentMutationPreparationTests {
    private func request() throws -> AgentRequest {
        let inner = AgentRequest(requestID: UUID(), libraryID: nil, operation: "drafts.update",
            targets: [.init(kind: .draft, id: UUID())], expectedVersion: "snapshot",
            parameters: ["changes": .object(["content": .string("Neutral 🐼")])])
        let value = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(inner))
        return AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "mutations.prepare", parameters: ["request": value])
    }
    @Test func preparationHasATypedRequestAndBoundResult() throws {
        let outer = try request()
        _ = try AgentOperationSchemas.validatedParameters(for: outer)
        let inner = try #require(outer.parameters["request"])
        guard case .object(let fields) = inner, case .string(let id) = fields["requestID"] else { Issue.record("Missing request ID"); return }
        let result: [String: AgentJSONValue] = ["requestID": .string(id), "retryKey": .string("opaque.key"),
            "expiresAt": .string("2026-11-01T00:00:00Z")]
        try AgentOperationSchemas.validateResult(result, for: outer)
        var wrong = result; wrong["requestID"] = .string(UUID().uuidString)
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(wrong, for: outer) }
    }
    @Test func preparingAnExistingKeyOrSupplyingAuthorityIsRejected() throws {
        let original = try request()
        guard case .object(let fields) = original.parameters["request"] else { Issue.record("Missing request"); return }
        for field in ["retryKey", "connectionID", "grantID", "approved"] {
            var changed = fields; changed[field] = .string("untrusted")
            let outer = AgentRequest(requestID: original.requestID, libraryID: original.libraryID,
                operation: original.operation, parameters: ["request": .object(changed)])
            #expect(throws: (any Error).self) { try AgentOperationSchemas.validatedParameters(for: outer) }
        }
    }
}
