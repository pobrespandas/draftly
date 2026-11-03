import CryptoKit
import Foundation
import Testing
@testable import Draftly

@Suite("MCP browser authorization") @MainActor
struct MCPAuthorizationRequestTests {
    func request() throws -> MCPAuthorizationRequest {
        try .init(server: .init(resource: URL(string: "https://mcp.example.test/tools")!,
            issuer: URL(string: "https://auth.example.test")!,
            authorizationEndpoint: URL(string: "https://auth.example.test/authorize")!,
            tokenEndpoint: URL(string: "https://auth.example.test/token")!, registrationEndpoint: nil,
            scopesSupported: ["read"]), clientID: "neutral-client",
            redirectURI: URL(string: "draftly://mcp/oauth")!, scopes: ["read"])
    }
    func callback(_ request: MCPAuthorizationRequest, query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(url: request.redirectURI, resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "state", value: request.state), .init(name: "code", value: "neutral+code")] + query
        return parts.url!
    }

    @Test func uniquePKCERequestsBindResourceAndUseFormEncoding() throws {
        let first = try request(), second = try request()
        #expect(first.state != second.state && first.verifier != second.verifier)
        let url = try first.browserURL()
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "code_challenge_method" }?.value == "S256")
        let digest = Data(SHA256.hash(data: Data(first.verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        #expect(items.first { $0.name == "code_challenge" }?.value == digest)
        #expect(items.first { $0.name == "resource" }?.value == first.server.resource.absoluteString)
        let code = try first.code(from: callback(first))
        let exchange = first.tokenRequest(code: code)
        #expect(exchange.url == first.server.tokenEndpoint && exchange.httpMethod == "POST")
        #expect(String(decoding: try #require(exchange.httpBody), as: UTF8.self).contains("neutral%2Bcode"))
        #expect(exchange.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func callbacksRejectStateIssuerDestinationAndDuplicateParameters() throws {
        let value = try request()
        for url in [
            callback(value, query: [.init(name: "state", value: "forged")]),
            callback(value, query: [.init(name: "code", value: "second")]),
            callback(value, query: [.init(name: "iss", value: "https://other.example.test")]),
            URL(string: callback(value).absoluteString.replacingOccurrences(of: "/oauth?", with: "/other?"))!,
            callback(try request())
        ] {
            #expect(throws: MCPAuthorizationRequest.Failure.invalidCallback) { try value.code(from: url) }
        }
        var denied = URLComponents(url: value.redirectURI, resolvingAgainstBaseURL: false)!
        denied.queryItems = [.init(name: "state", value: value.state), .init(name: "error", value: "access_denied")]
        #expect(throws: MCPAuthorizationRequest.Failure.denied) { try value.code(from: denied.url!) }
    }
}
