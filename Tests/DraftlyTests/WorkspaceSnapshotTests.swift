import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Workspace snapshot persistence") @MainActor
struct WorkspaceSnapshotTests {
    @Test func savedCurrentViewRetainsAdvancedFiltersAndUnknownMetadataAfterReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try LibraryStore(directory: folder, seed: false)
        var flagged = try library.createNote(content: "Included", tags: ["work"])
        flagged.flag = 1; try library.saveNote(flagged)
        _ = try library.createNote(content: "Excluded", tags: ["work"])
        let model = WindowModel(library: library)
        model.selectedTags = ["work"]
        model.tagPresence = true
        model.workspaceScriptMetadata = ["future": "preserve", "api": #"{"flaggedStatus":"flagged","startDate":{"type":"absolute","date":"2000-01-01T00:00:00Z","field":"created"},"_sorts":{"inbox":{"sort":"accessed","descending":true,"flagged":true}},"future":{"enabled":true}}"#]
        let snapshot = model.workspaceSnapshot(name: "Saved view")
        #expect(snapshot.tagged == true)
        #expect(snapshot.scriptMetadata == model.workspaceScriptMetadata)
        #expect(snapshot.filter(library.notes).map(\.id) == [flagged.id])
        #expect(snapshot.filter(library.notes).map(\.id) == model.visibleNotes.map(\.id))
        try library.saveWorkspace(snapshot)
        let reopened = try LibraryStore(directory: folder, seed: false)
        let saved = try #require(reopened.workspaces.first)
        #expect(saved == snapshot)
        #expect(saved.filter(reopened.notes).map(\.id) == [flagged.id])
        let restoredModel = WindowModel(library: reopened)
        try restoredModel.applyScriptWorkspace(saved)
        #expect(restoredModel.visibleNotes.map(\.id) == [flagged.id])
        #expect(NSDictionary(dictionary: restoredModel.workspaceSnapshot(name: "Saved view").apiOptions).isEqual(to: snapshot.apiOptions))
        #expect(restoredModel.workspaceScriptMetadata?["future"] == "preserve")
    }

    @Test func missingReferencesRejectSaveBeforeChangingLibraryOrWindow() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        model.query = "Keep query"
        var workspace = Workspace(name: "Invalid")
        workspace.scriptMetadata = ["api": #"{"loadActionListGroup":{"uuid":"DAAF7300-0000-4000-8000-000000000099","name":"Missing"}}"#]
        #expect(throws: (any Error).self) { try model.saveAndApplyWorkspace(workspace) }
        #expect(library.workspaces.isEmpty)
        #expect(model.query == "Keep query")
        #expect(model.selectedWorkspace == nil)
    }

    @Test func scriptingCurrentWorkspaceRetainsTagPresenceWithoutChangingEditor() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral 🐼")
        let model = WindowModel(library: library)
        model.select(note.id)
        model.editor.selection = NSRange(location: 8, length: 2)
        model.tagPresence = false
        let current = try #require(model.runner.currentWorkspace?())
        #expect(current.tagged == false)
        #expect(current.filter(library.notes).map(\.id) == model.visibleNotes.map(\.id))
        #expect(model.editor.content == note.content)
        #expect(model.editor.selection == NSRange(location: 8, length: 2))
    }
}
