import Foundation
import CoreData
import Testing
@testable import DraftlyCore

@Suite("Access date contracts") @MainActor
struct AccessDateTests {
    enum Failure: Error { case storage }

    @Test func openingPreservesContentModifiedDateAndVersions() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let date = Date(timeIntervalSince1970: 100)
        let note = Note(content: "Café 🐼", createdAt: date, modifiedAt: date)
        try store.saveNote(note, preserveDates: true)
        let revisions = store.revisions
        let access = Date(timeIntervalSince1970: 200)
        try store.recordAccess(note.id, at: access)
        let saved = try #require(store.notes.first)
        #expect(saved.accessedAt == access)
        #expect(saved.content == note.content && saved.modifiedAt == date && saved.createdAt == date)
        #expect(store.revisions == revisions)
        try store.recordAccess(note.id, at: date)
        #expect(store.notes.first?.accessedAt == access)
        var stale = note; stale.content = "Edited"
        try store.saveNote(stale)
        #expect(store.notes.first?.accessedAt == access)
    }

    @Test func openingDoesNotWriteTheContentRecord() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let note = try store.createNote(content: "Original 🐼")
        let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
        request.predicate = NSPredicate(format: "key == %@", "note:" + note.id.uuidString)
        let record = try #require(store.container.viewContext.fetch(request).first)
        let payload = record.value(forKey: "payload") as? String
        let modified = record.value(forKey: "modified") as? Date
        let date = Date().addingTimeInterval(10)
        try store.recordAccess(note.id, at: date)
        #expect(record.value(forKey: "payload") as? String == payload)
        #expect(record.value(forKey: "modified") as? Date == modified)
        var remote = note
        remote.content = "Remote edit Café"
        record.setValue(String(decoding: try JSONEncoder().encode(remote), as: UTF8.self), forKey: "payload")
        try store.container.viewContext.save()
        try store.reload()
        #expect(store.notes.first?.content == remote.content)
        #expect(store.notes.first?.accessedAt == date)
        try store.reload()
        #expect(store.notes.first?.accessedAt == date)
    }

    @Test func failedAccessDoesNotChangeTheStoredDraft() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let note = try store.createNote(content: "Original")
        let before = try #require(store.notes.first)
        let revisions = store.revisions
        store.beforeBatchCommit = { throw Failure.storage }
        #expect(throws: Failure.self) { try store.recordAccess(note.id) }
        #expect(store.notes.first == before)
        #expect(store.revisions == revisions)
        #expect(throws: (any Error).self) { try store.recordAccess(UUID()) }
        #expect(throws: (any Error).self) { try store.recordAccess(note.id, at: Date(timeIntervalSince1970: .infinity)) }
    }

    @Test func oldNotesKeepUnknownDatesAndBackupsPreserveKnownDates() throws {
        let note = Note(content: "Legacy")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        object.removeValue(forKey: "accessedAt")
        let legacy = try JSONDecoder().decode(Note.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.accessedAt == nil)
        let store = try LibraryStore(inMemory: true, seed: false)
        try store.saveNote(legacy)
        try store.recordAccess(legacy.id, at: Date(timeIntervalSince1970: 500))
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(store.backupData())
        #expect(restored.notes.first?.accessedAt == Date(timeIntervalSince1970: 500))
        #expect(DraftOperations.duplicate(try #require(restored.notes.first)).accessedAt == nil)
    }

    @Test func queriesSortUnknownDatesLastAndDoNotRecordAccess() throws {
        let old = Note(content: "Old", accessedAt: Date(timeIntervalSince1970: 100))
        let new = Note(content: "New", accessedAt: Date(timeIntervalSince1970: 200))
        let unknown = Note(content: "Unknown")
        var workspace = Workspace(name: "Access"); workspace.sort = .accessed
        workspace.ascending = true
        #expect(workspace.filter([unknown, new, old]).map(\.id) == [old.id, new.id, unknown.id])
        workspace.ascending = false
        #expect(workspace.filter([unknown, old, new]).map(\.id) == [new.id, old.id, unknown.id])
        #expect(unknown.accessedAt == nil)
        let encoded = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: encoded)
        #expect(decoded.filter([old, unknown, new]).map(\.id) == [new.id, old.id, unknown.id])
    }

    @Test func dateFiltersExcludeUnknownAccessDates() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_577_880_000)
        var workspace = Workspace(name: "Access filter")
        let options: [String: Any] = ["startDate": ["type": "absolute", "field": "accessed", "date": APIValues.date(date)],
                                      "endDate": ["type": "absolute", "field": "accessed", "date": APIValues.date(date)]]
        workspace.scriptMetadata = ["api": String(decoding: try JSONSerialization.data(withJSONObject: options), as: UTF8.self)]
        #expect(workspace.matchesScriptFilters(Note(content: "Today", accessedAt: date), calendar: calendar))
        #expect(!workspace.matchesScriptFilters(Note(content: "Unknown"), calendar: calendar))
        #expect(!workspace.matchesScriptFilters(Note(content: "Before", accessedAt: date.addingTimeInterval(-86400)), calendar: calendar))
        #expect(!workspace.matchesScriptFilters(Note(content: "After", accessedAt: date.addingTimeInterval(86400)), calendar: calendar))
    }
}
