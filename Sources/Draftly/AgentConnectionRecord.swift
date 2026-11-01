import Foundation
import AgentContracts

struct AgentConnectionRecord: Codable, Identifiable {
    enum ScopeKind: String, Codable { case library, resources }
    let id: UUID
    var name: String
    let createdAt: Date
    var grantID: UUID
    let libraryID: UUID
    var expiresAt: Date
    var revoked: Bool
    var renewable: Bool
    var capabilities: [AgentCapability]
    var scopeKind: ScopeKind
    var resources: [AgentResourceReference]

    var grant: AgentGrant {
        AgentGrant(connectionID: id, libraryID: libraryID, expiresAt: expiresAt, revoked: revoked,
            capabilities: Set(capabilities), scope: scopeKind == .library ? .library : .resources(Set(resources)), grantID: grantID)
    }
}

struct AgentConnectionMetadata: Codable {
    var version = 1
    var enabled = false
    var connections: [AgentConnectionRecord] = []

    static func decode(_ data: Data?) throws -> Self {
        guard let data else { return Self() }
        guard data.count <= AgentRequest.maximumBytes,
              case .object(let root) = try JSONDecoder().decode(AgentJSONValue.self, from: data),
              Set(root.keys).isSubset(of: ["version", "enabled", "connections"]),
              case .array(let records) = root["connections"] else { throw AgentErrorCode.storageError }
        let keys: Set<String> = ["id", "name", "createdAt", "grantID", "libraryID", "expiresAt", "revoked",
            "renewable", "capabilities", "scopeKind", "resources"]
        for record in records {
            guard case .object(let fields) = record, Set(fields.keys).isSubset(of: keys),
                  case .array(let targets) = fields["resources"] else { throw AgentErrorCode.storageError }
            for target in targets {
                guard case .object(let fields) = target, Set(fields.keys) == Set(["kind", "id"]) else {
                    throw AgentErrorCode.storageError
                }
            }
        }
        let metadata = try JSONDecoder().decode(Self.self, from: data)
        guard metadata.version == 1, metadata.connections.count <= 256,
              Set(metadata.connections.map(\.id)).count == metadata.connections.count,
              Set(metadata.connections.map(\.grantID)).count == metadata.connections.count else { throw AgentErrorCode.storageError }
        for record in metadata.connections {
            guard validName(record.name), record.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  record.expiresAt.timeIntervalSinceReferenceDate.isFinite, record.expiresAt > record.createdAt,
                  Set(record.capabilities).count == record.capabilities.count,
                  Set(record.resources).count == record.resources.count,
                  record.scopeKind != .library || record.resources.isEmpty else { throw AgentErrorCode.storageError }
        }
        return metadata
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        _ = try Self.decode(data)
        return data
    }

    static func validName(_ name: String) -> Bool {
        AgentConnectionName.isValid(name)
    }
}
