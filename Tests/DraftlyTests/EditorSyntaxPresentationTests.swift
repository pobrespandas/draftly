import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Editor syntax failures") @MainActor
struct EditorSyntaxPresentationTests {
    @Test func unavailableSyntaxReportsItsErrorWithoutChangingTheDraft() throws {
        let preferences = try TestPreferences(prefix: "Draftly.SyntaxPresentation.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        var note = try library.createNote(content: "Neutral 🐼 unsaved")
        note.syntax = "Missing grammar"
        try library.saveNote(note)
        let model = WindowModel(library: library, dependencies: WindowDependencies(preferences: WindowPreferences(defaults: preferences.defaults)))
        model.select(note.id)
        model.editor.content += " edit"
        model.editor.selection = NSRange(location: 8, length: 2)
        let before = model.editor.content
        let result = EditorSyntaxPresentation(model: model)
        #expect(result.definition == nil && result.error?.contains("Missing grammar") == true && !result.canAddFile)
        #expect(model.editor.content == before && model.editor.selection == NSRange(location: 8, length: 2))
        #expect(library.notes.first?.content == note.content && model.library.error == nil)
    }

    @Test func fileErrorsSurfaceAndReadingRecoversAfterRepair() throws {
        let preferences = try TestPreferences(prefix: "Draftly.SyntaxFilePresentation.")
        defer { preferences.close() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Neutral.draftsSyntax")
        let data = Data(#"{"name":"Neutral file","patterns":[],"navigationPatterns":[],"linkDefinitions":[],"taskMarkDefinitions":[],"indentationPatterns":[]}"#.utf8)
        try data.write(to: file)
        let library = try LibraryStore(inMemory: true, seed: false)
        let syntax = try SyntaxDefinition(data: data, type: "file")
        try SyntaxFileAccess.install(syntax, from: file, in: library, defaults: preferences.defaults)
        var note = try library.createNote(content: "Neutral 🐼"); note.syntax = syntax.name; try library.saveNote(note)
        let model = WindowModel(library: library, dependencies: WindowDependencies(preferences: WindowPreferences(defaults: preferences.defaults)))
        model.select(note.id)
        #expect(EditorSyntaxPresentation(model: model).definition?.id == syntax.id)
        try Data("{broken".utf8).write(to: file)
        let invalid = EditorSyntaxPresentation(model: model)
        #expect(invalid.definition == nil && invalid.error != nil && invalid.canAddFile)
        try FileManager.default.removeItem(at: file)
        #expect(EditorSyntaxPresentation(model: model).error != nil)
        try data.write(to: file)
        let repaired = EditorSyntaxPresentation(model: model)
        #expect(repaired.definition?.id == syntax.id && repaired.error == nil)
        #expect(model.editor.content == note.content && library.syntaxes == [syntax])
    }
}
