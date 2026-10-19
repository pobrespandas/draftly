import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Script editor undo") @MainActor
struct ScriptEditorUndoTests {
    @Test func newDraftEditsUndoWithinTheSameActionWithoutRestoringPreviousText() throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let previous = try model.library.createNote(content: "Previous draft")
        model.select(previous.id)
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, onChange: {})
        let coordinator = NativeEditor.Coordinator(native), text = UndoTextView(frame: .zero)
        text.string = previous.content; coordinator.textView = text; text.manager.groupsByEvent = false
        model.editor.synchronizeScriptEdit = {
            let changed = coordinator.noteID != model.editor.noteID
            if !changed { text.manager.beginUndoGrouping() }
            coordinator.synchronizeScriptEdit()
            if !changed { text.manager.endUndoGrouping() }
        }
        model.editor.performUndo = { redo in if redo { text.manager.redo() } else { text.manager.undo() } }
        let action = DraftAction(name: "New and undo", steps: [ActionStep("script", ["script": """
        editor.new();editor.setText('New 🐼');
        editor.undo();if(editor.getText()!=='')throw new Error('new undo');
        editor.redo();if(editor.getText()!=='New 🐼')throw new Error('new redo');
        """])])
        #expect(model.runner.run(action), Comment(rawValue: model.runner.message ?? ""))
        #expect(text.string == "New 🐼")
        #expect(model.library.notes.first { $0.id == previous.id }?.content == previous.content)
    }
    @Test func loadThenEditAndUndoUsesTheNewDraftWithinTheSameAction() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: store)
        let first = try store.createNote(content: "Previous draft")
        let second = try store.createNote(content: "New 🐼 café")
        model.select(first.id)
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, onChange: {})
        let coordinator = NativeEditor.Coordinator(native), text = UndoTextView(frame: .zero)
        text.string = first.content; coordinator.textView = text; text.manager.groupsByEvent = false
        model.editor.synchronizeScriptEdit = {
            let changedNote = coordinator.noteID != model.editor.noteID
            if !changedNote { text.manager.beginUndoGrouping() }
            coordinator.synchronizeScriptEdit()
            if !changedNote { text.manager.endUndoGrouping() }
        }
        model.editor.performUndo = { redo in if redo { text.manager.redo() } else { text.manager.undo() } }
        let value = DraftAction(name: "Load and undo", steps: [ActionStep("script", ["script": """
        editor.load(Draft.find('\(second.id.uuidString)'));
        editor.setSelectedRange(4,2);editor.setSelectedText('PANDA');
        editor.undo();
        if(editor.getText()!=='New 🐼 café'||editor.getSelectedRange().join(',')!=='4,2')throw new Error('load undo');
        editor.redo();if(editor.getText()!=='New PANDA café')throw new Error('load redo');
        """])])
        #expect(model.runner.run(value), Comment(rawValue: model.runner.message ?? ""))
        #expect(text.string == "New PANDA café")
        #expect(store.notes.first { $0.id == first.id }?.content == first.content)
        #expect(store.notes.first { $0.id == second.id }?.content == "New PANDA café")
    }
    @Test func nonblockingDictationInsertionSupportsNativeUndo() async throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let note = try model.library.createNote(content: "Original 🐼"); model.select(note.id)
        model.editor.selection = NSRange(location: 0, length: 8)
        let native = NativeEditor(session: model.editor, fontName: "SFMono-Regular", fontSize: 15, lineSpacing: 2, markdown: false, onChange: {})
        let coordinator = NativeEditor.Coordinator(native), text = UndoTextView(frame: .zero)
        text.string = model.editor.content; text.setSelectedRange(model.editor.selection); coordinator.textView = text
        text.manager.groupsByEvent = false
        model.editor.synchronizeScriptEdit = { text.manager.beginUndoGrouping(); coordinator.synchronizeScriptEdit(); text.manager.endUndoGrouping() }
        model.host.dictationHandler = { _ in "Dictated" }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            model.editor.focusForDictation = { continuation.resume(); return true }
            do { _ = try model.actionUIOperation(["operation": "showDictate"]) }
            catch { Issue.record(error); continuation.resume() }
        }
        #expect(model.editor.content == "Dictated 🐼" && text.string == "Dictated 🐼")
        text.manager.undo()
        #expect(model.editor.content == "Original 🐼" && model.editor.selection == NSRange(location: 0, length: 8))
        #expect(model.flush())
        #expect(model.library.notes.first { $0.id == note.id }?.content == "Original 🐼")
    }
    @Test func scriptEditsUndoImmediatelyAndRestoreSelection() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: store)
        let note = try store.createNote(content: "Original 🐼")
        model.select(note.id)
        model.editor.selection = NSRange(location: 0, length: 8)
        let native = NativeEditor(session: model.editor, fontName: "SFMono-Regular", fontSize: 15,
                                  lineSpacing: 2, markdown: false, onChange: {})
        let coordinator = NativeEditor.Coordinator(native)
        let text = UndoTextView(frame: .zero)
        text.string = model.editor.content; text.setSelectedRange(model.editor.selection)
        coordinator.textView = text
        model.editor.synchronizeScriptEdit = { text.manager.beginUndoGrouping(); coordinator.synchronizeScriptEdit(); text.manager.endUndoGrouping() }
        model.editor.performUndo = { redo in if redo { text.undoManager?.redo() } else { text.undoManager?.undo() } }
        text.manager.groupsByEvent = false
        let edit = DraftAction(name: "Edit", steps: [ActionStep("script", ["script": """
        editor.setSelectedText('Changed');
        if(draft.content!=='Changed 🐼')throw new Error('edit');
        editor.undo();
        if(editor.getText()!=='Original 🐼'||draft.content!=='Original 🐼')throw new Error('undo');
        if(editor.getSelectedRange().join(',')!=='0,8')throw new Error('selection');
        editor.redo();
        if(editor.getText()!=='Changed 🐼')throw new Error('redo');
        """])])
        #expect(model.runner.run(edit), Comment(rawValue: model.runner.message ?? ""))
        #expect(text.string == "Changed 🐼")
        #expect(store.notes.first { $0.id == note.id }?.content == "Changed 🐼")
    }
}

@MainActor private final class UndoTextView: NSTextView {
    let manager = UndoManager()
    override var undoManager: UndoManager? { manager }
}
