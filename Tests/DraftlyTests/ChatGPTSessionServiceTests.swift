import Foundation
import Testing
@testable import Draftly

@Suite("ChatGPT renewable sessions") @MainActor
struct ChatGPTSessionServiceTests {
    private actor Gate {
        var waiter: CheckedContinuation<Void, Never>?
        var entered: CheckedContinuation<Void, Never>?
        var didEnter = false
        func hold() async {
            didEnter = true; entered?.resume(); entered = nil
            await withCheckedContinuation { waiter = $0 }
        }
        func wait() async { if !didEnter { await withCheckedContinuation { entered = $0 } } }
        func release() { waiter?.resume(); waiter = nil }
    }

    private actor Server {
        let gate: Gate?
        let fail: Bool
        let revokeStatus: Int
        let scope: String?
        var requests: [URLRequest] = []
        init(gate: Gate? = nil, fail: Bool = false, revokeStatus: Int = 200, scope: String? = nil) {
            self.gate = gate; self.fail = fail; self.revokeStatus = revokeStatus; self.scope = scope
        }
        func exchange(_ request: URLRequest) async throws -> ChatGPTHTTP.Response {
            requests.append(request)
            if request.url?.path == "/api/accounts/oauth/token" {
                await gate?.hold()
                if fail { throw URLError(.networkConnectionLost) }
                var values: [String: Any] = ["access_token": "neutral-new-access", "refresh_token": "neutral-rotated-refresh",
                    "expires_in": 3600, "token_type": "Bearer"]
                if let scope { values["scope"] = scope }
                return .init(status: 200, data: try JSONSerialization.data(withJSONObject: values))
            }
            if request.url?.path == "/.well-known/openid-configuration" {
                return .init(status: 200, data: try JSONSerialization.data(withJSONObject: [
                    "issuer": "https://auth.openai.com", "revocation_endpoint": "https://auth.openai.com/api/accounts/oauth/revoke"]))
            }
            return .init(status: revokeStatus, data: Data())
        }
    }

