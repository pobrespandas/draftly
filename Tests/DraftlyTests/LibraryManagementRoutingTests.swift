import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Library management entry routing") @MainActor
struct LibraryManagementRoutingTests {
    @Test func eachEntryUsesItsRequestedSectionWithoutChangingTheCurrentWorkspaceOrEditor() throws {
        let preferences = try TestPreferences(prefix: "Draftly-ManagementRouting-")
        defer { preferences.close() }
        preferences.defaults.set("Keep local theme", forKey: "editor.theme")
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral café 🐼", tags: ["work"])
        var workspace = Workspace(name: "Keep workspace")
        workspace.tags = ["work"]; workspace.query = "Neutral"
        try library.saveWorkspace(workspace)
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.select(note.id)
        try model.applyScriptWorkspace(workspace)
        model.editor.selection = NSRange(location: 13, length: 2)
        let focus = model.editor.focusToken
        let beforePreferences = preferences.defaults.persistentDomain(forName: preferences.name)
        let beforeNotes = library.notes
        let beforeWorkspace = model.workspaceSnapshot(name: "Current")
        #expect(!model.showLibraryManagement && model.libraryManagementSection == .groups)
        for section in [LibraryManagementSection.workspaces, .groups, .actions, .workspaces] {
            model.openLibraryManagement(section: section)
            #expect(model.showLibraryManagement && model.libraryManagementSection == section)
            #expect(model.selectedWorkspace == workspace.id)
            var currentWorkspace = model.workspaceSnapshot(name: "Current")
            currentWorkspace.id = beforeWorkspace.id
            #expect(currentWorkspace == beforeWorkspace)
            #expect(model.editor.noteID == note.id && model.editor.content == note.content)
            #expect(model.editor.selection == NSRange(location: 13, length: 2) && model.editor.focusToken == focus)
            #expect(library.workspaces == [workspace] && library.notes == beforeNotes)
            #expect(NSDictionary(dictionary: preferences.defaults.persistentDomain(forName: preferences.name) ?? [:]).isEqual(to: beforePreferences ?? [:]))
            model.showLibraryManagement = false
        }
        model.openLibraryManagement()
        #expect(model.showLibraryManagement && model.libraryManagementSection == .groups)
    }
}
