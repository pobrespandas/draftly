import Foundation

struct MCPConnectionCredentials: Codable, Equatable {
    let connectionID: UUID
    let endpoint: URL
    let authorizationServer: URL
    let clientID: String
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scopes: Set<String>
    var refreshUncertain: Bool = false
}

/// Bind each credential record to one configured MCP connection and endpoint.
@MainActor final class MCPConnectionCredentialStore {
    enum Failure: Error { case invalidRecord, endpointMismatch, refreshUncertain, staleSession }
    private let store: DeviceCredentialStore

    init(bundleID: String = Bundle.main.bundleIdentifier ?? "com.pobrespandas.draftly",
         backend: DeviceCredentialStore.Backend = .system) {
        store = DeviceCredentialStore(service: bundleID + ".mcp.credentials.v1", backend: backend)
    }

    func read(_ connectionID: UUID, endpoint: URL) throws -> MCPConnectionCredentials? {
        guard let data = try store.read(connectionID) else { return nil }
        let record = try JSONDecoder().decode(MCPConnectionCredentials.self, from: data)
        try validate(record)
        guard record.connectionID == connectionID, record.endpoint == endpoint else { throw Failure.endpointMismatch }
        return record
    }

    func write(_ record: MCPConnectionCredentials) throws {
        try validate(record)
        if let existing = try store.read(record.connectionID) {
            let previous = try JSONDecoder().decode(MCPConnectionCredentials.self, from: existing)
            guard previous.endpoint == record.endpoint else { throw Failure.endpointMismatch }
        }
        try store.write(JSONEncoder().encode(record), accountID: record.connectionID)
    }

    /// Save uncertainty before a request can rotate the refresh token.
    func beginRefresh(_ connectionID: UUID, endpoint: URL) throws -> MCPConnectionCredentials {
        guard var record = try read(connectionID, endpoint: endpoint) else { throw Failure.invalidRecord }
        guard !record.refreshUncertain else { throw Failure.refreshUncertain }
        record.refreshUncertain = true
        try write(record)
        return record
    }

    func completeRefresh(expected: MCPConnectionCredentials, replacement: MCPConnectionCredentials) throws {
        guard expected.refreshUncertain, !replacement.refreshUncertain,
              replacement.connectionID == expected.connectionID,
              replacement.endpoint == expected.endpoint,
              replacement.authorizationServer == expected.authorizationServer,
              replacement.clientID == expected.clientID,
              try read(expected.connectionID, endpoint: expected.endpoint) == expected else {
            throw Failure.staleSession
        }
        try write(replacement)
    }

    func remove(_ connectionID: UUID) throws { try store.remove(connectionID) }

    private func validate(_ record: MCPConnectionCredentials) throws {
        guard secureURL(record.endpoint), secureURL(record.authorizationServer),
              !record.clientID.isEmpty, !record.accessToken.isEmpty,
              !record.accessToken.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw Failure.invalidRecord
        }
    }

    private func secureURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.isEmpty == false && url.user == nil
            && url.password == nil && url.fragment == nil
    }
}
