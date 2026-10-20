import Foundation
import Testing
@testable import DraftlyCore

@Suite("Engine deadline acceptance boundaries") @MainActor
struct EngineAcceptanceBoundaryTests {
    @Test(arguments: [Double.nan, .infinity, 0, -1], [false, true])
    func invalidSynchronousLimitsFailBeforeAnyStepEffect(_ value: Double, _ asynchronous: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        fixture.runner.synchronousScriptTimeout = value
        let report = await fixture.runner.runAsync(action(asynchronous: asynchronous))
        #expect(report.reason == .error)
        guard case .failure(let message) = report.result else { Issue.record("Invalid limits must fail."); return }
        #expect(message.contains("synchronous script timeout must be positive and finite"))
        assertUnchanged(fixture, report)
    }

    @Test(arguments: [Double.nan, .infinity, 0, -1])
    func invalidAsynchronousLimitsFailBeforeAnyStepEffect(_ value: Double) async throws {
        let fixture = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        fixture.runner.scriptTimeout = value
        let report = await fixture.runner.runAsync(action(asynchronous: true))
        #expect(report.reason == .error)
        guard case .failure(let message) = report.result else { Issue.record("Invalid limits must fail."); return }
        #expect(message.contains("asynchronous script timeout must be positive and finite"))
        assertUnchanged(fixture, report)
    }

    @Test(arguments: [false, true])
    func asynchronousInitialEvaluationUsesTheSmallerLimit(_ shorterAsync: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        fixture.runner.scriptTimeout = shorterAsync ? 0.01 : 2
        fixture.runner.synchronousScriptTimeout = shorterAsync ? 2 : 0.01
        let cpu = "var until=Date.now()+300;while(Date.now()<until){};script.complete();"
        let report = await fixture.runner.runAsync(action(asynchronous: true, source: cpu))
        #expect(report.reason == .timeout)
        assertUnchanged(fixture, report)
    }

    @Test func synchronousScriptsDoNotUseTheAsynchronousWaitLimit() async throws {
        let fixture = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        fixture.runner.scriptTimeout = .nan
        let report = await fixture.runner.runAsync(ScriptTestAction.make("editor.setText('Finite work');", name: "No async wait"))
        #expect(report.result == .success)
        #expect(fixture.editor.content == "Finite work")
    }

    private func action(asynchronous: Bool, source: String = "app.setClipboard('Invalid step ran');script.complete();") -> DraftAction {
        var action = ScriptTestAction.make(source, name: "Deadline boundary", allowAsync: asynchronous)
        action.afterSuccess = "archive"
        action.steps.append(ActionStep("clipboard", ["template": "Later step ran"]))
        return action
    }

    private func assertUnchanged(_ fixture: ScriptTestFixture<APIContractHost>, _ report: ActionExecutionReport) {
        #expect(!report.result.succeeded && report.successParameters.isEmpty)
        #expect(fixture.host.clipboard.isEmpty)
        #expect(fixture.editor.content == "Keep")
        #expect(fixture.library.notes.first?.content == "Keep")
        #expect(fixture.library.notes.first?.isArchived == false)
    }
}
