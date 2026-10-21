import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Window search initial queries") @MainActor
struct WindowSearchQueryTests {
    @Test func quickSearchReceivesExactQueryAndOmittedArgumentClearsIt() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral draft")
        var received: [String] = []
        var dependencies = WindowDependencies()
        dependencies.openQuickSearch = { received.append($0) }
        let model = WindowModel(library: library, dependencies: dependencies)
        model.select(note.id)
        model.query = "Keep list filter"
        model.editor.content = "Unsaved café 🐼"
        model.editor.selection = NSRange(location: 3, length: 4)
        let focus = model.noteSearchFocus

        _ = try model.actionUIOperation(["operation": "showQuickSearch", "value": "café 🐼\nNext"])
        _ = try model.actionUIOperation(["operation": "showQuickSearch"])

        #expect(received == ["café 🐼\nNext", ""])
        #expect(model.query == "Keep list filter" && model.noteSearchFocus == focus)
        #expect(model.editor.noteID == note.id && model.editor.content == "Unsaved café 🐼")
        #expect(model.editor.selection == NSRange(location: 3, length: 4))
    }

    @Test func paletteReceivesExactQueryAndOmittedArgumentClearsPreviousQuery() throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        model.query = "Keep list filter"
        model.actionQuery = "Keep action filter"

        _ = try model.actionUIOperation(["operation": "showCommandPalette", "value": "café 🐼"])
        #expect(model.showPalette && model.paletteQuery == "café 🐼")
        model.showPalette = false
        _ = try model.actionUIOperation(["operation": "showCommandPalette"])
        #expect(model.showPalette && model.paletteQuery.isEmpty)
        #expect(model.query == "Keep list filter" && model.actionQuery == "Keep action filter")
    }
}
