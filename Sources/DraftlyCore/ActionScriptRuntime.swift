import Foundation
import JavaScriptCore
import Darwin

// The caller owns the execution queue and all JavaScript values.
final class ActionScriptRuntime {
    let context = JSContext()!
    var scriptError: String?
    private var acceptingCalls = true
    private var rejectionEpoch: UUID?
    private typealias RejectionHook = @convention(c) (JSGlobalContextRef?, JSObjectRef?, UnsafeMutablePointer<JSValueRef?>?) -> Void
    private let rejectionHook: RejectionHook

    init(dispatch: @escaping (String, [String: Any]) throws -> Any?,
         requireSource: @escaping (String) throws -> String) throws {
        // This runtime requires the macOS JSC rejection SPI. It covers intrinsic async promises.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSGlobalContextSetUnhandledRejectionCallback") else {
            throw DraftlyError.message("JavaScriptCore cannot report unhandled promise rejections on this system.")
        }
        rejectionHook = unsafeBitCast(symbol, to: RejectionHook.self)
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
        try beginStep()
    }

    func beginStep() throws {
        let epoch = UUID()
        rejectionEpoch = epoch
        let callback: @convention(block) (JSValue?, JSValue?) -> Void = { [weak self] _, reason in
            guard let self, self.acceptingCalls, self.rejectionEpoch == epoch else { return }
            self.scriptError = reason?.toString() ?? "Unhandled promise rejection"
        }
        let value = JSValue(object: callback, in: context)!
        var exception: JSValueRef?
        let function = JSValueToObject(context.jsGlobalContextRef, value.jsValueRef, &exception)
        guard exception == nil, let function else {
            throw DraftlyError.message("JavaScriptCore could not create the promise rejection callback.")
        }
        rejectionHook(context.jsGlobalContextRef, function, &exception)
        if let exception {
            let message = JSValue(jsValueRef: exception, in: context)?.toString() ?? "Unknown JavaScript error"
            throw DraftlyError.message("JavaScriptCore could not install the promise rejection callback: " + message)
        }
    }

    func endStep() { rejectionEpoch = nil }
    func close() { endStep(); acceptingCalls = false }
}
