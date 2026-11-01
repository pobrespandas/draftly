import Foundation
import Testing
import AgentContracts

@Suite("Named agent tool input")
struct AgentToolInputTests {
    @Test func namesAreUniqueAndResolveOnlyTheRequiredCatalog() throws {
        let names = AgentOperationCatalog.operations.map { AgentToolInput.name(for: $0.name) }
        #expect(names.count == 136 && Set(names).count == names.count)
        for operation in AgentOperationCatalog.operations { #expect(AgentToolInput.operation(named: AgentToolInput.name(for: operation.name))?.name == operation.name) }
        #expect(AgentToolInput.operation(named: "run_any_script") == nil)
        #expect(Set(AgentOperationCatalog.operations.filter(\.isReadOnly).map(\.name)) == AgentReadSchemas.operationNames)
    }
    @Test func requestTargetsAndAuthorityCannotBeReboundByToolArguments() throws {
        let operation = try #require(AgentToolInput.operation(named: "draftly_drafts_get")), id = UUID()
        let targets = AgentJSONValue.array([.object(["kind": .string("draft"), "id": .string(id.uuidString)])])
        let request = try AgentToolInput.request(operation: operation, arguments: ["targets": targets])
        #expect(request.operation == "drafts.get" && request.libraryID == nil && request.targets == [.init(kind: .draft, id: id)])
        for field in ["operation", "libraryID", "grantID", "connectionID", "approved"] {
            #expect(throws: AgentErrorCode.invalidInput) { try AgentToolInput.request(operation: operation, arguments: ["targets": targets, field: .string("untrusted")]) }
        }
        #expect(throws: AgentErrorCode.invalidInput) { try AgentToolInput.request(operation: operation, arguments: [:]) }
    }
    @Test func exactJSONPreservesDecimalUnicodeAndUnknownImportedFields() throws {
        let operation = try #require(AgentOperationCatalog.operation(named: "actions.create")), id = UUID()
        let text = #"{"future":{"number":1.234567890123456789,"text":"e\u0301 🐼"}}"#
        let request = try AgentToolInput.request(operation: operation, arguments: ["requestID": .string(id.uuidString), "parametersJSON": .string(text)])
        guard case .object(let expected) = try JSONDecoder().decode(AgentJSONValue.self, from: Data(text.utf8)) else { return }
        #expect(request.parameters == expected && request.requestID == id)
        #expect(throws: AgentErrorCode.invalidInput) { try AgentToolInput.request(operation: operation, arguments: ["requestID": .string(id.uuidString), "parametersJSON": .string(text), "parameters": .object([:])]) }
        #expect(throws: AgentErrorCode.invalidInput) { try AgentToolInput.request(operation: operation, arguments: ["requestID": .string(id.uuidString), "parametersJSON": .string("[]")]) }
    }
    @Test func editsRequireAnExplicitRequestIDAndExpectedVersion() throws {
        let operation = try #require(AgentOperationCatalog.operation(named: "drafts.update")), id = UUID()
        let targets = AgentJSONValue.array([.object(["kind": .string("draft"), "id": .string(id.uuidString)])])
        #expect(throws: AgentErrorCode.invalidInput) { try AgentToolInput.request(operation: operation, arguments: ["targets": targets, "expectedVersion": .string("opaque")]) }
        #expect(throws: AgentErrorCode.invalidInput) { try AgentToolInput.request(operation: operation, arguments: ["targets": targets, "requestID": .string(UUID().uuidString)]) }
    }
    @Test func toolSchemasReuseTheHostsParameterRulesAndRejectBothRepresentations() throws {
        let operation = try #require(AgentOperationCatalog.operation(named: "drafts.search")), parameters = try #require(AgentReadSchemas.schema(for: "drafts.search")).parameters.jsonSchema
        guard case .object(let root) = AgentToolInput.schema(for: operation, parameters: parameters), case .object(let properties) = root["properties"] else { Issue.record("Missing tool schema"); return }
        #expect(properties["parameters"] == parameters)
        #expect(root["not"] == .object(["required": .array([.string("parameters"), .string("parametersJSON")])]))
    }
    @Test func mutationToolsCarryTheRetryKeyWithoutTreatingItAsAParameter() throws {
        let operation = try #require(AgentOperationCatalog.operation(named: "drafts.create"))
        let request = try AgentToolInput.request(operation: operation, arguments: [
            "requestID": .string(UUID().uuidString), "retryKey": .string("opaque.signed-key"),
            "parameters": .object(["content": .string("Neutral 🐼")])])
        let root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(root["retryKey"] as? String == "opaque.signed-key")
        #expect(request.parameters["retryKey"] == nil)
    }

}
