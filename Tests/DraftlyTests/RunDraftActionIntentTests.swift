import AppIntents
import Foundation
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
