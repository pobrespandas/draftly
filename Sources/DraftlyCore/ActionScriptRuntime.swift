import Foundation
import JavaScriptCore

@MainActor
final class ActionScriptRuntime {
    let context = JSContext()!
    var scriptError: String?
    private var acceptingCalls = true

    init(dispatch: @escaping (String, [String: Any]) throws -> Any?,
         requireSource: @escaping (String) throws -> String) throws {
        context.exceptionHandler = { [weak self] _, value in
            self?.scriptError = value?.toString() ?? "JavaScript error"
        }
        let bridge: @convention(block) (String, String) -> String = { [weak self] operation, text in
            guard let self, self.acceptingCalls else { return "{\"error\":\"The action was closed.\"}" }
            do {
                let values = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
                let result = try dispatch(operation, values)
                let data = try JSONSerialization.data(withJSONObject: ["value": result ?? NSNull()], options: [.fragmentsAllowed])
                return String(decoding: data, as: UTF8.self)
            } catch {
                let data = try! JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])
                return String(decoding: data, as: UTF8.self)
            }
        }
        context.setObject(bridge, forKeyedSubscript: "__host" as NSString)
        let require: @convention(block) (String) -> JSValue? = { [weak self] path in
            guard let self, self.acceptingCalls else { return nil }
            do {
                return self.context.evaluateScript(try requireSource(path), withSourceURL: URL(fileURLWithPath: path))
            } catch {
                self.context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: self.context)
                return nil
            }
        }
        context.setObject(require, forKeyedSubscript: "__require" as NSString)
        guard let url = Bundle.module.url(forResource: "Bridge", withExtension: "js") else { throw DraftlyError.message("The JavaScript bridge is missing.") }
        for name in ["datejs", "mustache"] {
            guard let resource = Bundle.module.url(forResource: name, withExtension: "js") else { throw DraftlyError.message("The \(name) runtime is missing.") }
            context.evaluateScript(try String(contentsOf: resource, encoding: .utf8))
        }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
    }

    func close() { acceptingCalls = false }
}
