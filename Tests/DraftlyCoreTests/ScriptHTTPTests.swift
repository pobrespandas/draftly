import Foundation
import Testing
@testable import DraftlyCore

@Suite("Script HTTP transport")
struct ScriptHTTPTests {
    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureHTTPProtocol.self]
        return configuration
    }

    private func envelope(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test func requestBuilderPreservesParametersAuthenticationAndEncoding() throws {
        let request = try ScriptHTTP.makeRequest([
            "url": "https://fixture.invalid/echo?existing=yes", "method": "POST",
            "parameters": ["q": "🐼 café"], "username": "user", "password": "pass",
            "data": ["text": "one+two"], "encoding": "form", "timeout": 900.0
        ])
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 900)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic dXNlcjpwYXNz")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(String(data: try #require(request.httpBody), encoding: .utf8) == "text=one%2Btwo")
        let url = try #require(request.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "existing", value: "yes")))
        #expect(query.contains(URLQueryItem(name: "q", value: "🐼 café")))
    }

    @Test func timeoutRetainsPositiveFiniteValuesAndRejectsInvalidDurations() throws {
        #expect(try ScriptHTTP.makeRequest(["url": "https://fixture.invalid/"]).timeoutInterval == 60)
        for seconds in [0.001, 2.5, 900, 3600] {
            let request = try ScriptHTTP.makeRequest(["url": "https://fixture.invalid/", "timeout": seconds])
            #expect(request.timeoutInterval == seconds)
        }
        for seconds in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            #expect(throws: (any Error).self) {
                try ScriptHTTP.makeRequest(["url": "https://fixture.invalid/", "timeout": seconds])
            }
        }
    }

    @Test func queryParametersPreservePlusAndExistingEncodedQuery() throws {
        let request = try ScriptHTTP.makeRequest([
            "url": "https://fixture.invalid/echo?existing=one+two&literal=one%2Btwo",
            "parameters": ["q": "café 🐼 +&=", "empty": ""]
        ])
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try #require(components.percentEncodedQuery)
        #expect(query.hasPrefix("existing=one+two&literal=one%2Btwo&"))
        #expect(query.contains("%2B%26%3D"))
        #expect(components.queryItems?.contains(URLQueryItem(name: "q", value: "café 🐼 +&=")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "empty", value: "")) == true)
    }

    @Test func asyncResponsePreservesUnicodeJSONStatusAndHeaders() async throws {
        let result = try envelope(await ScriptHTTP.requestSerialized(
            #"{"url":"https://fixture.invalid/json"}"#, configuration: configuration()))
        let value = try #require(result["value"] as? [String: Any])
        #expect(value["success"] as? Bool == true)
        #expect(value["statusCode"] as? Int == 201)
        #expect((value["responseData"] as? [String: String])?["text"] == "🐼 café")
        #expect((value["responseText"] as? String)?.contains("🐼 café") == true)
        #expect((value["headers"] as? [String: String])?["X-Fixture"] == "yes")
    }

    @Test func httpErrorRemainsAResponseAndNonJSONBodyIsNull() async throws {
        let result = try envelope(await ScriptHTTP.requestSerialized(
            #"{"url":"https://fixture.invalid/error"}"#, configuration: configuration()))
        let value = try #require(result["value"] as? [String: Any])
        #expect(value["success"] as? Bool == false)
        #expect(value["statusCode"] as? Int == 503)
        #expect(value["responseText"] as? String == "Unavailable 🐼")
        #expect(value["responseData"] is NSNull)
        #expect(value["error"] == nil)
    }

    @Test func networkFailureAndInvalidURLHaveExplicitFailureValues() async throws {
        let network = try envelope(await ScriptHTTP.requestSerialized(
            #"{"url":"https://fixture.invalid/network"}"#, configuration: configuration()))
        let value = try #require(network["value"] as? [String: Any])
        #expect(value["success"] as? Bool == false)
        #expect(value["statusCode"] as? Int == 0)
        #expect(value["error"] as? String != nil)
        let invalid = try envelope(await ScriptHTTP.requestSerialized(#"{"url":"file:///tmp/fixture"}"#))
        #expect((invalid["value"] as? [String: Any])?["error"] as? String == "HTTP requests require an HTTP or HTTPS URL.")
    }

    @Test func invalidSerializedPayloadHasAnInfrastructureError() async throws {
        for payload in ["not JSON", "[]"] {
            let result = try envelope(await ScriptHTTP.requestSerialized(payload))
            #expect(result["error"] as? String != nil)
            #expect(result["value"] == nil)
        }
    }

    @Test func cancellationReleasesAnInFlightRequestWithoutAResponse() async throws {
        let configuration = configuration()
        let request = Task {
            await ScriptHTTP.requestSerialized(#"{"url":"https://fixture.invalid/wait"}"#, configuration: configuration)
        }
        try await Task.sleep(for: .milliseconds(30))
        request.cancel()
        let value = try #require(try envelope(await request.value)["value"] as? [String: Any])
        #expect(value["success"] as? Bool == false)
        #expect(value["statusCode"] as? Int == 0)
        #expect(value["error"] as? String != nil)
    }
}

private final class FixtureHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/wait" { return }
        if url.path == "/network" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let isError = url.path == "/error"
        let response = HTTPURLResponse(url: url, statusCode: isError ? 503 : 201,
                                       httpVersion: "HTTP/1.1", headerFields: ["X-Fixture": "yes"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((isError ? "Unavailable 🐼" : #"{"text":"🐼 café"}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
