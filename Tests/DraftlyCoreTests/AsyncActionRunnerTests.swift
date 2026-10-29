import Foundation
import Testing
@testable import DraftlyCore

@Suite("Asynchronous action execution") @MainActor
struct AsyncActionRunnerTests {
    @Test func completionSuspendsWithoutBlockingMainActorAndPreservesSharedState() async throws {
        let f = try ScriptTestFixture(content: "Source 🐼", host: APIContractHost())
        let action = DraftAction(name: "Delayed", steps: [
            ActionStep("script", ["allowAsync": "true", "script": "var shared='Kept';setTimeout(()=>{editor.setText(shared+' 🐼');script.complete();script.complete();},40);"]),
            ActionStep("script", ["script": "if(shared!=='Kept')throw new Error('lost state');context.addSuccessParameter('value','café');"])
        ])
        let task = Task { await f.runner.runAsync(action) }
        try await Task.sleep(for: .milliseconds(10))
        #expect(f.runner.isRunning)
        #expect(f.editor.content == "Source 🐼")
        let report = await task.value
        #expect(report.result == .success && report.reason == .success)
        #expect(report.successParameters == ["value": "café"])
        #expect(f.editor.content == "Kept 🐼" && f.library.notes.first?.content == f.editor.content)
        #expect(!f.runner.isRunning && f.runner.activeSession == nil)
    }

