import Foundation
import Testing
@testable import DraftlyCore

@Suite("Exact Unicode draft persistence") @MainActor
struct UnicodeDraftPersistenceTests {
    @Test func canonicalVariantsAreDistinctContentEvenWhenDatesArePreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(directory: root, seed: false)
        let original = try library.createNote(content: "Café 🐼")
        var changed = original; changed.content = "Cafe\u{0301} 🐼"
        #expect(original.content == changed.content)
        try library.saveNote(changed, preserveDates: true)
        let stored = try #require(library.notes.first)
        #expect(stored.content.utf8.elementsEqual(changed.content.utf8))
        #expect(library.revisions.filter { $0.noteID == original.id }.count == 2)
        let reopened = try LibraryStore(directory: root, seed: false)
        #expect(try #require(reopened.notes.first).content.utf8.elementsEqual(changed.content.utf8))
    }
}
