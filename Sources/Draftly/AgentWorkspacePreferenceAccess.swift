import Foundation
import AgentContracts
import DraftlyCore

@MainActor enum AgentWorkspacePreferenceAccess {
    @MainActor struct Change {
        let storageKey = WorkspaceDefaults.key
        let value: String?
    }

    static func read(defaults: UserDefaults, capabilities: Set<AgentCapability>, scope: AgentResourceScope,
                     workspaceExists: (UUID) throws -> Bool) throws -> AgentPreferenceReading {
        guard capabilities.contains(.preferencesRead) else { throw AgentErrorCode.permissionDenied }
        guard let raw = defaults.object(forKey: WorkspaceDefaults.key) else {
            return .init(effectiveValue: .null, origin: "default", hasOverride: false)
        }
        guard let text = raw as? String, let id = UUID(uuidString: text) else {
            return .init(effectiveValue: .null, origin: "invalid", hasOverride: true)
        }
        try checkReference(id, capabilities: capabilities, scope: scope)
        guard try workspaceExists(id) else { return .init(effectiveValue: .null, origin: "invalid", hasOverride: true) }
        return .init(effectiveValue: .string(id.uuidString), origin: "stored", hasOverride: true)
    }

    static func prepare(value: AgentJSONValue?, capabilities: Set<AgentCapability>, scope: AgentResourceScope,
                        workspaceExists: (UUID) throws -> Bool) throws -> Change {
        guard capabilities.contains(.preferencesWrite) else { throw AgentErrorCode.permissionDenied }
        guard let value, value != .null else { return Change(value: nil) }
        let field = try AgentPreferenceCatalog.make().field(WorkspaceDefaults.key)
        try field.value.validate(value)
        guard case .string(let text) = value, let id = UUID(uuidString: text) else { throw AgentErrorCode.invalidInput }
        try checkReference(id, capabilities: capabilities, scope: scope)
        guard try workspaceExists(id) else { throw AgentErrorCode.notFound }
        return Change(value: id.uuidString)
    }

    // The service must also validate session lifetime, connection and library identity.
    private static func checkReference(_ id: UUID, capabilities: Set<AgentCapability>, scope: AgentResourceScope) throws {
        guard capabilities.contains(.workspacesRead), scope.permits(.init(kind: .workspace, id: id)) else {
            throw AgentErrorCode.notFound
        }
    }
}
