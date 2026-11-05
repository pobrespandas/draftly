import Foundation
import CryptoKit
import Security

enum ChatGPTAuthorizationError: Error, Equatable {
    case invalidCallback
    case denied
    case incompleteRegistration
    case randomGenerationFailed
}

/// One pending authorization. Its secrets must not enter logs or preferences.
struct ChatGPTAuthorization {
    static let resource = "https://api.openai.com/v1"
    static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    let redirectURI: URL
    let state: String
    let nonce: String
    let verifier: String
    let clientID: String?
    let hostID: String

    init(port: UInt16, hostID: String, clientID: String? = nil) throws {
        guard port > 0, !hostID.isEmpty,
              clientID == nil || (clientID?.hasPrefix("oaiapp_") == true && clientID != "oaiapp_") else {
            throw ChatGPTAuthorizationError.incompleteRegistration
        }
        self.redirectURI = URL(string: "http://127.0.0.1:\(port)/auth/callback")!
        self.hostID = hostID
        self.clientID = clientID
        self.state = try Self.randomValue()
        self.nonce = try Self.randomValue()
        self.verifier = try Self.randomValue()
    }

    var authorizationURL: URL {
        var components = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        var values = [
            URLQueryItem(name: "client_id", value: clientID ?? "dynamic_agent_client"),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "resource", value: Self.resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))))
        ]
        if clientID == nil { values.append(URLQueryItem(name: "agent_name_hint", value: "Draftly")) }
        components.queryItems = values
        return components.url!
    }

    struct Code: Equatable {
        let value: String
        let clientID: String
    }

    func validateCallback(_ url: URL) throws -> Code {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "http", components.host == "127.0.0.1",
              components.port == redirectURI.port, components.path == redirectURI.path,
              components.user == nil, components.password == nil, components.fragment == nil else {
            throw ChatGPTAuthorizationError.invalidCallback
        }
        let items = components.queryItems ?? []
        // Reject ambiguous security parameters before any code exchange.
        for key in ["state", "code", "client_id", "error"] {
            guard items.filter({ $0.name == key }).count <= 1 else {
                throw ChatGPTAuthorizationError.invalidCallback
            }
        }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == state else { throw ChatGPTAuthorizationError.invalidCallback }
        if value("error") != nil { throw ChatGPTAuthorizationError.denied }
        guard let code = value("code"), !code.isEmpty else { throw ChatGPTAuthorizationError.invalidCallback }
        let issued = value("client_id") ?? clientID
        guard let issued, issued.hasPrefix("oaiapp_"), issued != "oaiapp_",
              clientID == nil || clientID == issued else {
            throw ChatGPTAuthorizationError.incompleteRegistration
        }
        return Code(value: code, clientID: issued)
    }

    func exchangeRequest(for code: Code) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: code.clientID), URLQueryItem(name: "code", value: code.value),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "resource", value: Self.resource)]
        // A literal plus must not become a space in form decoding.
        request.httpBody = Data((body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    private static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ChatGPTAuthorizationError.randomGenerationFailed
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
