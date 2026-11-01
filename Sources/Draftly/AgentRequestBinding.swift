import Foundation
import AgentContracts

// Shared canonical inputs for approvals and retry keys. This grants no authority.
enum AgentRequestBinding {
    struct Prepared {
        let request: AgentRequest
        let value: AgentJSONValue
    }

    static func prepare(_ request: AgentRequest, preferences: AgentPreferenceRegistry) throws -> Prepared {
        let checked = try AgentRequest.decode(JSONEncoder().encode(request))
        let parameters = try AgentOperationSchemas.validatedParameters(for: checked, preferences: preferences)
        let normalized = AgentRequest(requestID: checked.requestID, libraryID: checked.libraryID,
            operation: checked.operation, targets: checked.targets, expectedVersion: checked.expectedVersion, parameters: parameters)
        let value = try JSONDecoder().decode(AgentJSONValue.self,
            from: encoded(normalized, maximum: AgentRequest.maximumBytes * 2))
        return Prepared(request: normalized, value: value)
    }

    static func grantValue(_ grant: AgentGrant) -> AgentJSONValue {
        let scope: AgentJSONValue
        switch grant.scope { case .library: scope = .string("library")
        case .resources(let values): scope = references(values) }
        return .object([
            "grantID": .string(grant.grantID.uuidString), "connectionID": .string(grant.connectionID.uuidString),
            "libraryID": .string(grant.libraryID.uuidString), "scope": scope, "revoked": .bool(grant.revoked),
            "expiresAt": .string(String(grant.expiresAt.timeIntervalSince1970.bitPattern, radix: 16)),
            "capabilities": .array(grant.capabilities.map(\.rawValue).sorted().map(AgentJSONValue.string))
        ])
    }

    static func references(_ values: Set<AgentResourceReference>) -> AgentJSONValue {
        .array(values.sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }
            .map { .object(["kind": .string($0.kind.rawValue), "id": .string($0.id.uuidString)]) })
    }

    static func encoded<T: Encodable>(_ value: T, maximum: Int = AgentRequest.maximumBytes) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= maximum else { throw AgentErrorCode.invalidInput }
        return data
    }
}
