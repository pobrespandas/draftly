import Foundation
import AgentContracts

@MainActor struct AgentOperationAuthorization {
    private let lookupGrant: (UUID) throws -> AgentGrant?
    private let validateHost: () throws -> Void
    private let isLocked: () -> Bool
    private let now: () -> Date

    init(currentGrant: @escaping (UUID) throws -> AgentGrant?,
         validateHost: @escaping () throws -> Void, isLocked: @escaping () -> Bool,
         now: @escaping () -> Date) {
        lookupGrant = currentGrant
        self.validateHost = validateHost
        self.isLocked = isLocked
        self.now = now
    }

    func currentGrant(for connectionID: UUID) throws -> AgentGrant? {
        try lookupGrant(connectionID)
    }

    func validate(_ original: AgentGrant, targets: Set<AgentResourceReference>, operationName: String) throws {
        guard let descriptor = AgentOperationCatalog.operation(named: operationName) else { throw AgentErrorCode.invalidInput }
        guard !isLocked() else { throw AgentErrorCode.permissionDenied }
        try validateHost()
        guard let current = try lookupGrant(original.connectionID), !current.revoked,
              current.expiresAt.timeIntervalSince1970.isFinite, current.expiresAt > now(),
              current.capabilities.isSuperset(of: descriptor.capabilities),
              AgentRequestBinding.grantValue(current) == AgentRequestBinding.grantValue(original),
              targets.allSatisfy(current.scope.permits), !isLocked() else { throw AgentErrorCode.permissionDenied }
    }
}
