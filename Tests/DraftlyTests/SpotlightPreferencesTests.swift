import CoreSpotlight
import DraftlyCore
import Testing
@testable import Draftly

@Suite("Spotlight preferences") @MainActor
struct SpotlightPreferencesTests {
    @Test func optInIndexesSavedUnicodeDraftsAndRemovesTrashWithoutChangingNotes() async throws {
        let preferences = try TestPreferences(prefix: "SpotlightContracts-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "# Café 🐼\nNeutral searchable body", tags: ["neutral"])
        var archived = Note(content: "Archive"); archived.isArchived = true
        try library.saveNote(archived)
        var trashed = Note(content: "Trash"); trashed.trashedAt = Date()
        try library.saveNote(trashed)
        let original = library.notes
        var snapshots: [[SpotlightDraft]] = []
        var removals = 0
        let model = SpotlightPreferences(defaults: preferences.defaults, isAvailable: true,
            replace: { snapshots.append($0) }, clear: { removals += 1 })
        model.attach(to: library)
        await model.waitForUpdates()
        #expect(!model.isEnabled && snapshots.isEmpty && removals == 0)
        model.setEnabled(true)
        await model.waitForUpdates()
        #expect(preferences.defaults.bool(forKey: SpotlightPreferences.enabledKey))
        let actualIDs = Set(snapshots.last?.map(\.id) ?? [])
        let expectedIDs = Set([note.id, archived.id])
        #expect(actualIDs == expectedIDs)
        #expect(snapshots.last?.map(\.id.uuidString) == expectedIDs.map(\.uuidString).sorted())
        let indexed = try #require(snapshots.last?.first { $0.id == note.id })
        #expect(indexed.title == "Café 🐼" && indexed.content == note.content && indexed.tags == ["neutral"])
        #expect(indexed.createdAt == note.createdAt && indexed.modifiedAt == note.modifiedAt)
        #expect(library.notes == original)
        let updateCount = snapshots.count
        try library.recordAccess(note.id)
        await model.waitForUpdates()
        #expect(snapshots.count == updateCount)
        var changed = note; changed.content += " Updated"
        try library.saveNote(changed)
        await model.waitForUpdates()
        #expect(snapshots.last?.first { $0.id == note.id }?.content == changed.content)
        changed.trashedAt = Date()
        try library.saveNote(changed)
        await model.waitForUpdates()
        #expect(snapshots.last?.map(\.id) == [archived.id])
        model.setEnabled(false)
        await model.waitForUpdates()
        #expect(removals == 1 && !preferences.defaults.bool(forKey: SpotlightPreferences.hasIndexKey))
    }

    @Test func disablingDuringAnUpdateClearsAfterTheOlderWrite() async throws {
        let preferences = try TestPreferences(prefix: "SpotlightOrdering-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Neutral")
        var finish: CheckedContinuation<Void, Never>?
        let signal = AsyncStream<Void>.makeStream()
        var operations: [String] = []
        let model = SpotlightPreferences(defaults: preferences.defaults, isAvailable: true, replace: { _ in
            operations.append("index started")
            signal.continuation.yield(())
            await withCheckedContinuation { finish = $0 }
            operations.append("index finished")
        }, clear: { operations.append("clear") })
        model.attach(to: library)
        model.setEnabled(true)
        var iterator = signal.stream.makeAsyncIterator()
        _ = await iterator.next()
        model.setEnabled(false)
        finish?.resume()
        await model.waitForUpdates()
        #expect(operations == ["index started", "index finished", "clear"])
        #expect(!model.isChanging && model.error == nil)
    }

    @Test func failureStaysVisibleAndPendingRemovalRetriesAfterRestart() async throws {
        let preferences = try TestPreferences(prefix: "SpotlightFailure-")
        defer { preferences.close() }
        preferences.defaults.set(true, forKey: SpotlightPreferences.hasIndexKey)
        let library = try LibraryStore(inMemory: true, seed: false)
        var fail = true
        var removals = 0
        let model = SpotlightPreferences(defaults: preferences.defaults, isAvailable: true, replace: { _ in }, clear: {
            removals += 1
            if fail { throw DraftlyError.message("Neutral index failure") }
        })
        model.attach(to: library)
        await model.waitForUpdates()
        #expect(model.error == "Neutral index failure")
        #expect(preferences.defaults.bool(forKey: SpotlightPreferences.hasIndexKey))
        fail = false
        let restarted = SpotlightPreferences(defaults: preferences.defaults, isAvailable: true, replace: { _ in }, clear: { removals += 1 })
        restarted.attach(to: library)
        await restarted.waitForUpdates()
        #expect(removals == 2 && restarted.error == nil)
        #expect(!preferences.defaults.bool(forKey: SpotlightPreferences.hasIndexKey))
    }

    @Test func failedIndexingRetainsTheOptInAndCanRetryWithoutAnotherToggle() async throws {
        let preferences = try TestPreferences(prefix: "SpotlightRetry-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Neutral retry")
        var calls = 0
        var fail = true
        let model = SpotlightPreferences(defaults: preferences.defaults, isAvailable: true, replace: { _ in
            calls += 1
            if fail { throw DraftlyError.message("Index unavailable") }
        }, clear: { })
        model.attach(to: library)
        model.setEnabled(true)
        await model.waitForUpdates()
        #expect(model.isEnabled && model.error == "Index unavailable")
        #expect(preferences.defaults.bool(forKey: SpotlightPreferences.hasIndexKey))
        fail = false
        model.retry()
        await model.waitForUpdates()
        #expect(calls == 2 && model.error == nil && !model.isChanging)
    }

    @Test func unavailableServiceDoesNotPretendToEnableOrRunAnOperation() async throws {
        let preferences = try TestPreferences(prefix: "SpotlightUnavailable-")
        defer { preferences.close() }
        var calls = 0
        let model = SpotlightPreferences(defaults: preferences.defaults, isAvailable: false,
            replace: { _ in calls += 1 }, clear: { calls += 1 })
        model.attach(to: try LibraryStore(inMemory: true, seed: false))
        model.setEnabled(true); model.retry()
        await model.waitForUpdates()
        #expect(!model.isEnabled && calls == 0)
        #expect(preferences.defaults.object(forKey: SpotlightPreferences.enabledKey) == nil)
    }

    @Test func activityResolutionAcceptsOnlyValidSpotlightDraftIdentifiers() {
        let id = UUID()
        #expect(SpotlightPreferences.draftID(activityType: CSSearchableItemActionType,
            userInfo: [CSSearchableItemActivityIdentifier: id.uuidString]) == id)
        #expect(SpotlightPreferences.draftID(activityType: "unrelated", userInfo: [CSSearchableItemActivityIdentifier: id.uuidString]) == nil)
        #expect(SpotlightPreferences.draftID(activityType: CSSearchableItemActionType, userInfo: [CSSearchableItemActivityIdentifier: "invalid"]) == nil)
        #expect(SpotlightPreferences.draftID(activityType: CSSearchableItemActionType, userInfo: nil) == nil)
    }
}
