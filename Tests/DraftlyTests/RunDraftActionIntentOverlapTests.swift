import AppIntents
import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Overlapping automation and window actions") @MainActor
struct RunDraftActionIntentOverlapTests {
    @Test(arguments: ["intent", "window async", "window scheduled", "batch async", "batch scheduled"])
    func headlessOwnerRejectsOtherEntryPointsBeforeTheySavePendingWindowEdits(access: String) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "Owner source")
        let target = try library.createNote(content: "Stored target")
        let waiting = DraftAction(name: "Headless owner", steps: [ActionStep("script", ["allowAsync": "true", "script": "app.setClipboard('Owner waiting');"])])
        let rejected = DraftAction(name: "Rejected overlap", steps: [ActionStep("script", ["script": "editor.setText('ERROR: overlapping execution');"])])
        try library.saveActions([waiting, rejected])
        let host = IntentOverlapMarkerHost()
        var owner = RunDraftActionIntent()
        owner.name = waiting.name; owner.uuid = source.id.uuidString
        owner.executionEnvironment = RunActionIntentEnvironment(library: library, models: [], host: host)
        let ownerTask = Task { try await owner.perform() }
        defer { ownerTask.cancel() }
        var started = host.started.stream.makeAsyncIterator()
        #expect(await started.next() == true)
        var saves = 0
        let model = WindowModel(library: library, saveDraft: { note in saves += 1; try library.saveNote(note) })
        model.select(target.id)
        model.editor.content = "Pending target"; model.hasUnsavedChanges = true
        var second = RunDraftActionIntent()
        second.name = rejected.name; second.uuid = target.id.uuidString
        second.executionEnvironment = RunActionIntentEnvironment(library: library, models: [model], host: host,
            resolveModel: { models, _ in models.first })
        if access == "intent" {
            do {
                _ = try await second.perform()
                Issue.record("The overlapping intent must report a busy library.")
            } catch { #expect(try #require(error as? AutomationActionError).reason == .busy) }
        } else if access == "window async" {
            let report = try #require(await model.runAsync(rejected))
            #expect(report.reason == .busy && report.actionID == rejected.id)
            #expect(report.successParameters.isEmpty)
        } else if access == "batch async" {
            await model.runActionAsync(rejected, on: [source.id, target.id])
            #expect(model.status == "An action is already running in this library.")
        } else if access == "batch scheduled" {
            model.runAction(rejected, on: [source.id, target.id])
            await model.actionTask?.value
            #expect(model.status == "An action is already running in this library.")
            #expect(!model.actionPending && model.actionTask == nil)
        } else {
            model.run(rejected)
            await model.actionTask?.value
            #expect(model.status == "An action is already running in this library.")
            #expect(!model.actionPending && model.actionTask == nil)
        }
        #expect(saves == 0 && model.hasUnsavedChanges && model.editor.content == "Pending target")
        #expect(model.editor.noteID == target.id)
        #expect(library.notes.first(where: { $0.id == target.id })?.content == "Stored target")
        #expect(model.runner.lastReport == nil && library.runs.isEmpty)
        ownerTask.cancel()
        do {
            _ = try await ownerTask.value
            Issue.record("The headless owner must return its cancellation.")
        } catch { #expect(try #require(error as? AutomationActionError).reason == .cancelled) }
        #expect(host.finishes == 1)
        #expect(library.notes.first(where: { $0.id == source.id })?.content == "Owner source")
        #expect(library.runs.count == 1 && library.runs.first?.actionID == waiting.id)
        #expect(library.runs.first?.status == "Cancelled")
        #expect(saves == 0 && model.hasUnsavedChanges)
    }
}

@MainActor private final class IntentOverlapMarkerHost: ActionHost {
    let started = AsyncStream.makeStream(of: Bool.self)
    private(set) var finishes = 0
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "device" { return [String: Any]() }
        if operation == "clipboard" { started.continuation.yield(true); return true }
        throw DraftlyError.message("Unexpected overlap test host operation: " + operation)
    }
    func finishAction() { finishes += 1 }
}
