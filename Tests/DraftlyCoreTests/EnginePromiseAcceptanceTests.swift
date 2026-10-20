import Foundation
import Testing
@testable import DraftlyCore

@Suite("Engine promise acceptance") @MainActor
struct EnginePromiseAcceptanceTests {
    @Test(arguments: ["zero", "negative", "infinite", "nan"])
    func invalidAsynchronousLimitsFailBeforeScriptEffects(limit: String) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        switch limit {
        case "zero": f.runner.scriptTimeout = 0
        case "negative": f.runner.scriptTimeout = -1
        case "infinite": f.runner.scriptTimeout = .infinity
        default: f.runner.scriptTimeout = .nan
        }
        var action = ScriptTestAction.make("app.setClipboard('Must not run');script.complete();", name: "Invalid async limit", allowAsync: true)
        action.steps.append(ActionStep("insertText", ["template": "Late"]))
        action.afterSuccess = "archive"
        let report = await f.runner.runAsync(action)
        #expect(report.reason == .error, Comment(rawValue: f.runner.message ?? ""))
        #expect(f.runner.message?.contains("asynchronous script timeout must be positive and finite") == true)
        #expect(f.host.calls.isEmpty && report.successParameters.isEmpty)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
        #expect(f.library.runs.first?.status == "Error")
    }

    @Test func unreturnedRejectedPromiseFailsInsteadOfWaitingForTimeout() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        f.runner.scriptTimeout = 0.1
        var action = ScriptTestAction.make("context.addSuccessParameter('private','discard');Promise.reject(new Error('Unreturned rejection'));void 0;", name: "Unreturned rejection", allowAsync: true)
        action.steps.append(ActionStep("clipboard", ["template": "Must not run"]))
        action.afterSuccess = "archive"
        let report = await f.runner.runAsync(action)
        #expect(report.reason == .error, Comment(rawValue: f.runner.message ?? ""))
        #expect(f.runner.message?.contains("Unreturned rejection") == true)
        #expect(report.successParameters.isEmpty && f.host.clipboard.isEmpty)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
    }
}
