import AppIntents
import Foundation
import Darwin
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Run action intent execution") @MainActor
struct RunDraftActionIntentTests {
    private func intent(_ action: DraftAction, note: Note, library: LibraryStore,
                        models: [WindowModel] = [], host: any ActionHost) -> RunDraftActionIntent {
        var intent = RunDraftActionIntent()
        intent.name = action.name; intent.uuid = note.id.uuidString
        intent.executionEnvironment = RunActionIntentEnvironment(library: library, models: models, host: host,
            resolveModel: { models, id in models.first { $0.editor.noteID == id } })
        return intent
    }

    @Test func conflictingPendingWindowsRejectIntentWithoutSavingOrRunning() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let first = WindowModel(library: library), second = WindowModel(library: library)
        first.select(note.id); second.select(note.id)
        first.editor.content = "First 🐼"; first.contentChanged()
        second.editor.content = "Second café"; second.contentChanged()
        let action = DraftAction(name: "Must not run", steps: [ActionStep("script", ["script": "editor.setText('Action ran');"])])
        try library.saveAction(action)
        do {
            _ = try await intent(action, note: note, library: library, models: [first, second], host: IntentMarkerHost()).perform()
            Issue.record("The intent ran with conflicting pending edits.")
        } catch { #expect(error.localizedDescription.contains("conflicting")) }
        try await Task.sleep(for: .milliseconds(650))
        #expect(first.editor.content == "First 🐼" && first.hasUnsavedChanges)
        #expect(second.editor.content == "Second café" && second.hasUnsavedChanges)
        #expect(library.notes.first?.content == "Stored" && library.runs.isEmpty)
    }

