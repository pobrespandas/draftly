import Testing
@testable import DraftlyCore

@Suite("Action runtime lifetime") @MainActor
struct ActionRuntimeBoundaryTests {
    @Test func closedRuntimeRejectsHostCallsAndModuleLoads() throws {
        var calls = 0
        var modules = 0
        let runtime = try ActionScriptRuntime(dispatch: { _, _ in calls += 1; return "neutral" },
            requireSource: { _ in modules += 1; return "42" })
        let initialCalls = calls
        let context = runtime.context
        #expect(context.evaluateScript("__host('neutral', '{}')")?.toString()?.contains("neutral") == true)
        #expect(context.evaluateScript("__require('neutral.js')")?.toInt32() == 42)
        runtime.close()
        #expect(context.evaluateScript("__host('neutral', '{}')")?.toString()?.contains("The action was closed.") == true)
        _ = context.evaluateScript("__require('neutral.js')")
        #expect(calls == initialCalls + 1 && modules == 1)
    }
}
