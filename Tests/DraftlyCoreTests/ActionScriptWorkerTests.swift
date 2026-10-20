import Foundation
import Testing
@testable import DraftlyCore

@Suite("Script worker host lifetime") @MainActor
struct ActionScriptWorkerTests {
    @Test func cancellingAHostWaitReleasesTheWorkerAndCancelsItsRequestTask() async throws {
        let gate = WorkerHostGate()
        let worker = ActionScriptWorker(executionID: UUID(), stepID: UUID(), hostTimeout: 120) { request in
            await gate.receive(request)
        }
        try await worker.start("")
        let task = Task { try await worker.run(source: "app.setClipboard('Neutral');", stepID: UUID(), asynchronous: false, timeout: 1, synchronousTimeout: 1) }
        var iterator = gate.started.stream.makeAsyncIterator()
        let request = try #require(await iterator.next())
        #expect(request.operation == "clipboard" && !request.payload.isEmpty)
        worker.cancel()
        do { _ = try await task.value; Issue.record("The worker must stop on cancellation") }
        catch { #expect(error as? ActionExecutionInterruption == .cancelled) }
        gate.release()
        await worker.close()
        #expect(gate.cancelled)
    }

    @Test func timedOutHostReplyCannotChangeTheNextScript() async throws {
        let gate = WorkerHostGate()
        let executionID = UUID(), stepID = UUID()
        let worker = ActionScriptWorker(executionID: executionID, stepID: UUID(), hostTimeout: 120) { request in
            await gate.receive(request)
        }
        try await worker.start("")
        let task = Task { try await worker.run(source: "app.setClipboard('Neutral');", stepID: stepID, asynchronous: true, timeout: 0.02, synchronousTimeout: 1) }
        var iterator = gate.started.stream.makeAsyncIterator()
        let request = try #require(await iterator.next())
        #expect(request.executionID == executionID && request.stepID == stepID)
        do { _ = try await task.value; Issue.record("The host request must time out") }
        catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        gate.release()
        let result = try await worker.run(source: "var marker='Next';if(marker!=='Next')throw new Error('corrupted');", stepID: UUID(), asynchronous: false, timeout: 1, synchronousTimeout: 1)
        #expect(result)
        await worker.close()
    }
}

@MainActor private final class WorkerHostGate {
    let started = AsyncStream.makeStream(of: ActionBridgeRequest.self)
    private var reply: CheckedContinuation<String, Never>?
    private(set) var cancelled = false

    func receive(_ request: ActionBridgeRequest) async -> String {
        if request.operation == "device" { return "{\"value\":{}}" }
        return await withTaskCancellationHandler {
            let response = await withCheckedContinuation { continuation in
                reply = continuation
                started.continuation.yield(request)
            }
            cancelled = Task.isCancelled
            return response
        } onCancel: {}
    }

    func release() {
        reply?.resume(returning: "{\"value\":true}")
        reply = nil
    }
}
