import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Action editor interruptions") @MainActor
struct ActionEditorInterruptionTests {
    private func delayedEdit() -> DraftAction {
        DraftAction(name: "Delayed neutral edit", steps: [ActionStep("script", ["allowAsync": "true", "script": "draft.addTag('waiting');draft.update();setTimeout(()=>{editor.setText('Stale action text');script.complete();},30000);"])])
    }

    private func waitUntilWaiting(_ library: LibraryStore, id: UUID) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while library.notes.first(where: { $0.id == id })?.tags.contains("waiting") != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(library.notes.first(where: { $0.id == id })?.tags.contains("waiting") == true)
    }

    @Test func explicitCancellationKeepsCompletedEffectsAndAllowsAnotherRun() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral source")
        let model = WindowModel(library: library); model.select(note.id)
        #expect(!model.canCancelActions)
        #expect(model.canRunActions)
        let otherWindow = WindowModel(library: library); otherWindow.select(note.id)
        let independentLibrary = try LibraryStore(inMemory: true, seed: false)
        let independentNote = try independentLibrary.createNote(content: "Independent source")
        let independent = WindowModel(library: independentLibrary); independent.select(independentNote.id)
        #expect(otherWindow.canRunActions && independent.canRunActions)
        var action = delayedEdit()
        action.afterSuccess = "archive"
        action.steps.append(ActionStep("insertText", ["template": "ERROR: cancellation tail ran"]))
        let task = Task { await model.runAsync(action) }
        try await waitUntilWaiting(library, id: note.id)
        #expect(model.canCancelActions)
        #expect(!model.canRunActions)
        #expect(!otherWindow.canRunActions && !otherWindow.canCancelActions)
        #expect(independent.canRunActions && !independent.canCancelActions)
        let openedWhileBusy = WindowModel(library: library); openedWhileBusy.select(note.id)
        #expect(!openedWhileBusy.canRunActions && !openedWhileBusy.canCancelActions)
        model.cancelActions()
        let report = await task.value
        #expect(report?.reason == .cancelled)
        #expect(otherWindow.canRunActions && openedWhileBusy.canRunActions && independent.canRunActions)
        #expect(!model.canCancelActions)
        #expect(model.canRunActions)
        #expect(model.editor.content == "Neutral source")
        let stored = try #require(library.notes.first { $0.id == note.id })
        #expect(stored.tags == ["waiting"] && !stored.isArchived)
        #expect(stored.content == "Neutral source")
        let next = DraftAction(name: "After cancellation", steps: [ActionStep("insertText", ["template": "Next run"])])
        #expect((await model.runAsync(next))?.reason == .success)
        #expect(model.editor.content.contains("Next run"))
        #expect(!model.canCancelActions)
        #expect(model.canRunActions)
    }

    @Test func userNavigationCancelsDelayedEditorWrite() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let a = try library.createNote(content: "A"), b = try library.createNote(content: "B")
        let model = WindowModel(library: library); model.select(a.id)
        let task = Task { await model.runAsync(delayedEdit()) }
        try await waitUntilWaiting(library, id: a.id)
        model.select(b.id)
        let report = await task.value
        #expect(report?.reason == .cancelled)
        #expect(model.editor.noteID == b.id && model.editor.content == "B")
        #expect(library.notes.first { $0.id == a.id }?.content == "A")
        #expect(library.notes.first { $0.id == b.id }?.content == "B")
    }

    @Test func userTypingCancelsDelayedEditorWriteAndSavesTheirText() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let model = WindowModel(library: library); model.select(note.id)
        let task = Task { await model.runAsync(delayedEdit()) }
        try await waitUntilWaiting(library, id: note.id)
        model.editor.content = "User text"; model.contentChanged()
        let report = await task.value
        #expect(report?.reason == .cancelled)
        #expect(model.editor.content == "User text")
        #expect(library.notes.first { $0.id == note.id }?.content == "User text")
    }

    @Test func externalStoredEditCancelsDelayedActionAndRetainsExternalText() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let model = WindowModel(library: library); model.select(note.id)
        let action = DraftAction(name: "Delayed cached draft", steps: [ActionStep("script", ["allowAsync": "true", "script": "draft.addTag('waiting');draft.update();setTimeout(()=>{draft.content='Stale action text';draft.update();script.complete();},500);"])])
        let task = Task { await model.runAsync(action) }
        try await waitUntilWaiting(library, id: note.id)
        var external = try #require(library.notes.first { $0.id == note.id })
        external.content = "External text"; try library.saveNote(external)
        model.synchronizeStoredEditor(library.notes)
        let report = await task.value
        #expect(report?.reason == .cancelled)
        #expect(model.editor.content == "External text")
        #expect(library.notes.first { $0.id == note.id }?.content == "External text")
    }

    @Test func scriptedNavigationCreationLoadingAndUndoDoNotCancelTheAction() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let a = try library.createNote(content: "A"), b = try library.createNote(content: "B")
        let model = WindowModel(library: library); model.sort = .title; model.ascending = true; model.select(a.id)
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, onChange: { model.contentChanged() })
        let coordinator = NativeEditor.Coordinator(native), text = TestUndoTextView(frame: .zero)
        text.string = "A"; coordinator.textView = text; text.manager.groupsByEvent = false
        model.editor.synchronizeScriptEdit = {
            let changedNote = coordinator.noteID != model.editor.noteID
            if !changedNote { text.manager.beginUndoGrouping() }
            coordinator.synchronizeScriptEdit()
            if !changedNote { text.manager.endUndoGrouping() }
        }
        model.editor.performUndo = { redo in if redo { text.manager.redo() } else { text.manager.undo() } }
        defer { model.editor.synchronizeScriptEdit = nil; model.editor.performUndo = nil; text.manager.removeAllActions() }
        let action = DraftAction(name: "Script navigation", steps: [ActionStep("script", ["script": """
        editor.nextDraft();if(editor.getText()!=='B')throw new Error('next');
        editor.new();editor.setText('Temporary');
        editor.load(Draft.find('\(a.id.uuidString)'));editor.setText('Changed');
        editor.undo();if(editor.getText()!=='A')throw new Error('undo');
        editor.redo();if(editor.getText()!=='Changed')throw new Error('redo');
        """])])
        let report = await model.runAsync(action)
        #expect(report?.reason == .success, Comment(rawValue: model.runner.message ?? ""))
        #expect(model.editor.noteID == a.id && model.editor.content == "Changed")
        #expect(library.notes.first { $0.id == b.id }?.content == "B")
    }
}
