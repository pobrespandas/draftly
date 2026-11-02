import Foundation
import AgentContracts

// This policy covers the listed draft calls only. It does not authorize an Action.
@MainActor final class AgentScriptAuthority {
    private let connectionID: UUID
    private let grantID: UUID
    private let libraryID: UUID
    private let currentGrant: () throws -> AgentGrant?
    private let validateHost: () throws -> Void
    private let isLocked: () -> Bool
    private let now: () -> Date
    private let draftExists: (UUID) -> Bool

    init(grant: AgentGrant, currentGrant: @escaping () throws -> AgentGrant?,
         validateHost: @escaping () throws -> Void, isLocked: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init, draftExists: @escaping (UUID) -> Bool) {
        connectionID = grant.connectionID; grantID = grant.grantID; libraryID = grant.libraryID
        self.currentGrant = currentGrant; self.validateHost = validateHost
        self.isLocked = isLocked; self.now = now; self.draftExists = draftExists
    }

    func authorize(_ operation: String, payload: String) throws {
        guard !isLocked() else { throw AgentErrorCode.permissionDenied }
        try validateHost()
        guard let grant = try currentGrant(), grant.connectionID == connectionID,
              grant.grantID == grantID, grant.libraryID == libraryID, !grant.revoked,
              grant.expiresAt.timeIntervalSince1970.isFinite, grant.expiresAt > now(),
              grant.capabilities.contains(.actionsRun) else { throw AgentErrorCode.permissionDenied }
        guard let data = payload.data(using: .utf8), data.count <= AgentRequest.maximumBytes,
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentErrorCode.invalidInput
        }
        switch operation {
        case "device":
            break
        case "findDraft", "updateDraft":
            let required: AgentCapability = operation == "findDraft" ? .draftsRead : .draftsWrite
            guard grant.capabilities.contains(required) else { throw AgentErrorCode.permissionDenied }
            guard let raw = fields["uuid"] as? String, let id = UUID(uuidString: raw) else { throw AgentErrorCode.invalidInput }
            guard grant.scope.permits(.init(kind: .draft, id: id)), draftExists(id) else { throw AgentErrorCode.notFound }
        case "queryDrafts":
            guard grant.capabilities.contains(.draftsRead), grant.scope == .library else { throw AgentErrorCode.permissionDenied }
        default:
            throw AgentErrorCode.unavailable
        }
        guard !isLocked() else { throw AgentErrorCode.permissionDenied }
        try validateHost()
        guard let current = try currentGrant(), current.connectionID == grant.connectionID,
              current.grantID == grant.grantID, current.libraryID == grant.libraryID,
              !current.revoked, current.expiresAt == grant.expiresAt, current.expiresAt > now(),
              current.capabilities == grant.capabilities, current.scope == grant.scope else {
            throw AgentErrorCode.permissionDenied
        }
        guard !isLocked() else { throw AgentErrorCode.permissionDenied }
    }
}
