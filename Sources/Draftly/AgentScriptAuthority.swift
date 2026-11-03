import Foundation
import AgentContracts
import DraftlyCore

// This policy guards supported steps. It does not grant permission to run an Action.
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
    private var approvedActions: [UUID: DraftAction]
    private let currentAction: ((UUID) -> DraftAction?)?
    private let reviewedNativeEffects: Bool

    init(grant: AgentGrant, currentGrant: @escaping () throws -> AgentGrant?,
         validateHost: @escaping () throws -> Void, isLocked: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init, draftExists: @escaping (UUID) -> Bool,
         targetDraftID: UUID? = nil, editorDraftID: (() -> UUID?)? = nil, windowID: UUID? = nil,
         approvedActions: [UUID: DraftAction] = [:], currentAction: ((UUID) -> DraftAction?)? = nil,
         reviewedNativeEffects: Bool = false) {
        connectionID = grant.connectionID; grantID = grant.grantID; libraryID = grant.libraryID
        self.currentGrant = currentGrant; self.validateHost = validateHost
        self.isLocked = isLocked; self.now = now; self.draftExists = draftExists
        self.targetDraftID = targetDraftID; self.editorDraftID = editorDraftID; self.windowID = windowID
        self.approvedActions = approvedActions; self.currentAction = currentAction
        self.reviewedNativeEffects = reviewedNativeEffects
    }

    func validateRequestIdentity(_ request: AgentRequest, connectionID: UUID, draftID: UUID) throws {
        let grant = try currentBaseline()
        guard self.connectionID == connectionID, targetDraftID == draftID,
              request.libraryID == nil || request.libraryID == libraryID else { throw AgentErrorCode.permissionDenied }
        try requireUnchanged(grant)
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
        let result = actions.filter { grant.scope.permits(.init(kind: .action, id: $0.id)) && approvedActions[$0.id] == $0 }
        try requireUnchanged(grant)
        return result
    }

    func authorizeStep(owner: UUID, step: ActionStep) throws {
        let grant = try currentBaseline()
        try requireTarget(grant, actionID: owner)
        let approved = try checkedAction(owner)
        guard approved.steps.contains(step) else { throw AgentErrorCode.versionConflict }
        switch step.type {
        case "script", "includeAction", "configurationKey": break
        case "share", "openIn", "print", "clipboard", "url":
            guard reviewedNativeEffects else { throw AgentErrorCode.unavailable }
            guard grant.capabilities.contains(.nativeUse) else { throw AgentErrorCode.permissionDenied }
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
        guard try checkedAction(owner) == approved else { throw AgentErrorCode.versionConflict }
        try requireUnchanged(grant)
    }

    func authorizeNative(_ operation: String, rootActionID: UUID) throws {
        let grant = try currentBaseline()
        try requireTarget(grant, actionID: rootActionID)
        let approved = try checkedAction(rootActionID)
        try requireApprovedActionsUnchanged()
        if operation != "device" {
            guard ["share", "shareFile", "print", "clipboard", "getClipboard", "htmlToClipboard", "openURL"].contains(operation), reviewedNativeEffects,
                  grant.capabilities.contains(.nativeUse) else { throw AgentErrorCode.permissionDenied }
        }
        try requireUnchanged(grant)
        guard try checkedAction(rootActionID) == approved else { throw AgentErrorCode.versionConflict }
        try requireApprovedActionsUnchanged()
        try requireUnchanged(grant)
    }

    private func requireApprovedActionsUnchanged() throws {
        for (id, approved) in approvedActions where currentAction?(id) != approved {
            throw AgentErrorCode.versionConflict
        }
    }

    func authorizeConfiguration(_ action: DraftAction) throws {
        let grant = try currentBaseline()
        try requireTarget(grant, actionID: action.id)
        guard try checkedAction(action.id) == action else { throw AgentErrorCode.versionConflict }
        guard grant.capabilities.contains(.actionsManage) else { throw AgentErrorCode.permissionDenied }
        try requireUnchanged(grant)
        guard try checkedAction(action.id) == action else { throw AgentErrorCode.versionConflict }
        try requireUnchanged(grant)
    }

    func acceptConfiguredAction(before: DraftAction, after: DraftAction) throws {
        let grant = try currentBaseline()
        try requireTarget(grant, actionID: before.id)
        guard grant.capabilities.contains(.actionsManage) else { throw AgentErrorCode.permissionDenied }
        guard approvedActions[before.id] == before, currentAction?(before.id) == after else { throw AgentErrorCode.versionConflict }
        var candidate = after
        candidate.configuredValues = before.configuredValues
        var oldMetadata = before.scriptMetadata ?? [:], newMetadata = after.scriptMetadata ?? [:]
        oldMetadata.removeValue(forKey: "_draftly.initialConfiguration")
        newMetadata.removeValue(forKey: "_draftly.initialConfiguration")
        guard oldMetadata == newMetadata else { throw AgentErrorCode.versionConflict }
        candidate.scriptMetadata = before.scriptMetadata
        guard candidate == before else { throw AgentErrorCode.versionConflict }
        try requireUnchanged(grant)
        guard currentAction?(before.id) == after else { throw AgentErrorCode.versionConflict }
        try requireUnchanged(grant)
        approvedActions[before.id] = after
    }

    func authorizeCompletion(_ action: DraftAction, draftID: UUID) throws {
        let grant = try currentBaseline()
        try requireTarget(grant, actionID: action.id)
        guard try checkedAction(action.id) == action else { throw AgentErrorCode.versionConflict }
        guard targetDraftID == draftID, editorDraftID?() == draftID,
              grant.capabilities.contains(.draftsWrite) else { throw AgentErrorCode.permissionDenied }
        if let windowID {
            guard grant.capabilities.contains(.editorWrite), grant.scope.permits(.init(kind: .window, id: windowID)) else {
                throw AgentErrorCode.permissionDenied
            }
        }
        try requireUnchanged(grant)
        guard try checkedAction(action.id) == action else { throw AgentErrorCode.versionConflict }
        try requireUnchanged(grant)
    }

    private func requireTarget(_ grant: AgentGrant, actionID: UUID) throws {
        guard let targetDraftID, grant.scope.permits(.init(kind: .draft, id: targetDraftID)),
              grant.scope.permits(.init(kind: .action, id: actionID)), draftExists(targetDraftID) else {
            throw AgentErrorCode.notFound
        }
    }

    private func checkedAction(_ id: UUID) throws -> DraftAction {
        guard let approved = approvedActions[id], let current = currentAction?(id), current == approved else {
            throw AgentErrorCode.versionConflict
        }
        return approved
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
