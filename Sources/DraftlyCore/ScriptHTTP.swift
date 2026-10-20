import Foundation

final class ScriptHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let follow: Bool

    init(follow: Bool) { self.follow = follow }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(follow ? request : nil)
    }

    private final class Result: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [String: Any]?
        func set(_ value: [String: Any]) { lock.lock(); self.value = value; lock.unlock() }
        func get() -> [String: Any]? { lock.lock(); defer { lock.unlock() }; return value }
    }

    static func makeRequest(_ values: [String: Any]) throws -> URLRequest {
        guard let string = values["url"] as? String,
              var components = URLComponents(string: string),
              ["http", "https"].contains(components.scheme?.lowercased() ?? "") else {
            throw DraftlyError.message("HTTP requests require an HTTP or HTTPS URL.")
        }
        if let parameters = values["parameters"] as? [String: Any] {
            components.queryItems = (components.queryItems ?? []) + parameters.map {
                URLQueryItem(name: $0.key, value: String(describing: $0.value))
            }
        }
        guard let url = components.url else { throw DraftlyError.message("The request URL is invalid.") }
        var request = URLRequest(url: url)
        request.httpMethod = values["method"] as? String ?? "GET"
        request.timeoutInterval = min(600, max(0.01, values["timeout"] as? Double ?? 60))
        for (key, value) in values["headers"] as? [String: String] ?? [:] {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let username = values["username"] as? String {
            request.setValue("Basic " + Data((username + ":" + (values["password"] as? String ?? "")).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        }
        if let data = values["data"] {
            if values["encoding"] as? String == "raw", let text = data as? String {
                request.httpBody = Data(text.utf8)
            } else if values["encoding"] as? String == "form", let fields = data as? [String: Any] {
                var form = URLComponents()
                form.queryItems = fields.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
                request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }
            } else {
                request.httpBody = try JSONSerialization.data(withJSONObject: data, options: [.fragmentsAllowed])
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        return request
    }

    static func responseValue(data: Data?, response: URLResponse?, error: Error?) -> [String: Any] {
        let response = response as? HTTPURLResponse
        let data = data ?? Data()
        var value: [String: Any] = [
            "success": error == nil && (200..<300).contains(response?.statusCode ?? 0),
            "statusCode": response?.statusCode ?? 0,
            "responseText": String(data: data, encoding: .utf8) ?? "",
            "headers": response?.allHeaderFields.reduce(into: [String: String]()) {
                $0[String(describing: $1.key)] = String(describing: $1.value)
            } ?? [:],
            "responseData": (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull()
        ]
        if let error { value["error"] = error.localizedDescription }
        return value
    }

    private static func failure(_ error: Error) -> [String: Any] {
        ["success": false, "statusCode": 0, "responseText": "", "headers": [:], "error": error.localizedDescription]
    }

    // This adapter retains the synchronous contract for legacy callers.
    static func request(_ values: [String: Any]) -> [String: Any] {
        do {
            let request = try makeRequest(values)
            let session = URLSession(configuration: .ephemeral,
                                     delegate: ScriptHTTP(follow: values["followRedirects"] as? Bool ?? true),
                                     delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let result = Result()
            session.dataTask(with: request) { data, response, error in
                result.set(responseValue(data: data, response: response, error: error))
            }.resume()
            let deadline = Date().addingTimeInterval(request.timeoutInterval + 1)
            while result.get() == nil && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            }
            return result.get() ?? failure(DraftlyError.message("The HTTP request timed out."))
        } catch { return failure(error) }
    }

    static func requestSerialized(_ payload: String) async -> String {
        await requestSerialized(payload, configuration: .ephemeral)
    }

    // The configuration parameter lets tests use an isolated URLProtocol.
    static func requestSerialized(_ payload: String, configuration: URLSessionConfiguration) async -> String {
        let envelope: [String: Any]
        do {
            guard let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
                throw DraftlyError.message("The HTTP request payload must be an object.")
            }
            let value: [String: Any]
            do {
                try Task.checkCancellation()
                let request = try makeRequest(values)
                let session = URLSession(configuration: configuration,
                                         delegate: ScriptHTTP(follow: values["followRedirects"] as? Bool ?? true),
                                         delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                do {
                    let (data, response) = try await session.data(for: request)
                    value = responseValue(data: data, response: response, error: nil)
                } catch {
                    value = responseValue(data: nil, response: nil, error: error)
                }
            } catch { value = failure(error) }
            envelope = ["value": value]
        } catch { envelope = ["error": error.localizedDescription] }
        do {
            return String(decoding: try JSONSerialization.data(withJSONObject: envelope, options: [.fragmentsAllowed]), as: UTF8.self)
        } catch {
            return "{\"error\":\"The HTTP response could not be serialized.\"}"
        }
    }
}
