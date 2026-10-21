import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Local scene draft restoration") @MainActor
struct WindowDraftRestorationTests {
    @Test func storedIdentityLoadsTheDraftAndItsUTF16SelectionWithoutChangingContentHistory() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var note = Note(content: "café 🐼\nSecond line", tags: ["neutral"])
        note.scriptMetadata = ["selectionStart": "5", "selectionLength": "2"]
        try library.saveNote(note, preserveDates: true)
        let revisions = library.revisions
        let model = WindowModel(library: library)
        #expect(model.restoreEditorDraft(note.id.uuidString))
        #expect(model.editor.noteID == note.id && model.editor.content == note.content)
        #expect(model.editor.selection == NSRange(location: 5, length: 2))
        #expect(model.selectedDraftIDs == [note.id])
        let stored = try #require(library.notes.first { $0.id == note.id })
        #expect(stored.modifiedAt == note.modifiedAt && stored.content == note.content)
        #expect(stored.accessedAt != nil && library.revisions == revisions)
    }

    @Test func invalidOrMissingIdentityDoesNotCreateOrReplaceADraft() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        for identifier in ["", "invalid", UUID().uuidString] {
            #expect(!model.restoreEditorDraft(identifier))
            #expect(model.editor.noteID == nil && model.editor.content.isEmpty)
        }
        #expect(library.notes.isEmpty && library.revisions.isEmpty)
    }

    @Test func accessWriteFailureLeavesTheEditorUnloadedAndAllowsARetry() throws {
        enum Failure: Error { case unavailable }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored neutral text")
        let model = WindowModel(library: library)
        library.beforeBatchCommit = { throw Failure.unavailable }
        #expect(!model.restoreEditorDraft(note.id.uuidString))
        #expect(model.editor.noteID == nil && model.editor.content.isEmpty)
        #expect(library.error != nil && library.notes.first?.accessedAt == nil)
        library.beforeBatchCommit = nil
        #expect(model.restoreEditorDraft(note.id.uuidString))
        #expect(model.editor.content == note.content)
    }

    @Test func aRestoredIdentityCannotOverwriteAnAlreadyChosenTargetOrPendingEdits() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Requested target")
        let previous = try library.createNote(content: "Previous scene")
        var saveAttempts = 0
        let model = WindowModel(library: library, saveDraft: { _ in saveAttempts += 1 })
        model.select(target.id)
        model.editor.content = "Pending café 🐼"
        model.editor.selection = NSRange(location: 2, length: 3)
        #expect(!model.restoreEditorDraft(previous.id.uuidString))
        #expect(model.editor.noteID == target.id && model.editor.content == "Pending café 🐼")
        #expect(model.editor.selection == NSRange(location: 2, length: 3))
        #expect(model.selectedDraftIDs == [target.id])
        #expect(saveAttempts == 0)
    }
}
