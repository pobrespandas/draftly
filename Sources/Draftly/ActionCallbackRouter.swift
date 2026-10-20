import AppKit
import DraftlyCore

@MainActor final class ActionCallbackRouter {
    static var callbackScheme: String { Bundle.main.object(forInfoDictionaryKey: "DraftlyCallbackScheme") as? String ?? "draftly" }
    private final class Pending {
        let continuation: CheckedContinuation<String, Error>
        var timeout: Task<Void, Never>?
        init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }
    }
    private static var pending: [String: Pending] = [:]
    private static var legacyTokens: Set<String> = []
    private static var responses: [String: [String: Any]] = [:]

    static func receive(_ url: URL) -> Bool {
        guard url.scheme == callbackScheme, url.host == "callback",
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let token = query.first(where: { $0.name == "token" })?.value,
              pending[token] != nil || legacyTokens.contains(token),
              let status = query.first(where: { $0.name == "status" })?.value,
              ["success", "cancelled", "error"].contains(status) else { return false }
        var parameters: [String: String] = [:]
        for item in query where item.name != "token" && item.name != "status" { parameters[item.name] = item.value ?? "" }
        let response: [String: Any] = ["status": status, "parameters": parameters]
        if pending[token] != nil { finish(token, result: .success(response)) }
        else {
            legacyTokens.remove(token)
            responses[token] = response
        }
        return true
    }

    static func openAsync(_ values: [String: Any], timeout: TimeInterval = 120,
                          openURL: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard timeout.isFinite, timeout > 0 else { throw DraftlyError.message("The callback timeout must be positive and finite.") }
        let token = UUID().uuidString, wait = values["waitForResponse"] as? Bool ?? true
        guard let url = callbackURL(values, token: token, wait: wait) else { return ["status": "invalid"] }
        if !wait { return openURL(url) ? ["status": "success", "parameters": [String: String]()] : ["status": "invalid"] }
        let response: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[token] = Pending(continuation)
                guard !Task.isCancelled else { finish(token, result: .failure(CancellationError())); return }
                guard openURL(url) else { finish(token, result: .success(["status": "invalid"])); return }
                guard let request = pending[token] else { return }
                request.timeout = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    finish(token, result: .success(["status": "timeout", "parameters": [String: String]()]))
                }
            }
        } onCancel: {
            Task { @MainActor in finish(token, result: .failure(CancellationError())) }
        }
        return try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any] ?? [:]
    }

    // Legacy callers keep their synchronous contract during migration.
    static func open(_ values: [String: Any]) throws -> [String: Any] {
        let token = UUID().uuidString, wait = values["waitForResponse"] as? Bool ?? true
        guard let url = callbackURL(values, token: token, wait: wait) else { return ["status": "invalid"] }
        if wait { legacyTokens.insert(token) }
        defer { legacyTokens.remove(token); responses.removeValue(forKey: token) }
        guard NSWorkspace.shared.open(url) else { return ["status": "invalid"] }
        if !wait { return ["status": "success", "parameters": [String: String]()] }
        let deadline = Date().addingTimeInterval(120)
        while responses[token] == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return responses[token] ?? ["status": "timeout", "parameters": [String: String]()]
    }

    private static func finish(_ token: String, result: Result<[String: Any], Error>) {
        guard let request = pending.removeValue(forKey: token) else { return }
        request.timeout?.cancel()
        switch result {
        case .success(let value):
            do {
                let data = try JSONSerialization.data(withJSONObject: value)
                request.continuation.resume(returning: String(decoding: data, as: UTF8.self))
            } catch { request.continuation.resume(throwing: error) }
        case .failure(let error): request.continuation.resume(throwing: error)
        }
    }

    private static func callbackURL(_ values: [String: Any], token: String, wait: Bool) -> URL? {
        guard var components = URLComponents(string: values["url"] as? String ?? ""),
              let scheme = components.scheme, !scheme.isEmpty,
              !["javascript", "data", "file"].contains(scheme.lowercased()) else { return nil }
        if wait {
            var query = (components.queryItems ?? []).filter { !["x-success", "x-cancel", "x-error"].contains($0.name) }
            for (key, status) in [("x-success", "success"), ("x-cancel", "cancelled"), ("x-error", "error")] {
                query.append(URLQueryItem(name: key, value: "\(callbackScheme)://callback?token=\(token)&status=\(status)"))
            }
            components.queryItems = query
        }
        return components.url
    }
}
