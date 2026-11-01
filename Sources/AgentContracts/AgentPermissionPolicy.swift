import Foundation

package enum AgentCapability: String, Codable, Sendable, CaseIterable {
    case draftsRead = "drafts.read", draftsWrite = "drafts.write"
    case editorRead = "editor.read", editorWrite = "editor.write", presentUI = "ui.present"
    case actionsRead = "actions.read", actionsManage = "actions.manage", actionsRun = "actions.run"
    case workspacesRead = "workspaces.read", workspacesManage = "workspaces.manage", workspacesApply = "workspaces.apply"
    case appearanceRead = "appearance.read", appearanceManage = "appearance.manage"
    case preferencesRead = "preferences.read", preferencesWrite = "preferences.write"
    case filesRead = "files.read", filesWrite = "files.write"
    case backupsExport = "backups.export", backupsRestore = "backups.restore"
    case nativeUse = "native.use", scriptsUnrestricted = "scripts.unrestricted"
    case destructiveRequest = "destructive.request"
}

package enum AgentResourceScope: Equatable, Sendable {
    case library
    case resources(Set<AgentResourceReference>)
}

package struct AgentGrant: Sendable {
    package let connectionID: UUID
    package let libraryID: UUID
    package let expiresAt: Date
    package let revoked: Bool
    package let capabilities: Set<AgentCapability>
    package let scope: AgentResourceScope

    package init(connectionID: UUID, libraryID: UUID, expiresAt: Date, revoked: Bool = false,
                 capabilities: Set<AgentCapability>, scope: AgentResourceScope) {
        self.connectionID = connectionID
        self.libraryID = libraryID
        self.expiresAt = expiresAt
        self.revoked = revoked
        self.capabilities = capabilities
        self.scope = scope
    }
}

package enum AgentPermissionDecision: Equatable, Sendable {
    // A permitted decision is not a claim that an operation has a handler.
    case permitted(AgentResourceScope)
    case needsHumanApproval(AgentResourceScope)
    case needsEffectAuthorization(AgentResourceScope, humanApproval: Bool)
    case denied(AgentErrorCode)
}

package enum AgentPermissionPolicy {
    package static func evaluate(_ request: AgentRequest, connectionID: UUID,
                                 grant: AgentGrant?, now: Date) -> AgentPermissionDecision {
        guard let grant, !grant.revoked, grant.expiresAt.timeIntervalSince1970.isFinite,
              grant.expiresAt > now, grant.connectionID == connectionID,
              request.libraryID == grant.libraryID else { return .denied(.permissionDenied) }
        guard let operation = AgentOperationCatalog.operation(named: request.operation) else {
            return .denied(.unavailable)
        }
        guard grant.capabilities.isSuperset(of: operation.capabilities) else {
            return .denied(.permissionDenied)
        }
        if operation.requiresLibraryScope, grant.scope != .library { return .denied(.permissionDenied) }
        guard operation.acceptsTargets(request.targets) else { return .denied(.invalidInput) }
        if case .resources(let allowed) = grant.scope,
           !Set(request.targets).isSubset(of: allowed) { return .denied(.notFound) }
        if operation.requiresExpectedVersion,
           request.expectedVersion?.isEmpty != false { return .denied(.invalidInput) }
        if operation.requiresEffectAuthorization {
            return .needsEffectAuthorization(grant.scope, humanApproval: operation.requiresHumanApproval)
        }
        return operation.requiresHumanApproval ? .needsHumanApproval(grant.scope) : .permitted(grant.scope)
    }
}
