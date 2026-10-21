import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Window dependency boundaries") @MainActor
struct WindowDependencyTests {
    @Test func windowsShareDataButKeepPreferencesAndEditorStateSeparate() throws {
        let name = "Draftly-WindowDependencies-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: GeneralPreferences.advancedFindKey)
        defaults.set(false, forKey: "list.showPreview")
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral café 🐼")
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: defaults)
        let first = WindowModel(library: library, dependencies: dependencies)
        let second = WindowModel(library: library, dependencies: dependencies)
        first.select(note.id)
        #expect(second.editor.noteID == nil)
        #expect(!first.listOptions.showPreview && !second.listOptions.showPreview)
        _ = try first.actionUIOperation(["operation": "showFind", "args": []])
        #expect(first.showAdvancedFind && !second.showAdvancedFind)
        #expect(second.library === first.library)
    }

    @Test func scriptNavigationUsesTheInjectedRoutes() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var received: (UUID?, Bool)?
        var searches = 0
        var dependencies = WindowDependencies()
        dependencies.openDraftWindow = { id, tab, _ in received = (id, tab); return true }
        dependencies.openQuickSearch = { _ in searches += 1 }
        let model = WindowModel(library: library, dependencies: dependencies)
        let id = UUID()
        _ = try model.actionUIOperation(["operation": "openInNewTab", "draft": ["uuid": id.uuidString]])
        #expect(received?.0 == id && received?.1 == true)
        _ = try model.actionUIOperation(["operation": "showQuickSearch"])
        #expect(searches == 1)
        #expect(library.notes.isEmpty && model.editor.noteID == nil)
    }
    @Test func renamingATagFlushesTheInjectedPeerWindows() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "Neutral", tags: ["old"])
        var windows: [WindowModel] = []
        defer { windows.removeAll() }
        var dependencies = WindowDependencies()
        dependencies.windowModels = { windows }
        let first = WindowModel(library: library, dependencies: dependencies)
        let second = WindowModel(library: library, dependencies: dependencies)
        windows = [first, second]
        first.select(source.id)
        second.select(source.id)
        second.editor.content = "Pending café 🐼"
        second.selectedTags = ["old"]
        #expect(first.changeLibraryTag("old", to: "new"))
        #expect(library.notes.first { $0.id == source.id }?.content == "Pending café 🐼")
        #expect(library.notes.first { $0.id == source.id }?.tags == ["new"])
        #expect(second.selectedTags == ["new"])
    }

}