    @Test func busyJavaScriptLeavesMainActorAvailableAndSynchronousDeadlineIsTyped() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        let started = AsyncStream.makeStream(of: Bool.self)
        f.host.onPerform = { operation in if operation == "clipboard" { started.continuation.yield(true) } }
        let task = Task { await f.runner.runAsync(ScriptTestAction.make("app.setClipboard('Started');var until=Date.now()+100;while(Date.now()<until){}", name: "CPU work")) }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(f.runner.isRunning)
        #expect(await task.value.result == .success)
        f.runner.synchronousScriptTimeout = 0.02
        let report = await f.runner.runAsync(ScriptTestAction.make("while(true){}", name: "CPU deadline"))
        #expect(report.reason == .timeout && !report.result.succeeded)
        #expect(f.editor.content == "Keep")
    }

    @Test func successfulQueueLoadsTheQueuedDraftAndSharesTheFinalReport() async throws {
        let f = try ScriptTestFixture(content: "Root", host: APIContractHost())
        let target = try f.library.createNote(content: "Target")
        let queued = ScriptTestAction.make("editor.setText('Queued 🐼');context.addSuccessParameter('queued','yes');", name: "Queued success")
        try f.library.saveAction(queued)
        let action = ScriptTestAction.make("app.queueAction(Action.find('Queued success'),Draft.find('\(target.id.uuidString)'));", name: "Queue root")
        let report = await f.runner.runAsync(action)
        #expect(report.result == .success && report.actionID == action.id)
        #expect(report.successParameters == ["queued": "yes"])
        #expect(f.editor.noteID == target.id && f.editor.content == "Queued 🐼")
        #expect(f.library.notes.first { $0.id == target.id }?.content == "Queued 🐼")
        #expect(f.runner.queued.isEmpty)
    }

    @Test func cancellationReleasesAnIdleScriptAndPreservesCompletedEffects() async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        var action = ScriptTestAction.make("app.setClipboard('Completed');setTimeout(()=>{editor.setText('Late');script.complete();},10000);", name: "Cancel", allowAsync: true)
        action.steps.append(ActionStep("insertText", ["template": "Must not run"]))
        action.afterSuccess = "archive"
        var finalReport: ActionExecutionReport?
        let task = Task { let report = await f.runner.runAsync(action); finalReport = report; return report }
        defer { task.cancel() }
        try await waitUntil({ f.host.clipboard == "Completed" || finalReport != nil },
            diagnostic: { "Wait expired; runner active: \(f.runner.isRunning), step: \(String(describing: f.runner.activeSession?.currentStep?.type)), host calls: \(f.host.calls.map(\.0)), report: \(String(describing: finalReport))" })
        try #require(f.host.clipboard == "Completed", Comment(rawValue: "Execution ended before the clipboard write: \(String(describing: finalReport))"))
        task.cancel()
        let report = await task.value
        #expect(report.result == .cancelled && report.reason == .cancelled)
        #expect(f.host.clipboard == "Completed")
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
        #expect(f.runner.queued.isEmpty && report.successParameters.isEmpty)
    }

    @Test func timeoutAndRejectedPromisesStopLaterStepsAndSuccessEffects() async throws {
        for source in ["void 0;", "Promise.reject(new Error('Rejected'));", "script.complete();context.fail('Failed after complete');"] {
            let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
            f.runner.scriptTimeout = 0.03
            var action = ScriptTestAction.make(source, name: "Failure", allowAsync: true)
            action.afterSuccess = "archive"
            action.steps.append(ActionStep("clipboard", ["template": "Must not run"]))
            let report = await f.runner.runAsync(action)
            #expect(!report.result.succeeded)
            #expect(report.reason == (source == "void 0;" ? .timeout : .error))
            #expect(f.host.clipboard.isEmpty && f.library.notes.first?.isArchived == false)
            #expect(f.library.runs.last?.status == "Error")
        }
    }

    @Test func stepTimersAndOldScriptHandlesCannotCompleteLaterStepsOrRuns() async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        f.runner.scriptTimeout = 0.04
        let action = DraftAction(name: "Isolation", steps: [
            ActionStep("script", ["allowAsync": "true", "script": "var old=script;setTimeout(()=>editor.setText('Late'),15);script.complete();"]),
            ActionStep("script", ["allowAsync": "true", "script": "old.complete();"])
        ])
        #expect(await f.runner.runAsync(action).reason == .timeout)
        #expect(f.editor.content == "Source")
        #expect(await f.runner.runAsync(ScriptTestAction.make("editor.setText('Next');", name: "Next")).result == .success)
        #expect(f.editor.content == "Next")
    }

    @Test func libraryExclusionCoversLegacyAndAsyncRunnersWithoutBlockingOtherLibraries() async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        let other = ActionRunner(library: f.library, editor: f.editor, host: f.host)
        var finalReport: ActionExecutionReport?
        let task = Task {
            let report = await f.runner.runAsync(ScriptTestAction.make("app.setClipboard('Started');setTimeout(()=>script.complete(),100);", name: "Hold", allowAsync: true))
            finalReport = report; return report
        }
        defer { task.cancel() }
        try await waitUntil({ f.host.clipboard == "Started" || finalReport != nil },
            diagnostic: { "Wait expired; runner active: \(f.runner.isRunning), step: \(String(describing: f.runner.activeSession?.currentStep?.type)), host calls: \(f.host.calls.map(\.0)), report: \(String(describing: finalReport))" })
        try #require(f.host.clipboard == "Started", Comment(rawValue: "Execution ended before the clipboard write: \(String(describing: finalReport))"))
        #expect(other.runReport(ScriptTestAction.make("", name: "Legacy")).reason == .busy)
        #expect(await other.runAsync(ScriptTestAction.make("", name: "Other")).reason == .busy)
        let independent = try ScriptTestFixture(content: "Independent", host: APIContractHost())
        #expect(await independent.runner.runAsync(ScriptTestAction.make("", name: "Independent")).result == .success)
        #expect(await task.value.result == .success)
    }

    @Test func includedStepsShareContextAndQueueStopsAfterCancellation() async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        let included = ScriptTestAction.make("shared+=' included';", name: "Included")
        let queued = ScriptTestAction.make("editor.setText('Must not run');", name: "Queued")
        try f.library.saveAction(included)
        try f.library.saveAction(queued)
        let action = DraftAction(name: "Includes", steps: [
            ActionStep("script", ["script": "var shared='Root';"]),
            ActionStep("includeAction", ["name": included.name]),
            ActionStep("script", ["script": "if(shared!=='Root included')throw new Error('shared context');app.queueAction(Action.find('Queued'),draft);context.cancel();"])
        ])
        #expect(await f.runner.runAsync(action).result == .cancelled)
        #expect(f.editor.content == "Source" && f.runner.queued.isEmpty)
    }

    @Test(arguments: [false, true]) func dynamicIncludesShareVariablesConfigurationAndRootDisposition(asynchronous: Bool) async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        var included = DraftAction(name: "Selected helper", steps: [
            ActionStep("configurationKey", ["key": "count", "dataType": "number", "defaultNumberValue": "7"]),
            ActionStep("script", ["script": "if(context.configuredValues.count!==7)throw new Error('configuration');shared+=' child';"])
        ])
        included.afterSuccess = "trash"
        try f.library.saveAction(included)
        let action = DraftAction(name: "Dynamic include", steps: [
            ActionStep("script", ["script": "var shared='Root';draft.setTemplateTag('helper','Selected helper');"]),
            ActionStep("includeAction", ["name": "[[helper]]"]),
            ActionStep("script", ["script": "if(shared!=='Root child')throw new Error('context');editor.setText(shared);"])
        ])
        let result = asynchronous ? await f.runner.runAsync(action).result : f.runner.runResult(action)
        #expect(result == .success)
        #expect(f.editor.content == "Root child" && f.library.notes.first?.trashedAt == nil)
    }

    @Test(arguments: [false, true]) func dynamicCyclesStopWithoutRepeatingEffects(asynchronous: Bool) async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        let action = DraftAction(name: "Cycle root", steps: [
            ActionStep("script", ["script": "app.setClipboard('Completed once');draft.setTemplateTag('loop','Cycle root');"]),
            ActionStep("includeAction", ["name": "[[loop]]"])
        ])
        try f.library.saveAction(action)
        let result = asynchronous ? await f.runner.runAsync(action).result : f.runner.runResult(action)
        #expect(!result.succeeded)
        #expect(f.host.calls.filter { $0.0 == "clipboard" }.count == 1)
        #expect(f.runner.message?.contains("itself") == true)
        #expect(f.editor.content == "Source")
    }

    @Test(arguments: [false, true]) func headlessActionDoesNotOverwriteConcurrentEditsOrRecreateDeletedDraft(deleted: Bool) async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        let target = try f.library.createNote(content: "Original target")
        let library = f.library
        var external = target; external.content = "External text"
        let changed = external
        f.host.onPerform = { operation in
            if operation == "clipboard" {
                do {
                    if deleted {
                        var trashed = target; trashed.trashedAt = Date()
                        try library.saveNote(trashed); try library.emptyTrash()
                    } else { try library.saveNote(changed) }
                } catch { Issue.record(error) }
            }
        }
        let action = ScriptTestAction.make("var target=Draft.find('\(target.id.uuidString)');app.setClipboard('Cached');setTimeout(()=>{target.content='Stale';target.update();script.complete();},0);", name: "Concurrent target", allowAsync: true)
        #expect(await f.runner.runAsync(action).reason == .cancelled)
        #expect(f.library.notes.first { $0.id == target.id }?.content == (deleted ? nil : "External text"))
        #expect(f.editor.content == "Source")
    }

    @Test(arguments: [false, true]) func staleHeadlessEditorCannotOverwriteTextBeforeTheFirstStep(pendingEdits: Bool) async throws {
        let f = try ScriptTestFixture(content: "Old source", host: APIContractHost())
        var stored = try #require(f.library.notes.first)
        stored.content = "New stored text"; try f.library.saveNote(stored)
        if pendingEdits { f.editor.content = "Unsaved local text" }
        let report = await f.runner.runAsync(ScriptTestAction.make("app.setClipboard('Must not run');", name: "Stale source"))
        #expect(report.reason == .cancelled)
        #expect(f.library.notes.first?.content == "New stored text")
        #expect(f.editor.content == (pendingEdits ? "Unsaved local text" : "New stored text"))
        #expect(f.host.clipboard.isEmpty)
    }

    @Test func unknownEnabledStepsFailBeforeEffectsAndDisabledStepsRemainIntact() async throws {
        let f = try ScriptTestFixture(content: "Source", host: APIContractHost())
        var unknown = ActionStep("futureStep", ["payload": "Keep"])
        var action = DraftAction(name: "Unknown", steps: [ActionStep("clipboard", ["template": "Must not run"]), unknown])
        #expect(await f.runner.runAsync(action).reason == .error)
        #expect(f.host.clipboard.isEmpty)
        unknown.isEnabled = false
        action.steps = [unknown, ActionStep("clipboard", ["template": "Allowed"])]
        #expect(await f.runner.runAsync(action).result == .success)
        #expect(f.host.clipboard == "Allowed" && action.steps.first?.values["payload"] == "Keep")
    }
    private func waitUntil(_ condition: () -> Bool, diagnostic: () -> String) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(condition(), Comment(rawValue: diagnostic()))
    }

}
