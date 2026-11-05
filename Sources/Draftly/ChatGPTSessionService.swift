import Foundation

/// Share this owner across app windows. Refresh does not belong to a chat turn.
@MainActor final class ChatGPTSessionService {
    enum Failure: Error, LocalizedError {
        case signedOut, signInRequired, permissionDenied, invalidResponse, storage
        var errorDescription: String? {
            switch self {
            case .signedOut: "Sign in with ChatGPT to continue."
            case .signInRequired: "The ChatGPT session needs a new sign-in."
            case .permissionDenied: "This ChatGPT connection does not have permission to use models."
            case .invalidResponse: "ChatGPT returned an invalid session response."
            case .storage: "The renewed ChatGPT session could not be saved in Keychain. Sign in again."
            }
        }
    }
    typealias Lease = @MainActor (UUID) throws -> AnyObject
    typealias VerifyRenewed = @Sendable (String, ChatGPTIdentity) async throws -> ChatGPTIdentity
    private let login: ChatGPTLoginService
    private let exchange: ChatGPTLoginService.Exchange
    private let verify: VerifyRenewed
    private let lease: Lease
    private let now: @Sendable () -> Date
    private var refreshes: [UUID: Task<ChatGPTAccountRecord, any Error>] = [:]
    private var signingOut = Set<UUID>()

    init(login: ChatGPTLoginService, exchange: @escaping ChatGPTLoginService.Exchange = ChatGPTHTTP.perform,
         verify: VerifyRenewed? = nil, lease: @escaping Lease = { try ChatGPTSessionLease(accountID: $0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.login = login; self.exchange = exchange; self.lease = lease; self.now = now
        if let verify { self.verify = verify }
        else {
            let verifier = ChatGPTIdentityVerifier()
            self.verify = { try await verifier.verifyRenewed($0, identity: $1) }
        }
    }

    func accessToken(for id: UUID) async throws -> String {
        try Task.checkCancellation()
        guard !signingOut.contains(id) else { throw Failure.signedOut }
        if let task = refreshes[id] { return try checkedToken(try await task.value, id: id) }
        guard var record = try login.read(id) else { throw Failure.signedOut }
        if record.refreshUncertain == true {
            let lock = try lease(id)
            defer { withExtendedLifetime(lock) {} }
            guard let current = try login.read(id), current.refreshUncertain != true else { throw Failure.signInRequired }
            record = current
        }
        guard let tokens = record.tokens else { throw Failure.signedOut }
        guard tokens.allowsInference else { throw Failure.permissionDenied }
        if tokens.expiresAt.timeIntervalSince(now()) > 60 { return tokens.accessToken }
        let task = Task { [self] in try await refresh(id) }
        refreshes[id] = task
        defer { refreshes[id] = nil }
        return try checkedToken(try await task.value, id: id)
    }

    private func checkedToken(_ record: ChatGPTAccountRecord, id: UUID) throws -> String {
        try Task.checkCancellation()
        guard !signingOut.contains(id), let refreshed = record.tokens else { throw Failure.signedOut }
        guard refreshed.allowsInference else { throw Failure.permissionDenied }
        return refreshed.accessToken
    }

    private func refresh(_ id: UUID) async throws -> ChatGPTAccountRecord {
        let lock = try lease(id)
        defer { withExtendedLifetime(lock) {} }
        // Another process may have renewed the session before this lock was acquired.
        guard var record = try login.read(id), let tokens = record.tokens else { throw Failure.signedOut }
        guard record.refreshUncertain != true else { throw Failure.signInRequired }
        if tokens.expiresAt.timeIntervalSince(now()) > 60 { return record }
        guard let refresh = tokens.refreshToken, !refresh.isEmpty else { throw Failure.signInRequired }
        let request = Self.form(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!, values: [
            "grant_type": "refresh_token", "client_id": record.identity.clientID,
            "refresh_token": refresh, "resource": ChatGPTAuthorization.resource])
        record.refreshUncertain = true
        try login.save(record)
        do {
            let result = try await exchange(request)
            guard result.status == 200, result.data.count <= 1048576 else { throw Failure.signInRequired }
            let response = try JSONDecoder().decode(RefreshResponse.self, from: result.data)
            guard !response.access_token.isEmpty, response.token_type.lowercased() == "bearer",
                  response.expires_in.isFinite, response.expires_in > 0, response.expires_in <= 31536000,
                  response.refresh_token == nil || !response.refresh_token!.isEmpty else { throw Failure.invalidResponse }
            if let idToken = response.id_token {
                let identity = try await verify(idToken, record.identity)
                guard identity.issuer == record.identity.issuer, identity.subject == record.identity.subject,
                      identity.clientID == record.identity.clientID else { throw Failure.invalidResponse }
            }
            record.tokens = ChatGPTTokens(accessToken: response.access_token,
                refreshToken: response.refresh_token ?? refresh, idToken: response.id_token ?? tokens.idToken,
                scopes: response.scope.map { Set($0.split(separator: " ").map(String.init)) } ?? tokens.scopes,
                expiresAt: now().addingTimeInterval(response.expires_in))
            record.refreshUncertain = nil
            do { try login.save(record) } catch { throw Failure.storage }
            return record
        } catch {
            // The server may have rotated the token even when the response was lost.
            // Never repeat that request automatically with the old refresh token.
            throw error
        }
    }

    /// Return false when local sign-out completed without confirmed remote revocation.
    func signOut(_ id: UUID) async throws -> Bool {
        guard signingOut.insert(id).inserted else { throw Failure.signedOut }
        defer { signingOut.remove(id) }
        login.cancel()
        // Let an in-flight rotation finish before choosing the refresh token to revoke.
        if let refresh = refreshes[id] { _ = try? await refresh.value }
        let lock = try lease(id)
        defer { withExtendedLifetime(lock) {} }
        guard var record = try login.read(id), let tokens = record.tokens else { return true }
        var revoked = false
        if let refresh = tokens.refreshToken {
            do {
                let discovery = try await exchange(URLRequest(url: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!))
                guard discovery.status == 200, discovery.data.count <= 1048576 else { throw Failure.invalidResponse }
                let configuration = try JSONDecoder().decode(Discovery.self, from: discovery.data)
                guard configuration.issuer == "https://auth.openai.com",
                      let endpoint = URL(string: configuration.revocation_endpoint), endpoint.scheme == "https",
                      endpoint.host == "auth.openai.com", endpoint.port == nil, endpoint.user == nil,
                      endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil else { throw Failure.invalidResponse }
                let result = try await exchange(Self.form(url: endpoint, values: [
                    "token": refresh, "token_type_hint": "refresh_token", "client_id": record.identity.clientID]))
                revoked = result.status == 200 && record.refreshUncertain != true
            } catch { revoked = false }
        }
        record.tokens = nil
        record.refreshUncertain = nil
        try login.save(record)
        return revoked
    }

    static func form(url: URL, values: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    private struct RefreshResponse: Decodable {
        let access_token: String; let refresh_token: String?; let id_token: String?
        let scope: String?; let expires_in: Double; let token_type: String
    }
    private struct Discovery: Decodable { let issuer: String; let revocation_endpoint: String }
}
