import Foundation
import Testing
@testable import DraftlyCore

@Suite("Queued execution acceptance") @MainActor
struct QueueAcceptanceTests {
    private let callbacks = ["x-success": "fixture://success?keep=yes&collision=old&collision=older", "x-cancel": "fixture://cancel?keep=yes", "x-error": "fixture://error?keep=yes&errorMessage=old"]

    @Test(arguments: [false, true])
    func queuedActionsHaveFreshGlobalsAndAggregateFinalSuccessParameters(asynchronous: Bool) async throws {
        let f = try ScriptTestFixture(content: "Root", host: APIContractHost())
        let first = ScriptTestAction.make("check(typeof queueSentinel==='undefined','root global leaked');var queueSentinel='first';context.addSuccessParameter('first','yes');", name: "First fresh queue")
        let second = ScriptTestAction.make("check(typeof queueSentinel==='undefined','first queued global leaked');context.addSuccessParameter('second','yes');editor.setText('Fresh runtimes');", name: "Second fresh queue")
        try f.library.saveAction(first); try f.library.saveAction(second)
        let root = ScriptTestAction.make("var queueSentinel='root';context.addSuccessParameter('root','yes');app.queueAction(Action.find('First fresh queue'),draft);app.queueAction(Action.find('Second fresh queue'),draft);", name: "Queue runtime isolation")
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.reason == .success, Comment(rawValue: f.runner.message ?? ""))
        #expect(report.successParameters == ["root": "yes", "first": "yes", "second": "yes"])
        #expect(f.editor.content == "Fresh runtimes" && f.library.notes.first?.content == "Fresh runtimes")
        #expect(f.library.runs.count == 1 && f.library.runs.first?.actionID == root.id)
    }

    @Test func queuedTimeoutRetainsCompletedEffectsAndSelectsOnlyTheErrorCallback() async throws {
        let f = try ScriptTestFixture(content: "Root", host: APIContractHost())
        let rootID = try #require(f.editor.noteID)
        let target = try f.library.createNote(content: "Target")
        f.runner.scriptTimeout = 1
        var child = ScriptTestAction.make("editor.setText('Completed queued edit 🐼');app.setClipboard('Completed queued effect');context.addSuccessParameter('private','discard');", name: "Queued timeout", allowAsync: true)
        child.afterSuccess = "archive"
        child.steps.append(ActionStep("insertText", ["template": "Must not run"]))
        let later = ScriptTestAction.make("app.setClipboard('Must not run');", name: "Later queue")
        try f.library.saveAction(child); try f.library.saveAction(later)
        let root = ScriptTestAction.make("context.addSuccessParameter('root','discard');app.queueAction(Action.find('Queued timeout'),Draft.find('\(target.id.uuidString)'));app.queueAction(Action.find('Later queue'),draft);", name: "Queue root")
        let report = await f.runner.runAsync(root)
        #expect(report.actionID == root.id && report.reason == .timeout)
        #expect(report.successParameters.isEmpty && f.runner.queued.isEmpty)
        #expect(f.editor.noteID == target.id && f.editor.content == "Completed queued edit 🐼")
        #expect(f.library.notes.first { $0.id == target.id }?.content == "Completed queued edit 🐼")
        #expect(f.library.notes.first { $0.id == target.id }?.isArchived == false)
        #expect(f.library.notes.first { $0.id == rootID }?.content == "Root")
        #expect(f.host.clipboard == "Completed queued effect")
        let url = try #require(report.result.callbackURL(parameters: callbacks, successParameters: report.successParameters))
        let values = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.host == "error")
        #expect(values.queryItems?.filter { $0.name == "errorMessage" }.count == 1)
        #expect(values.queryItems?.contains { $0.name == "keep" && $0.value == "yes" } == true)
        #expect(values.queryItems?.contains { $0.name == "private" || $0.name == "root" } == false)
    }

    @Test(arguments: [false, true], [false, true])
    func queuedInterruptionOnAnotherDraftKeepsEffectsAndStopsTheQueue(asynchronous: Bool, cancelled: Bool) async throws {
        let f = try ScriptTestFixture(content: "Source café 🐼", host: APIContractHost())
        let sourceID = try #require(f.editor.noteID)
        let target = try f.library.createNote(content: "Target")
        let stop = cancelled ? "context.cancel('Stopped café 🐼');" : "throw new Error('Stopped café 🐼');"
        var child = ScriptTestAction.make("editor.setText('Retained target 🐼');app.setClipboard('Retained effect');context.addSuccessParameter('child','discard');" + stop,
            name: "Interrupted target")
        child.afterSuccess = "archive"
        child.steps.append(ActionStep("insertText", ["template": "Must not run"]))
        let later = ScriptTestAction.make("editor.setText('Must not run');app.setClipboard('Must not run');", name: "Later target")
        try f.library.saveAction(child); try f.library.saveAction(later)
        let root = ScriptTestAction.make("context.addSuccessParameter('root','discard');app.queueAction(Action.find('Interrupted target'),Draft.find('\(target.id.uuidString)'));app.queueAction(Action.find('Later target'),draft);", name: "Interrupted queue root")
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.actionID == root.id)
        #expect(report.reason == (cancelled ? .cancelled : .error))
        #expect(report.successParameters.isEmpty && f.runner.queued.isEmpty)
        #expect(f.editor.noteID == target.id && f.editor.content == "Retained target 🐼")
        #expect(f.library.notes.first { $0.id == target.id }?.content == "Retained target 🐼")
        #expect(f.library.notes.first { $0.id == target.id }?.isArchived == false)
        #expect(f.library.notes.first { $0.id == sourceID }?.content == "Source café 🐼")
        #expect(f.host.clipboard == "Retained effect")
        let url = try #require(report.result.callbackURL(parameters: callbacks, successParameters: report.successParameters))
        #expect(url.host == (cancelled ? "cancel" : "error"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(!items.contains { $0.name == "root" || $0.name == "child" })
        #expect(f.library.runs.count == 1 && f.library.runs.first?.actionID == root.id)
    }

    @Test func queuedDraftLoadsTheCurrentStoredVersionInsteadOfItsCapturedText() async throws {
        let f = try ScriptTestFixture(content: "Root", host: APIContractHost())
        let rootID = try #require(f.editor.noteID)
        let target = try f.library.createNote(content: "Old target")
        let child = ScriptTestAction.make("if(draft.uuid!=='\(target.id.uuidString)'||editor.getText()!=='Updated target')throw new Error('stale queued draft');editor.setText(editor.getText()+' done');", name: "Current queued target")
        try f.library.saveAction(child)
        let root = ScriptTestAction.make("let target=Draft.find('\(target.id.uuidString)');app.queueAction(Action.find('Current queued target'),target);target.content='Updated target';target.update();", name: "Update after queue")
        let report = await f.runner.runAsync(root)
        #expect(report.reason == .success)
        #expect(f.editor.noteID == target.id && f.editor.content == "Updated target done")
        #expect(f.library.notes.first { $0.id == rootID }?.content == "Root")
    }

    @Test func finalQueuedParametersReplaceRootAndExistingCallbackValuesOnce() async throws {
        let f = try ScriptTestFixture(content: "Root", host: APIContractHost())
        let child = ScriptTestAction.make("context.addSuccessParameter('collision','queued 🐼 & café');context.addSuccessParameter('child','yes');", name: "Queued parameters")
        try f.library.saveAction(child)
        let root = ScriptTestAction.make("context.addSuccessParameter('collision','root');context.addSuccessParameter('root','yes');app.queueAction(Action.find('Queued parameters'),draft);", name: "Root parameters")
        let report = await f.runner.runAsync(root)
        #expect(report.reason == .success)
        #expect(report.successParameters == ["collision": "queued 🐼 & café", "child": "yes", "root": "yes"])
        let url = try #require(report.result.callbackURL(parameters: callbacks, successParameters: report.successParameters))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host == "success")
        #expect(items.filter { $0.name == "collision" }.map(\.value) == ["queued 🐼 & café"])
        #expect(items.contains { $0.name == "keep" && $0.value == "yes" })
        #expect(!items.contains { $0.name == "errorMessage" })
    }
}
