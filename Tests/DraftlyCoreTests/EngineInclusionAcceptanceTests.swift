import Foundation
import Testing
@testable import DraftlyCore

@Suite("Engine inclusion acceptance") @MainActor
struct EngineInclusionAcceptanceTests {
    @Test(arguments: [false, true])
    func repeatedSiblingIncludesReuseGlobalsWithoutSharingAncestry(asynchronous: Bool) async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        let child = ScriptTestAction.make("visits.push('child');", name: "Repeated sibling")
        try f.library.saveAction(child)
        let root = DraftAction(name: "Siblings", steps: [
            ActionStep("script", ["script": "var visits=['root'];"]),
            ActionStep("includeAction", ["uuid": child.id.uuidString]),
            ActionStep("includeAction", ["uuid": child.id.uuidString]),
            ActionStep("script", ["script": "if(visits.join('|')!=='root|child|child')throw new Error('Repeated include failed');editor.setText(visits.join('|'));"])
        ])
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.reason == .success && f.editor.content == "root|child|child")
        #expect(f.library.notes.first?.content == "root|child|child" && f.library.runs.count == 1)
    }

    @Test(arguments: [50, 51])
    func dynamicIncludeChainEnforcesDepthDuringExecution(actionCount: Int) async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        var actions = (0..<actionCount).map { DraftAction(name: "Child\($0)", steps: []) }
        for index in 0..<(actions.count - 1) {
            actions[index].steps = [ActionStep("includeAction", ["name": "Child\(index + 1)[[suffix]]"])]
        }
        actions[0].steps.insert(ActionStep("script", ["script": "draft.setTemplateTag('suffix','');app.setClipboard('Root reached');"]), at: 0)
        actions[actions.count - 1].steps = [ActionStep("script", ["script": "editor.setText('Leaf reached');"])]
        actions[0].afterSuccess = "archive"
        for action in actions { try f.library.saveAction(action) }
        let report = await f.runner.runAsync(actions[0])
        #expect(report.reason == (actionCount == 50 ? .success : .error))
        #expect(f.host.clipboard == "Root reached")
        #expect(f.editor.content == (actionCount == 50 ? "Leaf reached" : "Source"))
        #expect(f.library.notes.first?.isArchived == (actionCount == 50))
        #expect(f.library.runs.count == 1)
        if actionCount == 51 {
            #expect(f.runner.message?.contains("depth exceeded 50") == true)
            #expect(report.successParameters.isEmpty)
        }
    }

    @Test(arguments: [false, true], ["cancel", "fail"])
    func childTerminationStopsRootAndQueueWithoutRevertingCompletedEffects(asynchronous: Bool, termination: String) async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        let queued = ScriptTestAction.make("editor.setText('Queued late write');app.setClipboard('Queued late effect');", name: "Queued after include")
        var child = ScriptTestAction.make("shared.push('child');app.setClipboard(shared.join('|'));context.addSuccessParameter('child','discard');context.\(termination)('Child termination');", name: "Terminating child")
        child.steps.append(ActionStep("script", ["script": "editor.setText('Child late write');"]))
        try f.library.saveAction(queued); try f.library.saveAction(child)
        var root = DraftAction(name: "Parent termination", steps: [
            ActionStep("script", ["script": "var shared=['root'];editor.setText('Completed root write');draft.update();app.setClipboard('Completed root effect');context.addSuccessParameter('root','discard');app.queueAction(Action.find('Queued after include'),draft);"]),
            ActionStep("includeAction", ["uuid": child.id.uuidString]),
            ActionStep("script", ["script": "editor.setText('Root late write');app.setClipboard('Root late effect');"])
        ])
        root.afterSuccess = "archive"
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.reason == (termination == "cancel" ? .cancelled : .error))
        #expect(report.successParameters.isEmpty && f.runner.queued.isEmpty)
        #expect(f.host.clipboard == "root|child")
        #expect(f.host.calls.filter { $0.0 == "clipboard" }.count == 2)
        #expect(f.editor.content == "Completed root write")
        #expect(f.library.notes.first?.content == "Completed root write" && f.library.notes.first?.isArchived == false)
        #expect(f.library.runs.count == 1 && f.library.runs.first?.actionID == root.id)
        #expect(f.library.runs.first?.status == (termination == "cancel" ? "Cancelled" : "Error"))
    }

    @Test(arguments: [false, true])
    func selectedUUIDSharesRootContextAndIgnoresStaleName(asynchronous: Bool) async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        let selected = ScriptTestAction.make("shared.push('selected');context.addSuccessParameter('child','retained');", name: "Renamed helper")
        let stale = ScriptTestAction.make("throw new Error('Wrong name target');", name: "Old helper")
        try f.library.saveAction(selected); try f.library.saveAction(stale)
        let root = DraftAction(name: "UUID include", steps: [
            ActionStep("script", ["script": "var shared=['root'];"]),
            ActionStep("includeAction", ["uuid": selected.id.uuidString, "name": stale.name]),
            ActionStep("script", ["script": "if(shared.join('|')!=='root|selected')throw new Error('Context lost');editor.setText(shared.join('|'));context.addSuccessParameter('root','retained');"])
        ])
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.reason == .success)
        #expect(report.successParameters["child"] == "retained" && report.successParameters["root"] == "retained")
        #expect(f.editor.content == "root|selected" && f.library.notes.first?.content == "root|selected")
        #expect(f.library.runs.count == 1 && f.library.runs.first?.actionID == root.id)
    }

    @Test(arguments: [false, true])
    func disabledCircularIncludeDoesNotResolveOrRun(asynchronous: Bool) async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        var root = DraftAction(name: "Disabled cycle", steps: [])
        var cycle = ActionStep("includeAction", ["uuid": root.id.uuidString]); cycle.isEnabled = false
        root.steps = [cycle, ActionStep("script", ["script": "editor.setText('Completed');"])]
        try f.library.saveAction(root)
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.reason == .success && f.editor.content == "Completed")
        #expect(f.library.notes.first?.content == "Completed" && f.library.runs.count == 1)
    }

    @Test(arguments: [false, true])
    func dynamicSubtreeCycleIsRejectedBeforeItsEffectsButRetainsRootEffects(asynchronous: Bool) async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        var child = DraftAction(name: "Cyclic helper", steps: [])
        child.steps = [ActionStep("clipboard", ["template": "Must not replace root effect"]),
                       ActionStep("includeAction", ["uuid": child.id.uuidString])]
        try f.library.saveAction(child)
        var root = DraftAction(name: "Dynamic subtree", steps: [
            ActionStep("script", ["script": "app.setClipboard('Completed root effect');draft.setTemplateTag('selected','Cyclic helper');context.addSuccessParameter('discard','value');"]),
            ActionStep("includeAction", ["name": "[[selected]]"]),
            ActionStep("script", ["script": "editor.setText('Must not run');"])
        ])
        root.afterSuccess = "archive"
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.reason == .error && report.successParameters.isEmpty)
        #expect(f.runner.message?.contains("itself") == true)
        #expect(f.host.clipboard == "Completed root effect")
        #expect(f.host.calls.filter { $0.0 == "clipboard" }.count == 1)
        #expect(f.editor.content == "Source" && f.library.notes.first?.isArchived == false)
    }
}
