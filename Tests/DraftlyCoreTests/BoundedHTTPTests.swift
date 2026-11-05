import Foundation
import Testing
@testable import DraftlyCore

@Suite("Bounded reviewed HTTP transport")
struct BoundedHTTPTests {
    private func configuration() -> URLSessionConfiguration {
        let value = URLSessionConfiguration.ephemeral
        value.protocolClasses = [BoundedHTTPProtocol.self]
        value.httpAdditionalHeaders = ["X-Implicit": "must not send", "Authorization": "implicit credential", "Cookie": "implicit cookie"]
        if let cookie = HTTPCookie(properties: [.domain: "fixture.invalid", .path: "/", .name: "PRIVATE", .value: "never send"]) { value.httpCookieStorage?.setCookie(cookie) }
        return value
    }
    private func payload(_ path: String, body: String? = nil) throws -> String {
        var values: [String: Any] = ["url": "https://fixture.invalid" + path, "method": "POST", "headersJSON": "{\"X-Explicit\":\"allowed\"}"]
        if let body { values["bodyBase64"] = body }
        return String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
    }
    @Test func boundedReadsKeepBinaryAndUseOnlyExplicitHeaders() async throws {
        let result = try await BoundedHTTP.request(payload("/echo", body: Data([0, 128, 255]).base64EncodedString()), maximumBytes: 4, configuration: configuration())
        #expect(result.data == Data([0, 128, 255]) && result.statusCode == 201)
        #expect(result.headers["X-Fixture"] == "yes")
    }
    @Test(arguments: ["/length", "/stream"])
    func oversizedResponsesFailWhetherLengthIsDeclared(path: String) async throws {
        await #expect(throws: (any Error).self) {
            try await BoundedHTTP.request(payload(path), maximumBytes: 4, configuration: configuration())
        }
    }
    @Test func cancellationStopsARequestWaitingForHeaders() async throws {
        let payload = try payload("/wait")
        let task = Task { try await BoundedHTTP.request(payload, maximumBytes: 4, configuration: configuration()) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
    }
    @Test(arguments: ["https://fixture.invalid:443/next", "https://other.invalid/next", "http://fixture.invalid/next", "https://fixture.invalid:444/next", "https://user@fixture.invalid/next"])
    func redirectsCannotChangeTheReviewedOrigin(destination: String) throws {
        let origin = try #require(URL(string: "https://fixture.invalid/start")), target = try #require(URL(string: destination))
        #expect(BoundedHTTP.Delegate.sameOrigin(origin, target) == destination.contains(":443/"))
    }
}

private final class BoundedHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/wait" { return }
        guard request.value(forHTTPHeaderField: "X-Implicit") == nil,
              request.value(forHTTPHeaderField: "X-Explicit") == "allowed",
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Authorization") == nil else {
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired)); return
        }
        var headers = ["X-Fixture": "yes"]
        if url.path == "/length" { headers["Content-Length"] = "5" }
        let response = HTTPURLResponse(url: url, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 2048)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        client?.urlProtocol(self, didLoad: url.path == "/echo" ? data : Data(repeating: 1, count: 5))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
