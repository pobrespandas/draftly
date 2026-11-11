import Foundation

package enum AgentHelpSchemas {
    package static let operationNames: Set<String> = ["help.search", "help.get"]
    private static func required(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static let id = AgentValueShape.string(minimum: 1, maximum: 64)
    private static let metadata: [String: AgentFieldShape] = [
        "id": required(id), "title": required(.string(maximum: 200)),
        "category": required(.string(maximum: 100))
    ]
    package static func schema(for operation: String) -> AgentOperationSchema? {
        switch operation {
        case "help.search":
            .init(parameters: .init(fields: [
                "query": .init(shape: .string(maximum: 500), defaultValue: .string("")),
                "limit": .init(shape: .integer(minimum: 1, maximum: 30), defaultValue: .integer(5))
            ]), result: .init(fields: [
                "items": required(.array(.object(.init(fields: metadata.merging([
                    "summary": required(.string(maximum: 600))
                ], uniquingKeysWith: { _, new in new }))), maximum: 30)),
                "total": required(.integer(minimum: 0, maximum: 1000))
            ]))
        case "help.get":
            .init(parameters: .init(fields: ["id": required(id)]), result: .init(fields: metadata.merging([
                "markdown": required(.string(maximum: 20000))
            ], uniquingKeysWith: { _, new in new })))
        default: nil
        }
    }
}
