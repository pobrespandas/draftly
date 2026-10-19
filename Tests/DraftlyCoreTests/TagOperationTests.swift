import Foundation
import Testing
@testable import DraftlyCore

@Suite("Library tag operations") @MainActor
struct TagOperationTests {
    @Test func renameMergesTagsAcrossAllViewsAndWorkspaceFilters() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "Inbox", tags: ["old", "new", "old/child"])
        var archived = try library.createNote(content: "Archive", tags: ["old"]); archived.isArchived = true; archived.trashedAt = Date(); try library.saveNote(archived)
        var workspace = Workspace(name: "Filters"); workspace.tags = ["old"]; workspace.excludedTags = ["old", "other"]; try library.saveWorkspace(workspace)
        #expect(try library.changeTag(" OLD ", to: " NEW ") == 2)
        #expect(library.notes.first { $0.id == first.id }?.tags == ["new", "old/child"])
        #expect(library.notes.first { $0.id == archived.id }?.tags == ["new"])
        #expect(library.workspaces.first?.tags == ["new"])
        #expect(library.workspaces.first?.excludedTags == ["new", "other"])
        #expect(try library.changeTag("new", to: nil) == 2)
        #expect(library.notes.count == 2)
        #expect(library.notes.first { $0.id == first.id }?.tags == ["old/child"])
        #expect(library.workspaces.first?.tags.isEmpty == true)
    }
    @Test func failedTagChangeRollsBackNotesAndWorkspaces() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Saved", tags: ["old"])
        var workspace = Workspace(name: "Saved filter"); workspace.tags = ["old"]; try library.saveWorkspace(workspace)
        library.beforeBatchCommit = { throw DraftlyError.message("Disk full") }
        #expect(throws: (any Error).self) { try library.changeTag("old", to: "new") }
        #expect(library.notes.first?.tags == ["old"])
        #expect(library.workspaces.first?.tags == ["old"])
    }
}
