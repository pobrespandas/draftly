import Foundation
import Testing
@testable import DraftlyCore

@Suite("CPU-bound action cancellation") @MainActor
struct EngineCPUCancellationTests {
    @Test func taskCancellationDuringBusyJavaScriptWinsOverDeadlineAndReleasesLibrary() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        let started = AsyncStream.makeStream(of: Bool.self)
        f.host.onPerform = { operation in
            if operation == "clipboard" { started.continuation.yield(true) }
        }
        f.runner.synchronousScriptTimeout = 0.25
        var action = ScriptTestAction.make("context.addSuccessParameter('private','discard');app.setClipboard('Completed before CPU work');while(true){}", name: "Cancel CPU work")
        action.afterSuccess = "archive"
        action.steps.append(ActionStep("insertText", ["template": "Must not run"]))
        let task = Task { await f.runner.runAsync(action) }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        let cancellationStarted = ContinuousClock.now
        task.cancel()
        let report = await task.value
        let cancellationLatency = cancellationStarted.duration(to: .now)
        print("CPU cancellation latency: \(cancellationLatency); configured synchronous limit: \(f.runner.synchronousScriptTimeout) seconds")
        #expect(report.reason == .cancelled, Comment(rawValue: f.runner.message ?? ""))
        #expect(report.successParameters.isEmpty && f.runner.queued.isEmpty)
        #expect(f.host.clipboard == "Completed before CPU work")
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
        #expect(!f.runner.isRunning && f.runner.activeSession == nil)
        #expect(await f.runner.runAsync(ScriptTestAction.make("editor.setText('Next action');", name: "After CPU cancellation")).reason == .success)
        #expect(f.editor.content == "Next action" && f.library.notes.first?.content == "Next action")
    }
}
