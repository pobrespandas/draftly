import Foundation
import Testing
@testable import DraftlyCore

@Suite("Draft operations") @MainActor
struct DraftOperationsTests {
    enum Failure: Error { case save }

    @Test func mergeDialogOptionsAndAtomicMovement() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let a = try store.createNote(content: "A 🐼"), b = try store.createNote(content: "B café")
        let originals = store.notes
        store.beforeBatchCommit = { throw Failure.save }
        #expect(throws: Failure.self) { try store.mergeNotes([a, b]) }
        #expect(Dictionary(uniqueKeysWithValues: store.notes.map { ($0.id, $0) }) == Dictionary(uniqueKeysWithValues: originals.map { ($0.id, $0) }))
        store.beforeBatchCommit = nil
        let merged = try store.mergeNotes([b, a])
        #expect(merged.content == "B café\nA 🐼")
        #expect(store.notes.filter { $0.id == a.id || $0.id == b.id }.allSatisfy { $0.isArchived })
        #expect(!merged.isArchived && merged.trashedAt == nil && merged.flag == 0)
        let kept = store.notes
        _ = try store.mergeNotes([a, b], separator: "---", includeBlankLine: true, destination: .keep)
        #expect([a.id, b.id].allSatisfy { id in store.notes.first { $0.id == id } == kept.first { $0.id == id } })
        let trash = try store.mergeNotes([a, b], separator: "---", destination: .trash)
        #expect(trash.content == "A 🐼\n---\nB café")
        #expect(store.notes.filter { $0.id == a.id || $0.id == b.id }.allSatisfy { $0.trashedAt != nil })
        #expect(try DraftOperations.merge([a, b], separator: "---", includeBlankLine: true).content == "A 🐼\n\n---\n\nB café")
    }

    @Test func batchSaveRollsBackEveryDraftAndRevision() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let a = try store.createNote(content: "A"), b = try store.createNote(content: "B")
        let savedA = try #require(store.notes.first { $0.id == a.id }), savedB = try #require(store.notes.first { $0.id == b.id })
        let revisions = store.revisions
        var changedA = a, changedB = b; changedA.content = "Changed A"; changedB.content = "Changed B"
        store.beforeBatchCommit = { throw Failure.save }
        #expect(throws: Failure.self) { try store.saveNotes([changedA, changedB]) }
        #expect(store.notes.first { $0.id == a.id } == savedA)
        #expect(store.notes.first { $0.id == b.id } == savedB)
        #expect(store.revisions == revisions)
        store.beforeBatchCommit = nil
        try store.saveNotes([changedA, changedB])
        #expect(store.notes.allSatisfy { $0.content.hasPrefix("Changed") })
    }
    @Test func duplicateHasNewIdentityWithoutSourceHistory() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        var source = Note(content: "Source", tags: ["work"], flag: 7, isArchived: true, trashedAt: Date(), createdAt: .distantPast, syntax: "Plain Text")
        source.scriptMetadata = ["secret": "internal"]
        try store.saveNote(source, preserveDates: true)
        let copies = try store.duplicateNotes([source])
        let copy = try #require(copies.first)
        #expect(copy.id != source.id && copy.createdAt > source.createdAt)
        #expect(copy.content == source.content && copy.tags == source.tags && copy.flag == 7 && copy.syntax == source.syntax)
        #expect(!copy.isArchived && copy.trashedAt == nil && copy.scriptMetadata == nil)
        #expect(store.revisions.allSatisfy { $0.noteID != copy.id })
        #expect(store.notes.first { $0.id == source.id } == source)
    }
    @Test func mergeUsesVisibleOrderAndKeepsSources() throws {
        let first = Note(content: "First", tags: ["Work"], flag: 4, syntax: "Plain Text")
        let second = Note(content: "Second", tags: ["work", "other"], syntax: "Markdown")
        let merged = try DraftOperations.merge([second, first])
        #expect(merged.content == "Second\n\nFirst")
        #expect(merged.tags == ["other", "work"] && merged.syntax == "Markdown" && merged.flag == 0)
        #expect(merged.id != first.id && merged.id != second.id && !merged.isArchived && merged.trashedAt == nil)
        #expect(throws: (any Error).self) { try DraftOperations.merge([first]) }
        #expect(try DraftOperations.merge([first, first]).syntax == "Plain Text")
    }
    @Test func exportsRoundTripMetadataAndEscapeCSV() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.125)
        let source = Note(content: "Título, 🐼\n\"quoted\"\r\nbody", tags: ["tag,one", "tag\"two"], flag: 7,
                          isArchived: true, trashedAt: date, createdAt: date, modifiedAt: date, syntax: "Plain Text")
        let json = try DraftOperations.export([source], as: .json)
        let imported = try #require(try ActionImporter.importNotes(json).first)
        #expect(imported == source)
        let csv = String(decoding: try DraftOperations.export([source], as: .csv), as: UTF8.self)
        #expect(csv.hasPrefix("uuid,title,content,tags,flag,syntax,isArchived,trashedAt,createdAt,modifiedAt\r\n"))
        #expect(csv.contains("\"\"quoted\"\"") && csv.contains("Título, 🐼") && csv.contains("tag,one"))
        #expect(String(decoding: try DraftOperations.export([source, source], as: .txt), as: UTF8.self) == source.content + "\n\n" + source.content)
        let legacy = Data("[{\"content\":\"Old\",\"isFlagged\":true}]".utf8)
        let old = try #require(try ActionImporter.importNotes(legacy).first)
        #expect(old.flag == 1 && old.syntax == "Markdown" && old.trashedAt == nil)
    }
    @Test func emptyTrashIsAtomicAndRetainsActionHistory() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let saved = try store.createNote(content: "Keep")
        let trashed = Note(content: "Delete", trashedAt: Date()); try store.saveNote(trashed)
        var run = ActionRun(actionName: "Past", status: "Success", message: ""); run.noteID = trashed.id; store.log(run)
        store.beforeBatchCommit = { throw Failure.save }
        #expect(throws: Failure.self) { try store.emptyTrash() }
        #expect(store.notes.count == 2 && store.revisions.contains { $0.noteID == trashed.id })
        store.beforeBatchCommit = nil; try store.emptyTrash()
        #expect(store.notes.map(\.id) == [saved.id])
        #expect(!store.revisions.contains { $0.noteID == trashed.id })
        #expect(store.runs.contains { $0.id == run.id })
    }
    @Test func shortcutValidationNormalizesAndFindsBothKindsOfConflict() {
        var action = DraftAction(name: "Test", steps: []); action.shortcut = "P"; action.shortcutModifiers = [" SHIFT ", "COMMAND", "command"]
        #expect(ActionShortcut.conflict(for: action, in: [])?.contains("Command Palette") == true)
        action.shortcut = "k"; action.shortcutModifiers = ["command", "option"]
        #expect(ActionShortcut.conflict(for: action, in: [action]) == nil)
        var other = action; other.id = UUID(); other.name = "Other"; other.shortcut = "K"
        #expect(ActionShortcut.conflict(for: action, in: [action, other])?.contains("Other") == true)
        action.shortcut = ""; #expect(ActionShortcut.conflict(for: action, in: [other]) == nil)
        action.shortcut = "ab"; #expect(ActionShortcut.conflict(for: action, in: []) != nil)
    }
}
