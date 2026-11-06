import Foundation

// These contracts describe concrete native requests, not arbitrary host payloads.
package enum AgentNativeSchemas {
    package static let operationNames: Set<String> = Set(schemas.keys)
    package static let transientTextOperations: Set<String> = ["native.clipboardRead", "native.htmlToMarkdown", "native.dictate", "native.transcribe", "native.shortcut"]
    package static let unrestrictedOperations: Set<String> = ["native.shell", "native.appleScript", "native.shortcut"]
    package static func transientResultField(for operation: String) -> String? {
        if transientTextOperations.contains(operation) { return "text" }
        return ["native.http": "response", "native.xmlrpc": "response", "native.location": "coordinates", "native.shell": "process", "native.appleScript": "valueJSON", "native.models": "model"][operation]
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
    private static let httpResponse = AgentObjectShape(fields: [
        "success": r(.boolean), "statusCode": r(.integer(minimum: 100, maximum: 999)),
        "headersJSON": r(text), "responseText": r(text),
        "bodyBase64": r(.string(maximum: 87_384))
    ])
    private static let modelMode = AgentValueShape.string(choices: ["onDevice", "pcc"])
    private static let modelResult = AgentObjectShape(fields: [
        "modes": .init(shape: .array(modelMode, maximum: 2)),
        "text": .init(shape: text)
    ])
    private static let schemas: [String: AgentOperationSchema] = [
        "native.models": .init(parameters: .init(fields: [
            "mode": .init(shape: modelMode), "prompt": .init(shape: .string(minimum: 1, maximum: 65_536))
        ]), result: .init(fields: ["model": r(.nullable(.object(modelResult))), "resultAvailable": r(.boolean)])),
        "native.http": .init(parameters: .init(fields: [
            "url": r(.string(minimum: 1, maximum: 8192)),
            "method": .init(shape: .string(minimum: 1, maximum: 32), defaultValue: .string("GET")),
            "headersJSON": .init(shape: text, defaultValue: .string("{}")),
            "bodyText": .init(shape: text), "bodyBase64": .init(shape: .string(maximum: 87_384)),
            "timeout": .init(shape: .number(minimum: 0.001, maximum: 90), defaultValue: .integer(60)),
            "followRedirects": .init(shape: .boolean, defaultValue: .bool(false))
        ]), result: .init(fields: ["response": r(.nullable(.object(httpResponse))), "resultAvailable": r(.boolean)])),
        "native.xmlrpc": .init(parameters: .init(fields: [
            "url": r(.string(minimum: 1, maximum: 8192)),
            "methodName": r(.string(minimum: 1, maximum: 256)),
            "paramsJSON": .init(shape: text, defaultValue: .string("[]")),
            "timeout": .init(shape: .number(minimum: 0.001, maximum: 90), defaultValue: .integer(60))
        ]), result: .init(fields: ["response": r(.nullable(.object(.init(fields: [
            "success": r(.boolean), "statusCode": r(.integer(minimum: 100, maximum: 999)),
            "paramsJSON": r(text), "faultCode": .init(shape: .integer()), "error": .init(shape: text)
        ])))), "resultAvailable": r(.boolean)])),
        "native.clipboardRead": .init(parameters: .init(fields: [:]), result: textResult),
        "native.clipboardWrite": .init(parameters: .init(fields: ["text": r(text)]), result: completed),
        "native.htmlPreview": .init(parameters: .init(fields: ["html": r(text)]), result: completed),
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
        if request.operation == "native.models", (values["mode"] == nil) != (values["prompt"] == nil) {
            throw AgentSchemaError.invalidValue
        }
        if request.operation == "native.http" {
            guard case .string(let raw) = values["url"], let url = URLComponents(string: raw), url.url != nil,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
                  url.user == nil, url.password == nil, url.fragment == nil,
                  url.port.map({ (1...65535).contains($0) }) ?? true,
                  case .string(let method) = values["method"], httpToken(method),
                  case .string(let text) = values["headersJSON"], let headers = try boundedJSON(text) as? [String: String], headers.count <= 128,
                  Set(headers.keys.map { $0.lowercased() }).count == headers.count,
                  headers.allSatisfy({ name, value in name.utf8.count <= 1024 && httpToken(name)
                    && !["host", "connection", "content-length", "transfer-encoding", "proxy-authorization", "upgrade", "te", "trailer"].contains(name.lowercased())
                    && value.utf8.count <= 8192 && value.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) }),
                  values["bodyText"] == nil || values["bodyBase64"] == nil else { throw AgentSchemaError.invalidValue }
            if case .string(let body) = values["bodyText"], body.utf8.count > 65_536 { throw AgentSchemaError.invalidValue }
            if case .string(let body) = values["bodyBase64"] {
                guard let data = Data(base64Encoded: body), data.count <= 65_536, data.base64EncodedString() == body else { throw AgentSchemaError.invalidValue }
            }
        }
        if request.operation == "native.xmlrpc" {
            guard case .string(let raw) = values["url"], let url = URLComponents(string: raw), url.url != nil,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
                  url.user == nil, url.password == nil, url.fragment == nil,
                  url.port.map({ (1...65535).contains($0) }) ?? true,
                  case .string(let method) = values["methodName"],
                  method.utf8.allSatisfy({ byte in
                      (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
                          || [95, 46, 58, 47].contains(byte)
                  }),
                  case .string(let json) = values["paramsJSON"], let params = try boundedJSON(json) as? [Any],
                  params.count <= 128 else { throw AgentSchemaError.invalidValue }
        }
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
        if operation == "native.http", case .object(let response) = values["response"] {
            guard case .integer(let status) = response["statusCode"], response["success"] == .bool((200..<300).contains(status)),
                  case .string(let raw) = response["headersJSON"], try boundedJSON(raw) is [String: String],
                  case .string(let body) = response["bodyBase64"], let data = Data(base64Encoded: body),
                  data.count <= 65_536, data.base64EncodedString() == body else { throw AgentSchemaError.invalidValue }
        }
        if operation == "native.xmlrpc", case .object(let response) = values["response"] {
            guard case .string(let raw) = response["paramsJSON"], let params = try boundedJSON(raw) as? [Any],
                  case .integer(let status) = response["statusCode"],
                  response["success"] == .bool(false) || (status == 200 && response["error"] == nil && response["faultCode"] == nil),
                  response["success"] == .bool(true) || params.isEmpty else { throw AgentSchemaError.invalidValue }
        }
        if operation == "native.models", case .object(let model) = values["model"],
           (model["modes"] == nil) == (model["text"] == nil) { throw AgentSchemaError.invalidValue }
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

    private static func httpToken(_ value: String) -> Bool {
        let punctuation = Array("!#$%&'*+-.^_`|~".utf8)
        return !value.isEmpty && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || punctuation.contains($0)
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
