import Foundation
import Testing
@testable import Draftly

@Suite("MCP authorization discovery")
struct MCPAuthorizationDiscoveryTests {
    actor Server {
        var requests: [URLRequest] = []
        let responses: [String: ChatGPTHTTP.Response]
        init(_ responses: [String: ChatGPTHTTP.Response]) { self.responses = responses }
        func fetch(_ request: URLRequest) -> ChatGPTHTTP.Response {
            requests.append(request)
            return responses[request.url!.absoluteString] ?? .init(status: 404, data: Data())
        }
    }
    func json(_ value: String) -> ChatGPTHTTP.Response { .init(status: 200, data: Data(value.utf8)) }
    let resource = "https://mcp.example.test/tools"
    let issuer = "https://auth.example.test/tenant"
    var resourceDocument: String {
        "{\"resource\":\"\(resource)\",\"authorization_servers\":[\"\(issuer)\"],\"scopes_supported\":[\"read\"]}"
    }
    var serverDocument: String {
        "{\"issuer\":\"\(issuer)\",\"authorization_endpoint\":\"https://auth.example.test/authorize\",\"token_endpoint\":\"https://auth.example.test/token\",\"code_challenge_methods_supported\":[\"S256\"]}"
    }

    @Test func discoversPathMetadataThenOIDCFallbackWithoutCredentials() async throws {
        let server = Server([
            "https://mcp.example.test/.well-known/oauth-protected-resource/tools": json(resourceDocument),
            "https://auth.example.test/.well-known/openid-configuration/tenant": json(serverDocument)
        ])
        let discovered = try await MCPAuthorizationDiscovery(fetch: { await server.fetch($0) })
            .discover(endpoint: URL(string: resource + "?transport=stream")!)
        #expect(discovered.resource.absoluteString == resource)
        #expect(discovered.issuer.absoluteString == issuer)
        #expect(discovered.scopesSupported == ["read"])
        let requests = await server.requests
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.httpBody == nil })
    }

    @Test func resourceMismatchStopsBeforeContactingAuthorizationServer() async throws {
        let server = Server([
            "https://mcp.example.test/.well-known/oauth-protected-resource/tools":
                json(resourceDocument.replacingOccurrences(of: resource, with: "https://other.example.test/tools"))
        ])
        do {
            _ = try await MCPAuthorizationDiscovery(fetch: { await server.fetch($0) }).discover(endpoint: URL(string: resource)!)
            Issue.record("Accepted metadata for another resource")
        } catch { #expect(error as? MCPAuthorizationDiscovery.Failure == .invalidMetadata) }
        #expect(await server.requests.count == 1)
    }

    @Test func rejectsIssuerMismatchAndMissingPKCE() async throws {
        for document in [serverDocument.replacingOccurrences(of: issuer, with: "https://other.example.test"),
                         serverDocument.replacingOccurrences(of: "S256", with: "plain")] {
            let server = Server([
                "https://mcp.example.test/.well-known/oauth-protected-resource/tools": json(resourceDocument),
                "https://auth.example.test/.well-known/oauth-authorization-server/tenant": json(document)
            ])
            do {
                _ = try await MCPAuthorizationDiscovery(fetch: { await server.fetch($0) }).discover(endpoint: URL(string: resource)!)
                Issue.record("Accepted invalid authorization metadata")
            } catch {
                let failure = error as? MCPAuthorizationDiscovery.Failure
                #expect(failure == .invalidMetadata || failure == .unsupportedPKCE)
            }
        }
    }

    @Test func multipleIssuersRequireAnExplicitAdvertisedChoice() async throws {
        let multiple = resourceDocument.replacingOccurrences(of: "[\"\(issuer)\"]",
            with: "[\"\(issuer)\",\"https://second.example.test\"]")
        let server = Server([
            "https://mcp.example.test/.well-known/oauth-protected-resource/tools": json(multiple),
            "https://auth.example.test/.well-known/oauth-authorization-server/tenant": json(serverDocument)
        ])
        let discovery = MCPAuthorizationDiscovery(fetch: { await server.fetch($0) })
        do {
            _ = try await discovery.discover(endpoint: URL(string: resource)!)
            Issue.record("Selected an issuer without a choice")
        } catch { #expect(error as? MCPAuthorizationDiscovery.Failure == .chooseAuthorizationServer) }
        let selected = try await discovery.discover(endpoint: URL(string: resource)!, issuer: URL(string: issuer)!)
        #expect(selected.issuer.absoluteString == issuer)
        do {
            _ = try await discovery.discover(endpoint: URL(string: resource)!, issuer: URL(string: "https://unlisted.example.test")!)
            Issue.record("Accepted an unlisted issuer")
        } catch { #expect(error as? MCPAuthorizationDiscovery.Failure == .invalidMetadata) }
    }
}
