import CryptoKit
import Foundation
import Security

/// One browser request. Keep its verifier and state only in memory.
struct MCPAuthorizationRequest {
    enum Failure: Error { case invalidConfiguration, randomGeneration, invalidCallback, denied }
    let server: MCPAuthorizationServer
    let clientID: String
    let redirectURI: URL
    let scopes: Set<String>
    let state: String
    let verifier: String

    init(server: MCPAuthorizationServer, clientID: String, redirectURI: URL, scopes: Set<String>) throws {
        guard !clientID.isEmpty, redirectURI.scheme?.isEmpty == false,
              redirectURI.query == nil, redirectURI.fragment == nil,
              redirectURI.user == nil, redirectURI.password == nil,
              scopes.allSatisfy({ !$0.isEmpty && !$0.contains(where: { $0.isWhitespace }) }) else {
            throw Failure.invalidConfiguration
        }
        self.server = server; self.clientID = clientID; self.redirectURI = redirectURI; self.scopes = scopes
        state = try Self.random(); verifier = try Self.random()
    }

    func browserURL() throws -> URL {
        guard var components = URLComponents(url: server.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidConfiguration
        }
        let reserved = Set(["client_id", "response_type", "redirect_uri", "scope", "resource", "state", "code_challenge", "code_challenge_method"])
        let original = components.queryItems ?? []
        guard !original.contains(where: { reserved.contains($0.name) }) else { throw Failure.invalidConfiguration }
        let challenge = Self.base64(Data(SHA256.hash(data: Data(verifier.utf8))))
        components.queryItems = original + [
            .init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI.absoluteString),
            .init(name: "scope", value: scopes.sorted().joined(separator: " ")),
            .init(name: "resource", value: server.resource.absoluteString), .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")
        ]
        guard let result = components.url else { throw Failure.invalidConfiguration }
        return result
    }

    func code(from callback: URL) throws -> String {
        guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.scheme == redirectURI.scheme, parts.host == redirectURI.host,
              parts.port == redirectURI.port, parts.percentEncodedPath == URLComponents(url: redirectURI, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              parts.user == nil, parts.password == nil, parts.fragment == nil else { throw Failure.invalidCallback }
        let items = parts.queryItems ?? []
        for name in ["state", "code", "error", "iss"] {
            guard items.filter({ $0.name == name }).count <= 1 else { throw Failure.invalidCallback }
        }
        guard items.first(where: { $0.name == "state" })?.value == state else { throw Failure.invalidCallback }
        if let issuer = items.first(where: { $0.name == "iss" })?.value,
           issuer != server.issuer.absoluteString { throw Failure.invalidCallback }
        if items.contains(where: { $0.name == "error" }) { throw Failure.denied }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw Failure.invalidCallback }
        return code
    }

    @MainActor func tokenRequest(code: String) -> URLRequest {
        ChatGPTSessionService.form(url: server.tokenEndpoint, values: [
            "grant_type": "authorization_code", "client_id": clientID, "code": code,
            "redirect_uri": redirectURI.absoluteString, "code_verifier": verifier,
            "resource": server.resource.absoluteString
        ])
    }

    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.randomGeneration }
        return base64(Data(bytes))
    }

    private static func base64(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
