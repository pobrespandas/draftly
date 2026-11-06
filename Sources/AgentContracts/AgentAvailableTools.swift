import Foundation

/// A current tool snapshot. Execution must still check the live grant.
package struct AgentAvailableTools: Sendable {
    package struct Definition: Equatable, Sendable {
        package let operation: String
        package let name: String
        package let summary: String
        package let inputSchema: AgentJSONValue
        package let isReadOnly: Bool
    }
    package let capabilities: Set<AgentCapability>
    package let inputs: [String: AgentJSONValue]
    package let definitions: [Definition]

    package init(capabilities: [String: AgentJSONValue], schemas: [String: AgentJSONValue]) throws {
        try AgentReadSchemas.validateResult(capabilities, for: "server.capabilities")
        try AgentReadSchemas.validateResult(schemas, for: "server.schemas")
        guard case .array(let caps) = capabilities["capabilities"],
              case .array(let operations) = schemas["operations"],
              case .object(let scope) = capabilities["scope"], case .bool(let allResources) = scope["allResources"] else {
            throw AgentErrorCode.unavailable
        }
        let allowed = Set(caps.compactMap { if case .string(let name) = $0 { return AgentCapability(rawValue: name) }; return nil })
        var inputs: [String: AgentJSONValue] = [:]
        var seen = Set<String>()
        for item in operations {
            guard case .object(let fields) = item, case .string(let name) = fields["name"],
                  seen.insert(name).inserted else { throw AgentErrorCode.invalidInput }
            guard fields["available"] == .bool(true),
                  let descriptor = AgentOperationCatalog.operation(named: name),
                  descriptor.permits(capabilities: allowed),
                  !descriptor.requiresLibraryScope || allResources,
                  let input = fields["inputSchema"], input != .null else { continue }
            inputs[name] = input
        }
        self.capabilities = allowed
        self.inputs = inputs
        definitions = AgentOperationCatalog.operations.sorted { $0.name < $1.name }.compactMap { operation in
            guard let input = inputs[operation.name] else { return nil }
            return Definition(operation: operation.name, name: AgentToolInput.name(for: operation.name),
                summary: operation.summary, inputSchema: AgentToolInput.schema(for: operation, parameters: input),
                isReadOnly: operation.isReadOnly)
        }
    }

    package func request(tool name: String, argumentsJSON: String) throws -> AgentRequest {
        guard argumentsJSON.utf8.count <= AgentRequest.maximumBytes,
              let operation = AgentToolInput.operation(named: name), inputs[operation.name] != nil else {
            throw AgentErrorCode.permissionDenied
        }
        guard case .object(let values) = try JSONDecoder().decode(AgentJSONValue.self, from: Data(argumentsJSON.utf8)) else {
            throw AgentErrorCode.invalidInput
        }
        return try AgentToolInput.request(operation: operation, arguments: values)
    }
}
