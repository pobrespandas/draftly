import Foundation
import JavaScriptCore

public enum MustacheRenderer {
    public static func render(_ template: String, data: Any, escape: Bool = true, partials: [String: String] = [:]) throws -> String {
        guard let context = JSContext(), let url = Bundle.module.url(forResource: "mustache", withExtension: "js") else { throw DraftlyError.message("The Mustache runtime is missing.") }
        var failure: String?
        context.exceptionHandler = { _, error in failure = error?.toString() }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        context.setObject(template, forKeyedSubscript: "__template" as NSString)
        context.setObject(data, forKeyedSubscript: "__data" as NSString)
        context.setObject(partials, forKeyedSubscript: "__partials" as NSString)
        context.setObject(escape, forKeyedSubscript: "__escape" as NSString)
        let value = context.evaluateScript("Mustache.render(__template, __data, __partials, {escape: __escape ? Mustache.escape : String})")
        if let failure { throw DraftlyError.message(failure) }
        return value?.toString() ?? ""
    }
}
