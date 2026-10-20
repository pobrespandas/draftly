import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Editor range undo contracts") @MainActor
struct EditorRangeUndoContractTests {
    @Test func setTextInRangeRestoresUnicodeTextAndSelectionWithNativeUndoAndRedo() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        let original = "🐼 café\r\nTail"
        let note = try library.createNote(content: original)
        model.select(note.id)
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
                                  lineSpacing: 2, markdown: false, onChange: {})
        let coordinator = NativeEditor.Coordinator(native)
        let text = TestUndoTextView(frame: .zero)
        text.string = original
        coordinator.textView = text
        text.manager.groupsByEvent = false
        model.editor.synchronizeScriptEdit = {
            let changedNote = coordinator.noteID != model.editor.noteID
            if !changedNote { text.manager.beginUndoGrouping() }
            coordinator.synchronizeScriptEdit()
            if !changedNote { text.manager.endUndoGrouping() }
        }
        model.editor.performUndo = { redo in
            if redo { text.manager.redo() } else { text.manager.undo() }
        }
        let action = DraftAction(name: "Range replacement undo contract", steps: [ActionStep("script", ["script": #"""
        function check(value,label){if(!value)throw new Error(label);}
        editor.setSelectedRange(3,4);
        check(editor.setTextInRange(3,4,'té')===undefined,'range returns void');
        check(editor.getText()==='🐼 té\r\nTail','range replacement');
        check(editor.getSelectedRange().join(',')==='5,0','replacement cursor');
        editor.undo();
        check(editor.getText()==='🐼 café\r\nTail','native undo content');
        check(editor.getSelectedRange().join(',')==='3,4','native undo selection');
        editor.redo();
        check(editor.getText()==='🐼 té\r\nTail','native redo content');
        check(editor.getSelectedRange().join(',')==='5,0','native redo selection');
        """#])])
        #expect(model.runner.run(action), Comment(rawValue: model.runner.message ?? ""))
        #expect(text.string == "🐼 té\r\nTail")
        #expect(text.selectedRange() == NSRange(location: 5, length: 0))
        #expect(model.editor.selection == text.selectedRange())
        #expect(library.notes.first { $0.id == note.id }?.content == text.string)
    }
}
