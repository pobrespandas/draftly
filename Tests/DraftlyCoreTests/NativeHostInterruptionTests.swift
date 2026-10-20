import Foundation
import Testing
@testable import DraftlyCore

@Suite("Native host interruption contracts") @MainActor
struct NativeHostInterruptionTests {
    @Test(arguments: [false, true])
    func caughtHostInterruptionCannotRunLaterHostEffects(timeout: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: InterruptedNativeHost(timeout: timeout))
        var action = ScriptTestAction.make("try{Bookmark.findOrCreate('Neutral');}catch(e){};try{editor.setText('Late');}catch(e){};try{app.setClipboard('Late');}catch(e){};", name: "Native interruption")
        action.steps.append(ActionStep("insertText", ["template": "Later step"]))
        action.afterSuccess = "archive"
        let report = await f.runner.runAsync(action)
        #expect(report.reason == (timeout ? .timeout : .cancelled))
        #expect(f.host.operations == ["bookmark"])
        #expect(f.editor.content == "Keep" && f.library.notes.first?.content == "Keep")
        #expect(f.library.notes.first?.isArchived == false && report.successParameters.isEmpty)
    }
}

@MainActor private final class InterruptedNativeHost: ActionHost {
    let timeout: Bool
    var operations: [String] = []
    init(timeout: Bool) { self.timeout = timeout }
    func supportsAsync(_ operation: String) -> Bool { operation == "bookmark" }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        operations.append(operation); return true
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        operations.append(operation)
        throw timeout ? ActionExecutionInterruption.timeout : .cancelled
    }
}

@Suite("Native host deadline ordering") @MainActor
struct NativeHostDeadlineOrderingTests {
    @Test func aLateResponseCannotWinBeforeTheTimerTaskRuns() async throws {
        let host = ExpiredReplyHost()
        let f = try ScriptTestFixture(content: "Keep", host: host)
        var now = Date()
        f.runner.hostOperationNow = { now }
        f.runner.hostOperationTimeout = 30
        host.onStart = { now = now.addingTimeInterval(60) }
        var action = DraftAction(name: "Late native reply", steps: [ActionStep("callbackUrl", ["url": "neutral://test"]), ActionStep("insertText", ["template": "Late"])])
        action.afterSuccess = "archive"
        let report = await f.runner.runAsync(action)
        #expect(host.started && report.reason == .timeout)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
    }
}

@MainActor private final class ExpiredReplyHost: ActionHost {
    var onStart: (() -> Void)?
    var started = false
    func supportsAsync(_ operation: String) -> Bool { operation == "callbackURL" }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? { nil }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        started = true; onStart?()
        return #"{"value":{"status":"success","parameters":{}}}"#
    }
}
