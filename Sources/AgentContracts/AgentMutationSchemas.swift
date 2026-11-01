import Foundation

// Preparation signs an authorized intent. It does not execute it or approve effects.
package enum AgentMutationSchemas {
    package static let name = "mutations.prepare"
    package static let operationNames: Set<String> = [name]
    private static func r(_ value: AgentValueShape) -> AgentFieldShape { .init(shape: value, required: true) }
    private static let reference = AgentObjectShape(fields: [
        "kind": r(.string(choices: AgentResourceKind.allCases.map(\.rawValue))), "id": r(.uuid)
    ])
    private static let frame = AgentObjectShape(fields: [
        "apiVersion": r(.integer(minimum: 1, maximum: 1)), "requestID": r(.uuid),
        "libraryID": .init(shape: .uuid), "operation": r(.string(minimum: 1, maximum: 128)),
        "targets": r(.array(.object(reference), maximum: AgentRequest.maximumTargets)),
        "expectedVersion": .init(shape: AgentResourceShapes.token),
        "parameters": r(.object(.init(fields: [:], allowsAdditionalFields: true)))
    ])
    private static let value = AgentOperationSchema(parameters: .init(fields: ["request": r(.object(frame))]),
        result: .init(fields: ["requestID": r(.uuid), "retryKey": r(.string(minimum: 1, maximum: AgentRequest.maximumRetryKeyBytes)),
                              "expiresAt": r(.utcDate)]))

    package static func schema(for operation: String) -> AgentOperationSchema? { operation == name ? value : nil }
    package static func mutation(from parameters: [String: AgentJSONValue]) throws -> AgentRequest {
        guard let frame = parameters["request"] else { throw AgentSchemaError.invalidValue }
        do { return try AgentRequest.decode(JSONEncoder().encode(frame)) }
        catch { throw AgentSchemaError.invalidValue }
    }
    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard request.retryKey == nil else { throw AgentSchemaError.invalidValue }
        let parameters = try value.validatedParameters(request.parameters)
        _ = try mutation(from: parameters)
        return parameters
    }
    package static func validateResult(_ values: [String: AgentJSONValue], for request: AgentRequest) throws {
        try value.result.validate(values)
        let input = try mutation(from: request.parameters)
        guard case .string(let id) = values["requestID"], UUID(uuidString: id) == input.requestID else {
            throw AgentSchemaError.invalidValue
        }
    }
}
