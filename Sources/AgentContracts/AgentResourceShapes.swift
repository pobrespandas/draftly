import Foundation

// Shared resource receipts do not disclose the definition changed by a write.
package enum AgentResourceShapes {
    package static let token = AgentValueShape.string(minimum: 1, maximum: 4096)
    package static let receipt = AgentObjectShape(fields: [
        "id": .init(shape: .uuid, required: true),
        "versionToken": .init(shape: token, required: true)
    ])
    package static let updated = AgentObjectShape(fields: [
        "resource": .init(shape: .object(receipt), required: true)
    ])
    package static let deleted = AgentObjectShape(fields: [
        "deletedIDs": .init(shape: .array(.uuid, maximum: AgentRequest.maximumTargets), required: true)
    ])
    package static let reordered = AgentObjectShape(fields: [
        "resources": .init(shape: .array(.object(receipt), maximum: AgentRequest.maximumTargets), required: true)
    ])

    package static func validateDefinitionID(_ value: AgentJSONValue?, target: AgentResourceReference?) throws {
        guard case .object(let definition) = value, case .string(let rawID) = definition["id"],
              let target, UUID(uuidString: rawID) == target.id else { throw AgentSchemaError.invalidValue }
    }

    package static func validateOrder(_ value: AgentJSONValue?, targets: [AgentResourceReference]) throws {
        guard case .array(let order) = value else { throw AgentSchemaError.invalidValue }
        let ids = order.compactMap { value -> UUID? in
            guard case .string(let text) = value else { return nil }
            return UUID(uuidString: text)
        }
        guard ids.count == order.count, Set(ids).count == ids.count,
              Set(ids) == Set(targets.map(\.id)) else { throw AgentSchemaError.invalidValue }
    }
}
