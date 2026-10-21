import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Workspace management persistence") @MainActor
struct WorkspaceManagementContractTests {
    @Test func editDuplicateOrderAndDeleteRetainOtherDefinitionsThroughReopenAndBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try LibraryStore(directory: directory, seed: false)
        let note = try library.createNote(content: "Keep café 🐼", tags: ["work"])
        var first = Workspace(name: "First café 🐼")
        first.order = 0; first.tags = ["work"]; first.folder = .all
        first.excludedTags = ["blocked"]; first.matchAnyTag = true
        first.listOptions = DraftListOptions(); first.listOptions?.showTags = false
        first.scriptMetadata = ["future": "outer", "api": #"{"future":{"enabled":true},"_sorts":{"all":{"sort":"name","descending":false,"future":"order"}}}"#]
        var second = Workspace(name: "Second")
        second.order = 1
        try library.saveWorkspaces([first, second])

        var duplicate = first
        duplicate.id = UUID(); duplicate.name += " Copy"; duplicate.order = 2
        try library.saveWorkspace(duplicate)
        first.name = "Edited café 🐼"; first.query = "Keep"
        try library.saveWorkspace(first)
        duplicate.order = 0; first.order = 1; second.order = 2
        try library.saveWorkspaces([duplicate, first, second])

        let reopened = try LibraryStore(directory: directory, seed: false)
        #expect(reopened.workspaces == [duplicate, first, second])
        #expect(duplicate.id != first.id && duplicate.scriptMetadata == first.scriptMetadata)
        #expect(duplicate.query.isEmpty && first.query == "Keep")
        #expect(reopened.notes.first { $0.id == note.id } == note)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(reopened.backupData())
        #expect(restored.workspaces == [duplicate, first, second])
        #expect(restored.notes.first { $0.id == note.id } == note)

        try reopened.deleteWorkspace(duplicate.id)
        let afterDeletion = try LibraryStore(directory: directory, seed: false)
        #expect(afterDeletion.workspaces == [first, second])
        #expect(afterDeletion.notes.first { $0.id == note.id } == note)
        let restoredAfterDeletion = try LibraryStore(inMemory: true, seed: false)
        try restoredAfterDeletion.restore(afterDeletion.backupData())
        #expect(restoredAfterDeletion.workspaces == [first, second])
    }

    @Test func failedSaveAndApplyKeepsPersistedDefinitionWindowAndEditorForRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try LibraryStore(directory: directory, seed: false)
        let note = try library.createNote(content: "Keep café 🐼", tags: ["keep"])
        let model = WindowModel(library: library)
        model.select(note.id)
        model.editor.selection = NSRange(location: 10, length: 2)
        var original = Workspace(name: "Keep workspace")
        original.tags = ["keep"]; original.sort = .title; original.ascending = true
        try model.saveAndApplyWorkspace(original)
        let focus = model.editor.focusToken
        let metadata = model.workspaceScriptMetadata
        let listOptions = model.listOptions
        let visibleIDs = model.visibleNotes.map(\.id)
        var candidate = original
        candidate.name = "Changed"; candidate.tags = ["other"]; candidate.folder = .trash
        candidate.sort = .created; candidate.ascending = false
        candidate.listOptions = DraftListOptions(); candidate.listOptions?.showTags = false
        library.beforeBatchCommit = { throw DraftlyError.message("Injected workspace save failure") }
        #expect(throws: (any Error).self) { try model.saveAndApplyWorkspace(candidate) }
        #expect(library.workspaces == [original])
        #expect(model.selectedWorkspace == original.id && model.folder == .inbox)
        #expect(model.sort == .title && model.ascending && model.selectedTags == ["keep"])
        #expect(model.workspaceScriptMetadata == metadata && model.listOptions == listOptions)
        #expect(model.visibleNotes.map(\.id) == visibleIDs)
        #expect(model.editor.noteID == note.id && model.editor.content == note.content)
        #expect(model.editor.selection == NSRange(location: 10, length: 2) && model.editor.focusToken == focus)
        #expect(!library.container.viewContext.hasChanges)
        let reopened = try LibraryStore(directory: directory, seed: false)
        #expect(reopened.workspaces == [original])
        library.beforeBatchCommit = nil
        try model.saveAndApplyWorkspace(candidate)
        #expect(library.workspaces == [candidate])
        #expect(model.folder == .trash && model.selectedTags == ["other"])
        #expect(model.visibleNotes.isEmpty && !model.listOptions.showTags)
        #expect(model.editor.noteID == note.id && model.editor.content == note.content)
        #expect(model.editor.selection == NSRange(location: 10, length: 2) && model.editor.focusToken == focus)
        let final = try LibraryStore(directory: directory, seed: false)
        #expect(final.workspaces == [candidate])
    }
}
