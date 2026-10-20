import Foundation
import Testing
@testable import DraftlyCore

@Suite("Unhandled promise runtime")
struct UnhandledPromiseRuntimeTests {
    private func runtime() throws -> ActionScriptRuntime {
        let runtime = try ActionScriptRuntime(dispatch: { operation, _ in
            operation == "device" ? [String: Any]() : nil
        }, requireSource: { _ in "" })
        try #require(runtime.scriptError == nil, "The bridge must load before the rejection checks.")
        return runtime
    }

    @Test(arguments: [
        "Promise.reject(new Error('Discarded rejection'));void 0;",
        "void (async function(){throw new Error('Discarded rejection');})();",
        "Promise.resolve().then(function(){throw new Error('Discarded rejection');});void 0;"
    ])
    func discardedRejectionsReachTheRuntime(source: String) throws {
        let runtime = try runtime()
        defer { runtime.close() }
        runtime.context.evaluateScript(source)
        runtime.context.evaluateScript("void 0;")
        #expect(runtime.scriptError?.contains("Discarded rejection") == true)
    }

    @Test(arguments: [
        "Promise.reject(new Error('Handled rejection')).catch(function(){});",
        "(async function(){throw new Error('Handled rejection');})().catch(function(){});",
        "(async function(){try{await Promise.reject(new Error('Handled rejection'));}catch(error){}})();"
    ])
    func caughtRejectionsDoNotFailTheRuntime(source: String) throws {
        let runtime = try runtime()
        defer { runtime.close() }
        runtime.context.evaluateScript(source)
        runtime.context.evaluateScript("void 0;")
        #expect(runtime.scriptError == nil)
    }

    @Test func endedStepIgnoresRejectionsAndNewStepAcceptsThem() throws {
        let runtime = try runtime()
        defer { runtime.close() }
        runtime.endStep()
        runtime.context.evaluateScript("void (async function(){throw new Error('Ended step');})();")
        #expect(runtime.scriptError == nil)
        try runtime.beginStep()
        runtime.context.evaluateScript("void (async function(){throw new Error('Current step');})();")
        #expect(runtime.scriptError?.contains("Current step") == true)
    }

    @Test func closedRuntimeIgnoresRejections() throws {
        let runtime = try runtime()
        runtime.close()
        runtime.context.evaluateScript("Promise.reject(new Error('Closed runtime'));void 0;")
        #expect(runtime.scriptError == nil)
    }
}
