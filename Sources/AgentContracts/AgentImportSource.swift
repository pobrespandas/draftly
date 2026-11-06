import Foundation

// This identifies input. It does not open a file, fetch a URL or grant access.
package enum AgentImportSource {
    package static let shape = AgentValueShape.oneOf([
        variant("inline", ["text": .string()]),
        variant("transfer", ["transferID": .uuid]),
        variant("bookmark", ["bookmarkID": .uuid, "path": .string(minimum: 1, maximum: 4096)]),
        variant("installationURL", ["url": .string(minimum: 1)]),
        variant("https", ["url": .string(minimum: 1)])
    ])

    package static let backupShape = AgentValueShape.oneOf([
        variant("inline", ["text": .string()]),
        variant("transfer", ["transferID": .uuid]),
        variant("bookmark", ["bookmarkID": .uuid, "path": .string(minimum: 1, maximum: 4096)]),
        variant("https", ["url": .string(minimum: 1)])
    ])

    private static func variant(_ kind: String, _ fields: [String: AgentValueShape]) -> AgentValueShape {
        var result = fields.mapValues { AgentFieldShape(shape: $0, required: true) }
        result["kind"] = .init(shape: .string(choices: [kind]), required: true)
        return .object(.init(fields: result))
    }

    package static func validate(_ value: AgentJSONValue?, installationEndpoint: String? = nil) throws -> String {
        guard case .object(let fields) = value else { throw AgentSchemaError.invalidValue }
        try shape.validate(.object(fields))
        guard case .string(let kind) = fields["kind"] else { throw AgentSchemaError.invalidValue }
        switch kind {
        case "inline", "transfer": break
        case "bookmark":
            guard case .string(let path) = fields["path"], !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
                  path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw AgentSchemaError.invalidValue
            }
        case "installationURL", "https":
            guard case .string(let text) = fields["url"], let url = URLComponents(string: text), url.url != nil,
                  url.user == nil, url.password == nil, url.fragment == nil else { throw AgentSchemaError.invalidValue }
            if kind == "installationURL" {
                guard let installationEndpoint, url.scheme == "draftly", url.host == installationEndpoint,
                      url.port == nil, url.path.isEmpty, let items = url.queryItems, !items.isEmpty,
                      Set(items.map(\.name)).count == items.count,
                      Set(items.map(\.name)).isSubset(of: installationEndpoint == "theme" ? ["type", "name", "data"] : ["name", "data"]),
                      items.allSatisfy({ $0.value != nil }) else { throw AgentSchemaError.invalidValue }
            } else {
                guard url.scheme == "https", let host = url.host, !host.isEmpty,
                      url.port.map({ (1...65535).contains($0) }) ?? true else { throw AgentSchemaError.invalidValue }
            }
        default: throw AgentSchemaError.invalidValue
        }
        return kind
    }
}


package enum AgentImportSchemas {
    package static let operationNames: Set<String> = ["imports.validate", "imports.preview", "imports.commit"]

    private static let input = AgentObjectShape(fields: [
        "source": .init(shape: AgentImportSource.backupShape, required: true),
        "fileExtension": .init(shape: .string(minimum: 1, maximum: 32), required: true)
    ])
    private static let changes = AgentFieldShape(shape: .object(AgentBackupSchemas.changes), required: true)
    private static let version = AgentFieldShape(shape: AgentResourceShapes.token, required: true)

    package static func schema(for operation: String) -> AgentOperationSchema? {
        let fields: [String: AgentFieldShape]
        switch operation {
        case "imports.validate": fields = ["valid": .init(shape: .boolean, required: true)]
        case "imports.preview": fields = ["changes": changes, "versionToken": version]
        case "imports.commit": fields = ["changes": changes]
        default: return nil
        }
        return .init(parameters: input, result: .init(fields: fields))
    }

    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard let schema = schema(for: request.operation) else { throw AgentErrorCode.unavailable }
        let values = try schema.validatedParameters(request.parameters)
        _ = try AgentImportSource.validate(values["source"])
        guard case .string(let fileExtension) = values["fileExtension"], fileExtension.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
        }) else { throw AgentSchemaError.invalidValue }
        return values
    }
}
