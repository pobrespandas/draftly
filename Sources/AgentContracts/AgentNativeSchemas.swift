import Foundation

// These contracts describe concrete native requests, not arbitrary host payloads.
package enum AgentNativeSchemas {
    package static let operationNames: Set<String> = Set(schemas.keys)
    package static let transientTextOperations: Set<String> = ["native.clipboardRead", "native.htmlToMarkdown"]
    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static let text = AgentValueShape.string(maximum: 65_536)
    private static let textResult = AgentObjectShape(fields: ["text": r(.nullable(text)), "resultAvailable": r(.boolean)])
    private static let completed = AgentObjectShape(fields: ["completed": r(.boolean)])
    private static let schemas: [String: AgentOperationSchema] = [
        "native.clipboardRead": .init(parameters: .init(fields: [:]), result: textResult),
        "native.clipboardWrite": .init(parameters: .init(fields: ["text": r(text)]), result: completed),
        "native.htmlToMarkdown": .init(parameters: .init(fields: ["html": r(text)]), result: textResult),
        "native.share": .init(parameters: .init(fields: ["text": r(text)]), result: completed),
        "native.print": .init(parameters: .init(fields: ["text": r(text),
            "format": .init(shape: .string(choices: ["text", "html"]), defaultValue: .string("text"))]), result: completed),
        "native.openURL": .init(parameters: .init(fields: ["url": r(.string(minimum: 1, maximum: 8192))]), result: completed),
        "native.speak": .init(parameters: .init(fields: ["text": r(text)]), result: completed)
    ]

    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }

    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard request.apiVersion == AgentRequest.version, request.targets.isEmpty,
              let schema = schemas[request.operation], request.retryKey == nil else { throw AgentSchemaError.invalidValue }
        let values = try schema.validatedParameters(request.parameters)
        if request.operation == "native.openURL" {
            guard case .string(let raw) = values["url"], let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(), !scheme.isEmpty,
                  !["file", "javascript", "data"].contains(scheme),
                  !["http", "https"].contains(scheme) || url.host?.isEmpty == false else { throw AgentSchemaError.invalidValue }
        }
        return values
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for operation: String) throws {
        guard let schema = schemas[operation] else { throw AgentErrorCode.unavailable }
        try schema.result.validate(values)
        if transientTextOperations.contains(operation) {
            if values["resultAvailable"] == .bool(true) {
                guard case .string = values["text"] else { throw AgentSchemaError.invalidValue }
            } else if values["text"] != .null { throw AgentSchemaError.invalidValue }
        }
    }
}
