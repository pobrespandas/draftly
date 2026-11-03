import AppKit
import Foundation

@MainActor final class MCPLoginService {
    enum Failure: Error { case busy, invalidTokenResponse, sessionChanged }
    typealias Browser = @MainActor (URL, URL) async throws -> URL
    private let store: MCPConnectionCredentialStore
    private let discovery: MCPAuthorizationDiscovery
    private let exchange: MCPAuthorizationDiscovery.Fetch
    private let lease: MCPConnectionSession.Lease
    private let browser: Browser
    private var attemptID: UUID?

    init(store: MCPConnectionCredentialStore, discovery: MCPAuthorizationDiscovery = .init(),
         exchange: @escaping MCPAuthorizationDiscovery.Fetch = ChatGPTHTTP.perform,
         lease: @escaping MCPConnectionSession.Lease = MCPConnectionSession.acquireLease,
         browser: @escaping Browser = { url, redirect in
             guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { throw MCPBrowserAuthorization.Failure.unavailable }
             let authorization = MCPBrowserAuthorization(anchor: window)
             return try await authorization.authenticate(url: url, redirectURI: redirect)
         }) {
        self.store = store; self.discovery = discovery; self.exchange = exchange; self.browser = browser; self.lease = lease
    }

    func signIn(connectionID: UUID, endpoint: URL, clientID: String, redirectURI: URL,
                scopes: Set<String>, issuer: URL? = nil) async throws -> MCPConnectionCredentials {
        guard attemptID == nil else { throw Failure.busy }
        let id = UUID(); attemptID = id
        defer { if attemptID == id { attemptID = nil } }
        let previous = try store.read(connectionID, endpoint: endpoint)
        let server = try await discovery.discover(endpoint: endpoint, issuer: issuer)
        try check(id)
        let authorization = try MCPAuthorizationRequest(server: server, clientID: clientID, redirectURI: redirectURI, scopes: scopes)
        let callback = try await browser(authorization.browserURL(), redirectURI)
        try check(id)
        let code = try authorization.code(from: callback)
        let response = try await exchange(authorization.tokenRequest(code: code))
        try check(id)
        guard response.status == 200, response.data.count <= 1048576 else { throw Failure.invalidTokenResponse }
        let token: TokenResponse
        do { token = try JSONDecoder().decode(TokenResponse.self, from: response.data) }
        catch { throw Failure.invalidTokenResponse }
        guard token.token_type.lowercased() == "bearer", !token.access_token.isEmpty,
              token.expires_in.map({ $0.isFinite && $0 > 0 && $0 <= 31536000 }) ?? true,
              token.refresh_token.map({ !$0.isEmpty }) ?? true else { throw Failure.invalidTokenResponse }
        let granted = token.scope.map { Set($0.split(separator: " ").map(String.init)) } ?? scopes
        let record = MCPConnectionCredentials(connectionID: connectionID, endpoint: endpoint,
            authorizationServer: server.issuer, clientID: clientID, accessToken: token.access_token,
            refreshToken: token.refresh_token, expiresAt: token.expires_in.map { Date().addingTimeInterval($0) }, scopes: granted)
        let lock = try lease(connectionID)
        defer { withExtendedLifetime(lock) {} }
        guard try store.read(connectionID, endpoint: endpoint) == previous else { throw Failure.sessionChanged }
        try store.write(record)
        return record
    }

    private func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard attemptID == id else { throw CancellationError() }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let token_type: String
        let refresh_token: String?
        let expires_in: Double?
        let scope: String?
    }
}
