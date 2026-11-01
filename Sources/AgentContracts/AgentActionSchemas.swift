import Foundation

package enum AgentActionSchemas {
    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }
    package static var operationNames: Set<String> { Set(schemas.keys) }

    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard let schema = schemas[request.operation],
              let descriptor = AgentOperationCatalog.operation(named: request.operation) else {
            throw AgentErrorCode.unavailable
        }
        guard descriptor.acceptsTargets(request.targets) else { throw AgentSchemaError.invalidValue }
        let values = try schema.validatedParameters(request.parameters)
        if request.operation == "actions.update" || request.operation == "actionGroups.update" {
            let key = request.operation == "actions.update" ? "action" : "group"
            guard case .object(let definition) = values[key], case .string(let rawID) = definition["id"],
                  UUID(uuidString: rawID) == request.targets.first?.id else { throw AgentSchemaError.invalidValue }
        }
        if request.operation == "actions.reorder" || request.operation == "actionGroups.reorder" {
            guard case .array(let order) = values["order"] else { throw AgentSchemaError.invalidValue }
            let ids = order.compactMap { value -> UUID? in
                guard case .string(let text) = value else { return nil }; return UUID(uuidString: text)
            }
            guard ids.count == order.count, Set(ids).count == ids.count,
                  Set(ids) == Set(request.targets.map(\.id)) else { throw AgentSchemaError.invalidValue }
        }
        return values
    }

    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static func o(_ shape: AgentValueShape, default value: AgentJSONValue? = nil) -> AgentFieldShape {
        .init(shape: shape, defaultValue: value)
    }
    private static let text = AgentValueShape.string()
    private static let token = AgentValueShape.string(minimum: 1, maximum: 4096)
    private static let strings = AgentValueShape.array(text, maximum: 10_000)
    private static let stringMap = AgentValueShape.map(text)
    private static let rawObject = AgentValueShape.object(.init(fields: [:], allowsAdditionalFields: true))

    // These are the canonical Codable fields, not the external .draftsAction import format.
    private static let presentation = AgentObjectShape(fields: [
        "description": r(text), "tintColor": o(.nullable(text)), "barLabel": o(.nullable(text)),
        "barUsesIcon": o(.nullable(.boolean)), "showInList": r(.boolean), "showInBar": r(.boolean),
        "showInSearch": r(.boolean), "confirmBeforeRun": r(.boolean), "notifyOnSuccess": r(.boolean),
        "notifyOnError": r(.boolean), "logLevel": o(.nullable(.integer())),
        "addTags": r(strings), "removeTags": r(strings), "flagAfterSuccess": o(.nullable(.integer())),
        "section": r(text), "order": r(.integer())
    ], allowsAdditionalFields: true)

    private static let step = AgentObjectShape(fields: [
        "id": r(.uuid), "type": r(text), "values": r(stringMap),
        "isEnabled": o(.nullable(.boolean))
    ], allowsAdditionalFields: true)

    private static let action = AgentObjectShape(fields: [
        "id": r(.uuid), "name": r(text), "symbol": r(text), "group": r(text), "shortcut": r(text),
        "shortcutModifiers": o(.nullable(strings)), "afterSuccess": r(text),
        "configuredValues": r(stringMap), "steps": r(.array(.object(step), maximum: 10_000)),
        "options": o(.nullable(.object(presentation))), "sourceURL": o(.nullable(text)),
        "rawPayload": o(.nullable(text)), "scriptMetadata": o(.nullable(stringMap))
    ], allowsAdditionalFields: true)

    private static let newStep = AgentObjectShape(fields: [
        "id": o(.uuid), "type": r(.string(minimum: 1)), "values": o(stringMap),
        "isEnabled": o(.nullable(.boolean))
    ], allowsAdditionalFields: true)

    private static let newAction = AgentObjectShape(fields: action.fields.merging([
        "id": o(.uuid), "symbol": o(text), "group": o(text), "shortcut": o(text),
        "afterSuccess": o(text), "configuredValues": o(stringMap),
        "steps": r(.array(.object(newStep), maximum: 10_000))
    ], uniquingKeysWith: { _, new in new }), allowsAdditionalFields: true)

    private static let group = AgentObjectShape(fields: [
        "id": r(.uuid), "name": r(text), "symbol": r(text), "order": r(.integer()),
        "importedMetadata": o(rawObject)
    ])
    private static let newGroup = AgentObjectShape(fields: [
        "id": o(.uuid), "name": r(text), "symbol": o(text), "order": o(.integer()),
        "importedMetadata": o(rawObject)
    ])
    private static let receipt = AgentObjectShape(fields: ["id": r(.uuid), "versionToken": r(token)])
    private static let summary = AgentObjectShape(fields: [
        "id": r(.uuid), "name": r(text), "symbol": r(text), "groupID": r(.uuid),
        "group": r(text), "versionToken": r(token)
    ])
    private static let page = AgentObjectShape(fields: [
        "limit": o(.integer(minimum: 1, maximum: 200), default: .integer(50)), "cursor": o(token)
    ])

    private static let schemas: [String: AgentOperationSchema] = {
        let none = AgentObjectShape(fields: [:])
        let updated = AgentObjectShape(fields: ["resource": r(.object(receipt))])
        let deleted = AgentObjectShape(fields: ["deletedIDs": r(.array(.uuid, maximum: 10_000))])
        let reordered = AgentObjectShape(fields: ["resources": r(.array(.object(receipt), maximum: 10_000))])
        let order = AgentObjectShape(fields: ["order": r(.array(.uuid, maximum: 10_000))])
        let duplicate = AgentObjectShape(fields: ["name": o(text)])
        var list = page.fields
        list["groupID"] = o(.uuid)
        list["surface"] = o(.string(choices: ["list", "bar", "search", "all"]), default: .string("list"))
        return [
            "actions.list": .init(parameters: .init(fields: list), result: .init(fields: [
                "items": r(.array(.object(summary), maximum: 200)), "nextCursor": r(.nullable(token))
            ])),
            "actions.get": .init(parameters: none, result: .init(fields: [
                "action": r(.object(action)), "versionToken": r(token)
            ])),
            "actions.stepSchemas": .init(parameters: none, result: .init(fields: [
                "steps": r(.array(rawObject, maximum: 10_000))
            ])),
            "actions.groups": .init(parameters: page, result: .init(fields: [
                "items": r(.array(.object(.init(fields: ["id": r(.uuid), "name": r(text),
                    "symbol": r(text), "order": r(.integer()), "versionToken": r(token)])), maximum: 200)),
                "nextCursor": r(.nullable(token))
            ])),
            "actions.create": .init(parameters: .init(fields: ["action": r(.object(newAction))]), result: updated),
            "actions.update": .init(parameters: .init(fields: ["action": r(.object(action))]), result: updated),
            "actions.duplicate": .init(parameters: duplicate, result: updated),
            "actions.move": .init(parameters: none, result: updated),
            "actions.reorder": .init(parameters: order, result: reordered),
            "actions.delete": .init(parameters: none, result: deleted),
            "actions.validateShortcut": .init(parameters: .init(fields: [
                "key": r(text), "modifiers": o(.nullable(strings)), "actionID": o(.uuid)
            ]), result: .init(fields: ["available": r(.boolean)])),
            "actions.run": .init(parameters: .init(fields: [
                "interactive": o(.boolean, default: .bool(false)), "windowID": o(.uuid),
                "timeoutSeconds": o(.integer(minimum: 1, maximum: 3600))
            ]), result: .init(fields: ["operationID": r(.uuid),
                "state": r(.string(choices: ["queued", "running", "waiting_for_user"]))])),
            "actionGroups.get": .init(parameters: none, result: .init(fields: [
                "group": r(.object(group)), "versionToken": r(token)
            ])),
            "actionGroups.create": .init(parameters: .init(fields: ["group": r(.object(newGroup))]), result: updated),
            "actionGroups.update": .init(parameters: .init(fields: ["group": r(.object(group))]), result: updated),
            "actionGroups.duplicate": .init(parameters: duplicate, result: updated),
            "actionGroups.reorder": .init(parameters: order, result: reordered),
            "actionGroups.delete": .init(parameters: none, result: deleted)
        ]
    }()
}
