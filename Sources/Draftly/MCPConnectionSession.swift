import Foundation

/// One owner coordinates the MCP sessions used by all app windows.
@MainActor final class MCPConnectionSession {
    enum Failure: Error { case disconnected, signInRequired, permissionDenied, invalidRenewal }
    typealias Renew = @MainActor (MCPConnectionCredentials) async throws -> MCPConnectionCredentials
    typealias Lease = @MainActor (UUID) throws -> AnyObject
    private let store: MCPConnectionCredentialStore
    private let renew: Renew
    private let lease: Lease
    private let now: () -> Date
    private var pending: [UUID: Task<MCPConnectionCredentials, Error>] = [:]
    private var disconnecting = Set<UUID>()

    init(store: MCPConnectionCredentialStore, renew: @escaping Renew,
         lease: @escaping Lease = { id in
             let bundle = Bundle.main.bundleIdentifier ?? "com.pobrespandas.draftly"
             let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                 .appendingPathComponent(bundle).appendingPathComponent("MCP/Sessions")
             return try ChatGPTSessionLease(accountID: id, directory: directory)
         }, now: @escaping () -> Date = { Date() }) {
        self.store = store; self.renew = renew; self.lease = lease; self.now = now
    }

    func accessToken(_ id: UUID, endpoint: URL, requiredScopes: Set<String>) async throws -> String {
        try Task.checkCancellation()
        guard !disconnecting.contains(id) else { throw Failure.disconnected }
        let record: MCPConnectionCredentials
        if let task = pending[id] { record = try await task.value }
        else {
            guard let current = try store.read(id, endpoint: endpoint) else { throw Failure.disconnected }
            guard !current.refreshUncertain else { throw Failure.signInRequired }
            guard requiredScopes.isSubset(of: current.scopes) else { throw Failure.permissionDenied }
            if current.expiresAt.map({ $0.timeIntervalSince(now()) <= 60 }) == true {
                let task = Task { try await self.refresh(id, endpoint: endpoint) }
                pending[id] = task
                defer { pending[id] = nil }
                record = try await task.value
            } else { record = current }
        }
        try Task.checkCancellation()
        guard !disconnecting.contains(id),
              try store.read(id, endpoint: endpoint) == record else { throw Failure.disconnected }
        guard record.endpoint == endpoint, requiredScopes.isSubset(of: record.scopes) else { throw Failure.permissionDenied }
        return record.accessToken
    }

    private func refresh(_ id: UUID, endpoint: URL) async throws -> MCPConnectionCredentials {
        let lock = try lease(id)
        defer { withExtendedLifetime(lock) {} }
        guard let current = try store.read(id, endpoint: endpoint) else { throw Failure.disconnected }
        guard !current.refreshUncertain else { throw Failure.signInRequired }
        if current.expiresAt.map({ $0.timeIntervalSince(now()) > 60 }) ?? true { return current }
        guard current.refreshToken?.isEmpty == false else { throw Failure.signInRequired }
        let expected = try store.beginRefresh(id, endpoint: endpoint)
        let renewed = try await renew(expected)
        guard let expiry = renewed.expiresAt, expiry.timeIntervalSince(now()) > 60 else { throw Failure.invalidRenewal }
        try store.completeRefresh(expected: expected, replacement: renewed)
        return renewed
    }

    /// Disconnect locally. The caller must report remote revocation separately.
    func disconnect(_ id: UUID) async throws {
        guard disconnecting.insert(id).inserted else { throw Failure.disconnected }
        defer { disconnecting.remove(id) }
        if let task = pending[id] { _ = try? await task.value }
        let lock = try lease(id)
        defer { withExtendedLifetime(lock) {} }
        try store.remove(id)
    }
}