    @Test func actualPerformReturnsAValueAfterSavingTheScriptResult() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let action = DraftAction(name: "Intent success", steps: [ActionStep("script", ["script": "editor.setText('Intent café 🐼');"])])
        try library.saveAction(action)
        let result = try await intent(action, note: note, library: library, host: IntentMarkerHost()).perform()
        #expect(result.value == "Intent success completed")
        #expect(library.notes.first(where: { $0.id == note.id })?.content == "Intent café 🐼")
        #expect(library.runs.count == 1 && library.runs.first?.status == "Success")
    }

    @Test(arguments: [false, true])
    func actualPerformThrowsTheFinalWorkerTimeout(cpuBound: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let model = WindowModel(library: library); model.select(note.id); model.runner.scriptTimeout = 0.02; model.runner.synchronousScriptTimeout = 0.02
        model.editor.selection = NSRange(location: 0, length: note.content.utf16.count)
        let action = DraftAction(name: "Intent timeout", steps: [
            ActionStep("insertText", ["template": "Retained before timeout"]),
            ActionStep("script", ["allowAsync": cpuBound ? "false" : "true", "script": cpuBound ? "while(true){}" : "void 0;"])
        ])
        try library.saveAction(action)
        do {
            _ = try await intent(action, note: note, library: library, models: [model], host: IntentMarkerHost()).perform()
            Issue.record("The intent must throw its final timeout.")
        } catch {
            let error = try #require(error as? AutomationActionError)
            #expect(error.reason == .timeout && error.executionID == model.runner.lastReport?.executionID)
        }
        #expect(library.notes.first(where: { $0.id == note.id })?.content == "Retained before timeout")
    }

    @Test func busyIntentDoesNotFlushPendingEditsOrRunSteps() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        var saves = 0
        let model = WindowModel(library: library, saveDraft: { note in saves += 1; try library.saveNote(note) })
        model.select(note.id); model.editor.content = "Pending"; model.hasUnsavedChanges = true; model.actionPending = true
        defer { model.actionPending = false }
        let action = DraftAction(name: "Intent busy", steps: [ActionStep("script", ["script": "editor.setText('ERROR: busy execution');"])])
        try library.saveAction(action)
        do {
            _ = try await intent(action, note: note, library: library, models: [model], host: IntentMarkerHost()).perform()
            Issue.record("The intent must report a busy library.")
        } catch { #expect(try #require(error as? AutomationActionError).reason == .busy) }
        #expect(saves == 0 && model.editor.content == "Pending" && model.hasUnsavedChanges)
        #expect(library.notes.first(where: { $0.id == note.id })?.content == "Stored" && library.runs.isEmpty)
    }

    @Test(arguments: [false, true])
    func failedPendingSaveRejectsIntentAndCanRecover(otherDraft: Bool) async throws {
        struct SaveFailure: LocalizedError {
            var errorDescription: String? { "Neutral storage failure café 🐼" }
        }
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Target")
        let pending = otherDraft ? try library.createNote(content: "Other stored") : target
        var rejectSave = false
        let model = WindowModel(library: library, saveDraft: { note in
            if rejectSave { throw SaveFailure() }
            try library.saveNote(note)
        })
        model.select(pending.id)
        model.editor.content = "Pending café 🐼"; model.hasUnsavedChanges = true
        rejectSave = true
        let action = DraftAction(name: "Intent save boundary", steps: [ActionStep("script", ["script": "editor.setText('Intent recovered');"])])
        try library.saveAction(action)
        let request = intent(action, note: target, library: library, models: [model], host: IntentMarkerHost())
        do { _ = try await request.perform(); Issue.record("The intent started after a failed pending save.") }
        catch { #expect(error.localizedDescription == "Pending edits could not be saved. The action was not started.") }
        #expect(library.error == "Neutral storage failure café 🐼")
        #expect(model.editor.content == "Pending café 🐼" && model.hasUnsavedChanges)
        #expect(model.editor.noteID == pending.id)
        #expect(library.notes.first { $0.id == pending.id }?.content == pending.content)
        #expect(library.runs.isEmpty && !model.actionPending && !model.runner.isRunning)
        #expect(!ActionRunner.isExecuting(in: library))
        rejectSave = false
        _ = try await request.perform()
        #expect(library.runs.count == 1 && library.runs.first?.status == "Success")
        #expect(library.notes.first { $0.id == target.id }?.content == "Intent recovered")
        if otherDraft { #expect(library.notes.first { $0.id == pending.id }?.content == "Pending café 🐼") }
    }

    @Test func invalidTargetsFailWithoutExecution() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let action = DraftAction(name: "Present", steps: [])
        try library.saveAction(action)
        for invalid in ["uuid", "missing note", "name", "library"] {
            var request = intent(action, note: note, library: library, host: IntentMarkerHost())
            if invalid == "uuid" { request.uuid = "invalid" }
            else if invalid == "missing note" { request.uuid = UUID().uuidString }
            else if invalid == "library" { request.executionEnvironment = RunActionIntentEnvironment(library: nil, models: [], host: IntentMarkerHost()) }
            else { request.name = "Missing" }
            do { _ = try await request.perform(); Issue.record("The invalid intent target must fail.") }
            catch { #expect(error.localizedDescription.contains("not found")) }
        }
        #expect(library.notes.first?.content == "Neutral" && library.runs.isEmpty)
    }

    @Test func cancellationWhileWorkerWaitsThrowsTheFinalCancellation() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let action = DraftAction(name: "Intent cancellation", steps: [ActionStep("script", ["allowAsync": "true", "script": "editor.setText('Retained before cancellation');draft.update();app.setClipboard('Waiting');"])])
        try library.saveAction(action)
        let host = IntentMarkerHost()
        let request = intent(action, note: note, library: library, host: host)
        let task = Task { try await request.perform() }
        var events = host.started.stream.makeAsyncIterator()
        #expect(await events.next() == true)
        task.cancel()
        do { _ = try await task.value; Issue.record("The waiting intent must cancel.") }
        catch { #expect(try #require(error as? AutomationActionError).reason == .cancelled) }
        #expect(library.notes.first?.content == "Retained before cancellation")
        #expect(library.runs.count == 1 && library.runs.first?.status == "Cancelled")
    }

    @Test func explicitScriptFailureRetainsCompletedEffectsAndStopsSuccessDisposition() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        var action = DraftAction(name: "Intent script failure", steps: [
            ActionStep("script", ["script": "editor.setText('Retained before failure');draft.update();context.addSuccessParameter('discard','value');context.fail('Neutral intent failure');"]),
            ActionStep("insertText", ["template": "ERROR: failure tail ran"])
        ])
        action.afterSuccess = "archive"
        try library.saveAction(action)
        do {
            _ = try await intent(action, note: note, library: library, host: IntentMarkerHost()).perform()
            Issue.record("The intent must throw the script failure.")
        } catch {
            let error = try #require(error as? AutomationActionError)
            #expect(error.reason == .error && error.localizedDescription == "Neutral intent failure")
        }
        #expect(library.notes.first?.content == "Retained before failure")
        #expect(library.notes.first?.isArchived == false)
        #expect(library.runs.count == 1 && library.runs.first?.status == "Error")
    }

    @Test(arguments: [false, true])
    func includedCancellationStopsQueueAndAllowsFollowingIntent(template: Bool) async throws {
        try await verifyIncludedInterruption(template: template, failure: false)
    }

    @Test(arguments: [false, true])
    func includedFailureStopsQueueAndAllowsFollowingIntent(template: Bool) async throws {
        try await verifyIncludedInterruption(template: template, failure: true)
    }

    private func verifyIncludedInterruption(template: Bool, failure: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let model = WindowModel(library: library); model.select(note.id)
        let child = DraftAction(name: "Intent child café", steps: [
            ActionStep("script", ["script": "if (trace !== 'root') throw Error('missing context'); " + (failure ? "context.fail('Included failure café');" : "context.cancel();")]),
            ActionStep("script", ["script": "editor.setText('ERROR: child tail');"])
        ])
        let queued = DraftAction(name: "Intent queued sentinel", steps: [ActionStep("script", ["script": "editor.setText('ERROR: queue');"])])
        try library.saveAction(child); try library.saveAction(queued)
        let reference = template ? ["name": "[[child]]"] : ["uuid": child.id.uuidString]
        var root = DraftAction(name: "Intent include cancellation", steps: [
            ActionStep("script", ["script": "var trace='root';draft.setTemplateTag('child','Intent child café');editor.setText('Retained café 🐼');draft.update();app.queueAction(Action.find('Intent queued sentinel'),draft);context.addSuccessParameter('discard','yes');"]),
            ActionStep("includeAction", reference),
            ActionStep("script", ["script": "editor.setText('ERROR: root tail');"])
        ])
        root.afterSuccess = "archive"
        try library.saveAction(root)
        do {
            _ = try await intent(root, note: note, library: library, models: [model], host: IntentMarkerHost()).perform()
            Issue.record("The included interruption must reach the intent.")
        } catch {
            let error = try #require(error as? AutomationActionError)
            #expect(error.reason == (failure ? .error : .cancelled) && error.executionID == model.runner.lastReport?.executionID)
            if failure { #expect(error.localizedDescription == "Included failure café") }
        }
        let cancelled = try #require(model.runner.lastReport)
        #expect(cancelled.successParameters.isEmpty)
        let retained = try #require(library.notes.first { $0.id == note.id })
        #expect(retained.content == "Retained café 🐼" && !retained.isArchived)
        #expect(library.runs.count == 1 && library.runs.first?.status == (failure ? "Error" : "Cancelled"))
        let recovery = DraftAction(name: "Intent after include", steps: [ActionStep("script", ["script": "editor.setText('Recovered');"])])
        try library.saveAction(recovery)
        _ = try await intent(recovery, note: retained, library: library, models: [model], host: IntentMarkerHost()).perform()
        #expect(model.runner.lastReport?.reason == .success)
        #expect(model.runner.lastReport?.executionID != cancelled.executionID)
        #expect(library.notes.first { $0.id == note.id }?.content == "Recovered")
        #expect(library.runs.count == 2)
    }

    @Test(arguments: ["Promise.reject(new Error('Neutral rejection'));", "script.complete();context.fail('Neutral failure');"])
    func failedCompletionRetainsPriorWritesStopsTailAndAllowsFollowingIntent(_ source: String) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let model = WindowModel(library: library); model.select(note.id)
        var action = DraftAction(name: "Intent final failure", steps: [
            ActionStep("script", ["script": "editor.setText('Retained café 🐼');draft.update();context.addSuccessParameter('discard','yes');"]),
            ActionStep("script", ["allowAsync": "true", "script": source]),
            ActionStep("script", ["script": "editor.setText('ERROR: tail ran');"])
        ])
        action.afterSuccess = "archive"
        try library.saveAction(action)
        do {
            _ = try await intent(action, note: note, library: library, models: [model], host: IntentMarkerHost()).perform()
            Issue.record("The intent must report the final failure.")
        } catch {
            let error = try #require(error as? AutomationActionError)
            #expect(error.reason == .error && error.executionID == model.runner.lastReport?.executionID)
        }
        let failed = try #require(model.runner.lastReport)
        #expect(failed.successParameters.isEmpty)
        #expect(!model.actionPending && !model.runner.isRunning)
        let retained = try #require(library.notes.first { $0.id == note.id })
        #expect(retained.content == "Retained café 🐼" && !retained.isArchived)
        let next = DraftAction(name: "Intent recovery", steps: [ActionStep("script", ["script": "editor.setText('Recovery');"])])
        try library.saveAction(next)
        _ = try await intent(next, note: retained, library: library, models: [model], host: IntentMarkerHost()).perform()
        #expect(model.runner.lastReport?.reason == .success)
        #expect(model.runner.lastReport?.executionID != failed.executionID)
        #expect(library.notes.first { $0.id == note.id }?.content == "Recovery")
    }

    @Test(arguments: [false, true])
    func shellInterruptionWaitsForProcessCleanupBeforeIntentReturns(cancel: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("started")
        let shell = "trap '' TERM\n/bin/sleep 30 &\nchild=$!\nprintf '%s\\n%s\\n%s' \"$$\" \"$child\" \"$0\" > \"$1.pending\"\n/bin/mv \"$1.pending\" \"$1\"\nwait"
        func literal(_ value: String) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed), as: UTF8.self)
        }
        let script = try "editor.setText('Retained Intent shell café 🐼');draft.update();context.addSuccessParameter('discard','yes');const sh=ShellScript.create(" + literal(shell) + ");sh.execute([" + literal(marker.path) + "]);editor.setText('ERROR: shell continued');draft.update();"
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let model = WindowModel(library: library); model.select(note.id)
        model.runner.hostOperationTimeout = 2
        var action = DraftAction(name: "Intent shell interruption", steps: [
            ActionStep("script", ["script": script]),
            ActionStep("insertText", ["template": "ERROR: tail ran"])
        ])
        action.afterSuccess = "archive"
        try library.saveAction(action)
        let request = intent(action, note: note, library: library, models: [model], host: NativeActionHost())
        let task = Task { try await request.perform() }
        defer { task.cancel() }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let fields = try String(contentsOf: marker, encoding: .utf8).components(separatedBy: "\n")
        try #require(fields.count == 3)
        let parent = try #require(Int32(fields[0])), child = try #require(Int32(fields[1]))
        let shellFolder = URL(fileURLWithPath: fields[2]).deletingLastPathComponent()
        if cancel { task.cancel() }
        do { _ = try await task.value; Issue.record("The interrupted shell Intent succeeded.") }
        catch { #expect(try #require(error as? AutomationActionError).reason == (cancel ? .cancelled : .timeout)) }
        #expect(getpgid(parent) == -1)
        #expect(getpgid(child) == -1)
        #expect(!FileManager.default.fileExists(atPath: shellFolder.path))
        #expect(model.runner.lastReport?.successParameters.isEmpty == true)
        #expect(library.notes.first?.content == "Retained Intent shell café 🐼")
        #expect(library.notes.first?.isArchived == false)
        #expect(!ActionRunner.isExecuting(in: library))
        let recovery = DraftAction(name: "Intent shell recovery", steps: [ActionStep("script", ["script": "editor.setText('Recovered');draft.update();"])])
        try library.saveAction(recovery)
        _ = try await intent(recovery, note: note, library: library, models: [model], host: NativeActionHost()).perform()
        #expect(library.notes.first?.content == "Recovered")
        #expect(library.runs.count == 2)
        #expect(library.runs.first { $0.actionID == recovery.id }?.status == "Success")
        #expect(library.runs.first { $0.actionID == action.id }?.status == (cancel ? "Cancelled" : "Error"))
    }

    @Test func preCancelledIntentReturnsTypedCancellationWithoutEffects() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let action = DraftAction(name: "Intent pre-cancel", steps: [ActionStep("script", ["script": "editor.setText('ERROR: pre-cancel execution');"])])
        try library.saveAction(action)
        let request = intent(action, note: note, library: library, host: IntentMarkerHost())
        let task = Task { try await request.perform() }
        task.cancel()
        do { _ = try await task.value; Issue.record("The pre-cancelled intent must cancel.") }
        catch { #expect(try #require(error as? AutomationActionError).reason == .cancelled) }
        #expect(library.notes.first?.content == "Neutral" && library.runs.isEmpty)
    }
}

@MainActor private final class IntentMarkerHost: ActionHost {
    let started = AsyncStream.makeStream(of: Bool.self)
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "device" { return [String: Any]() }
        if operation == "clipboard" { started.continuation.yield(true); return true }
        throw DraftlyError.message("Unexpected intent test host operation: " + operation)
    }
}
