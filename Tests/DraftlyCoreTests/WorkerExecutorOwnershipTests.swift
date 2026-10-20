import Foundation
import Testing
@testable import DraftlyCore

@Suite("Worker executor ownership") @MainActor
struct WorkerExecutorOwnershipTests {
    @Test(arguments: [false, true])
    func runtimeLifecycleStaysOnItsWorkerAcrossHostSuspensionAndCancellation(cancelled: Bool) async throws {
        let events = OwnershipEvents(), host = OwnershipHostGate()
        let worker = ActionScriptWorker(executionID: UUID(), stepID: UUID(), hostTimeout: 30,
            lifecycleProbe: { events.append($0) }, dispatch: { await host.receive($0) })
        try await worker.start("")
        let task = Task { try await worker.run(source: "app.setClipboard('Neutral');setTimeout(()=>script.complete(),0);",
            stepID: UUID(), asynchronous: true, timeout: 30, synchronousTimeout: 10) }
        await host.waitForStart()
        if cancelled { worker.cancel() }
        host.release()
        if cancelled {
            do { _ = try await task.value; Issue.record("Cancelled worker must not complete successfully.") }
            catch { #expect(error as? ActionExecutionInterruption == .cancelled) }
        } else { #expect(try await task.value) }
        await worker.close()
        let captured = events.snapshot()
        #expect(captured.contains { $0.phase == .created })
        #expect(captured.contains { $0.phase == .evaluation })
        #expect(captured.contains { $0.phase == .request })
        if !cancelled { #expect(captured.contains { $0.phase == .timer }) }
        #expect(captured.last?.phase == .closed)
        #expect(captured.filter { $0.phase == .closed }.count == 1)
        #expect(captured.allSatisfy { $0.isOnOwnerQueue && !$0.isMainThread })
    }
}

private final class OwnershipEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ActionScriptWorker.LifecycleEvent] = []
    func append(_ event: ActionScriptWorker.LifecycleEvent) { lock.lock(); defer { lock.unlock() }; events.append(event) }
    func snapshot() -> [ActionScriptWorker.LifecycleEvent] { lock.lock(); defer { lock.unlock() }; return events }
}

@MainActor private final class OwnershipHostGate {
    private let started = AsyncStream.makeStream(of: Bool.self)
    private var pending: CheckedContinuation<String, Never>?
    func receive(_ request: ActionBridgeRequest) async -> String {
        guard request.operation == "clipboard" else { return #"{"value":{}}"# }
        return await withCheckedContinuation { continuation in
            pending = continuation
            started.continuation.yield(true)
        }
    }
    func waitForStart() async { var iterator = started.stream.makeAsyncIterator(); _ = await iterator.next() }
    func release() { pending?.resume(returning: #"{"value":true}"#); pending = nil }
}
