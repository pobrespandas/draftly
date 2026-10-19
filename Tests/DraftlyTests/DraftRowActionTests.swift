import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Draft row swipe actions") @MainActor
struct DraftRowActionTests {
    @Test func swipeArchivesOnlyItsCapturedRowAndKeepsTheEditor() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "Selected draft")
        let second = try library.createNote(content: "Swiped draft")
        let model = WindowModel(library: library); model.select(first.id)
        let commands = model.swipeCommands(for: second.id)
        #expect(commands.map(\.title) == ["Trash", "Archive"])
        let table = NSTableView()
        let native = commands.map { $0.nativeAction(model: model, table: table) }
        #expect(native[0].style == .destructive)
        #expect(native[0].image != nil && native[1].image != nil)
        commands[1].perform(on: model)
        #expect(library.notes.first { $0.id == second.id }?.isArchived == true)
        #expect(library.notes.first { $0.id == first.id }?.isArchived == false)
        #expect(model.editor.noteID == first.id)
        #expect(model.swipeCommands(for: second.id).map(\.title) == ["Trash", "Inbox"])
    }
    @Test func failedSaveDoesNotTrashTheRowAndRestoreKeepsArchiveState() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "Editor")
        let second = try library.createNote(content: "Target")
        let failing = WindowModel(library: library, saveDraft: { _ in throw DraftlyError.message("Disk full") })
        failing.select(first.id); failing.editor.content = "Unsaved edit"; failing.contentChanged()
        failing.swipeCommands(for: second.id)[0].perform(on: failing)
        #expect(library.notes.first { $0.id == second.id }?.trashedAt == nil)
        #expect(failing.editor.content == "Unsaved edit")
        let model = WindowModel(library: library)
        model.moveDrafts([second.id], to: .archive)
        model.swipeCommands(for: second.id)[0].perform(on: model)
        #expect(library.notes.first { $0.id == second.id }?.trashedAt != nil)
        let restore = model.swipeCommands(for: second.id)
        #expect(restore.map(\.title) == ["Restore"])
        restore[0].perform(on: model)
        #expect(library.notes.first { $0.id == second.id }?.trashedAt == nil)
        #expect(library.notes.first { $0.id == second.id }?.isArchived == true)
    }
}
