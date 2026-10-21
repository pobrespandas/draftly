import AppKit
import DraftlyCore
@testable import Draftly

@MainActor final class ScriptUndoEditorFixture {
    let text: TestUndoTextView
    private let session: EditorSession
    private let coordinator: NativeEditor.Coordinator

    init(_ native: NativeEditor, content: String) {
        let coordinator = NativeEditor.Coordinator(native)
        let text = TestUndoTextView(frame: .zero)
        self.session = native.session
        self.coordinator = coordinator
        self.text = text
        text.string = content
        coordinator.textView = text
        text.manager.groupsByEvent = false
        session.synchronizeScriptEdit = {
            text.manager.beginUndoGrouping()
            coordinator.synchronizeScriptEdit()
            text.manager.endUndoGrouping()
        }
        session.performUndo = { redo in
            if redo { text.manager.redo() } else { text.manager.undo() }
        }
    }

    func close() {
        session.synchronizeScriptEdit = nil
        session.performUndo = nil
        coordinator.textView = nil
        text.manager.removeAllActions()
    }
}
