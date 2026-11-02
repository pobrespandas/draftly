import Foundation
import Testing
@testable import DraftlyCore

@Suite("Script worker host lifetime") @MainActor
struct ActionScriptWorkerTests {
    @Test(arguments: [false, true]) func deniedCompletionDoesNotApplyDispositionOrFlush(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let editor = EditorSession(); editor.load(note)
        let runner = ActionRunner(library: library, editor: editor)
        var action = DraftAction(name: "Finish", steps: []); action.afterSuccess = "trash"
        runner.authorizeActionCompletion = { candidate, id in
            #expect(candidate.id == action.id && id == note.id)
            editor.content = "Unapproved"
            throw DraftlyError.message("Denied")
        }
        let report = worker ? await runner.runAsync(action) : runner.runReport(action)
        #expect(report.reason == .error)
        #expect(library.notes.first?.content == "Original" && library.notes.first?.trashedAt == nil)
    }
    @Test(arguments: [false, true]) func deniedStepDoesNotFlushPendingEditorChanges(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let editor = EditorSession(); editor.load(note)
        let runner = ActionRunner(library: library, editor: editor)
        runner.authorizeActionStep = { _, _ in
            editor.content = "Unapproved"
            throw DraftlyError.message("Denied")
        }
        let action = DraftAction(name: "Create", steps: [ActionStep("createDraft", ["template": "Created"])])
        let report = worker ? await runner.runAsync(action) : runner.runReport(action)
        #expect(report.reason == .error)
        #expect(library.notes.count == 1 && library.notes.first?.content == "Original")
    }
    @Test func synchronousNativeStepRequiresAuthorizationBeforeCreation() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let editor = EditorSession(); editor.load(note)
        let runner = ActionRunner(library: library, editor: editor)
        var denied = 0
        runner.authorizeActionStep = { _, step in
            if step.type == "createDraft" { denied += 1; throw DraftlyError.message("Denied") }
        }
        let action = DraftAction(name: "Create", steps: [ActionStep("createDraft", ["template": "Created"])])
        let report = runner.runReport(action)
        #expect(denied == 1 && report.reason == .error)
        #expect(library.notes.count == 1 && library.notes.first?.content == "Original")
    }
    @Test func synchronousScriptChecksAuthorizationBeforeUpdatingDraft() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let editor = EditorSession(); editor.load(note)
        let runner = ActionRunner(library: library, editor: editor)
        var denied = 0
        runner.authorizeScriptOperation = { operation, _ in
            if operation == "updateDraft" { denied += 1; throw DraftlyError.message("Denied") }
        }
        let action = DraftAction(name: "Change", steps: [ActionStep("script", ["script": "draft.content='Changed'; draft.update();"])])
        let report = runner.runReport(action)
        #expect(denied == 1 && report.reason == .error)
        #expect(library.notes.first { $0.id == note.id }?.content == "Original")
    }
    @Test func concurrentWorkersCompleteMainActorHostRequests() async {
        let counter = WorkerRequestCounter()
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<24 {
                group.addTask {
                    let worker = ActionScriptWorker(executionID: UUID(), stepID: UUID(), hostTimeout: 10) { request in
                        await Task.yield()
                        if request.operation == "clipboard" { await counter.record() }
                        return request.operation == "device" ? "{\"value\":{}}" : "{\"value\":true}"
                    }
                    do {
                        try await worker.start("")
                        let result = try await worker.run(source: "app.setClipboard('Neutral');", stepID: UUID(), asynchronous: false, timeout: 10, synchronousTimeout: 10)
                        await worker.close()
                        return result
                    } catch {
                        await worker.close()
                        return false
                    }
                }
            }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 24 && results.allSatisfy { $0 })
        #expect(counter.count == 24 && counter.onMainThread)
    }
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

@MainActor private final class WorkerRequestCounter {
    private(set) var count = 0
    private(set) var onMainThread = true
    func record() { count += 1; onMainThread = onMainThread && Thread.isMainThread }
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
