import Foundation
import Testing
@testable import DraftlyCore

@Suite("Engine closure contracts") @MainActor
struct EngineClosureContractTests {
    @Test func omittedAsyncFlagUsesSynchronousCompletionAndCurrentDeadlineDefaults() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        #expect(f.runner.scriptTimeout == 120)
        #expect(f.runner.hostOperationTimeout == 120)
        #expect(f.runner.synchronousScriptTimeout == 10)
        let action = ScriptTestAction.make("editor.setText('Immediate');", name: "Default script")
        #expect(action.steps[0].values["allowAsync"] == nil)
        #expect(action.steps[0].values["allowAsynchronous"] == nil)
        let report = await f.runner.runAsync(action)
        #expect(report.reason == .success)
        #expect(f.editor.content == "Immediate")
    }

    @Test(arguments: [
        "script.complete();script.complete();Promise.reject(new Error('Rejected final result'));",
        "setTimeout(()=>{script.complete();script.complete();context.fail('Failure in completion callback');},0);"
    ])
    func completionCannotOverrideFailureInTheSameEvaluation(source: String) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        var action = ScriptTestAction.make(source, name: "Completion failure", allowAsync: true)
        action.afterSuccess = "archive"
        action.steps.append(ActionStep("insertText", ["template": "Late"]))
        let report = await f.runner.runAsync(action)
        #expect(report.reason == .error)
        #expect(report.successParameters.isEmpty)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
        #expect(f.runner.lastReport == report)
    }

    @Test(arguments: [false, true])
    func separateStoresForTheSameCanonicalFileShareExecutionExclusion(useSymlink: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("actual")
        let library = try LibraryStore(directory: folder, seed: false)
        let note = try library.createNote(content: "Keep")
        let alias = root.appendingPathComponent("alias")
        if useSymlink { try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder) }
        let secondLibrary = try LibraryStore(directory: useSymlink ? alias : folder, seed: false)
        #expect(library !== secondLibrary)
        #expect(library.executionIdentity == secondLibrary.executionIdentity)
        let editor = EditorSession(); editor.load(note)
        let secondEditor = EditorSession(); secondEditor.load(note)
        let host = APIContractHost()
        let started = AsyncStream.makeStream(of: Bool.self)
        host.onPerform = { if $0 == "clipboard" { started.continuation.yield(true) } }
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let second = ActionRunner(library: secondLibrary, editor: secondEditor, host: host)
        let action = ScriptTestAction.make("app.setClipboard('Started');", name: "Hold store", allowAsync: true)
        let task = Task { await runner.runAsync(action) }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        let ownerID = runner.activeSession?.id
        #expect(ActionRunner.isExecuting(in: library) && ActionRunner.isExecuting(in: secondLibrary))
        let next = ScriptTestAction.make("", name: "Other store")
        #expect(second.runReport(next).reason == .busy)
        let rejected = await second.runAsync(next)
        #expect(rejected.reason == .busy && rejected.successParameters.isEmpty)
        #expect(runner.activeSession?.id == ownerID)
        runner.cancel()
        #expect(await task.value.reason == .cancelled)
        #expect(!ActionRunner.isExecuting(in: library) && !ActionRunner.isExecuting(in: secondLibrary))
        #expect(await second.runAsync(next).reason == .success)
    }
}
