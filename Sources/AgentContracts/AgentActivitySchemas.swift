import Foundation

package enum AgentActivitySchemas {
    package static let operationNames: Set<String> = ["activity.list"]
    private static func required(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static let token = AgentValueShape.string(minimum: 1, maximum: 4096)
    private static let entry = AgentObjectShape(fields: [
        "id": required(.uuid), "requestID": required(.uuid), "operation": required(.string()),
        "date": required(.utcDate), "result": required(.string())
    ])
    private static let value = AgentOperationSchema(parameters: .init(fields: [
        "limit": .init(shape: .integer(minimum: 1, maximum: 200), defaultValue: .integer(50)),
        "cursor": .init(shape: token)
    ]), result: .init(fields: [
        "items": required(.array(.object(entry), maximum: 200)), "nextCursor": required(.nullable(token))
    ]))
    package static func schema(for operation: String) -> AgentOperationSchema? { operation == "activity.list" ? value : nil }
}
