import Foundation
import Testing
@testable import DraftlyCore

@Suite("Asynchronous native action host") @MainActor
struct AsyncNativeHostTests {
    @Test func cancelledConfirmationIgnoresLateAcceptanceAndKeepsLibraryReservedUntilCleanup() async throws {
        let f = try ScriptTestFixture(content: "Keep 🐼", host: ConfirmationGateHost())
        var action = DraftAction(name: "Pending confirmation", steps: [ActionStep("insertText", ["template": "Late"])])
        action.presentation.confirmBeforeRun = true
        action.afterSuccess = "archive"
        let task = Task { await f.runner.runAsync(action) }
        defer { task.cancel(); f.host.release() }
        var iterator = f.host.started.stream.makeAsyncIterator()
        _ = await iterator.next()
        let competing = ActionRunner(library: f.library, editor: f.editor, host: f.host)
        f.runner.cancel()
        let busy = await competing.runAsync(DraftAction(name: "Competing", steps: []))
        #expect(busy.reason == .busy)
        #expect(f.editor.content == "Keep 🐼" && f.library.notes.first?.isArchived == false)
        f.host.release()
        let report = await task.value
        #expect(report.reason == .cancelled && report.successParameters.isEmpty)
        #expect(f.host.observedCancellation && f.host.finishes == 1)
        #expect(f.editor.content == "Keep 🐼" && f.library.notes.first?.isArchived == false)
        #expect(f.library.runs.count == 1 && f.library.runs.first?.status == "Cancelled")
        let next = await f.runner.runAsync(DraftAction(name: "Recovery", steps: [ActionStep("insertText", ["template": "Next"]) ]))
        #expect(next.reason == .success && next.executionID != report.executionID)
        #expect(f.library.runs.count == 2)
    }
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

@MainActor private final class ConfirmationGateHost: ActionHost {
    let started = AsyncStream.makeStream(of: Bool.self)
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var observedCancellation = false
    private(set) var finishes = 0
    func supportsAsync(_ operation: String) -> Bool { operation == "confirmAction" }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        throw DraftlyError.message("Unexpected synchronous operation.")
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        let result = await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.continuation.yield(true)
        }
        observedCancellation = Task.isCancelled
        return result
    }
    func release() { continuation?.resume(returning: #"{"value":true}"#); continuation = nil }
    func finishAction() { finishes += 1 }
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

@Suite("Async input bridge contracts") @MainActor
struct AsyncInputBridgeTests {
    @Test func transcriptionReturnsTextWithoutChangingTheEditor() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: AsyncInputHost())
        f.runner.uiOperation = { _ in Issue.record("The synchronous window adapter ran."); return nil }
        let report = await f.runner.runAsync(ScriptTestAction.make("context.addSuccessParameter('text',editor.transcribe());", name: "Transcribe"))
        #expect(report.reason == .success)
        #expect(report.successParameters["text"] == "café 🐼")
        #expect(f.editor.content == "Keep" && f.library.notes.first?.content == "Keep")
        #expect(f.host.calls == ["transcribe"])
    }

    @Test func transcriptionWithoutAWindowFailsBeforeTheHostRuns() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: AsyncInputHost())
        let report = await f.runner.runAsync(ScriptTestAction.make("editor.transcribe();", name: "No window"))
        #expect(report.reason == .error && f.host.calls.isEmpty)
        #expect(f.editor.content == "Keep")
    }

    @Test func dictationForwardsLocaleAndDoesNotInsertText() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: AsyncInputHost())
        f.runner.uiOperation = { _ in Issue.record("The synchronous window adapter ran."); return nil }
        let report = await f.runner.runAsync(ScriptTestAction.make("context.addSuccessParameter('text',editor.dictate('es-AR'));", name: "Dictate"))
        #expect(report.reason == .success && report.successParameters["text"] == "café 🐼")
        #expect(f.host.calls == ["dictate"] && f.host.lastPayload == #"{"locale":"es-AR"}"#)
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [true, false])
    func arrangementReturnsItsResultWithoutChangingTheEditor(windowBound: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: AsyncInputHost())
        f.runner.uiOperation = { _ in Issue.record("The synchronous window adapter ran."); return nil }
        if !windowBound { f.runner.uiOperation = nil }
        let report = await f.runner.runAsync(ScriptTestAction.make("context.addSuccessParameter('text',editor.arrange('First\\nSecond 🐼'));", name: "Arrange"))
        #expect(report.reason == .success && report.successParameters["text"] == "café 🐼")
        #expect(f.host.calls == ["arrangeText"] && f.editor.content == "Keep")
        let payload = try JSONSerialization.jsonObject(with: Data(f.host.lastPayload.utf8)) as? [String: String]
        #expect(payload?["text"] == "First\nSecond 🐼")
    }

    @Test func appleScriptStepUsesTheAsyncHostAndKeepsStructuredResults() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: AsyncInputHost())
        let report = await f.runner.runAsync(DraftAction(name: "AppleScript", steps: [
            ActionStep("runAppleScript", ["script": "on execute(draft)\nreturn \"café 🐼\"\nend execute"]),
            ActionStep("script", ["script": "context.addSuccessParameter('text',context.appleScriptResponses[0]);"])
        ]))
        #expect(report.reason == .success && report.successParameters["text"] == "café 🐼")
        #expect(f.host.calls == ["appleScript"] && f.editor.content == "Keep")
        let payload = try JSONSerialization.jsonObject(with: Data(f.host.lastPayload.utf8)) as? [String: Any]
        #expect(payload?["subroutine"] as? String == "execute")
        #expect((payload?["arguments"] as? [[String: Any]])?.first?["uuid"] as? String == f.editor.noteID?.uuidString)
    }

    @Test func modelToolsRejectCallsOutsideAnAction() throws {
        let f = try ScriptTestFixture(content: "Keep", host: AsyncInputHost())
        #expect(throws: DraftlyError.self) {
            try f.runner.performModelTool("draft.create", json: #"{"text":"Late"}"#)
        }
        #expect(f.library.notes.count == 1 && f.editor.content == "Keep")
    }

    @Test func declinedAsyncConfirmationDoesNotRunAnyStep() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: AsyncInputHost())
        var action = DraftAction(name: "Confirm", steps: [ActionStep("insertText", ["template": "Late"])])
        action.presentation.confirmBeforeRun = true
        let report = await f.runner.runAsync(action)
        #expect(report.reason == .cancelled && f.host.calls == ["confirmAction"])
        #expect(f.editor.content == "Keep")
    }
}

@MainActor private final class AsyncInputHost: ActionHost {
    var calls: [String] = []
    var lastPayload = ""
    func supportsAsync(_ operation: String) -> Bool { ["transcribe", "dictate", "arrangeText", "appleScript", "confirmAction"].contains(operation) }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        Issue.record("The synchronous host ran."); return nil
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        calls.append(operation)
        lastPayload = payload
        await Task.yield()
        return operation != "confirmAction" ? #"{"value":"café 🐼"}"# : #"{"value":false}"#
    }
}
