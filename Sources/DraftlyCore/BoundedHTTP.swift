import Foundation

// Agent effects use a private session and keep a bounded response in memory.
package enum BoundedHTTP {
    package struct Response: Sendable {
        package let statusCode: Int
        package let headers: [String: String]
        package let data: Data
        package let text: String
    }
    enum Failure: Error { case invalidInput, invalidResponse, responseTooLarge, headersTooLarge }

    final class Delegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let origin: URL
        let follow: Bool
        init(origin: URL, follow: Bool) { self.origin = origin; self.follow = follow }
        static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
            func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
            return ["http", "https"].contains(second.scheme?.lowercased() ?? "")
                && second.user == nil && second.password == nil
                && first.scheme?.lowercased() == second.scheme?.lowercased()
                && first.host?.lowercased() == second.host?.lowercased() && port(first) == port(second)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(follow && request.url.map { Self.sameOrigin(origin, $0) } == true ? request : nil)
        }
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
        }
    }

    package static func request(_ payload: String, maximumBytes: Int,
                                configuration: URLSessionConfiguration = .ephemeral) async throws -> Response {
        guard maximumBytes > 0, maximumBytes <= 32 * 1024 * 1024,
              payload.utf8.count <= 1_048_576,
              let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let rawURL = values["url"] as? String, let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.fragment == nil,
              let headerText = values["headersJSON"] as? String,
              let headers = try JSONSerialization.jsonObject(with: Data(headerText.utf8)) as? [String: String] else {
            throw Failure.invalidInput
        }
        var input: [String: Any] = ["url": rawURL, "headers": headers]
        input["method"] = values["method"]; input["timeout"] = values["timeout"]
        var request = try ScriptHTTP.makeRequest(input)
        guard values["bodyText"] == nil || values["bodyBase64"] == nil else { throw Failure.invalidInput }
        if let text = values["bodyText"] as? String { request.httpBody = Data(text.utf8) }
        if let text = values["bodyBase64"] as? String {
            guard let data = Data(base64Encoded: text), data.base64EncodedString() == text else { throw Failure.invalidInput }
            request.httpBody = data
        }
        guard request.httpBody?.count ?? 0 <= 65_536 else { throw Failure.invalidInput }
        request.httpShouldHandleCookies = false
        guard let configuration = configuration.copy() as? URLSessionConfiguration else { throw Failure.invalidInput }
        configuration.urlCredentialStorage = nil; configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        configuration.httpAdditionalHeaders = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration,
            delegate: Delegate(origin: url, follow: values["followRedirects"] as? Bool ?? false), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
            if request.httpMethod != "HEAD" && ![204, 304].contains(response.statusCode) {
                guard response.expectedContentLength <= maximumBytes else { throw Failure.responseTooLarge }
            }
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) }
            guard try JSONSerialization.data(withJSONObject: headers).count <= 65_536 else { throw Failure.headersTooLarge }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else { throw Failure.responseTooLarge }
                data.append(byte)
            }
            try Task.checkCancellation()
            return Response(statusCode: response.statusCode, headers: headers, data: data,
                            text: ScriptHTTP.responseText(data, response: response))
        } onCancel: { session.invalidateAndCancel() }
    }
}
