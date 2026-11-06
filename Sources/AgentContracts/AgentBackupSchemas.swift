import Foundation

package enum AgentBackupSchemas {
    package static let operationNames: Set<String> = ["backups.export", "backups.validate", "backups.previewRestore", "backups.requestRestore"]
    package static let collectionNames = ["drafts", "versions", "actions", "actionGroups", "workspaces", "themes", "syntaxes", "runs"]
    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static let counts = AgentObjectShape(fields: Dictionary(uniqueKeysWithValues: collectionNames.map {
        ($0, r(.integer(minimum: 0)))
    }))
    package static let changes = AgentObjectShape(fields: Dictionary(uniqueKeysWithValues: collectionNames.map {
        ($0, r(.object(.init(fields: ["created": r(.integer(minimum: 0)), "updated": r(.integer(minimum: 0))]))))
    }))
    private static let input = AgentObjectShape(fields: ["source": r(AgentImportSource.backupShape)])
    private static let schemas: [String: AgentOperationSchema] = [
        "backups.export": .init(parameters: .init(fields: [:]), result: .init(fields: ["transfer": r(.object(AgentTransferSchemas.transferShape))])),
        "backups.validate": .init(parameters: input, result: .init(fields: ["valid": r(.boolean), "counts": r(.object(counts))])),
        "backups.previewRestore": .init(parameters: input, result: .init(fields: ["counts": r(.object(counts)),
            "changes": r(.object(changes)), "versionToken": r(AgentResourceShapes.token)])),
        "backups.requestRestore": .init(parameters: input, result: .init(fields: [
            "changes": r(.object(changes)), "recoveryID": r(.uuid)
        ]))
    ]
    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }
    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard let schema = schema(for: request.operation) else { throw AgentErrorCode.unavailable }
        let values = try schema.validatedParameters(request.parameters)
        if request.operation != "backups.export" { _ = try AgentImportSource.validate(values["source"]) }
        return values
    }
}
