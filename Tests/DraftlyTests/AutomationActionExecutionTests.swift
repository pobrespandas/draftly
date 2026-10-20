import Combine
import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Automation action editor safety") @MainActor
struct AutomationActionExecutionTests {
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

    @Test func visibleTypingCancelsAutomationAndRetainsTheNewText() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored")
        let model = WindowModel(library: library); model.select(note.id)
        let task = try await startAndWaitForAction(library, id: note.id) {
            try await AutomationActionExecution.run(delayedAction(), noteID: note.id, library: library, models: [model], host: model.host)
        }
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
