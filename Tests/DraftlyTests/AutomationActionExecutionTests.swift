import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Automation action editor safety") @MainActor
struct AutomationActionExecutionTests {
    private func delayedAction() -> DraftAction {
        DraftAction(name: "Delayed automation", steps: [ActionStep("script", ["allowAsync": "true", "script": "draft.addTag('waiting');draft.update();setTimeout(()=>{draft.content='Stale';draft.update();script.complete();},500);"])])
    }
    private func waitForAction(_ library: LibraryStore, id: UUID) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while library.notes.first(where: { $0.id == id })?.tags.contains("waiting") != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(library.notes.first(where: { $0.id == id })?.tags.contains("waiting") == true)
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

    @Test func visibleTypingCancelsAutomationAndRetainsTheNewText() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let model = WindowModel(library: library); model.select(note.id)
        let task = Task { try await AutomationActionExecution.run(delayedAction(), noteID: note.id, library: library, models: [model], host: model.host) }
        try await waitForAction(library, id: note.id)
        model.editor.content = "User text"; model.contentChanged()
        let output = try await task.value
        #expect(output.report.reason == .cancelled)
        #expect(model.editor.content == "User text")
        #expect(library.notes.first { $0.id == note.id }?.content == "User text")
    }

    @Test func externalStoredTextCancelsAutomationWithoutAnOpenWindow() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let host = NativeActionHost()
        let task = Task { try await AutomationActionExecution.run(delayedAction(), noteID: note.id, library: library, models: [], host: host) }
        try await waitForAction(library, id: note.id)
        var external = try #require(library.notes.first { $0.id == note.id })
        external.content = "External"; try library.saveNote(external)
        let output = try await task.value
        #expect(output.report.reason == .cancelled)
        #expect(library.notes.first { $0.id == note.id }?.content == "External")
    }
}
