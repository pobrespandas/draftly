import Foundation
import AgentContracts
import DraftlyCore

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
    private let targetDraftID: UUID?
    private let editorDraftID: (() -> UUID?)?
    private let windowID: UUID?

    init(grant: AgentGrant, currentGrant: @escaping () throws -> AgentGrant?,
         validateHost: @escaping () throws -> Void, isLocked: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init, draftExists: @escaping (UUID) -> Bool,
         targetDraftID: UUID? = nil, editorDraftID: (() -> UUID?)? = nil, windowID: UUID? = nil) {
        connectionID = grant.connectionID; grantID = grant.grantID; libraryID = grant.libraryID
        self.currentGrant = currentGrant; self.validateHost = validateHost
        self.isLocked = isLocked; self.now = now; self.draftExists = draftExists
        self.targetDraftID = targetDraftID; self.editorDraftID = editorDraftID; self.windowID = windowID
    }

    func authorize(_ operation: String, payload: String) throws {
        let grant = try currentBaseline()
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
            guard grant.capabilities.contains(.draftsRead) else { throw AgentErrorCode.permissionDenied }
        default:
            throw AgentErrorCode.unavailable
        }
        try requireUnchanged(grant)
    }

    private func currentBaseline() throws -> AgentGrant {
        guard !isLocked() else { throw AgentErrorCode.permissionDenied }
        try validateHost()
        guard let grant = try currentGrant(), grant.connectionID == connectionID,
              grant.grantID == grantID, grant.libraryID == libraryID, !grant.revoked,
              grant.expiresAt.timeIntervalSince1970.isFinite, grant.expiresAt > now(),
              grant.capabilities.isSuperset(of: [.actionsRun, .draftsRead]) else { throw AgentErrorCode.permissionDenied }
        return grant
    }

    private func requireUnchanged(_ grant: AgentGrant) throws {
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

    func visibleActions(_ actions: [DraftAction]) throws -> [DraftAction] {
        let grant = try currentBaseline()
        let result = actions.filter { grant.scope.permits(.init(kind: .action, id: $0.id)) }
        try requireUnchanged(grant)
        return result
    }

    func authorizeStep(owner: UUID, step: ActionStep) throws {
        let grant = try currentBaseline()
        try requireTarget(grant, actionID: owner)
        switch step.type {
        case "script", "includeAction", "configurationKey": break
        case "insertText":
            guard grant.capabilities.contains(.draftsWrite), editorDraftID?() == targetDraftID else {
                throw AgentErrorCode.permissionDenied
            }
            if let windowID {
                guard grant.capabilities.contains(.editorWrite), grant.scope.permits(.init(kind: .window, id: windowID)) else {
                    throw AgentErrorCode.permissionDenied
                }
            }
        default: throw AgentErrorCode.unavailable
        }
        try requireUnchanged(grant)
    }

    func authorizeConfiguration(_ action: DraftAction) throws {
        let grant = try currentBaseline()
        try requireTarget(grant, actionID: action.id)
        guard grant.capabilities.contains(.actionsManage) else { throw AgentErrorCode.permissionDenied }
        try requireUnchanged(grant)
    }

    func authorizeCompletion(_ action: DraftAction, draftID: UUID) throws {
        let grant = try currentBaseline()
        try requireTarget(grant, actionID: action.id)
        guard targetDraftID == draftID, editorDraftID?() == draftID,
              grant.capabilities.contains(.draftsWrite) else { throw AgentErrorCode.permissionDenied }
        if let windowID {
            guard grant.capabilities.contains(.editorWrite), grant.scope.permits(.init(kind: .window, id: windowID)) else {
                throw AgentErrorCode.permissionDenied
            }
        }
        try requireUnchanged(grant)
    }

    private func requireTarget(_ grant: AgentGrant, actionID: UUID) throws {
        guard let targetDraftID, grant.scope.permits(.init(kind: .draft, id: targetDraftID)),
              grant.scope.permits(.init(kind: .action, id: actionID)), draftExists(targetDraftID) else {
            throw AgentErrorCode.notFound
        }
    }

    func visibleDrafts(_ drafts: [Note]) throws -> [Note] {
        try authorize("queryDrafts", payload: "{}")
        guard let grant = try currentGrant(), grant.connectionID == connectionID,
              grant.grantID == grantID, grant.libraryID == libraryID, !grant.revoked,
              grant.expiresAt > now(), grant.capabilities.isSuperset(of: [.actionsRun, .draftsRead]) else {
            throw AgentErrorCode.permissionDenied
        }
        let result = drafts.filter { grant.scope.permits(.init(kind: .draft, id: $0.id)) }
        try authorize("queryDrafts", payload: "{}")
        guard let current = try currentGrant(), current.connectionID == connectionID,
              current.libraryID == libraryID, current.grantID == grant.grantID, !current.revoked,
              current.scope == grant.scope, current.capabilities == grant.capabilities,
              current.expiresAt == grant.expiresAt else { throw AgentErrorCode.permissionDenied }
        return result
    }
}
