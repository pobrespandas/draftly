import Foundation

package struct AgentOperationSchema: Sendable {
    package let parameters: AgentObjectShape
    package let result: AgentObjectShape

    package func validatedParameters(_ values: [String: AgentJSONValue]) throws -> [String: AgentJSONValue] {
        try parameters.applyingDefaults(to: values)
    }
}

package enum AgentReadSchemas {
    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }
    package static var operationNames: Set<String> { Set(schemas.keys) }

    package static func validateResult(_ values: [String: AgentJSONValue], for operation: String) throws {
        guard let schema = schemas[operation] else { throw AgentErrorCode.unavailable }
        try schema.result.validate(values)
        if operation == "drafts.get", case .object(let chunk) = values["content"],
           case .string(let text) = chunk["text"], case .bool(let hasMore) = chunk["hasMore"] {
            func integer(_ name: String) throws -> Int64 {
                switch chunk[name] {
                case .integer(let value): return value
                case .number(let value): return NSDecimalNumber(decimal: value).int64Value
                default: throw AgentSchemaError.invalidValue
                }
            }
            let offset = try integer("offset"), length = try integer("length"), total = try integer("totalLength")
            guard offset <= total, length <= total - offset,
                  Int64(text.utf16.count) == length, hasMore == (length < total - offset) else {
                throw AgentSchemaError.invalidValue
            }
        }
    }

    private static func required(_ shape: AgentValueShape) -> AgentFieldShape {
        .init(shape: shape, required: true)
    }
    private static func optional(_ shape: AgentValueShape, default value: AgentJSONValue? = nil) -> AgentFieldShape {
        .init(shape: shape, defaultValue: value)
    }
    private static let token = AgentValueShape.string(minimum: 1, maximum: 4096)
    private static let text = AgentValueShape.string()
    private static let count = AgentValueShape.integer(minimum: 0)
    private static let page: [String: AgentFieldShape] = [
        "limit": optional(.integer(minimum: 1, maximum: 200), default: .integer(50)),
        "cursor": optional(token)
    ]

    private static let summary = AgentObjectShape(fields: [
        "id": required(.uuid), "title": required(text), "preview": required(text),
        "tags": required(.array(text, maximum: 10_000)),
        "flag": required(.integer(minimum: 0, maximum: 7)),
        "isArchived": required(.boolean), "trashedAt": required(.nullable(.utcDate)),
        "syntax": required(text), "createdAt": required(.utcDate), "modifiedAt": required(.utcDate),
        "accessedAt": required(.nullable(.utcDate)), "versionToken": required(token)
    ])

    private static let query = AgentObjectShape(fields: page.merging([
        "query": optional(.string(maximum: 65_536), default: .string("")),
        "folder": optional(.string(choices: ["inbox", "archive", "trash", "all", "flagged"]), default: .string("all")),
        "sort": optional(.string(choices: ["modified", "created", "title", "accessed"]), default: .string("modified")),
        "ascending": optional(.boolean, default: .bool(false)),
        "tags": optional(.array(text, maximum: 10_000), default: .array([])),
        "excludedTags": optional(.array(text, maximum: 10_000), default: .array([])),
        "matchAnyTag": optional(.boolean, default: .bool(false)),
        "tagged": optional(.boolean), "caseSensitive": optional(.boolean, default: .bool(false))
    ], uniquingKeysWith: { _, new in new }))

    private static let draftPage = AgentObjectShape(fields: [
        "items": required(.array(.object(summary), maximum: 200)),
        "nextCursor": required(.nullable(token))
    ])

    private static let schemas: [String: AgentOperationSchema] = {
        var search = query
        search = AgentObjectShape(fields: search.fields.merging([
            "query": required(.string(minimum: 1, maximum: 65_536))
        ], uniquingKeysWith: { _, new in new }))
        let reference = AgentObjectShape(fields: [
            "kind": required(.string(choices: AgentResourceKind.allCases.map(\.rawValue))), "id": required(.uuid)
        ])
        let scope = AgentObjectShape(fields: [
            "allResources": required(.boolean),
            "resources": required(.array(.object(reference), maximum: 100_000))
        ])
        let descriptor = AgentObjectShape(fields: [
            "name": required(.string(choices: AgentOperationCatalog.operations.map(\.name))),
            "inputSchema": required(.nullable(.object(.init(fields: [:], allowsAdditionalFields: true)))),
            "resultSchema": required(.nullable(.object(.init(fields: [:], allowsAdditionalFields: true)))),
            "available": required(.boolean)
        ])
        let revision = AgentObjectShape(fields: [
            "id": required(.uuid), "noteID": required(.uuid), "date": required(.utcDate),
            "content": optional(text)
        ])
        return [
            "server.status": .init(parameters: .init(fields: [:]), result: .init(fields: [
                "apiVersion": required(.integer(minimum: 1, maximum: 1)),
                "appVersion": required(.string(minimum: 1)), "accessEnabled": required(.boolean)
            ])),
            "server.capabilities": .init(parameters: .init(fields: [:]), result: .init(fields: [
                "capabilities": required(.array(.string(choices: AgentCapability.allCases.map(\.rawValue)), maximum: AgentCapability.allCases.count)),
                "scope": required(.object(scope)), "expiresAt": required(.utcDate)
            ])),
            "server.schemas": .init(parameters: .init(fields: [
                "operations": optional(.array(.string(choices: AgentOperationCatalog.operations.map(\.name)), maximum: AgentOperationCatalog.operations.count))
            ]), result: .init(fields: ["operations": required(.array(.object(descriptor), maximum: AgentOperationCatalog.operations.count))])),
            "library.summary": .init(parameters: .init(fields: [:]), result: .init(fields: [
                "draftCount": required(count)
            ])),
            "drafts.list": .init(parameters: query, result: draftPage),
            "drafts.search": .init(parameters: search, result: draftPage),
            "drafts.get": .init(parameters: .init(fields: [
                "offset": optional(.integer(minimum: 0), default: .integer(0)),
                "length": optional(.integer(minimum: 1, maximum: 65_536), default: .integer(65_536))
            ]), result: .init(fields: [
                "draft": required(.object(summary)),
                "content": required(.object(.init(fields: [
                    "text": required(text), "offset": required(count),
                    "length": required(.integer(minimum: 0, maximum: 65_536)),
                    "totalLength": required(count), "hasMore": required(.boolean)
                ])))
            ])),
            "drafts.versions": .init(parameters: .init(fields: page.merging([
                "includeContent": optional(.boolean, default: .bool(false))
            ], uniquingKeysWith: { _, new in new })), result: .init(fields: [
                "items": required(.array(.object(revision), maximum: 200)),
                "nextCursor": required(.nullable(token))
            ]))
        ]
    }()
}
