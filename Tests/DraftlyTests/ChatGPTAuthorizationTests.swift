import Foundation
import CryptoKit
import Testing
@testable import Draftly

@Suite("Direct ChatGPT authorization")
struct ChatGPTAuthorizationTests {
    private func callback(_ attempt: ChatGPTAuthorization, _ values: [URLQueryItem]) -> URL {
        var url = URLComponents(url: attempt.redirectURI, resolvingAgainstBaseURL: false)!
        url.queryItems = values
        return url.url!
    }

    @Test func freshSecretsAndPKCE() throws {
        let attempt = try ChatGPTAuthorization(port: 1455, hostID: "urn:uuid:test")
        let other = try ChatGPTAuthorization(port: 1455, hostID: "urn:uuid:test")
        #expect(attempt.state != other.state && attempt.nonce != other.nonce && attempt.verifier != other.verifier)
        #expect(Set([attempt.state, attempt.nonce, attempt.verifier]).count == 3)
        #expect(attempt.verifier.count == 43)
        let query = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        let challenge = Data(SHA256.hash(data: Data(attempt.verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(value("code_challenge") == challenge)
        #expect(value("client_id") == "dynamic_agent_client")
        #expect(value("agent_name_hint") == "Draftly")
        #expect(value("redirect_uri") == attempt.redirectURI.absoluteString)
    }

    @Test func firstRegistrationRequiresIssuedClient() throws {
        let attempt = try ChatGPTAuthorization(port: 32123, hostID: "host")
        let items = [URLQueryItem(name: "state", value: attempt.state), URLQueryItem(name: "code", value: "a+b&c")]
        #expect(throws: ChatGPTAuthorizationError.incompleteRegistration) { try attempt.validateCallback(callback(attempt, items)) }
        let code = try attempt.validateCallback(callback(attempt, items + [URLQueryItem(name: "client_id", value: "oaiapp_test")]))
        let request = attempt.exchangeRequest(for: code)
        let body = String(data: request.httpBody!, encoding: .utf8)!
        #expect(body.contains("code=a%2Bb%26c"))
        #expect(!body.contains("dynamic_agent_client"))
        #expect(request.url?.host == "auth.openai.com")
    }

    @Test func returningRegistrationCannotChangeClient() throws {
        let attempt = try ChatGPTAuthorization(port: 1455, hostID: "host", clientID: "oaiapp_saved")
        let items = [URLQueryItem(name: "state", value: attempt.state), URLQueryItem(name: "code", value: "code")]
        #expect(try attempt.validateCallback(callback(attempt, items)).clientID == "oaiapp_saved")
        #expect(throws: ChatGPTAuthorizationError.incompleteRegistration) {
            try attempt.validateCallback(callback(attempt, items + [URLQueryItem(name: "client_id", value: "oaiapp_other")]))
        }
        #expect(!attempt.authorizationURL.absoluteString.contains("agent_name_hint"))
    }

    @Test func rejectsWrongStateDuplicateParametersAndCallbackOrigin() throws {
        let attempt = try ChatGPTAuthorization(port: 1455, hostID: "host")
        let valid = [URLQueryItem(name: "state", value: attempt.state), URLQueryItem(name: "code", value: "code"),
                     URLQueryItem(name: "client_id", value: "oaiapp_test")]
        for key in ["state", "code", "client_id", "error"] {
            #expect(throws: (any Error).self) {
                try attempt.validateCallback(callback(attempt, valid + [URLQueryItem(name: key, value: "bad"), URLQueryItem(name: key, value: "bad")]))
            }
        }
        let original = callback(attempt, valid).absoluteString
        for changed in [original.replacingOccurrences(of: "127.0.0.1", with: "localhost"),
                        original.replacingOccurrences(of: ":1455/", with: ":1456/"),
                        original.replacingOccurrences(of: "/auth/callback", with: "/callback"),
                        original.replacingOccurrences(of: attempt.state, with: "wrong")] {
            #expect(throws: ChatGPTAuthorizationError.invalidCallback) { try attempt.validateCallback(URL(string: changed)!) }
        }
        let denied = [URLQueryItem(name: "state", value: attempt.state), URLQueryItem(name: "error", value: "access_denied")]
        #expect(throws: ChatGPTAuthorizationError.denied) { try attempt.validateCallback(callback(attempt, denied)) }
        #expect(throws: ChatGPTAuthorizationError.invalidCallback) {
            try attempt.validateCallback(callback(attempt, [.init(name: "state", value: "wrong"), .init(name: "error", value: "access_denied")]))
        }
    }
}
