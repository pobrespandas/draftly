import Foundation
import Testing
@testable import DraftlyCore

@Suite("Asynchronous host cleanup") @MainActor
struct AsyncHostDrainTests {
    @Test(arguments: [ActionTerminationReason.cancelled, .timeout])
    func scriptRequestKeepsLibraryBusyUntilInterruptedHostCleanupReturns(reason: ActionTerminationReason) async throws {
        let host = CleanupGateHost()
        let f = try ScriptTestFixture(content: "Keep", host: host)
        f.runner.hostOperationTimeout = reason == .timeout ? 5 : 30
        let clock = HostCleanupClock()
        f.runner.hostOperationNow = { clock.now }
        f.runner.hostOperationSleep = { try await clock.sleep($0) }
        let other = ActionRunner(library: f.library, editor: f.editor, host: host)
        var action = ScriptTestAction.make("ShellScript.create('neutral').execute();editor.setText('Late');", name: "Host cleanup")
        action.afterSuccess = "archive"
        let task = Task {
            let report = await f.runner.runAsync(action)
            host.finishSignals()
            return report
        }
        defer { task.cancel(); host.releaseCleanup() }
        try #require(await host.waitForStart(), Comment(rawValue: f.runner.message ?? "The action ended before the host started."))
        if reason == .timeout { clock.expire(after: 5) }
        else { f.runner.cancel() }
        try #require(await host.waitForCleanup(), Comment(rawValue: f.runner.message ?? "The action ended before host cleanup started."))
        // This host pauses cleanup. MainActor must remain available during the drain.
        #expect(f.runner.isRunning)
        #expect(f.runner.activeSession?.report == nil)
        #expect(host.finishes == 0)
        let next = ScriptTestAction.make("editor.setText('Next');", name: "Next")
        #expect(await other.runAsync(next).reason == .busy)
        #expect(f.editor.content == "Keep")
        host.releaseCleanup()
        let report = await task.value
        #expect(report.reason == reason)
        #expect(host.cleaned && host.finishes == 1)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
        #expect(await other.runAsync(next).reason == .success)
        #expect(f.editor.content == "Next")
    }

    @Test func actionFailureBeforeHostStartFinishesBothSignalStreams() async throws {
        let host = CleanupGateHost()
        let f = try ScriptTestFixture(content: "Keep", host: host)
        let action = ScriptTestAction.make("throw new Error('Before host');", name: "Early failure")
        let task = Task {
            let report = await f.runner.runAsync(action)
            host.finishSignals()
            return report
        }
        defer { task.cancel(); host.releaseCleanup() }
        #expect(await host.waitForStart() == false)
        #expect(await host.waitForCleanup() == false)
        let report = await task.value
        #expect(report.reason == .error)
        #expect(f.runner.message?.contains("Before host") == true)
        #expect(!f.runner.isRunning && f.runner.activeSession == nil)
        #expect(f.editor.content == "Keep" && host.finishes == 1)
        let next = ActionRunner(library: f.library, editor: f.editor, host: host)
        #expect(await next.runAsync(ScriptTestAction.make("", name: "Next")).reason == .success)
    }
}

@MainActor private final class HostCleanupClock {
    private let expiration = AsyncStream.makeStream(of: Void.self)
    private(set) var now = Date(timeIntervalSince1970: 10_000)

    func sleep(_ interval: TimeInterval) async throws {
        if interval > 0 {
            var events = expiration.stream.makeAsyncIterator()
            _ = await events.next()
        }
        try Task.checkCancellation()
    }
    func expire(after interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
        expiration.continuation.yield(())
        expiration.continuation.finish()
    }
}

@MainActor private final class CleanupGateHost: ActionHost {
    private let started = AsyncStream.makeStream(of: Bool.self)
    private let cleanup = AsyncStream.makeStream(of: Bool.self)
    private var cleanupGate: CheckedContinuation<Void, Never>?
    private var cleanupReleased = false
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
                if cleanupReleased { continuation.resume() }
                else { cleanupGate = continuation }
                cleanup.continuation.yield(true)
            }
            cleaned = true
            throw error
        }
        return #"{"value":{"status":0,"stdout":"","stderr":""}}"#
    }
    func waitForStart() async -> Bool {
        var iterator = started.stream.makeAsyncIterator()
        return await iterator.next() != nil
    }
    func waitForCleanup() async -> Bool {
        var iterator = cleanup.stream.makeAsyncIterator()
        return await iterator.next() != nil
    }
    func releaseCleanup() {
        cleanupReleased = true
        cleanupGate?.resume()
        cleanupGate = nil
    }
    func finishSignals() {
        started.continuation.finish()
        cleanup.continuation.finish()
    }
    func finishAction() { finishes += 1 }
}
