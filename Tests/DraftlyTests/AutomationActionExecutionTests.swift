import Combine
import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Automation action editor safety") @MainActor
struct AutomationActionExecutionTests {
    @Test(arguments: [false, true]) func conflictingPendingEditorsDoNotOverwriteEachOtherOrStartAction(reverse: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let first = WindowModel(library: library), second = WindowModel(library: library)
        first.select(note.id); second.select(note.id)
        first.editor.content = "First pending 🐼"; first.contentChanged()
        second.editor.content = "Second pending café"; second.contentChanged()
        let action = DraftAction(name: "Must not run", steps: [ActionStep("script", ["script": "editor.setText('Action ran');"])])
        let models = reverse ? [second, first] : [first, second]
        do {
            _ = try await AutomationActionExecution.run(action, noteID: note.id, library: library, models: models, host: first.host)
            Issue.record("Automation started with conflicting pending editors.")
        } catch {
            #expect(error.localizedDescription.contains("conflicting"))
        }
        try await Task.sleep(for: .milliseconds(650))
        #expect(first.editor.content == "First pending 🐼" && first.hasUnsavedChanges)
        #expect(second.editor.content == "Second pending café" && second.hasUnsavedChanges)
        #expect(library.notes.first?.content == "Stored" && library.runs.isEmpty)
    }
    @Test func identicalPendingEditorsCanRunAutomation() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let first = WindowModel(library: library), second = WindowModel(library: library)
        first.select(note.id); second.select(note.id)
        first.editor.content = "Same 🐼"; first.contentChanged()
        second.editor.content = "Same 🐼"; second.contentChanged()
        let action = DraftAction(name: "Append", steps: [ActionStep("script", ["script": "draft.content+=' done';draft.update();"])])
        let output = try await AutomationActionExecution.run(action, noteID: note.id, library: library, models: [first, second], host: first.host)
        #expect(output.report.reason == .success)
        #expect(library.notes.first?.content == "Same 🐼 done")
    }
    private func delayedAction() -> DraftAction {
        DraftAction(name: "Delayed automation", steps: [
            ActionStep("script", ["allowAsync": "true", "script": "draft.addTag('waiting');draft.update();"]),
            ActionStep("insertText", ["template": "Stale"])
        ])
    }

    private func startAndWaitForAction(_ library: LibraryStore, id: UUID,
        run: @escaping @MainActor () async throws -> AutomationActionExecution.Output
    ) async throws -> Task<AutomationActionExecution.Output, Error> {
        let ready = AsyncStream.makeStream(of: Bool.self)
        let subscription = library.$notes.sink { notes in
            if notes.first(where: { $0.id == id })?.tags.contains("waiting") == true {
                ready.continuation.yield(true)
            }
        }
        let task = Task {
            defer { ready.continuation.finish() }
            return try await run()
        }
        var iterator = ready.stream.makeAsyncIterator()
        let started = await iterator.next()
        subscription.cancel()
        guard started == true else {
            task.cancel()
            _ = try await task.value
            throw DraftlyError.message("Automation ended before its ready signal.")
        }
        return task
    }

    @Test func pendingVisibleEditsAreSavedBeforeAutomationLoadsTheDraft() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let model = WindowModel(library: library); model.select(note.id)
        model.editor.content = "Pending"; model.contentChanged()
        let action = DraftAction(name: "Append", steps: [ActionStep("script", ["script": "draft.content+=' done';draft.update();"])])
        let output = try await AutomationActionExecution.run(action, noteID: note.id, library: library, models: [model], host: model.host)
        #expect(output.report.reason == .success)
        #expect(library.notes.first { $0.id == note.id }?.content == "Pending done")
    }

    @Test func ownNativeTextAndDraftCreationDoNotCancelAutomation() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let host = NativeActionHost()
        let action = DraftAction(name: "Native editor changes", steps: [
            ActionStep("insertText", ["template": "Native "]),
            ActionStep("createDraft", ["template": "Created", "openInEditor": "true"])
        ])
        let output = try await AutomationActionExecution.run(action, noteID: note.id, library: library, models: [], host: host)
        #expect(output.report.reason == .success)
        #expect(library.notes.first { $0.id == note.id }?.content == "Native Stored")
        #expect(library.notes.first { $0.id == output.noteID }?.content == "Created")
    }

    @Test func failedVisibleSavePreventsAutomation() async throws {
        enum Failure: Error { case save }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let model = WindowModel(library: library, saveDraft: { _ in throw Failure.save }); model.select(note.id)
        model.editor.content = "Pending"; model.contentChanged()
        do {
            _ = try await AutomationActionExecution.run(delayedAction(), noteID: note.id, library: library, models: [model], host: model.host)
            Issue.record("Automation started after a failed save.")
        } catch { }
        #expect(library.runs.isEmpty)
        #expect(library.notes.first { $0.id == note.id }?.content == "Stored")
        #expect(model.editor.content == "Pending")
    }

    @Test(arguments: [false, true])
    func visibleTypingCancelsAutomationAndRetainsTheNewText(queued: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let target = queued ? try library.createNote(content: "Queued target") : note
        let model = WindowModel(library: library); model.select(note.id)
        let action: DraftAction
        if queued {
            let child = delayedAction()
            try library.saveAction(child)
            let later = DraftAction(name: "Later queued sentinel", steps: [ActionStep("insertText", ["template": "Stale queue"])])
            try library.saveAction(later)
            action = DraftAction(name: "Queue owner", steps: [ActionStep("script", ["script":
                "app.queueAction(Action.find('Delayed automation'),Draft.find('\(target.id.uuidString)'));app.queueAction(Action.find('Later queued sentinel'),draft);"])])
        } else { action = delayedAction() }
        let task = try await startAndWaitForAction(library, id: target.id) {
            try await AutomationActionExecution.run(action, noteID: note.id, library: library, models: [model], host: model.host,
                resolveModel: { models, _ in models.first })
        }
        #expect(model.editor.noteID == target.id)
        model.editor.content = "User text"; model.contentChanged()
        let output = try await task.value
        #expect(output.report.reason == .cancelled)
        #expect(model.editor.content == "User text")
        #expect(library.notes.first { $0.id == target.id }?.content == "User text")
        if queued { #expect(library.notes.first { $0.id == note.id }?.content == "Stored") }
    }

    @Test func externalStoredTextCancelsAutomationWithoutAnOpenWindow() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let host = NativeActionHost()
        let task = try await startAndWaitForAction(library, id: note.id) {
            try await AutomationActionExecution.run(delayedAction(), noteID: note.id, library: library, models: [], host: host)
        }
        var external = try #require(library.notes.first { $0.id == note.id })
        external.content = "External"; try library.saveNote(external)
        let output = try await task.value
        #expect(output.report.reason == .cancelled)
        #expect(library.notes.first { $0.id == note.id }?.content == "External")
    }
}
