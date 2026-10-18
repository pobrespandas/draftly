import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Recent drafts") @MainActor
struct RecentDraftStoreTests {
    @Test func storesMostRecentDraftsAcrossInstances() throws {
        let domain = "DraftlyTests.RecentDrafts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        let ids = (0..<12).map { _ in UUID() }
        let store = RecentDraftStore(defaults: defaults, key: "recent", limit: 10)
        for id in ids { store.record(id) }

        #expect(store.ids == Array(ids.reversed().prefix(10)))
        #expect(RecentDraftStore(defaults: defaults, key: "recent", limit: 10).ids == store.ids)
    }

    @Test func omitsDeletedAndTrashedDrafts() throws {
        let domain = "DraftlyTests.RecentDrafts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        let library = try LibraryStore(inMemory: true, seed: false)
        let active = try library.createNote(content: "Active draft")
        var trashed = try library.createNote(content: "Trashed draft")
        trashed.trashedAt = Date()
        try library.saveNote(trashed)

        let store = RecentDraftStore(defaults: defaults, key: "recent")
        store.record(UUID())
        store.record(trashed.id)
        store.record(active.id)

        #expect(store.notes(in: library).map(\.id) == [active.id])
        #expect(store.ids == [active.id])
    }
}
