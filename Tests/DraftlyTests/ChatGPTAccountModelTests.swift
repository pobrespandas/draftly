import Foundation
import Testing
@testable import Draftly

@Suite("Direct ChatGPT account controls") @MainActor
struct ChatGPTAccountModelTests {
    private func wait(_ model: ChatGPTAccountModel) async throws {
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isBusy, clock.now < deadline { await Task.yield() }
        #expect(!model.isBusy)
    }

    @Test func loginPersistsOnlyRegistrationIDsOutsideKeychainAndRestoresSelection() async throws {
        let suite = "ChatGPTAccountModelTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = ChatGPTLoginServiceTests.Vault()
        let identity = ChatGPTIdentity(issuer: "https://auth.openai.com", clientID: "oaiapp_neutral", subject: "neutral-subject", email: nil, name: nil)
        let data = try JSONSerialization.data(withJSONObject: ["access_token": "neutral-access", "refresh_token": "neutral-refresh",
            "id_token": "neutral-id", "token_type": "Bearer", "expires_in": 3600, "scope": "resource.invoke chatgpt.tokens.use.direct"])
        let login = ChatGPTLoginService(defaults: defaults, store: vault.store, authorize: { host, client in
            let attempt = try ChatGPTAuthorization(port: 1455, hostID: host, clientID: client)
            return (attempt, .init(value: "neutral-code", clientID: "oaiapp_neutral"))
        }, exchange: { _ in .init(status: 200, data: data) }, verify: { _, _, _, _ in identity }, lease: { _ in NSObject() })
        let model = ChatGPTAccountModel(defaults: defaults, login: login)
        model.signIn()
        try await wait(model)
        #expect(model.isSignedIn && model.accounts.count == 1)
        let id = try #require(model.selectedID)
        let restored = ChatGPTAccountModel(defaults: defaults, login: login)
        restored.refresh()
        #expect(restored.selectedID == id && restored.isSignedIn)
        let preferences = String(describing: defaults.persistentDomain(forName: suite))
        #expect(!preferences.contains("neutral-access") && !preferences.contains("neutral-refresh") && !preferences.contains("neutral-id"))
    }

    @Test func failedAdditionalLoginKeepsSelectedAccountAndItsCredentials() async throws {
        let suite = "ChatGPTAccountModelTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = ChatGPTLoginServiceTests.Vault()
        let login = ChatGPTLoginService(defaults: defaults, store: vault.store, authorize: { _, _ in throw ChatGPTAuthorizationError.denied },
                                       lease: { _ in NSObject() })
        let identity = ChatGPTIdentity(issuer: "https://auth.openai.com", clientID: "oaiapp_existing", subject: "neutral", email: nil, name: nil)
        let record = ChatGPTAccountRecord(id: UUID(), identity: identity, hostID: login.hostID,
            tokens: ChatGPTTokens(accessToken: "neutral-access", refreshToken: nil, idToken: "neutral-id",
                                 scopes: ["resource.invoke", "chatgpt.tokens.use.direct"], expiresAt: .distantFuture))
        try login.save(record)
        defaults.set([record.id.uuidString], forKey: "chatGPT.registrationIDs")
        defaults.set(record.id.uuidString, forKey: "chatGPT.selectedID")
        let model = ChatGPTAccountModel(defaults: defaults, login: login)
        model.refresh(); model.addAccount()
        try await wait(model)
        #expect(model.selectedID == record.id && model.isSignedIn)
        #expect(try login.read(record.id) == record)
        #expect(model.errorMessage != nil)
    }
}
