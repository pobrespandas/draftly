import Foundation
import Testing
@testable import Draftly

@Suite("MCP login service") @MainActor
struct MCPLoginServiceTests {
    final class Lease {}
    func server(token: String = "{\"access_token\":\"neutral-access\",\"token_type\":\"Bearer\",\"expires_in\":3600,\"refresh_token\":\"neutral-refresh\",\"scope\":\"read\"}") -> MCPAuthorizationDiscoveryTests.Server {
        let fixture = MCPAuthorizationDiscoveryTests()
        return .init([
            "https://mcp.example.test/.well-known/oauth-protected-resource/tools": fixture.json(fixture.resourceDocument),
            "https://auth.example.test/.well-known/oauth-authorization-server/tenant": fixture.json(fixture.serverDocument),
            "https://auth.example.test/token": fixture.json(token)
        ])
    }
    func callback(_ browser: URL, redirect: URL) -> URL {
        let state = URLComponents(url: browser, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        var parts = URLComponents(url: redirect, resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "state", value: state), .init(name: "code", value: "neutral-code")]
        return parts.url!
    }
    let endpoint = URL(string: "https://mcp.example.test/tools")!
    let redirect = URL(string: "draftly://mcp/oauth")!

    @Test func completeFlowSavesOnlyGrantedScopesAndRestoresFromKeychain() async throws {
        let transport = server(), vault = MCPConnectionCredentialTests.Vault()
        let store = MCPConnectionCredentialStore(backend: vault.backend)
        let login = MCPLoginService(store: store,
            discovery: .init(fetch: { await transport.fetch($0) }), exchange: { await transport.fetch($0) },
            lease: { _ in Lease() }, browser: { url, redirect in callback(url, redirect: redirect) })
        let id = UUID()
        let record = try await login.signIn(connectionID: id, endpoint: endpoint, clientID: "neutral-client",
            redirectURI: redirect, scopes: ["read", "write"])
        #expect(record.scopes == ["read"])
        #expect(try MCPConnectionCredentialStore(backend: vault.backend).read(id, endpoint: endpoint) == record)
        let requests = await transport.requests
        #expect(requests.count == 3)
        let token = try #require(requests.last)
        #expect(token.httpMethod == "POST")
        #expect(String(decoding: try #require(token.httpBody), as: UTF8.self).contains("code_verifier="))
    }

    @Test func cancelledBrowserNeverExchangesOrSavesTokens() async throws {
        let transport = server(), vault = MCPConnectionCredentialTests.Vault()
        let login = MCPLoginService(store: .init(backend: vault.backend),
            discovery: .init(fetch: { await transport.fetch($0) }), exchange: { await transport.fetch($0) },
            lease: { _ in Lease() }, browser: { _, _ in throw CancellationError() })
        do {
            _ = try await login.signIn(connectionID: UUID(), endpoint: endpoint, clientID: "neutral-client",
                redirectURI: redirect, scopes: ["read"])
            Issue.record("Cancelled login succeeded")
        } catch { #expect(error is CancellationError) }
        #expect(await transport.requests.count == 2)
        #expect(vault.records.isEmpty)
    }

    actor DelayedExchange {
        var continuation: CheckedContinuation<ChatGPTHTTP.Response, Never>?
        var started: Bool { continuation != nil }
        func wait() async -> ChatGPTHTTP.Response {
            await withCheckedContinuation { continuation = $0 }
        }
        func finish() {
            continuation?.resume(returning: .init(status: 200,
                data: Data("{\"access_token\":\"late-token\",\"token_type\":\"Bearer\"}".utf8)))
            continuation = nil
        }
    }

    @Test func cancellationRejectsAnExchangeThatIgnoresCancellation() async throws {
        let transport = server(), delayed = DelayedExchange(), vault = MCPConnectionCredentialTests.Vault()
        let login = MCPLoginService(store: .init(backend: vault.backend),
            discovery: .init(fetch: { await transport.fetch($0) }), exchange: { _ in await delayed.wait() },
            lease: { _ in Lease() }, browser: { url, redirect in callback(url, redirect: redirect) })
        let work = Task {
            try await login.signIn(connectionID: UUID(), endpoint: endpoint, clientID: "neutral-client",
                redirectURI: redirect, scopes: ["read"])
        }
        for _ in 0..<100 {
            if await delayed.started { break }
            await Task.yield()
        }
        try #require(await delayed.started)
        work.cancel()
        await delayed.finish()
        do { _ = try await work.value; Issue.record("Cancelled exchange saved a session") }
        catch { #expect(error is CancellationError) }
        #expect(vault.records.isEmpty)
    }

    @Test func changedSessionRejectsLateLoginResult() async throws {
        let transport = server(), vault = MCPConnectionCredentialTests.Vault()
        let store = MCPConnectionCredentialStore(backend: vault.backend), id = UUID()
        let newer = MCPConnectionCredentialTests().record(id: id)
        let login = MCPLoginService(store: store,
            discovery: .init(fetch: { await transport.fetch($0) }), exchange: { await transport.fetch($0) },
            lease: { _ in Lease() }, browser: { url, redirect in
                try store.write(newer)
                return callback(url, redirect: redirect)
            })
        do {
            _ = try await login.signIn(connectionID: id, endpoint: endpoint, clientID: "neutral-client",
                redirectURI: redirect, scopes: ["read"])
            Issue.record("Late login replaced another session")
        } catch { #expect(error as? MCPLoginService.Failure == .sessionChanged) }
        #expect(try store.read(id, endpoint: endpoint) == newer)
    }
}
