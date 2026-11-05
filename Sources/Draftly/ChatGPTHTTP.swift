import Foundation

enum ChatGPTHTTP {
    struct Response: Sendable { let status: Int; let data: Data }
    enum Failure: Error { case invalidResponse, tooLarge }

    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func perform(_ request: URLRequest) async throws -> Response {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url == request.url else { throw Failure.invalidResponse }
        guard response.expectedContentLength <= 1048576 else { throw Failure.tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1048576 else { throw Failure.tooLarge }
            data.append(byte)
        }
        return Response(status: response.statusCode, data: data)
    }

    static func makeSession(requestTimeout: TimeInterval = 30, resourceTimeout: TimeInterval = 30) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
    }
}
