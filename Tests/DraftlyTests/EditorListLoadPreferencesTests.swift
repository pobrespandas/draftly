import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Editor list load preferences") @MainActor
struct EditorListLoadPreferencesTests {
    @Test func listSelectionUsesCursorAndFocusPreferencesWithoutChangingText() throws {
        let prefs = try TestPreferences(prefix: "Draftly-ListLoad-")
        defer { prefs.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "first")
        let target = try library.createNote(content: "café 🐼")
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: prefs.defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.select(first.id, focusEditor: false)
        for (placement, expected) in [("top", 0), ("bottom", target.content.utf16.count), ("invalid", 0)] {
            prefs.defaults.set(placement, forKey: "editor.cursorOnListSelection")
            prefs.defaults.set(true, forKey: "editor.focusOnListSelection")
            let before = model.editor.focusToken
            model.selectFromList(target.id)
            #expect(model.editor.content == target.content)
            #expect(model.editor.selection == NSRange(location: expected, length: 0))
            #expect(model.editor.focusToken != before)
            model.select(first.id, focusEditor: false)
        }
        prefs.defaults.removeObject(forKey: "editor.focusOnListSelection")
        prefs.defaults.removeObject(forKey: "editor.cursorOnListSelection")
        let before = model.editor.focusToken
        model.selectFromList(target.id)
        #expect(model.editor.focusToken == before)
        #expect(model.editor.selection == NSRange(location: 0, length: 0))
    }
    @Test func lastRestoresStoredSelectionAndFailedAccessDoesNotMoveTheEditor() throws {
        enum Failure: Error { case unavailable }
        let prefs = try TestPreferences(prefix: "Draftly-ListLoad-")
        defer { prefs.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "first")
        var target = Note(content: "café 🐼")
        target.scriptMetadata = ["selectionStart": "5", "selectionLength": "2"]
        try library.saveNote(target, preserveDates: true)
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: prefs.defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.select(first.id, focusEditor: false)
        model.selectFromList(target.id)
        #expect(model.editor.selection == NSRange(location: 5, length: 2))
        model.select(first.id, focusEditor: false)
        model.editor.selection = NSRange(location: 2, length: 0)
        prefs.defaults.set("bottom", forKey: "editor.cursorOnListSelection")
        let token = model.editor.focusToken
        library.beforeBatchCommit = { throw Failure.unavailable }
        defer { library.beforeBatchCommit = nil }
        model.selectFromList(target.id)
        #expect(model.editor.noteID == first.id && model.editor.content == first.content)
        #expect(model.editor.selection == NSRange(location: 2, length: 0))
        #expect(model.editor.focusToken == token)
    }

}
