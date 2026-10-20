import Foundation
import Testing
@testable import DraftlyCore

@Suite("Asynchronous native action host") @MainActor
struct AsyncNativeHostTests {
    @Test func callbackStepSuspendsAndSharesItsResponseWithTheNextScript() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: WaitingNativeHost())
        let task = Task { await f.runner.runAsync(DraftAction(name: "Callback", steps: [
            ActionStep("callbackUrl", ["url": "neutral://test"]),
            ActionStep("script", ["script": "editor.setText(context.callbackResponses[0].value);"])
        ])) }
        await f.host.waitForStart()
        #expect(f.runner.isRunning && f.editor.content == "Keep")
        let report = await task.value
        #expect(report.reason == .success)
        #expect(f.editor.content == "café 🐼")
        #expect(f.host.syncCalls == 0 && f.host.calls == ["callbackURL"])
    }

    @Test func explicitRunnerCancellationReleasesANativeStepAndStopsSuccessEffects() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: WaitingNativeHost(delay: 30))
        var action = DraftAction(name: "Cancel native", steps: [
            ActionStep("callbackUrl", ["url": "neutral://test"]),
            ActionStep("insertText", ["template": "Late"])
        ])
        action.afterSuccess = "archive"
        let task = Task { await f.runner.runAsync(action) }
        await f.host.waitForStart()
        f.runner.cancel()
        let report = await task.value
        #expect(report.reason == .cancelled)
        #expect(f.host.cancelled && f.editor.content == "Keep")
        #expect(f.library.notes.first?.isArchived == false)
    }

    @Test func hostDeadlineHasATypedResultAndStopsLaterSteps() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: WaitingNativeHost(delay: 30))
        f.runner.hostOperationTimeout = 0.03
        let report = await f.runner.runAsync(DraftAction(name: "Native timeout", steps: [
            ActionStep("callbackUrl", ["url": "neutral://test"]),
            ActionStep("insertText", ["template": "Late"])
        ]))
        #expect(report.reason == .timeout)
        #expect((f.host.cancelled || f.host.calls.isEmpty) && f.editor.content == "Keep")
    }

    @Test func scriptedHostOperationUsesTheAsyncBridge() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: WaitingNativeHost())
        let report = await f.runner.runAsync(ScriptTestAction.make(
            "let cb=CallbackURL.create();cb.baseURL='neutral://test';if(!cb.open())throw new Error('callback');editor.setText(cb.callbackResponse.value);",
            name: "Script callback"))
        #expect(report.reason == .success)
        #expect(f.editor.content == "café 🐼" && f.host.syncCalls == 0)
    }
}

@MainActor private final class WaitingNativeHost: ActionHost {
    let delay: TimeInterval
    var calls: [String] = []
    var syncCalls = 0
    var cancelled = false
    private let started = AsyncStream.makeStream(of: Bool.self)
    init(delay: TimeInterval = 0.03) { self.delay = delay }
    func supportsAsync(_ operation: String) -> Bool { operation == "callbackURL" }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        syncCalls += 1
        throw DraftlyError.message("The synchronous host must not run.")
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        calls.append(operation)
        started.continuation.yield(true)
        do { try await Task.sleep(for: .seconds(delay)) }
        catch { cancelled = true; throw error }
        return #"{"value":{"status":"success","parameters":{"value":"café 🐼"}}}"#
    }
    func waitForStart() async {
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
}
