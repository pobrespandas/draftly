import Foundation
import Testing
@testable import DraftlyCore

@Suite("Engine boundary contracts") @MainActor
struct EngineBoundaryContractTests {
    @Test(arguments: [50, 51])
    func actualIncludeChainsRespectTheDepthBoundary(actionCount: Int) throws {
        let leaf = ActionStep("clipboard", ["template": "Leaf"])
        var actions = (0..<actionCount).map { DraftAction(name: "Level \($0)", steps: []) }
        for index in 0..<(actions.count - 1) {
            actions[index].steps = [ActionStep("includeAction", ["uuid": actions[index + 1].id.uuidString])]
        }
        actions[actions.count - 1].steps = [leaf]
        if actionCount == 50 {
            #expect(try ActionStepExpansion.expand(actions[0], actions: actions) == [leaf])
        } else {
            do {
                _ = try ActionStepExpansion.expand(actions[0], actions: actions)
                Issue.record("A chain past the supported depth must fail.")
            } catch { #expect(error.localizedDescription.contains("depth exceeded 50")) }
        }
    }

    @Test(arguments: [100, 101])
    func queueLimitCountsExecutedActionsAndRetainsCompletedEffects(requested: Int) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        let child = DraftAction(name: "Queued effect", steps: [ActionStep("clipboard", ["template": "Completed"])])
        try f.library.saveAction(child)
        let root = ScriptTestAction.make("let child=Action.find('Queued effect');for(let i=0;i<\(requested);i++)app.queueAction(child,draft);", name: "Queue boundary")
        let report = await f.runner.runAsync(root)
        #expect(report.actionID == root.id)
        #expect(report.reason == (requested == 100 ? .success : .error))
        #expect(f.host.calls.filter { $0.0 == "clipboard" }.count == 100)
        #expect(f.host.clipboard == "Completed")
        #expect(f.editor.content == "Keep" && f.library.notes.first?.content == "Keep")
        #expect(f.runner.queued.isEmpty)
        if requested == 101 {
            #expect(f.runner.message?.contains("queue exceeded 100") == true)
            #expect(report.successParameters.isEmpty)
        }
    }

    @Test(arguments: ["cancel", "fail"])
    func asynchronousQueuedTerminationStopsLaterWorkAndClearsSuccessParameters(mode: String) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        f.runner.scriptTimeout = 10
        var terminating = ScriptTestAction.make("setTimeout(()=>{app.setClipboard('Completed queued effect');context.addSuccessParameter('queued','discard');context.\(mode)('Queued termination');script.complete();},0);", name: "Terminate queued", allowAsync: true)
        terminating.afterSuccess = "archive"
        terminating.steps.append(ActionStep("insertText", ["template": "Later step"]))
        let later = DraftAction(name: "Later queued", steps: [ActionStep("clipboard", ["template": "Must not run"])])
        try f.library.saveAction(terminating)
        try f.library.saveAction(later)
        let root = ScriptTestAction.make("context.addSuccessParameter('root','discard');app.queueAction(Action.find('Terminate queued'),draft);app.queueAction(Action.find('Later queued'),draft);", name: "Queue termination")
        let report = await f.runner.runAsync(root)
        #expect(report.reason == (mode == "cancel" ? .cancelled : .error))
        #expect(report.successParameters.isEmpty && f.runner.queued.isEmpty)
        #expect(f.host.clipboard == "Completed queued effect")
        #expect(f.host.calls.filter { $0.0 == "clipboard" }.count == 1)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
        #expect(f.library.runs.first?.status == (mode == "cancel" ? "Cancelled" : "Error"))
    }

    @Test func separateRootExecutionsDoNotShareJavaScriptGlobals() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        let first = await f.runner.runAsync(ScriptTestAction.make("var priorExecutionValue='old';context.addSuccessParameter('old','discard');", name: "First root"))
        #expect(first.reason == .success)
        let second = await f.runner.runAsync(ScriptTestAction.make("if(typeof priorExecutionValue!=='undefined')throw new Error('Leaked global');if(Object.keys(context.successParameters).length!==0)throw new Error('Leaked parameters');editor.setText('Fresh runtime');", name: "Second root"))
        #expect(second.reason == .success)
        #expect(first.executionID != second.executionID)
        #expect(second.successParameters.isEmpty)
        #expect(f.editor.content == "Fresh runtime")
    }

    @Test func cancellationBeforeStartupPreventsAllActionEffects() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        var action = ScriptTestAction.make("app.setClipboard('Must not run');editor.setText('Must not save');", name: "Cancelled before startup")
        action.afterSuccess = "archive"
        let task = Task { await f.runner.runAsync(action) }
        task.cancel()
        let report = await task.value
        #expect(report.reason == .cancelled && report.successParameters.isEmpty)
        #expect(f.host.calls.isEmpty)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
        #expect(f.runner.activeSession == nil && !f.runner.isRunning)
    }

    @Test func absentAndFalseSeparatorFlagsRemainNormalActions() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        for (name, flag) in [("Absent flag", ""), ("False flag", ",\"backingIsSeparator\":false")] {
            let source = "{\"name\":\"\(name)\",\"steps\":[]\(flag)}"
            let imported = try #require(ActionImporter.decode(Data(source.utf8)).first)
            try f.library.saveAction(imported)
            let report = await f.runner.runAsync(ScriptTestAction.make("if(Action.find('\(name)').isSeparator!==false)throw new Error('Unexpected separator');", name: "Separator defaults"))
            #expect(report.reason == .success)
        }
    }

    @Test(arguments: [
        #"{"backingIsSeparator":true,"steps":[]}"#,
        #"{"name":"Malformed section","backingIsSeparator":true}"#,
        #"{"name":"Malformed section","backingIsSeparator":true,"steps":"invalid"}"#,
        #"{"name":"Malformed section","backingIsSeparator":true,"steps":[{"data":{}}]}"#
    ])
    func separatorFlagDoesNotBypassImportValidation(source: String) {
        #expect(throws: DraftlyError.self) { try ActionImporter.decode(Data(source.utf8)) }
    }
}
