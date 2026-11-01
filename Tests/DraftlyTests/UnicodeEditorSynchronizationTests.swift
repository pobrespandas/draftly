import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Exact Unicode editor synchronization") @MainActor
struct UnicodeEditorSynchronizationTests {
    @Test func canonicalVariantRegistersUndoAndRestoresExactCodeUnits() {
        let session = EditorSession(), original = "Café 🐼", replacement = "Cafe\u{0301} 🐼"
        session.load(Note(content: original), focusEditor: false)
        let native = NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
            markdown: false, onChange: {})
        let fixture = ScriptUndoEditorFixture(native, content: original)
        defer { fixture.close() }
        session.content = replacement
        session.selection = NSRange(location: replacement.utf16.count, length: 0)
        session.synchronizeScriptEdit?()
        #expect(fixture.text.string.utf8.elementsEqual(replacement.utf8))
        #expect(fixture.text.manager.canUndo)
        session.performUndo?(false)
        #expect(session.content.utf8.elementsEqual(original.utf8))
        session.performUndo?(true)
        #expect(session.content.utf8.elementsEqual(replacement.utf8))
    }

    @Test func pendingCanonicalVariantBecomesDirtyAndFlushes() throws {
        let preferences = try TestPreferences(prefix: "Draftly-Unicode-Flush-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Café 🐼")
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.editor.load(note, focusEditor: false)
        model.editor.content = "Cafe\u{0301} 🐼"
        model.contentChanged()
        #expect(model.hasUnsavedChanges)
        #expect(model.flush())
        #expect(try #require(library.notes.first).content.utf8.elementsEqual(model.editor.content.utf8))
        #expect(!model.editor.hasUnpersistedText)
    }

    @Test func aStoredCanonicalVariantUpdatesACleanEditor() throws {
        let preferences = try TestPreferences(prefix: "Draftly-Unicode-Reload-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Café 🐼")
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.editor.load(note, focusEditor: false)
        var changed = note; changed.content = "Cafe\u{0301} 🐼"
        model.synchronizeStoredEditor([changed])
        #expect(model.editor.content.utf8.elementsEqual(changed.content.utf8))
        #expect(!model.editor.hasUnpersistedText)
    }
}
