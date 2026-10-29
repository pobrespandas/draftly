import Foundation
import Testing
@testable import DraftlyCore

@Suite("Engine inclusion acceptance") @MainActor
struct EngineInclusionAcceptanceTests {
    @Test(arguments: [false, true], ["uuid", "template"])
    func includedTimeoutKeepsCompletedEffectsAndCannotLeakIntoTheNextExecution(asynchronous: Bool, reference: String) async throws {
        let f = try ScriptTestFixture(content: "Original 🐼", host: APIContractHost())
        f.runner.scriptTimeout = 0.05
        let queued = ScriptTestAction.make("editor.setText('Queued late');", name: "Queued after timeout")
        let child = ScriptTestAction.make("setTimeout(()=>{editor.setText('Old timer');script.complete();},150);", name: "Slow child", allowAsync: true)
        try f.library.saveAction(queued); try f.library.saveAction(child)
        let referenceValues = reference == "uuid" ? ["uuid": child.id.uuidString] : ["name": "[[selected]]"]
        var root = DraftAction(name: "Root timeout", steps: [
            ActionStep("script", ["script": "editor.setText('Retained 🐼');draft.update();draft.setTemplateTag('selected','Slow child');context.addSuccessParameter('drop','yes');app.queueAction(Action.find('Queued after timeout'),draft);"]),
            ActionStep("includeAction", referenceValues),
            ActionStep("script", ["script": "editor.setText('Root late');"])
        ])
        root.afterSuccess = "archive"
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.reason == .timeout && report.successParameters.isEmpty)
        #expect(f.editor.content == "Retained 🐼" && f.library.notes.first?.content == "Retained 🐼")
        #expect(f.library.notes.first?.isArchived == false && f.runner.queued.isEmpty)
        #expect(f.library.runs.count == 1 && f.library.runs.first?.actionID == root.id && f.library.runs.first?.status == "Error")
        let recovery = asynchronous
            ? await f.runner.runAsync(ScriptTestAction.make("editor.setText('Recovery 🐼');", name: "Recovery"))
            : f.runner.runReport(ScriptTestAction.make("editor.setText('Recovery 🐼');", name: "Recovery"))
        #expect(recovery.reason == .success && recovery.executionID != report.executionID)
        try await Task.sleep(for: .milliseconds(200))
        #expect(f.editor.content == "Recovery 🐼" && f.library.notes.first?.content == "Recovery 🐼")
        #expect(f.library.runs.count == 2)
    }
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
    @Test(arguments: [false, true], ["name", "uuid", "template"])
    func includedStepsKeepTheirOwnerAndOneExecutionIdentity(asynchronous: Bool, reference: String) async throws {
        let childName = "Child café 🐼"
        let f = try ScriptTestFixture(content: childName, host: APIContractHost())
        let leafStep = ActionStep("script", ["script": "app.setClipboard('Leaf');"])
        let leaf = DraftAction(name: "Nested leaf", steps: [leafStep])
        let childPrefix = ActionStep("script", ["script": "app.setClipboard('Child prefix');"])
        let childSuffix = ActionStep("clipboard", ["template": "Child suffix"])
        let child = DraftAction(name: childName, steps: [childPrefix,
            ActionStep("includeAction", ["uuid": leaf.id.uuidString]), childSuffix])
        try f.library.saveAction(leaf); try f.library.saveAction(child)
        let values = reference == "uuid" ? ["uuid": child.id.uuidString]
            : ["name": reference == "template" ? "[[title]]" : childName]
        let prefix = ActionStep("clipboard", ["template": "Root prefix"])
        let suffix = ActionStep("script", ["script": "app.setClipboard('Root suffix');"])
        let root = DraftAction(name: "Owner identity", steps: [prefix,
            ActionStep("includeAction", values), suffix])
        var observed: [ActionExecutionStep] = []
        var executions: [UUID] = []
        f.host.onPerform = { [weak runner = f.runner] operation in
            guard operation == "clipboard", let session = runner?.activeSession,
                  let step = session.currentStep else { return }
            observed.append(step)
            executions.append(session.id)
        }
        defer { f.host.onPerform = nil }
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.reason == .success && report.actionID == root.id)
        #expect(observed.map(\.actionID) == [root.id, child.id, leaf.id, child.id, root.id])
        #expect(observed.map(\.stepID) == [prefix.id, childPrefix.id, leafStep.id, childSuffix.id, suffix.id])
        #expect(observed.map(\.index) == [0, 2, 4, 5, 6])
        #expect(observed.map(\.type) == ["clipboard", "script", "script", "clipboard", "script"])
        #expect(executions == Array(repeating: report.executionID, count: 5))
        #expect(f.host.calls.filter { $0.0 == "clipboard" }.compactMap { $0.1["text"] as? String }
            == ["Root prefix", "Child prefix", "Leaf", "Child suffix", "Root suffix"])
        #expect(f.library.runs.count == 1 && f.library.runs.first?.actionID == root.id)
    }

}
