import Foundation

package enum AgentBookmarkSchemas {
    package static var operationNames: Set<String> { Set(schemas.keys) }
    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }
    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static let summary = AgentObjectShape(fields: [
        "id": r(.uuid), "name": r(.string(minimum: 1)), "versionToken": r(AgentResourceShapes.token)
    ])
    private static let schemas: [String: AgentOperationSchema] = [
        "bookmarks.list": .init(parameters: .init(fields: [
            "limit": .init(shape: .integer(minimum: 1, maximum: 200), defaultValue: .integer(50)),
            "cursor": .init(shape: AgentResourceShapes.token)
        ]), result: .init(fields: ["items": r(.array(.object(summary), maximum: 200)),
            "nextCursor": r(.nullable(AgentResourceShapes.token))])),
        "bookmarks.requestAdd": .init(parameters: .init(fields: [
            "name": r(.string(minimum: 1)), "interactive": .init(shape: .boolean, defaultValue: .bool(false))
        ]), result: .init(fields: ["bookmark": r(.object(summary))])),
        "bookmarks.forget": .init(parameters: .init(fields: [:]), result: AgentResourceShapes.deleted)
    ]

    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard let schema = schema(for: request.operation) else { throw AgentErrorCode.unavailable }
        let values = try schema.validatedParameters(request.parameters)
        if request.operation == "bookmarks.requestAdd" {
            guard case .string(let name) = values["name"], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentSchemaError.invalidValue
            }
        }
        return values
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for operation: String) throws {
        guard let schema = schema(for: operation) else { throw AgentErrorCode.unavailable }
        try schema.result.validate(values)
        if operation == "bookmarks.list", case .array(let items) = values["items"] {
            let ids = items.compactMap { value -> UUID? in
                guard case .object(let fields) = value, case .string(let id) = fields["id"] else { return nil }
                return UUID(uuidString: id)
            }
            guard Set(ids).count == ids.count else { throw AgentSchemaError.invalidValue }
        }
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for request: AgentRequest) throws {
        try validateResult(values, for: request.operation)
        if request.operation == "bookmarks.forget" {
            try AgentResourceShapes.validateOrder(values["deletedIDs"], targets: request.targets)
        } else if request.operation == "bookmarks.requestAdd" {
            guard case .object(let bookmark) = values["bookmark"], bookmark["name"] == request.parameters["name"] else {
                throw AgentSchemaError.invalidValue
            }
        }
    }
}
