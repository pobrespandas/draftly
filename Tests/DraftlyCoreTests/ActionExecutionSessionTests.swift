import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action execution session") @MainActor
struct ActionExecutionSessionTests {
    @Test func completionIsFinalAndFailedRunsDropSuccessParameters() {
        let session = ActionExecutionSession(actionID: UUID())
        let step = ActionStep("script")
        session.enter(actionID: session.actionID, step: step)
        #expect(session.currentStep?.stepID == step.id)
        let first = session.finish(.failure("Expected"), reason: .error, successParameters: ["drop": "value"])
        session.cancel()
        session.enter(actionID: UUID(), step: ActionStep("clipboard"))
        let second = session.finish(.success, reason: .success, successParameters: ["late": "value"])
        #expect(first == second)
        #expect(first.executionID == session.id)
        #expect(first.successParameters.isEmpty)
        #expect(!session.cancellationRequested)
        #expect(session.currentStep?.stepID == step.id)
    }

    @Test func reportDistinguishesTimeoutAndCancellationAndClearsTheSession() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "Neutral café 🐼"))
        let runner = ActionRunner(library: library, editor: editor)
        runner.scriptTimeout = 0.01
        let timedOut = DraftAction(name: "Timeout", steps: [ActionStep("script", ["allowAsync": "true", "script": "void 0;"])])
        let timeout = runner.runReport(timedOut)
        #expect(timeout.reason == .timeout)
        #expect(!timeout.result.succeeded)
        #expect(runner.activeSession == nil && !runner.isRunning)
        let cancelled = runner.runReport(DraftAction(name: "Cancel", steps: [ActionStep("script", ["script": "context.cancel();"])]))
        #expect(cancelled.reason == .cancelled && cancelled.result == .cancelled)
        #expect(cancelled.executionID != timeout.executionID)
        #expect(runner.lastReport == cancelled)
        #expect(editor.content == "Neutral café 🐼")
    }

    @Test func rejectedReentryKeepsTheLegacyMessageAndDoesNotReplaceTheActiveReport() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "Neutral"))
        let host = SessionCancellationHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let other = ActionRunner(library: library, editor: editor, host: host)
        let action = DraftAction(name: "Reentry", steps: [ActionStep("clipboard")])
        var ownReport: ActionExecutionReport?
        var otherReport: ActionExecutionReport?
        var ownMessage: String?
        host.onPerform = {
            ownReport = runner.runReport(action)
            ownMessage = runner.message
            otherReport = other.runReport(action)
        }
        let report = runner.runReport(action)
        #expect(report.result == .success)
        #expect(ownReport?.reason == .busy && otherReport?.reason == .busy)
        #expect(ownMessage == "An action is already running.")
        #expect(other.message == "An action is already running in this library.")
        #expect(runner.lastReport == report)
        #expect(other.lastReport == nil)
        #expect(host.completed == ["clipboard"])
    }

    @Test func cancellationStopsLaterStepsAndSuccessEffects() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        let note = try library.createNote(content: "Keep")
        editor.load(note)
        let host = SessionCancellationHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        host.onPerform = { runner.cancel() }
        var action = DraftAction(name: "Cancellation", steps: [ActionStep("clipboard", ["template": "Completed effect"]), ActionStep("insertText", ["template": "Must not run"])])
        action.afterSuccess = "archive"
        let report = runner.runReport(action)
        #expect(report.result == .cancelled)
        #expect(host.completed == ["clipboard"])
        #expect(editor.content == "Keep")
        #expect(library.notes.first { $0.id == note.id }?.isArchived == false)
    }
}

@MainActor private final class SessionCancellationHost: ActionHost {
    var completed: [String] = []
    var onPerform: (() -> Void)?
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        completed.append(operation)
        onPerform?()
        return true
    }
}
