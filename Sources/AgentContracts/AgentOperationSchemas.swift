import Foundation

package enum AgentOperationSchemas {
    package static var operationNames: Set<String> {
        AgentReadSchemas.operationNames.union(AgentActionSchemas.operationNames).union(AgentExecutionSchemas.operationNames).union(AgentWorkspaceSchemas.operationNames).union(AgentDraftSchemas.operationNames)
    }

    package static func schema(for operation: String) -> AgentOperationSchema? {
        AgentReadSchemas.schema(for: operation) ?? AgentActionSchemas.schema(for: operation)
            ?? AgentExecutionSchemas.schema(for: operation) ?? AgentWorkspaceSchemas.schema(for: operation) ?? AgentDraftSchemas.schema(for: operation)
    }

    // This validates shape and target binding. It does not authorize or execute a request.
    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard let descriptor = AgentOperationCatalog.operation(named: request.operation) else {
            throw AgentErrorCode.unavailable
        }
        guard request.apiVersion == AgentRequest.version, descriptor.acceptsTargets(request.targets) else {
            throw AgentSchemaError.invalidValue
        }
        if descriptor.requiresExpectedVersion {
            guard let version = request.expectedVersion, !version.isEmpty else { throw AgentSchemaError.invalidValue }
        }
        if AgentActionSchemas.operationNames.contains(request.operation) {
            return try AgentActionSchemas.validatedParameters(for: request)
        }
        if AgentWorkspaceSchemas.operationNames.contains(request.operation) {
            return try AgentWorkspaceSchemas.validatedParameters(for: request)
        }
        if AgentDraftSchemas.operationNames.contains(request.operation) {
            return try AgentDraftSchemas.validatedParameters(for: request)
        }
        guard let schema = schema(for: request.operation) else { throw AgentErrorCode.unavailable }
        return try schema.validatedParameters(request.parameters)
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for operation: String) throws {
        if AgentReadSchemas.operationNames.contains(operation) {
            try AgentReadSchemas.validateResult(values, for: operation)
        } else if AgentExecutionSchemas.operationNames.contains(operation) {
            try AgentExecutionSchemas.validateResult(values, for: operation)
        } else {
            guard let schema = schema(for: operation) else { throw AgentErrorCode.unavailable }
            try schema.result.validate(values)
        }
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for request: AgentRequest) throws {
        guard let descriptor = AgentOperationCatalog.operation(named: request.operation),
              request.apiVersion == AgentRequest.version, descriptor.acceptsTargets(request.targets) else {
            throw AgentSchemaError.invalidValue
        }
        if AgentDraftSchemas.operationNames.contains(request.operation) {
            try AgentDraftSchemas.validateResult(values, for: request)
            return
        }
        try validateResult(values, for: request.operation)
        let binding: (field: String, key: String, kind: AgentResourceKind)?
        switch request.operation {
        case "drafts.get": binding = ("draft", "id", .draft)
        case "actions.get": binding = ("action", "id", .action)
        case "workspaces.get": binding = ("workspace", "id", .workspace)
        case "workspaces.update": binding = ("resource", "id", .workspace)
        case "actionGroups.get": binding = ("group", "id", .actionGroup)
        case "actions.update", "actions.move": binding = ("resource", "id", .action)
        case "actionGroups.update": binding = ("resource", "id", .actionGroup)
        case "operations.get", "operations.wait", "operations.cancel", "operations.answerPrompt":
            binding = ("operation", "operationID", .operation)
        default: binding = nil
        }
        if request.operation == "workspaces.apply" {
            for (key, kind) in [("workspaceID", AgentResourceKind.workspace), ("windowID", .window)] {
                guard case .string(let rawID) = values[key],
                      UUID(uuidString: rawID) == request.targets.first(where: { $0.kind == kind })?.id else {
                    throw AgentSchemaError.invalidValue
                }
            }
        }
        if let binding {
            guard case .object(let object) = values[binding.field], case .string(let id) = object[binding.key],
                  UUID(uuidString: id) == request.targets.first(where: { $0.kind == binding.kind })?.id else {
                throw AgentSchemaError.invalidValue
            }
        }
    }
}
