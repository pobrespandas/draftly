import Foundation
import Testing
@testable import DraftlyCore

@Suite("Engine session defaults") @MainActor
struct EngineDefaultsContractTests {
    @Test(arguments: [false, true])
    func aNewRunStartsUncancelledAtItsFirstStepAfterAnExplicitlyCancelledRun(asynchronous: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        let runner = f.runner
        defer { f.host.onPerform = nil }
        f.host.onPerform = { operation in
            if operation == "clipboard" { runner.cancel() }
        }
        let cancelled = ScriptTestAction.make("app.setClipboard('Earlier effect');", name: "Explicit cancellation")
        let previous = asynchronous ? await runner.runAsync(cancelled) : runner.runReport(cancelled)
        #expect(previous.reason == .cancelled)
        let next = ScriptTestAction.make("app.setClipboard('Fresh session');", name: "New session defaults")
        var observed: ActionExecutionSession?
        var sawFirstStep = false
        f.host.onPerform = { operation in
            guard operation == "clipboard" else { return }
            observed = runner.activeSession
            sawFirstStep = true
            #expect(observed?.cancellationRequested == false)
            #expect(observed?.report == nil)
            #expect(observed?.currentStep?.index == 0)
            #expect(observed?.currentStep?.actionID == next.id)
            #expect(observed?.currentStep?.stepID == next.steps[0].id)
            #expect(observed?.currentStep?.type == "script")
        }
        let report = asynchronous ? await runner.runAsync(next) : runner.runReport(next)
        #expect(sawFirstStep)
        #expect(report.reason == .success && f.host.clipboard == "Fresh session")
        #expect(observed?.id == report.executionID && report.executionID != previous.executionID)
        #expect(observed?.cancellationRequested == false)
        #expect(observed?.report == report)
        #expect(runner.activeSession == nil)
    }
}
