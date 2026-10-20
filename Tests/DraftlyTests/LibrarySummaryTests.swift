import Foundation
import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Library summary") @MainActor
struct LibrarySummaryTests {
    @Test func trashDoesNotCountAgainInInboxOrArchive() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Inbox")
        var archive = try library.createNote(content: "Archive")
        archive.isArchived = true
        try library.saveNote(archive)
        var trash = try library.createNote(content: "Trash")
        trash.isArchived = true
        trash.trashedAt = Date()
        try library.saveNote(trash)
        let summary = LibrarySummary(library: library)
        #expect(summary.inbox == 1)
        #expect(summary.archive == 1)
        #expect(summary.trash == 1)
        #expect(library.notes.count == 3)
    }
}

@Suite("Library Trash command") @MainActor
struct LibraryTrashCommandTests {
    @Test func noWindowStillRequiresConfirmationAndPreservesActiveDrafts() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let active = try library.createNote(content: "Keep café 🐼")
        var trash = try library.createNote(content: "Disposable neutral draft")
        trash.trashedAt = Date()
        try library.saveNote(trash)
        var confirmations: [Int] = []
        #expect(try !LibraryTrashCommand.run(library: library, models: [], confirm: { count in confirmations.append(count); return false }))
        #expect(library.notes.count == 2)
        #expect(try LibraryTrashCommand.run(library: library, models: [], confirm: { count in confirmations.append(count); return true }))
        #expect(confirmations == [1, 1])
        #expect(library.notes.map(\.id) == [active.id])
    }

    @Test func failedEditorSaveStopsBeforeConfirmationAndKeepsTrash() throws {
        _ = NSApplication.shared
        let library = try LibraryStore(inMemory: true, seed: false)
        var trash = try library.createNote(content: "Disposable draft")
        trash.trashedAt = Date()
        try library.saveNote(trash)
        let active = try library.createNote(content: "Original")
        let model = WindowModel(library: library, saveDraft: { _ in throw CocoaError(.fileWriteNoPermission) })
        model.select(active.id)
        model.editor.content = "Pending café 🐼"
        var asked = false
        #expect(throws: (any Error).self) {
            try LibraryTrashCommand.run(library: library, models: [model], confirm: { _ in asked = true; return true })
        }
        #expect(!asked)
        #expect(model.editor.content == "Pending café 🐼")
        #expect(library.notes.first { $0.id == active.id }?.content == "Original")
        #expect(library.notes.contains { $0.id == trash.id })
    }

    @Test func emptyTrashDoesNotAskAndChangedTrashCancelsDeletion() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var called = false
        #expect(try !LibraryTrashCommand.run(library: library, models: [], confirm: { _ in called = true; return true }))
        #expect(!called)
        var first = try library.createNote(content: "First disposable draft")
        first.trashedAt = Date()
        try library.saveNote(first)
        var second = try library.createNote(content: "Second neutral draft")
        #expect(throws: (any Error).self) {
            try LibraryTrashCommand.run(library: library, models: [], confirm: { _ in
                second.trashedAt = Date()
                try library.saveNote(second)
                return true
            })
        }
        #expect(library.notes.count == 2)
    }
}
