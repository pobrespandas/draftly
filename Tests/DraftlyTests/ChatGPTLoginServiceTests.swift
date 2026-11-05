import Foundation
import Security
import Testing
@testable import Draftly

@Suite("Direct ChatGPT login transaction") @MainActor
struct ChatGPTLoginServiceTests {
    @MainActor final class Vault {
        var records: [String: Data] = [:]
        var rejectWrites = false
        var writes = 0
        var store: ChatGPTCredentialStore { ChatGPTCredentialStore(bundleID: "neutral.login.tests", backend: .init(
            copy: { [self] query in
                guard let key = query[kSecAttrAccount as String] as? String, let data = records[key] else {
                    return (errSecItemNotFound, nil)
                }
                return (errSecSuccess, data)
            }, update: { [self] query, values in
                if rejectWrites { return errSecInteractionNotAllowed }
                let key = query[kSecAttrAccount as String] as! String
                guard records[key] != nil else { return errSecItemNotFound }
                records[key] = values[kSecValueData as String] as? Data; writes += 1
                return errSecSuccess
            }, add: { [self] values in
                if rejectWrites { return errSecInteractionNotAllowed }
                records[values[kSecAttrAccount as String] as! String] = values[kSecValueData as String] as? Data
                writes += 1
                return errSecSuccess
            }, remove: { _ in errSecSuccess })) }
    }

    private actor Gate {
        private var waiter: CheckedContinuation<ChatGPTHTTP.Response, Never>?
        private var entered: CheckedContinuation<Void, Never>?
        private var didEnter = false
        func response() async -> ChatGPTHTTP.Response {
            didEnter = true; entered?.resume(); entered = nil
            return await withCheckedContinuation { waiter = $0 }
        }
        func waitUntilEntered() async {
            if didEnter { return }
            await withCheckedContinuation { entered = $0 }
        }
        func release(_ response: ChatGPTHTTP.Response) { waiter?.resume(returning: response); waiter = nil }
    }

    private func defaults() throws -> (UserDefaults, String) {
        let suite = "ChatGPTLoginServiceTests." + UUID().uuidString
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    private static func response(scope: String = "openid resource.invoke chatgpt.tokens.use.direct") throws -> ChatGPTHTTP.Response {
        .init(status: 200, data: try JSONSerialization.data(withJSONObject: [
            "access_token": "neutral-access", "refresh_token": "neutral-refresh", "id_token": "neutral-id",
            "token_type": "Bearer", "expires_in": 3600, "scope": scope]))
    }

    nonisolated private static func identity(_ client: String, subject: String = "neutral-subject") -> ChatGPTIdentity {
        ChatGPTIdentity(issuer: "https://auth.openai.com", clientID: client, subject: subject, email: nil, name: nil)
    }

    private static func authorize(host: String, client: String?) throws -> (ChatGPTAuthorization, ChatGPTAuthorization.Code) {
        let authorization = try ChatGPTAuthorization(port: 1455, hostID: host, clientID: client)
        var callback = URLComponents(url: authorization.redirectURI, resolvingAgainstBaseURL: false)!
        callback.queryItems = [.init(name: "state", value: authorization.state), .init(name: "code", value: "neutral-code"),
                               .init(name: "client_id", value: client ?? "oaiapp_neutral")]
        return (authorization, try authorization.validateCallback(callback.url!))
    }

    @Test func commitsValidatedSessionAndRestoresFromKeychainWithStableHost() async throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault(), response = try Self.response()
        let service = ChatGPTLoginService(defaults: defaults, store: vault.store, authorize: Self.authorize,
            exchange: { _ in response }, verify: { _, nonce, client, subject in
                #expect(!nonce.isEmpty && subject == nil)
                return Self.identity(client)
            }, lease: { _ in NSObject() })
        let record = try await service.signIn()
        #expect(record.tokens?.allowsInference == true && vault.writes == 1)
        #expect(record.identity.subject == "neutral-subject")
        let restarted = ChatGPTLoginService(defaults: defaults, store: vault.store, lease: { _ in NSObject() })
        #expect(restarted.hostID == service.hostID)
        #expect(try restarted.read(record.id)?.tokens?.accessToken == "neutral-access")
        let serializedDefaults = String(describing: defaults.persistentDomain(forName: suite))
        #expect(!serializedDefaults.contains("neutral-access") && !serializedDefaults.contains("neutral-refresh"))
    }

