import Foundation

package enum AgentDraftSchemas {
    package static var operationNames: Set<String> { Set(schemas.keys) }
    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }

    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard let schema = schemas[request.operation] else { throw AgentErrorCode.unavailable }
        let values = try schema.validatedParameters(request.parameters)
        if request.operation == "drafts.merge" {
            guard request.targets.count >= 2 else { throw AgentSchemaError.invalidValue }
            try AgentResourceShapes.validateOrder(values["order"], targets: request.targets)
        } else if request.operation == "drafts.patch" {
            try validateEdits(values["edits"])
        } else if request.operation == "drafts.syntax" {
            guard (values["name"] != nil) != (values["syntaxID"] != nil) else { throw AgentSchemaError.invalidValue }
        }
        return values
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for request: AgentRequest) throws {
        guard let schema = schemas[request.operation] else { throw AgentErrorCode.unavailable }
        try schema.result.validate(values)
        let drafts = request.targets.filter { $0.kind == .draft }
        if batchOperations.contains(request.operation) || request.operation == "drafts.merge" {
            let field = request.operation == "drafts.merge" ? "originals" : "resources"
            guard case .array(let receipts) = values[field] else { throw AgentSchemaError.invalidValue }
            let ids = receipts.map { value -> AgentJSONValue in
                guard case .object(let receipt) = value else { return .null }
                return receipt["id"] ?? .null
            }
            try AgentResourceShapes.validateOrder(.array(ids), targets: drafts)
        } else if request.operation == "drafts.purge" {
            try AgentResourceShapes.validateOrder(values["deletedIDs"], targets: drafts)
        } else if ["drafts.update", "drafts.patch", "drafts.restoreVersion"].contains(request.operation) {
            try AgentResourceShapes.validateDefinitionID(values["resource"], target: drafts.first)
        }
        if request.operation == "drafts.merge" || request.operation == "drafts.duplicate" {
            guard case .object(let resource) = values["resource"], case .string(let id) = resource["id"],
                  let uuid = UUID(uuidString: id), !drafts.contains(where: { $0.id == uuid }) else {
                throw AgentSchemaError.invalidValue
            }
        }
    }

    // Offsets refer to one original UTF-16 snapshot. The handler must also check
    // the current content, scalar boundaries, editor conflicts and version token.
    private static func validateEdits(_ value: AgentJSONValue?) throws {
        guard case .array(let values) = value else { throw AgentSchemaError.invalidValue }
        let edits = try values.map { value -> (offset: Int64, end: Int64) in
            guard case .object(let fields) = value else { throw AgentSchemaError.invalidValue }
            func count(_ key: String) throws -> Int64 {
                switch fields[key] {
                case .integer(let value): return value
                case .number(let value): return NSDecimalNumber(decimal: value).int64Value
                default: throw AgentSchemaError.invalidValue
                }
            }
            let offset = try count("offset"), length = try count("length")
            let (end, overflow) = offset.addingReportingOverflow(length)
            guard !overflow else { throw AgentSchemaError.invalidValue }
            return (offset, end)
        }.sorted { $0.offset < $1.offset }
        for index in edits.indices.dropFirst() {
            let previous = edits[index - 1], current = edits[index]
            guard current.offset > previous.offset, current.offset >= previous.end else {
                throw AgentSchemaError.invalidValue
            }
        }
    }

    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static func o(_ shape: AgentValueShape, default value: AgentJSONValue? = nil) -> AgentFieldShape {
        .init(shape: shape, defaultValue: value)
    }
    private static let text = AgentValueShape.string()
    private static let strings = AgentValueShape.array(text, maximum: 10_000)
    private static let flag = AgentValueShape.integer(minimum: 0, maximum: 7)
    private static let batchOperations: Set<String> = ["drafts.archive", "drafts.trash", "drafts.restore", "drafts.flag", "drafts.tags", "drafts.syntax"]
    private static let schemas: [String: AgentOperationSchema] = {
        let none = AgentObjectShape(fields: [:])
        let changes = AgentObjectShape(fields: [
            "content": o(text), "tags": o(strings), "flag": o(flag), "syntax": o(.string(minimum: 1)),
            "isArchived": o(.boolean), "trashedAt": o(.nullable(.utcDate)),
            "createdAt": o(.utcDate), "modifiedAt": o(.utcDate), "scriptMetadata": o(.nullable(.map(text)))
        ], minimumFields: 1)
        let edit = AgentObjectShape(fields: [
            "offset": r(.integer(minimum: 0)), "length": r(.integer(minimum: 0)), "text": r(text)
        ])
        var result: [String: AgentOperationSchema] = [
            "drafts.create": .init(parameters: .init(fields: [
                "content": o(text, default: .string("")), "tags": o(strings, default: .array([])),
                "flag": o(flag, default: .integer(0)), "syntax": o(.string(minimum: 1), default: .string("Markdown")),
                "folder": o(.string(choices: ["inbox", "archive"]), default: .string("inbox")),
                "scriptMetadata": o(.map(text))
            ]), result: AgentResourceShapes.updated),
            "drafts.update": .init(parameters: .init(fields: ["changes": r(.object(changes))]), result: AgentResourceShapes.updated),
            "drafts.patch": .init(parameters: .init(fields: ["edits": r(.array(.object(edit), minimum: 1, maximum: 10_000))]), result: AgentResourceShapes.updated),
            "drafts.duplicate": .init(parameters: none, result: AgentResourceShapes.updated),
            "drafts.merge": .init(parameters: .init(fields: [
                "order": r(.array(.uuid, minimum: 2, maximum: AgentRequest.maximumTargets)),
                "separator": o(text, default: .string("")), "includeBlankLine": o(.boolean, default: .bool(false)),
                "destination": o(.string(choices: ["archive", "trash", "keep"]), default: .string("archive"))
            ]), result: .init(fields: ["resource": r(.object(AgentResourceShapes.receipt)),
                "originals": r(.array(.object(AgentResourceShapes.receipt), minimum: 2, maximum: AgentRequest.maximumTargets))])),
            "drafts.flag": .init(parameters: .init(fields: ["flag": r(flag)]), result: AgentResourceShapes.reordered),
            "drafts.tags": .init(parameters: .init(fields: [
                "mode": r(.string(choices: ["replace", "add", "remove"])), "tags": r(strings)
            ]), result: AgentResourceShapes.reordered),
            "drafts.syntax": .init(parameters: .init(fields: ["name": o(.string(minimum: 1)), "syntaxID": o(.uuid)]), result: AgentResourceShapes.reordered),
            "drafts.restoreVersion": .init(parameters: none, result: AgentResourceShapes.updated),
            "drafts.purge": .init(parameters: none, result: AgentResourceShapes.deleted)
        ]
        for name in ["drafts.archive", "drafts.trash", "drafts.restore"] {
            result[name] = .init(parameters: none, result: AgentResourceShapes.reordered)
        }
        return result
    }()
}
