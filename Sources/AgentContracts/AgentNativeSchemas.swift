import Foundation

// These contracts describe concrete native requests, not arbitrary host payloads.
package enum AgentNativeSchemas {
    package static let operationNames: Set<String> = Set(schemas.keys)
    package static let transientTextOperations: Set<String> = ["native.clipboardRead", "native.htmlToMarkdown", "native.dictate", "native.transcribe", "native.shortcut"]
    package static let unrestrictedOperations: Set<String> = ["native.shell", "native.appleScript", "native.shortcut"]
    package static func transientResultField(for operation: String) -> String? {
        if transientTextOperations.contains(operation) { return "text" }
        return ["native.location": "coordinates", "native.shell": "process", "native.appleScript": "valueJSON"][operation]
    }
    package static func unavailableResult(for operation: String) -> [String: AgentJSONValue]? {
        guard let field = transientResultField(for: operation) else { return nil }
        return [field: .null, "resultAvailable": .bool(false)]
    }
    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static let text = AgentValueShape.string(maximum: 65_536)
    private static let textResult = AgentObjectShape(fields: ["text": r(.nullable(text)), "resultAvailable": r(.boolean)])
    private static let completed = AgentObjectShape(fields: ["completed": r(.boolean)])
    private static let locale = AgentObjectShape(fields: ["locale": .init(shape: .string(maximum: 128), defaultValue: .string(""))])
    private static let coordinates = AgentObjectShape(fields: ["latitude": r(.number(minimum: -90, maximum: 90)),
        "longitude": r(.number(minimum: -180, maximum: 180))])
    private static let process = AgentObjectShape(fields: ["status": r(.integer(minimum: -2_147_483_648, maximum: 2_147_483_647)),
        "stdout": r(text), "stderr": r(text)])
    private static let schemas: [String: AgentOperationSchema] = [
        "native.clipboardRead": .init(parameters: .init(fields: [:]), result: textResult),
        "native.clipboardWrite": .init(parameters: .init(fields: ["text": r(text)]), result: completed),
        "native.htmlToMarkdown": .init(parameters: .init(fields: ["html": r(text)]), result: textResult),
        "native.share": .init(parameters: .init(fields: ["text": r(text)]), result: completed),
        "native.print": .init(parameters: .init(fields: ["text": r(text),
            "format": .init(shape: .string(choices: ["text", "html"]), defaultValue: .string("text"))]), result: completed),
        "native.openURL": .init(parameters: .init(fields: ["url": r(.string(minimum: 1, maximum: 8192))]), result: completed),
        "native.speak": .init(parameters: .init(fields: ["text": r(text)]), result: completed),
        "native.dictate": .init(parameters: locale, result: textResult),
        "native.transcribe": .init(parameters: locale, result: textResult),
        "native.location": .init(parameters: .init(fields: [:]), result: .init(fields: [
            "coordinates": r(.nullable(.object(coordinates))), "resultAvailable": r(.boolean)])),
        "native.shell": .init(parameters: .init(fields: ["source": r(text),
            "arguments": .init(shape: .array(.string(maximum: 8192), maximum: 128), defaultValue: .array([]))]),
            result: .init(fields: ["process": r(.nullable(.object(process))), "resultAvailable": r(.boolean)])),
        "native.appleScript": .init(parameters: .init(fields: ["source": r(text),
            "subroutine": .init(shape: .string(maximum: 1024), defaultValue: .string("")),
            "argumentsJSON": .init(shape: text, defaultValue: .string("[]"))]),
            result: .init(fields: ["valueJSON": r(.nullable(text)), "resultAvailable": r(.boolean)])),
        "native.shortcut": .init(parameters: .init(fields: ["name": r(.string(minimum: 1, maximum: 1024)),
            "text": .init(shape: text, defaultValue: .string(""))]), result: textResult)
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
        if request.operation == "native.shell", case .array(let arguments) = values["arguments"] {
            guard arguments.allSatisfy({ if case .string(let value) = $0 { return !value.contains("\0") }; return false }) else {
                throw AgentSchemaError.invalidValue
            }
        }
        if request.operation == "native.appleScript" {
            guard case .string(let raw) = values["argumentsJSON"],
                  let arguments = try boundedJSON(raw) as? [Any], arguments.count <= 128,
                  arguments.isEmpty || values["subroutine"] != .string("") else { throw AgentSchemaError.invalidValue }
        }
        return values
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for operation: String) throws {
        guard let schema = schemas[operation] else { throw AgentErrorCode.unavailable }
        try schema.result.validate(values)
        if let field = transientResultField(for: operation) {
            if values["resultAvailable"] == .bool(true) {
                guard values[field] != .null else { throw AgentSchemaError.invalidValue }
                if operation == "native.appleScript" {
                    guard case .string(let raw) = values[field], let envelope = try boundedJSON(raw) as? [String: Any],
                          envelope["value"] != nil, Set(envelope.keys).isSubset(of: ["value", "appleScriptDatePaths"]) else {
                        throw AgentSchemaError.invalidValue
                    }
                    if let paths = envelope["appleScriptDatePaths"] {
                        guard let paths = paths as? [String], paths.count <= 1024, Set(paths).count == paths.count,
                              paths.allSatisfy({ $0.isEmpty || $0.hasPrefix("/") }) else { throw AgentSchemaError.invalidValue }
                    }
                }
            } else if values[field] != .null { throw AgentSchemaError.invalidValue }
        }
    }

    // JSON-valued AppleScript data stays separate from native host routing fields.
    package static func boundedJSON(_ text: String) throws -> Any {
        guard text.unicodeScalars.count <= 65_536 else { throw AgentSchemaError.invalidValue }
        let value = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        var nodes = 0
        func check(_ value: Any, depth: Int) throws {
            nodes += 1
            guard depth <= 16, nodes <= 4096 else { throw AgentSchemaError.invalidValue }
            if let values = value as? [String: Any] { for child in values.values { try check(child, depth: depth + 1) } }
            else if let values = value as? [Any] { for child in values { try check(child, depth: depth + 1) } }
            else if let number = value as? NSNumber, !number.doubleValue.isFinite { throw AgentSchemaError.invalidValue }
        }
        try check(value, depth: 0)
        return value
    }
}
