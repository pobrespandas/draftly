import Foundation
import Testing
@testable import DraftlyCore

@Suite("Asynchronous window opening bridge") @MainActor
struct AsyncWindowOpeningTests {
    @Test(arguments: [false, true])
    func scriptWaitsForTheConfirmedWindowResult(accepted: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        defer { f.runner.uiOperationAsync = nil }
        var confirmed = false
        f.runner.uiOperation = { _ in throw DraftlyError.message("Unexpected synchronous window route") }
        f.runner.uiOperationAsync = { values, timeout in
            #expect(values["operation"] as? String == "openInNewTab")
            #expect((values["value"] as? [String: Any])?["uuid"] as? String == f.editor.noteID?.uuidString)
            #expect(timeout > 0 && timeout <= 120)
            await Task.yield()
            #expect(f.editor.content == "Keep")
            confirmed = true
            return accepted
        }
        let action = makeAPIAction("""
        check(app.currentWindow.openInNewTab(draft)===\(accepted),'confirmed Boolean result');
        editor.setText('After confirmation');
        """)
        #expect(await f.runner.runAsync(action).reason == .success)
        #expect(confirmed && f.editor.content == "After confirmation")
    }

    @Test(arguments: [false, true])
    func cancellationAndTimeoutDrainTheOpeningWaitBeforeReturning(timeout: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        f.runner.hostOperationTimeout = timeout ? 5 : 10
        let started = AsyncStream.makeStream(of: Bool.self)
        var cleaned = false
        f.runner.uiOperationAsync = { _, _ in
            defer { cleaned = true }
            started.continuation.yield(true)
            try await Task.sleep(for: .seconds(30))
            return true
        }
        var action = makeAPIAction("app.currentWindow.openInNewTab(draft);editor.setText('Late effect');")
        action.afterSuccess = "archive"
        let task = Task {
            let report = await f.runner.runAsync(action)
            started.continuation.finish()
            return report
        }
        defer { task.cancel() }
        var events = started.stream.makeAsyncIterator()
        try #require(await events.next() == true)
        if !timeout { f.runner.cancel() }
        let report = await task.value
        #expect(report.reason == (timeout ? .timeout : .cancelled))
        #expect(cleaned && f.editor.content == "Keep")
        #expect(f.library.notes.first?.isArchived == false)
    }

    @Test func missingAsyncHookKeepsTheLegacyBooleanAdapter() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        var calls = 0
        f.runner.uiOperation = { values in
            #expect(values["operation"] as? String == "openInNewTab")
            calls += 1
            return false
        }
        #expect(await f.runner.runAsync(makeAPIAction("check(app.currentWindow.openInNewTab(draft)===false,'legacy adapter result');")).reason == .success)
        #expect(calls == 1 && f.editor.content == "Keep")
    }
}
