import Foundation
import Testing
@testable import Draftly

@Suite("MCP session renewal") @MainActor
struct MCPConnectionSessionTests {
    final class TestLease {}
    func replacement(_ old: MCPConnectionCredentials, scopes: Set<String>? = nil) -> MCPConnectionCredentials {
        .init(connectionID: old.connectionID, endpoint: old.endpoint, authorizationServer: old.authorizationServer,
              clientID: old.clientID, accessToken: "renewed-access", refreshToken: "renewed-refresh",
              expiresAt: Date().addingTimeInterval(3600), scopes: scopes ?? old.scopes)
    }

    @Test func concurrentRequestsShareRenewalAndCheckReturnedScopes() async throws {
        let vault = MCPConnectionCredentialTests.Vault()
        let store = MCPConnectionCredentialStore(backend: vault.backend)
        let old = MCPConnectionCredentialTests().record()
        try store.write(old)
        var calls = 0
        var continuation: CheckedContinuation<MCPConnectionCredentials, Error>?
        let owner = MCPConnectionSession(store: store, renew: { _ in
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }, lease: { _ in TestLease() })
        let first = Task { try await owner.accessToken(old.connectionID, endpoint: old.endpoint, requiredScopes: ["read"]) }
        let second = Task { try await owner.accessToken(old.connectionID, endpoint: old.endpoint, requiredScopes: ["write"]) }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        #expect(calls == 1)
        try #require(continuation).resume(returning: replacement(old))
        #expect(try await first.value == "renewed-access")
        do { _ = try await second.value; Issue.record("Missing scope was accepted") }
        catch { #expect(error as? MCPConnectionSession.Failure == .permissionDenied) }
        #expect(try store.read(old.connectionID, endpoint: old.endpoint)?.refreshUncertain == false)
    }

    @Test func disconnectDuringRenewalLeavesNoCredentialsOrUsableResult() async throws {
        let vault = MCPConnectionCredentialTests.Vault()
        let store = MCPConnectionCredentialStore(backend: vault.backend)
        let old = MCPConnectionCredentialTests().record()
        try store.write(old)
        var continuation: CheckedContinuation<MCPConnectionCredentials, Error>?
        let owner = MCPConnectionSession(store: store, renew: { _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, lease: { _ in TestLease() })
        let response = Task { try await owner.accessToken(old.connectionID, endpoint: old.endpoint, requiredScopes: ["read"]) }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let disconnect = Task { try await owner.disconnect(old.connectionID) }
        await Task.yield()
        try #require(continuation).resume(returning: replacement(old))
        try await disconnect.value
        do { _ = try await response.value; Issue.record("Disconnected token was returned") }
        catch { #expect(error as? MCPConnectionSession.Failure == .disconnected) }
        #expect(try store.read(old.connectionID, endpoint: old.endpoint) == nil)
    }

    @Test func failedRenewalRequiresSignInAcrossOwnersAndLateCompletionCannotRestoreDeletedSession() async throws {
        let vault = MCPConnectionCredentialTests.Vault()
        let store = MCPConnectionCredentialStore(backend: vault.backend)
        let old = MCPConnectionCredentialTests().record()
        try store.write(old)
        var calls = 0
        let owner = MCPConnectionSession(store: store, renew: { _ in
            calls += 1; throw URLError(.networkConnectionLost)
        }, lease: { _ in TestLease() })
        do { _ = try await owner.accessToken(old.connectionID, endpoint: old.endpoint, requiredScopes: []) }
        catch { #expect(error is URLError) }
        let restored = MCPConnectionSession(store: store, renew: { _ in calls += 1; return old }, lease: { _ in TestLease() })
        do { _ = try await restored.accessToken(old.connectionID, endpoint: old.endpoint, requiredScopes: []) }
        catch { #expect(error as? MCPConnectionSession.Failure == .signInRequired) }
        #expect(calls == 1)
        let expected = try #require(try store.read(old.connectionID, endpoint: old.endpoint))
        try store.remove(old.connectionID)
        #expect(throws: MCPConnectionCredentialStore.Failure.staleSession) {
            try store.completeRefresh(expected: expected, replacement: replacement(old))
        }
        #expect(try store.read(old.connectionID, endpoint: old.endpoint) == nil)
    }
}