    @Test func reauthorizationRejectsAnotherSubjectWithoutReplacingExistingSession() async throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault(), response = try Self.response()
        let first = ChatGPTLoginService(defaults: defaults, store: vault.store, authorize: Self.authorize,
            exchange: { _ in response }, verify: { _, _, client, _ in Self.identity(client) }, lease: { _ in NSObject() })
        let record = try await first.signIn(), oldData = vault.records
        let replacement = ChatGPTLoginService(defaults: defaults, store: vault.store, authorize: { host, client in
            #expect(client == record.identity.clientID)
            return try Self.authorize(host: host, client: client)
        }, exchange: { _ in response }, verify: { _, _, client, subject in
            #expect(subject == record.identity.subject)
            return Self.identity(client, subject: "wrong-subject")
        }, lease: { _ in NSObject() })
        await #expect(throws: ChatGPTLoginService.Failure.identityMismatch) { try await replacement.signIn(registrationID: record.id) }
        #expect(vault.records == oldData && vault.writes == 1)
    }

    @Test func expiredCodeKeepsIssuedClientForRetryAndNeverWritesTokens() async throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault()
        var suppliedClients: [String?] = []
        let service = ChatGPTLoginService(defaults: defaults, store: vault.store, authorize: { host, client in
            suppliedClients.append(client)
            return try Self.authorize(host: host, client: client)
        }, exchange: { _ in .init(status: 400, data: Data()) }, verify: { _, _, client, _ in Self.identity(client) }, lease: { _ in NSObject() })
        for _ in 0..<2 {
            await #expect(throws: ChatGPTLoginService.Failure.exchangeRejected) { try await service.signIn() }
        }
        #expect(suppliedClients.count == 2 && suppliedClients[0] == nil && suppliedClients[1] == "oaiapp_neutral")
        #expect(vault.records.isEmpty && vault.writes == 0)
        service.startDifferentRegistration()
        #expect(service.pendingClientID == nil)
    }

    @Test func cancellationRejectsLateNonCooperativeExchange() async throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault(), gate = Gate()
        let service = ChatGPTLoginService(defaults: defaults, store: vault.store, authorize: Self.authorize,
            exchange: { _ in await gate.response() }, verify: { _, _, client, _ in Self.identity(client) }, lease: { _ in NSObject() })
        let task = Task { try await service.signIn() }
        await gate.waitUntilEntered()
        await #expect(throws: ChatGPTLoginService.Failure.busy) { try await service.signIn() }
        service.cancel()
        await gate.release(try Self.response())
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(vault.records.isEmpty)
    }

    @Test func deniedPlanScopeDoesNotBecomeInferencePermission() async throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault(), response = try Self.response(scope: "openid profile email")
        let service = ChatGPTLoginService(defaults: defaults, store: vault.store, authorize: Self.authorize,
            exchange: { _ in response }, verify: { _, _, client, _ in Self.identity(client) }, lease: { _ in NSObject() })
        #expect(try await service.signIn().tokens?.allowsInference == false)
    }

    @Test func storageFailureDoesNotReportSuccessfulLogin() async throws {
        let (defaults, suite) = try defaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault(), response = try Self.response()
        vault.rejectWrites = true
        let service = ChatGPTLoginService(defaults: defaults, store: vault.store, authorize: Self.authorize,
            exchange: { _ in response }, verify: { _, _, client, _ in Self.identity(client) }, lease: { _ in NSObject() })
        await #expect(throws: ChatGPTLoginService.Failure.storage) { try await service.signIn() }
        #expect(vault.records.isEmpty)
    }
}
