import Foundation

// Use only pure builders. Rendering can suspend between builder attempts.
@MainActor enum ActionTemplateBuilder {
    private struct Request: Error { let text: String }

    static func build<Value>(render: (String) async throws -> String,
                             _ builder: ((String) throws -> String) throws -> Value) async throws -> Value {
        var resolved: [(text: String, value: String)] = []
        while true {
            try Task.checkCancellation()
            var index = 0
            do {
                return try builder { text in
                    guard index < resolved.count else { throw Request(text: text) }
                    let entry = resolved[index]
                    guard entry.text == text else { throw DraftlyError.message("The template builder changed its render order.") }
                    index += 1
                    return entry.value
                }
            } catch let request as Request {
                resolved.append((request.text, try await render(request.text)))
            }
        }
    }
}
