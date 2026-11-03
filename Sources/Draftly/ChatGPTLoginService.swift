import AppKit
import Foundation

struct ChatGPTAccountRecord: Codable, Equatable, Sendable {
    let id: UUID
    let identity: ChatGPTIdentity
    let hostID: String
    var tokens: ChatGPTTokens?
    var refreshUncertain: Bool?
}

struct ChatGPTTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String
    let scopes: Set<String>
    let expiresAt: Date

    var allowsInference: Bool { scopes.contains("chatgpt.tokens.use.direct") && scopes.contains("resource.invoke") }
}

/// Commit a new session only after callback and identity validation succeed.
@MainActor final class ChatGPTLoginService {
    enum Failure: Error, Equatable, LocalizedError {
        case busy, invalidRegistration, invalidTokenResponse, exchangeRejected, identityMismatch, storage

        var errorDescription: String? {
            switch self {
            case .busy: "A ChatGPT sign-in is already in progress."
            case .invalidRegistration: "The saved ChatGPT registration could not be read."
            case .invalidTokenResponse: "ChatGPT returned an incomplete sign-in response."
            case .exchangeRejected: "ChatGPT could not complete sign-in. Please sign in again."
            case .identityMismatch: "The signed-in account does not match the selected ChatGPT registration."
            case .storage: "The ChatGPT session could not be saved in Keychain."
            }
        }
    }

    typealias Authorize = @MainActor (String, String?) async throws -> (ChatGPTAuthorization, ChatGPTAuthorization.Code)
    typealias Exchange = @Sendable (URLRequest) async throws -> ChatGPTHTTP.Response
    typealias Verify = @Sendable (String, String, String, String?) async throws -> ChatGPTIdentity
    private let authorize: Authorize
    private let exchange: Exchange
    private let verify: Verify
    private let store: ChatGPTCredentialStore
    private let now: @Sendable () -> Date
    private let lease: @MainActor (UUID) throws -> AnyObject
    let hostID: String
    private var activeID: UUID?
    private var task: Task<ChatGPTAccountRecord, any Error>?
    // An issued client can be reused after an expired code without trusting an identity.
    private(set) var pendingClientID: String?

    init(defaults: UserDefaults = .standard, store: ChatGPTCredentialStore = ChatGPTCredentialStore(),
         authorize: @escaping Authorize = ChatGPTLoginService.browserAuthorization,
         exchange: @escaping Exchange = ChatGPTHTTP.perform,
         verify: Verify? = nil, now: @escaping @Sendable () -> Date = { Date() },
         lease: @escaping @MainActor (UUID) throws -> AnyObject = { try ChatGPTSessionLease(accountID: $0) }) {
        let key = "chatGPT.hostID"
        if let saved = defaults.string(forKey: key), saved.hasPrefix("urn:uuid:"),
           UUID(uuidString: String(saved.dropFirst(9))) != nil { hostID = saved }
        else {
            hostID = "urn:uuid:" + UUID().uuidString.lowercased()
            defaults.set(hostID, forKey: key)
        }
        self.store = store; self.authorize = authorize; self.exchange = exchange; self.now = now; self.lease = lease
        if let verify { self.verify = verify }
        else {
            let verifier = ChatGPTIdentityVerifier()
            self.verify = { token, nonce, client, subject in
                try await verifier.verify(token, nonce: nonce, clientID: client, expectedSubject: subject)
            }
        }
    }

    func read(_ id: UUID) throws -> ChatGPTAccountRecord? {
        guard let data = try store.read(id) else { return nil }
        guard let record = try? JSONDecoder().decode(ChatGPTAccountRecord.self, from: data), record.id == id,
              record.hostID == hostID, record.identity.issuer == "https://auth.openai.com",
              record.identity.clientID.hasPrefix("oaiapp_"), !record.identity.subject.isEmpty else {
            throw Failure.invalidRegistration
        }
        return record
    }

    func save(_ record: ChatGPTAccountRecord) throws {
        guard record.hostID == hostID else { throw Failure.invalidRegistration }
        do { try store.write(JSONEncoder().encode(record), accountID: record.id) }
        catch { throw Failure.storage }
    }

    func signIn(registrationID: UUID? = nil) async throws -> ChatGPTAccountRecord {
        guard activeID == nil else { throw Failure.busy }
        let previous: ChatGPTAccountRecord?
        if let registrationID {
            guard let record = try read(registrationID) else { throw Failure.invalidRegistration }
            previous = record
        } else { previous = nil }
        let id = UUID()
        activeID = id
        let task = Task { [self] in
            let (authorization, code) = try await authorize(hostID, previous?.identity.clientID ?? pendingClientID)
            try checkActive(id)
            guard authorization.hostID == hostID,
                  previous == nil || previous?.identity.clientID == code.clientID else { throw Failure.invalidRegistration }
            pendingClientID = code.clientID
            let response = try await exchange(authorization.exchangeRequest(for: code))
            try checkActive(id)
            guard response.status == 200 else { throw Failure.exchangeRejected }
            guard response.data.count <= 1048576,
                  let tokens = try? JSONDecoder().decode(TokenResponse.self, from: response.data),
                  tokens.token_type.lowercased() == "bearer", !tokens.access_token.isEmpty,
                  !tokens.id_token.isEmpty, tokens.expires_in.isFinite, tokens.expires_in > 0,
                  tokens.expires_in <= 31536000 else { throw Failure.invalidTokenResponse }
            let identity = try await verify(tokens.id_token, authorization.nonce, code.clientID, previous?.identity.subject)
            try checkActive(id)
            guard identity.clientID == code.clientID, identity.issuer == "https://auth.openai.com",
                  !identity.subject.isEmpty, previous == nil || previous?.identity.subject == identity.subject else {
                throw Failure.identityMismatch
            }
            let record = ChatGPTAccountRecord(id: previous?.id ?? UUID(), identity: identity, hostID: hostID,
                tokens: ChatGPTTokens(accessToken: tokens.access_token, refreshToken: tokens.refresh_token,
                    idToken: tokens.id_token, scopes: Set(tokens.scope.split(separator: " ").map(String.init)),
                    expiresAt: now().addingTimeInterval(tokens.expires_in)))
            let lock = try lease(record.id)
            defer { withExtendedLifetime(lock) {} }
            if let previous, try read(previous.id) != previous { throw Failure.invalidRegistration }
            try save(record)
            pendingClientID = nil
            return record
        }
        self.task = task
        defer { if activeID == id { activeID = nil; self.task = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    func cancel() {
        activeID = nil
        task?.cancel(); task = nil
    }

    func startDifferentRegistration() {
        cancel()
        pendingClientID = nil
    }

    private func checkActive(_ id: UUID) throws {
        try Task.checkCancellation()
        guard activeID == id else { throw CancellationError() }
    }

    static func browserAuthorization(hostID: String, clientID: String?) async throws -> (ChatGPTAuthorization, ChatGPTAuthorization.Code) {
        let listener = ChatGPTCallbackListener()
        defer { listener.cancel() }
        let port = try await listener.start()
        let authorization = try ChatGPTAuthorization(port: port, hostID: hostID, clientID: clientID)
        let code = try await listener.waitForCode(using: authorization, openBrowser: { NSWorkspace.shared.open($0) })
        return (authorization, code)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let id_token: String
        let token_type: String
        let scope: String
        let expires_in: Double
    }
}
