import Foundation
import Security
import Testing
@testable import Draftly

@Suite("MCP connection credentials") @MainActor
struct MCPConnectionCredentialTests {
    final class Vault {
        var records: [String: Data] = [:]
        var failWrites = false
        var additions: [[String: Any]] = []
        func key(_ query: [String: Any]) -> String {
            "\(query[kSecAttrService as String]!)|\(query[kSecAttrAccount as String]!)"
        }
        var backend: DeviceCredentialStore.Backend {
            .init(copy: { query in
                guard let data = self.records[self.key(query)] else { return (errSecItemNotFound, nil) }
                return (errSecSuccess, data)
            }, update: { query, attributes in
                if self.failWrites { return errSecInteractionNotAllowed }
                let key = self.key(query)
                guard self.records[key] != nil else { return errSecItemNotFound }
                self.records[key] = attributes[kSecValueData as String] as? Data
                return errSecSuccess
            }, add: { query in
                if self.failWrites { return errSecInteractionNotAllowed }
                self.additions.append(query)
                self.records[self.key(query)] = query[kSecValueData as String] as? Data
                return errSecSuccess
            }, remove: { query in
                self.records.removeValue(forKey: self.key(query))
                return errSecSuccess
            })
        }
    }

    func record(id: UUID = UUID(), endpoint: String = "https://mcp.example.test/tools") -> MCPConnectionCredentials {
        .init(connectionID: id, endpoint: URL(string: endpoint)!,
              authorizationServer: URL(string: "https://auth.example.test")!, clientID: "neutral-client",
              accessToken: "neutral-access", refreshToken: "neutral-refresh", expiresAt: Date(), scopes: ["read"])
    }

    @Test func credentialsAreBoundToConnectionEndpointAndAppIdentity() throws {
        let vault = Vault(), credentials = record()
        let store = MCPConnectionCredentialStore(bundleID: "qa.example", backend: vault.backend)
        try store.write(credentials)
        #expect(try store.read(credentials.connectionID, endpoint: credentials.endpoint) == credentials)
        #expect(throws: MCPConnectionCredentialStore.Failure.endpointMismatch) {
            try store.read(credentials.connectionID, endpoint: URL(string: "https://other.example.test")!)
        }
        #expect(throws: MCPConnectionCredentialStore.Failure.endpointMismatch) {
            try store.write(record(id: credentials.connectionID, endpoint: "https://other.example.test"))
        }
        #expect(try ChatGPTCredentialStore(bundleID: "qa.example", backend: vault.backend).read(credentials.connectionID) == nil)
        #expect(try MCPConnectionCredentialStore(bundleID: "production.example", backend: vault.backend)
            .read(credentials.connectionID, endpoint: credentials.endpoint) == nil)
        #expect(vault.additions.allSatisfy { $0[kSecAttrSynchronizable as String] as? Bool == false })
        #expect(vault.additions.allSatisfy {
            $0[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        })
    }

    @Test func uncertainRefreshSurvivesRecreationAndFailedReplacement() throws {
        let vault = Vault(), credentials = record()
        let store = MCPConnectionCredentialStore(backend: vault.backend)
        try store.write(credentials)
        _ = try store.beginRefresh(credentials.connectionID, endpoint: credentials.endpoint)
        vault.failWrites = true
        #expect(throws: DeviceCredentialStore.Failure(status: errSecInteractionNotAllowed)) { try store.write(credentials) }
        let restored = MCPConnectionCredentialStore(backend: vault.backend)
        #expect(try restored.read(credentials.connectionID, endpoint: credentials.endpoint)?.refreshUncertain == true)
        #expect(throws: MCPConnectionCredentialStore.Failure.refreshUncertain) {
            try restored.beginRefresh(credentials.connectionID, endpoint: credentials.endpoint)
        }
        try restored.remove(credentials.connectionID)
        #expect(try restored.read(credentials.connectionID, endpoint: credentials.endpoint) == nil)
    }

    @Test func failedUncertaintyWritePreventsRefreshAndInsecureEndpointsAreRejected() throws {
        let vault = Vault(), credentials = record()
        let store = MCPConnectionCredentialStore(backend: vault.backend)
        try store.write(credentials)
        vault.failWrites = true
        #expect(throws: DeviceCredentialStore.Failure(status: errSecInteractionNotAllowed)) {
            try store.beginRefresh(credentials.connectionID, endpoint: credentials.endpoint)
        }
        #expect(try store.read(credentials.connectionID, endpoint: credentials.endpoint)?.refreshUncertain == false)
        for endpoint in ["http://mcp.example.test", "https://user:password@mcp.example.test", "https://mcp.example.test/#fragment"] {
            #expect(throws: MCPConnectionCredentialStore.Failure.invalidRecord) { try store.write(record(endpoint: endpoint)) }
        }
    }
}
