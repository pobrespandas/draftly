import Foundation

package enum AgentEditorSchemas {
    package static var operationNames: Set<String> { Set(schemas.keys) }
    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }

    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard let schema = schemas[request.operation] else { throw AgentErrorCode.unavailable }
        let values = try schema.validatedParameters(request.parameters)
        if request.operation == "editor.replaceRange" || request.operation == "editor.setSelection" {
            _ = try AgentTextShapes.bounds(values["range"])
        } else if request.operation == "editor.tasks" {
            _ = try AgentTextShapes.bounds(values["stateRange"])
        } else if request.operation == "editor.open" {
            let createsWindow = values["newWindow"] == .bool(true)
            let hasWindow = values["windowID"] != nil
            let hasVersion = values["expectedWindowVersion"] != nil
            guard createsWindow ? (!hasWindow && !hasVersion) : (hasWindow && hasVersion) else {
                throw AgentSchemaError.invalidValue
            }
        }
        return values
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for operation: String) throws {
        guard let schema = schemas[operation] else { throw AgentErrorCode.unavailable }
        try schema.result.validate(values)
        if operation == "editor.get" {
            let total = try AgentTextShapes.validateChunk(values["content"])
            _ = try AgentTextShapes.bounds(values["selection"], totalLength: total)
            if values["draftID"] == .null {
                guard total == 0, values["hasUnsavedChanges"] == .bool(false) else { throw AgentSchemaError.invalidValue }
            }
        } else if let selection = values["selection"] {
            _ = try AgentTextShapes.bounds(selection)
        }
        if case .array(let items) = values["items"] {
            if operation == "editor.windows" {
                let ids = items.compactMap { value -> UUID? in
                    guard case .object(let fields) = value, case .string(let id) = fields["windowID"] else { return nil }
                    return UUID(uuidString: id)
                }
                guard Set(ids).count == ids.count else { throw AgentSchemaError.invalidValue }
            } else {
                if values["draftID"] == .null, !items.isEmpty { throw AgentSchemaError.invalidValue }
                for item in items {
                    guard case .object(let fields) = item else { throw AgentSchemaError.invalidValue }
                    let keys = operation == "editor.listTasks" ? ["lineRange", "labelRange", "stateRange", "interactiveRange"] : ["range"]
                    for key in keys { _ = try AgentTextShapes.bounds(fields[key]) }
                }
            }
        }
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for request: AgentRequest) throws {
        try validateResult(values, for: request.operation)
        guard request.operation != "editor.windows" else { return }
        if request.operation == "editor.open" {
            guard case .string(let draftID) = values["draftID"],
                  UUID(uuidString: draftID) == request.targets.first?.id else { throw AgentSchemaError.invalidValue }
            if let expected = request.parameters["windowID"] {
                guard case .string(let rawExpected) = expected, case .string(let actual) = values["windowID"],
                      UUID(uuidString: rawExpected) == UUID(uuidString: actual) else { throw AgentSchemaError.invalidValue }
            }
        } else {
            guard case .string(let windowID) = values["windowID"],
                  UUID(uuidString: windowID) == request.targets.first?.id else { throw AgentSchemaError.invalidValue }
        }
        if request.operation == "editor.setSelection" {
            let expected = try AgentTextShapes.bounds(request.parameters["range"])
            let actual = try AgentTextShapes.bounds(values["selection"])
            guard expected == actual else { throw AgentSchemaError.invalidValue }
        }
        if request.operation == "editor.preview", values["visible"] != request.parameters["visible"] {
            throw AgentSchemaError.invalidValue
        }
    }

    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static func o(_ shape: AgentValueShape, default value: AgentJSONValue? = nil) -> AgentFieldShape {
        .init(shape: shape, defaultValue: value)
    }
    private static let text = AgentValueShape.string()
    private static let range = AgentValueShape.object(AgentTextShapes.range)
    private static let page = AgentObjectShape(fields: [
        "limit": o(.integer(minimum: 1, maximum: 200), default: .integer(50)), "cursor": o(AgentResourceShapes.token)
    ])
    private static let query: [String: AgentFieldShape] = [
        "query": r(.string(maximum: 65_536)), "caseSensitive": o(.boolean, default: .bool(false)),
        "regularExpression": o(.boolean, default: .bool(false))
    ]
    private static let snapshot: [String: AgentFieldShape] = [
        "windowID": r(.uuid), "draftID": r(.nullable(.uuid)), "versionToken": r(AgentResourceShapes.token)
    ]
    private static let editResult = AgentObjectShape(fields: [
        "windowID": r(.uuid), "draftID": r(.uuid), "versionToken": r(AgentResourceShapes.token), "selection": r(range)
    ])
    private static let schemas: [String: AgentOperationSchema] = {
        let none = AgentObjectShape(fields: [:])
        func pageResult(_ item: AgentObjectShape) -> AgentObjectShape {
            .init(fields: snapshot.merging([
                "items": r(.array(.object(item), maximum: 200)), "nextCursor": r(.nullable(AgentResourceShapes.token))
            ], uniquingKeysWith: { _, new in new }))
        }
        let marker = AgentObjectShape(fields: ["label": r(text), "prefix": r(text), "level": r(.integer(minimum: 0, maximum: 9)), "range": r(range)])
        let link = AgentObjectShape(fields: ["key": r(text), "value": r(text), "link": r(text), "prefix": r(text), "suffix": r(text), "range": r(range)])
        let task = AgentObjectShape(fields: [
            "line": r(text), "label": r(text), "state": r(text), "interactive": r(text), "isCompleted": r(.boolean),
            "lineRange": r(range), "labelRange": r(range), "stateRange": r(range), "interactiveRange": r(range)
        ])
        var definitions: [String: AgentOperationSchema] = [
            "editor.windows": .init(parameters: page, result: .init(fields: [
                "items": r(.array(.object(.init(fields: snapshot.merging([
                    "title": r(text), "hasUnsavedChanges": r(.boolean)
                ], uniquingKeysWith: { _, new in new }))), maximum: 200)),
                "nextCursor": r(.nullable(AgentResourceShapes.token))
            ])),
            "editor.get": .init(parameters: AgentTextShapes.chunkParameters, result: .init(fields: snapshot.merging([
                "selection": r(range), "content": r(.object(AgentTextShapes.chunk)), "hasUnsavedChanges": r(.boolean)
            ], uniquingKeysWith: { _, new in new }))),
            "editor.find": .init(parameters: .init(fields: page.fields.merging(query, uniquingKeysWith: { _, new in new })),
                result: pageResult(.init(fields: ["range": r(range)]))),
            "editor.markers": .init(parameters: page, result: pageResult(marker)),
            "editor.links": .init(parameters: page, result: pageResult(link)),
            "editor.listTasks": .init(parameters: page, result: pageResult(task)),
            "editor.replaceRange": .init(parameters: .init(fields: ["range": r(range), "text": r(text)]), result: editResult),
            "editor.setSelection": .init(parameters: .init(fields: ["range": r(range)]), result: editResult),
            "editor.replaceAll": .init(parameters: .init(fields: query.merging(["replacement": r(text)], uniquingKeysWith: { _, new in new })), result: editResult),
            "editor.tasks": .init(parameters: .init(fields: [
                "stateRange": r(range), "state": r(text), "operation": r(.string(choices: ["complete", "reset", "advance"]))
            ]), result: editResult),
            "editor.open": .init(parameters: .init(fields: [
                "windowID": o(.uuid), "expectedWindowVersion": o(AgentResourceShapes.token),
                "newWindow": o(.boolean, default: .bool(false)), "focus": o(.boolean, default: .bool(false))
            ]), result: editResult),
            "editor.navigate": .init(parameters: .init(fields: ["direction": r(.string(choices: ["previous", "next"]))]),
                result: .init(fields: snapshot.merging(["selection": r(range)], uniquingKeysWith: { _, new in new }))),
            "editor.preview": .init(parameters: .init(fields: ["visible": r(.boolean)]), result: .init(fields: [
                "windowID": r(.uuid), "draftID": r(.uuid), "visible": r(.boolean)
            ]))
        ]
        for name in ["editor.undo", "editor.redo"] { definitions[name] = .init(parameters: none, result: editResult) }
        return definitions
    }()
}