    @MainActor private final class Fixture {
        let defaults: UserDefaults
        let suite = "ChatGPTSessionServiceTests." + UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = ChatGPTLoginServiceTests.Vault()
        let login: ChatGPTLoginService
        let record: ChatGPTAccountRecord
        let instant = Date(timeIntervalSince1970: 1700000000)
        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            login = ChatGPTLoginService(defaults: defaults, store: vault.store, lease: { _ in NSObject() })
            record = ChatGPTAccountRecord(id: UUID(), identity: ChatGPTIdentity(issuer: "https://auth.openai.com",
                clientID: "oaiapp_neutral", subject: "neutral-subject", email: nil, name: nil), hostID: login.hostID,
                tokens: ChatGPTTokens(accessToken: "neutral-old-access", refreshToken: "neutral-old-refresh", idToken: "neutral-id",
                    scopes: ["resource.invoke", "chatgpt.tokens.use.direct"], expiresAt: instant.addingTimeInterval(-10)))
            try login.save(record)
        }
        func service(_ server: Server) -> ChatGPTSessionService {
            let instant = instant, root = root
            return ChatGPTSessionService(login: login, exchange: { try await server.exchange($0) },
                lease: { try ChatGPTSessionLease(accountID: $0, directory: root) }, now: { instant })
        }
        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test func concurrentReadersShareRotationAndPersistWholeTokenSet() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let gate = Gate(), server = Server(gate: gate), service = fixture.service(server)
        let first = Task { try await service.accessToken(for: fixture.record.id) }
        await gate.wait()
        #expect(try fixture.login.read(fixture.record.id)?.refreshUncertain == true)
        let second = Task { try await service.accessToken(for: fixture.record.id) }
        await gate.release()
        #expect(try await first.value == "neutral-new-access")
        #expect(try await second.value == "neutral-new-access")
        let stored = try #require(try fixture.login.read(fixture.record.id))
        #expect(stored.tokens?.refreshToken == "neutral-rotated-refresh")
        #expect(stored.tokens?.scopes == fixture.record.tokens?.scopes)
        #expect(stored.refreshUncertain == nil)
        #expect(await server.requests.count == 1)
    }

    @Test func lostResponsePersistsUncertaintyAcrossSessionOwnerRestart() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let server = Server(fail: true), service = fixture.service(server)
        await #expect(throws: URLError.self) { try await service.accessToken(for: fixture.record.id) }
        let restarted = fixture.service(server)
        await #expect(throws: ChatGPTSessionService.Failure.self) { try await restarted.accessToken(for: fixture.record.id) }
        #expect(await server.requests.count == 1)
        #expect(try fixture.login.read(fixture.record.id)?.tokens?.accessToken == "neutral-old-access")
        #expect(try fixture.login.read(fixture.record.id)?.refreshUncertain == true)
    }

    @Test func signOutWaitsForRotationAndRevokesNewestToken() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let gate = Gate(), server = Server(gate: gate), service = fixture.service(server)
        let response = Task { try await service.accessToken(for: fixture.record.id) }
        await gate.wait()
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let logout = Task {
            continuation.yield(); continuation.finish()
            return try await service.signOut(fixture.record.id)
        }
        for await _ in started { break }
        await gate.release()
        _ = try? await response.value
        #expect(try await logout.value)
        let stored = try #require(try fixture.login.read(fixture.record.id))
        #expect(stored.tokens == nil && stored.identity == fixture.record.identity)
        let calls = await server.requests
        #expect(calls.count == 3)
        let body = String(decoding: try #require(calls.last?.httpBody), as: UTF8.self)
        #expect(body.contains("token=neutral-rotated-refresh"))
        await #expect(throws: ChatGPTSessionService.Failure.self) { try await service.accessToken(for: fixture.record.id) }
    }

    @Test func revocationFailureStillClearsLocalTokensAndKeepsRegistration() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let service = fixture.service(Server(revokeStatus: 503))
        #expect(try await service.signOut(fixture.record.id) == false)
        let stored = try #require(try fixture.login.read(fixture.record.id))
        #expect(stored.tokens == nil && stored.identity.clientID == "oaiapp_neutral")
    }

    @Test func changedGrantedScopesCannotKeepOldInferencePermission() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let service = fixture.service(Server(scope: "openid profile"))
        await #expect(throws: ChatGPTSessionService.Failure.self) { try await service.accessToken(for: fixture.record.id) }
        #expect(try fixture.login.read(fixture.record.id)?.tokens?.allowsInference == false)
    }

    @Test func failedRotatedCredentialWriteCannotRetryOldToken() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let gate = Gate(), server = Server(gate: gate), service = fixture.service(server)
        let response = Task { try await service.accessToken(for: fixture.record.id) }
        await gate.wait()
        fixture.vault.rejectWrites = true
        await gate.release()
        await #expect(throws: ChatGPTSessionService.Failure.self) { try await response.value }
        fixture.vault.rejectWrites = false
        await #expect(throws: ChatGPTSessionService.Failure.self) {
            try await fixture.service(server).accessToken(for: fixture.record.id)
        }
        #expect(await server.requests.count == 1)
    }

    @Test func accountLeaseExcludesOtherOwnersAndRejectsSymlinks() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        var first: ChatGPTSessionLease? = try ChatGPTSessionLease(accountID: fixture.record.id, directory: fixture.root)
        #expect(first != nil)
        #expect(throws: ChatGPTSessionLease.Failure.self) {
            try ChatGPTSessionLease(accountID: fixture.record.id, directory: fixture.root)
        }
        first = nil
        let second = try ChatGPTSessionLease(accountID: fixture.record.id, directory: fixture.root)
        withExtendedLifetime(second) {}
        let another = UUID(), link = fixture.root.appendingPathComponent(another.uuidString.lowercased() + ".lock")
        let target = fixture.root.appendingPathComponent("neutral-target")
        try Data().write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: ChatGPTSessionLease.Failure.self) { try ChatGPTSessionLease(accountID: another, directory: fixture.root) }
    }
}
