import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Local theme migration") @MainActor
struct LocalThemeMigrationTests {
    @Test func migrationMovesDefinitionsOnceAndKeepsDevicePreferences() throws {
        let suite = "Draftly.ThemeMigration.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = try LibraryStore(inMemory: true, seed: false)
        var theme = EditorTheme(); theme.name = "Neutral 🐼"
        defaults.set(String(decoding: try JSONEncoder().encode([theme]), as: UTF8.self), forKey: LocalThemeMigration.key)
        defaults.set(theme.name, forKey: "editor.theme")
        defaults.set("Menlo-Regular", forKey: "editor.fontName")
        try LocalThemeMigration.run(in: library, defaults: defaults)
        #expect(library.themes == [theme])
        #expect(defaults.object(forKey: LocalThemeMigration.key) == nil)
        #expect(defaults.string(forKey: "editor.theme") == theme.name)
        #expect(defaults.string(forKey: "editor.fontName") == "Menlo-Regular")
        try library.deleteTheme(theme.id)
        defaults.set(String(decoding: try JSONEncoder().encode([theme]), as: UTF8.self), forKey: LocalThemeMigration.key)
        try LocalThemeMigration.run(in: library, defaults: defaults)
        #expect(library.themes.isEmpty)
    }

    @Test func secondDeviceMigratesItsOwnDefinitionsAndStorageFailureKeepsLegacyData() throws {
        let firstName = "Draftly.ThemeMigration.\(UUID())", secondName = "Draftly.ThemeMigration.\(UUID())"
        let first = try #require(UserDefaults(suiteName: firstName))
        let second = try #require(UserDefaults(suiteName: secondName))
        defer { first.removePersistentDomain(forName: firstName); second.removePersistentDomain(forName: secondName) }
        let library = try LibraryStore(inMemory: true, seed: false)
        var a = EditorTheme(); a.name = "First Mac"
        var b = EditorTheme(); b.name = "Second Mac"
        first.set(String(decoding: try JSONEncoder().encode([a]), as: UTF8.self), forKey: LocalThemeMigration.key)
        second.set(String(decoding: try JSONEncoder().encode([b]), as: UTF8.self), forKey: LocalThemeMigration.key)
        try LocalThemeMigration.run(in: library, defaults: first)
        library.beforeBatchCommit = { throw DraftlyError.message("Test write failure") }
        #expect(throws: (any Error).self) { try LocalThemeMigration.run(in: library, defaults: second) }
        #expect(second.string(forKey: LocalThemeMigration.key) != nil)
        #expect(library.themes == [a])
        library.beforeBatchCommit = nil
        try LocalThemeMigration.run(in: library, defaults: second)
        #expect(Set(library.themes.map(\.id)) == [a.id, b.id])
        #expect(second.object(forKey: LocalThemeMigration.key) == nil)
    }

    @Test func invalidLegacyDataStaysAvailableForRetry() throws {
        let suite = "Draftly.ThemeMigration.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = try LibraryStore(inMemory: true, seed: false)
        defaults.set("invalid", forKey: LocalThemeMigration.key)
        #expect(throws: (any Error).self) { try LocalThemeMigration.run(in: library, defaults: defaults) }
        #expect(defaults.string(forKey: LocalThemeMigration.key) == "invalid")
        #expect(library.themes.isEmpty)
        var theme = EditorTheme(); theme.name = "Retry"
        defaults.set(String(decoding: try JSONEncoder().encode([theme]), as: UTF8.self), forKey: LocalThemeMigration.key)
        try LocalThemeMigration.run(in: library, defaults: defaults)
        #expect(library.themes == [theme])
    }
}
