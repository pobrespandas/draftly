import Foundation

package enum AgentTransferSchemas {
    package static let maximumBytes = 32 * 1024 * 1024
    package static let maximumChunkBytes = 64 * 1024
    package static var operationNames: Set<String> { Set(schemas.keys) }
    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }
    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static let count = AgentValueShape.integer(minimum: 0, maximum: Int64(maximumBytes))
    private static let digest = AgentValueShape.string(minimum: 64, maximum: 64)
    private static let transfer = AgentObjectShape(fields: [
        "transferID": r(.uuid), "direction": r(.string(choices: ["import", "export"])),
        "state": r(.string(choices: ["receiving", "ready"])), "byteLength": r(count), "receivedBytes": r(count),
        "sha256": r(digest), "expiresAt": r(.utcDate)
    ])
    private static let metadata = AgentObjectShape(fields: ["transfer": r(.object(transfer))])
    private static let schemas: [String: AgentOperationSchema] = [
        "transfers.beginImport": .init(parameters: .init(fields: ["byteLength": r(count), "sha256": r(digest)]), result: metadata),
        "transfers.appendChunk": .init(parameters: .init(fields: ["offset": r(count),
            "data": r(.string(minimum: 1, maximum: 4 * ((maximumChunkBytes + 2) / 3)))]), result: metadata),
        "transfers.finishImport": .init(parameters: .init(fields: [:]), result: metadata),
        "transfers.readChunk": .init(parameters: .init(fields: ["offset": r(count),
            "length": .init(shape: .integer(minimum: 1, maximum: Int64(maximumChunkBytes)), defaultValue: .integer(Int64(maximumChunkBytes)))]),
            result: .init(fields: ["transferID": r(.uuid), "offset": r(count), "byteLength": r(count),
                "data": r(.string(maximum: 4 * ((maximumChunkBytes + 2) / 3))), "hasMore": r(.boolean)])),
        "transfers.cancel": .init(parameters: .init(fields: [:]), result: .init(fields: ["transferID": r(.uuid), "cancelled": r(.boolean)])),
        "exports.drafts": .init(parameters: .init(fields: [
            "format": .init(shape: .string(choices: ["text", "draftly"]), defaultValue: .string("draftly")),
            "includeVersions": .init(shape: .boolean, defaultValue: .bool(false))]), result: .init(fields: [
                "transfer": r(.object(transfer)), "format": r(.string(choices: ["text", "draftly"])),
                "draftIDs": r(.array(.uuid, maximum: AgentRequest.maximumTargets))]))
    ]

    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard let schema = schema(for: request.operation) else { throw AgentErrorCode.unavailable }
        let values = try schema.validatedParameters(request.parameters)
        if request.operation == "transfers.beginImport" {
            guard case .string(let hash) = values["sha256"], hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw AgentSchemaError.invalidValue
            }
        }
        if request.operation == "transfers.appendChunk" {
            guard case .string(let text) = values["data"], let data = Data(base64Encoded: text),
                  !data.isEmpty, data.count <= maximumChunkBytes, data.base64EncodedString() == text else { throw AgentSchemaError.invalidValue }
        }
        if request.operation == "exports.drafts", values["format"] == .string("text") {
            guard request.targets.count == 1, values["includeVersions"] == .bool(false) else { throw AgentSchemaError.invalidValue }
        }
        return values
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for request: AgentRequest) throws {
        guard let schema = schema(for: request.operation) else { throw AgentErrorCode.unavailable }
        try schema.result.validate(values)
        if request.operation == "exports.drafts" {
            try AgentResourceShapes.validateOrder(values["draftIDs"], targets: request.targets)
            let parameters = try validatedParameters(for: request)
            guard values["format"] == parameters["format"] else { throw AgentSchemaError.invalidValue }
        }
        if request.operation.hasPrefix("transfers."), request.operation != "transfers.beginImport" {
            let rawID: AgentJSONValue?
            if case .object(let metadata) = values["transfer"] { rawID = metadata["transferID"] }
            else { rawID = values["transferID"] }
            guard case .string(let text) = rawID, UUID(uuidString: text) == request.targets.first?.id else { throw AgentSchemaError.invalidValue }
        }
    }
}
