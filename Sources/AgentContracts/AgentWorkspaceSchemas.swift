import Foundation

package enum AgentWorkspaceSchemas {
    package static var operationNames: Set<String> { Set(schemas.keys) }
    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }

    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard let schema = schemas[request.operation] else { throw AgentErrorCode.unavailable }
        let values = try schema.validatedParameters(request.parameters)
        if request.operation == "workspaces.update" {
            try AgentResourceShapes.validateDefinitionID(values["workspace"], target: request.targets.first)
        } else if request.operation == "workspaces.reorder" {
            try AgentResourceShapes.validateOrder(values["order"], targets: request.targets)
        }
        return values
    }

    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static func o(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape) }
    private static let text = AgentValueShape.string()
    private static let strings = AgentValueShape.array(text, maximum: 10_000)
    private static let listOptions = AgentObjectShape(fields: [
        "showPreview": r(.boolean), "previewLines": r(.integer()), "showTags": r(.boolean),
        "showDate": r(.boolean), "searchTitlesOnly": r(.boolean), "caseSensitiveSearch": r(.boolean),
        "previewSearchMatches": r(.boolean), "showLastAction": r(.boolean), "highlightFlagged": r(.boolean)
    ])
    // Keep canonical Workspace metadata, including the existing JSON API string.
    // Handlers must use WorkspaceDefaults for creation and the shared evaluator for queries.
    private static let definition = AgentObjectShape(fields: [
        "id": r(.uuid), "name": r(text), "query": r(text), "tags": r(strings),
        "folder": r(.string(choices: ["inbox", "archive", "trash", "all", "flagged"])),
        "sort": r(.string(choices: ["modified", "created", "title", "accessed"])), "ascending": r(.boolean),
        "order": o(.nullable(.integer())), "listOptions": o(.nullable(.object(listOptions))),
        "excludedTags": o(.nullable(strings)), "matchAnyTag": o(.nullable(.boolean)),
        "tagged": o(.nullable(.boolean)), "scriptMetadata": o(.nullable(.map(text)))
    ])
    private static let newDefinition = AgentObjectShape(fields: definition.fields.mapValues { field in
        .init(shape: field.shape)
    }.merging(["name": r(text)], uniquingKeysWith: { _, new in new }))
    private static let page = AgentObjectShape(fields: [
        "limit": .init(shape: .integer(minimum: 1, maximum: 200), defaultValue: .integer(50)),
        "cursor": o(AgentResourceShapes.token)
    ])
    private static let schemas: [String: AgentOperationSchema] = {
        let none = AgentObjectShape(fields: [:])
        let summary = AgentObjectShape(fields: [
            "id": r(.uuid), "name": r(text), "order": r(.nullable(.integer())),
            "versionToken": r(AgentResourceShapes.token)
        ])
        return [
            "workspaces.list": .init(parameters: page, result: .init(fields: [
                "items": r(.array(.object(summary), maximum: 200)),
                "nextCursor": r(.nullable(AgentResourceShapes.token))
            ])),
            "workspaces.get": .init(parameters: none, result: .init(fields: [
                "workspace": r(.object(definition)), "versionToken": r(AgentResourceShapes.token)
            ])),
            "workspaces.query": .init(parameters: page, result: AgentReadSchemas.draftPage),
            "workspaces.create": .init(parameters: .init(fields: ["workspace": r(.object(newDefinition))]), result: AgentResourceShapes.updated),
            "workspaces.update": .init(parameters: .init(fields: ["workspace": r(.object(definition))]), result: AgentResourceShapes.updated),
            "workspaces.duplicate": .init(parameters: .init(fields: ["name": o(text)]), result: AgentResourceShapes.updated),
            "workspaces.reorder": .init(parameters: .init(fields: ["order": r(.array(.uuid, maximum: 10_000))]), result: AgentResourceShapes.reordered),
            "workspaces.delete": .init(parameters: none, result: AgentResourceShapes.deleted),
            "workspaces.apply": .init(parameters: none, result: .init(fields: [
                "workspaceID": r(.uuid), "windowID": r(.uuid)
            ]))
        ]
    }()
}
