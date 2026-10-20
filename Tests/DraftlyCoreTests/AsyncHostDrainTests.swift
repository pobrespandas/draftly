import Foundation
import Testing
@testable import DraftlyCore

@Suite("Asynchronous host cleanup") @MainActor
struct AsyncHostDrainTests {
    @Test(arguments: [false, true])
    func scriptRequestKeepsLibraryBusyUntilCancelledHostCleanupReturns(timeout: Bool) async throws {
        let host = CleanupGateHost()
        let f = try ScriptTestFixture(content: "Keep", host: host)
        f.runner.hostOperationTimeout = timeout ? 5 : 30
        let other = ActionRunner(library: f.library, editor: f.editor, host: host)
        var action = ScriptTestAction.make("ShellScript.create('neutral').execute();editor.setText('Late');", name: "Host cleanup")
        action.afterSuccess = "archive"
        let task = Task { await f.runner.runAsync(action) }
        await host.waitForStart()
        if !timeout { f.runner.cancel() }
        await host.waitForCleanup()
        // This host pauses cleanup. MainActor must remain available during the drain.
        #expect(f.runner.isRunning)
        #expect(f.runner.activeSession?.report == nil)
        #expect(host.finishes == 0)
        let next = ScriptTestAction.make("editor.setText('Next');", name: "Next")
        #expect(await other.runAsync(next).reason == .busy)
        #expect(f.editor.content == "Keep")
        host.releaseCleanup()
        let report = await task.value
        #expect(report.reason == (timeout ? .timeout : .cancelled))
        #expect(host.cleaned && host.finishes == 1)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
        #expect(await other.runAsync(next).reason == .success)
        #expect(f.editor.content == "Next")
    }
}

@MainActor private final class CleanupGateHost: ActionHost {
    private let started = AsyncStream.makeStream(of: Bool.self)
    private let cleanup = AsyncStream.makeStream(of: Bool.self)
    private var cleanupGate: CheckedContinuation<Void, Never>?
    var cleaned = false
    var finishes = 0

    func supportsAsync(_ operation: String) -> Bool { operation == "shellScript" }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        throw DraftlyError.message("Unexpected synchronous operation: \(operation)")
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        started.continuation.yield(true)
        do { try await Task.sleep(for: .seconds(30)) }
        catch {
            await withCheckedContinuation { continuation in
                cleanupGate = continuation
                cleanup.continuation.yield(true)
            }
            cleaned = true
            throw error
        }
        return #"{"value":{"status":0,"stdout":"","stderr":""}}"#
    }
    func waitForStart() async {
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
    func waitForCleanup() async {
        var iterator = cleanup.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
    func releaseCleanup() {
        cleanupGate?.resume()
        cleanupGate = nil
    }
    func finishAction() { finishes += 1 }
}
