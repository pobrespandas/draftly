import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Theme development refresh routing") @MainActor
struct ThemeDevelopmentRefreshTests {
    @Test func controllerRefreshUsesLocalFolderAndPreservesEditorAndStoredDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "Draftly.ThemeDevelopment.Controller.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let controller = AppController(library: library, recentDrafts: RecentDraftStore(defaults: defaults))
        var source = EditorThemeDefinition(name: "Development café 🐼", background: "112233")
        let file = directory.appendingPathComponent("neutral.json")
        try JSONEncoder().encode(source).write(to: file)
        #expect(try ThemeDevelopmentFolder.select(directory, in: library, defaults: defaults) == 1)
        let theme = try #require(library.themes.first)
        let model = WindowModel(library: library, dependencies: WindowDependencies(preferences: WindowPreferences(defaults: defaults)))
        let note = try library.createNote(content: "Keep original 🐼"); model.select(note.id)
        model.editor.content = "Keep pending café 🐼"; model.editor.selection = NSRange(location: 5, length: 7)
        try model.setConfiguredThemeReference(["type": "file", "uuid": theme.id.uuidString], dark: false)
        #expect(model.editorThemePresentation(systemIsDark: false).theme?.background == "112233")
        let stored = library.notes, beforeSelection = model.editor.selection, beforeFocus = model.editor.focusToken
        source.background = "445566"; try JSONEncoder().encode(source).write(to: file)
        controller.refreshThemeDevelopmentFolder(defaults: defaults)
        #expect(library.error == nil)
        #expect(library.themes.first?.id == theme.id && library.themes.first?.background == "445566")
        #expect(model.editorThemePresentation(systemIsDark: false).theme?.background == "445566")
        #expect(model.editor.content == "Keep pending café 🐼" && model.editor.selection == beforeSelection)
        #expect(model.editor.focusToken == beforeFocus && library.notes == stored)
        let before = library.themes, revision = defaults.integer(forKey: ThemeCatalog.revisionKey)
        try Data("invalid".utf8).write(to: file)
        controller.refreshThemeDevelopmentFolder(defaults: defaults)
        #expect(library.error != nil && library.themes == before)
        #expect(defaults.integer(forKey: ThemeCatalog.revisionKey) == revision)
        #expect(model.editorThemePresentation(systemIsDark: false).theme?.background == "445566")
        #expect(model.editor.content == "Keep pending café 🐼" && library.notes == stored)
    }
}
