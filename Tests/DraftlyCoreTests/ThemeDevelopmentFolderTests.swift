import Foundation
import Testing
@testable import DraftlyCore

@Suite("Theme development folder") @MainActor
struct ThemeDevelopmentFolderTests {
    private func withFolder(_ body: (URL, LibraryStore, UserDefaults, String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DraftlyThemeFolder-" + UUID().uuidString)
        let suite = "Draftly.ThemeFolder." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(directory, LibraryStore(inMemory: true, seed: false), defaults, suite)
    }

    private func write(_ theme: EditorThemeDefinition, to url: URL) throws {
        try JSONEncoder().encode(theme).write(to: url, options: .atomic)
    }

    @Test func discoveryIsDirectTypedAndStableWithoutImportingUnsafeChildren() throws {
        try withFolder { directory, library, defaults, _ in
            try write(EditorThemeDefinition(name: "Beta"), to: directory.appendingPathComponent("B.DRAFTSTHEME"))
            try write(EditorThemeDefinition(name: "Alpha café 🐼"), to: directory.appendingPathComponent("A.JSON"))
            try Data("invalid hidden".utf8).write(to: directory.appendingPathComponent(".hidden.json"))
            try Data("not a theme".utf8).write(to: directory.appendingPathComponent("readme.txt"))
            let nested = directory.appendingPathComponent("nested.json")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data("invalid nested".utf8).write(to: nested.appendingPathComponent("ignored.json"))
            let outside = directory.appendingPathComponent("outside.txt")
            try Data("not JSON".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("linked.json"), withDestinationURL: outside)
            try library.saveTheme(EditorThemeDefinition(name: "Alpha café 🐼"))
            #expect(try ThemeDevelopmentFolder.select(directory, in: library, defaults: defaults) == 2)
            let files = library.themes.filter { $0.type == "file" }
            #expect(files.map(\.name) == ["Alpha café 🐼", "Beta"])
            #expect(defaults.bool(forKey: ThemeDevelopmentFolder.enabledKey))
            #expect(try ThemeDevelopmentFolder.folderName(defaults: defaults) == directory.lastPathComponent)
            let revision = defaults.integer(forKey: ThemeCatalog.revisionKey)
            library.beforeBatchCommit = { throw DraftlyError.message("An unchanged discovery must not save library records.") }
            #expect(try ThemeDevelopmentFolder.refresh(in: library, defaults: defaults) == 2)
            library.beforeBatchCommit = nil
            #expect(library.themes.filter { $0.type == "file" } == files)
            #expect(defaults.integer(forKey: ThemeCatalog.revisionKey) == revision + 1)
        }
    }

    @Test func exchangingNamesPreservesEachSourceIdentityAndUpdatesBothSnapshots() throws {
        try withFolder { directory, library, defaults, _ in
            let first = directory.appendingPathComponent("first.json"), second = directory.appendingPathComponent("second.json")
            try write(EditorThemeDefinition(name: "First", background: "111111"), to: first)
            try write(EditorThemeDefinition(name: "Second", background: "222222"), to: second)
            try ThemeDevelopmentFolder.select(directory, in: library, defaults: defaults)
            let firstID = try #require(library.themes.first { $0.name == "First" }?.id)
            let secondID = try #require(library.themes.first { $0.name == "Second" }?.id)
            try write(EditorThemeDefinition(name: "Second", background: "333333"), to: first)
            try write(EditorThemeDefinition(name: "First", background: "444444"), to: second)
            #expect(try ThemeDevelopmentFolder.refresh(in: library, defaults: defaults) == 2)
            #expect(library.themes.first { $0.id == firstID }?.name == "Second")
            #expect(library.themes.first { $0.id == firstID }?.background == "333333")
            #expect(library.themes.first { $0.id == secondID }?.name == "First")
            #expect(library.themes.first { $0.id == secondID }?.background == "444444")
            try library.reload()
            #expect(library.themes.first { $0.id == firstID }?.name == "Second")
        }
    }

    @Test func malformedLaterFileAndCommitFailureKeepEveryRecordAndPreference() throws {
        try withFolder { directory, library, defaults, suite in
            let first = directory.appendingPathComponent("a.json"), later = directory.appendingPathComponent("z.json")
            try write(EditorThemeDefinition(name: "Original", background: "111111"), to: first)
            try ThemeDevelopmentFolder.select(directory, in: library, defaults: defaults)
            let before = try library.backupData(), preferences = defaults.persistentDomain(forName: suite) ?? [:]
            try write(EditorThemeDefinition(name: "Replacement", background: "222222"), to: first)
            try Data("invalid later".utf8).write(to: later)
            var commits = 0
            library.beforeBatchCommit = { commits += 1 }
            #expect(throws: (any Error).self) { try ThemeDevelopmentFolder.refresh(in: library, defaults: defaults) }
            #expect(commits == 0 && library.themes.count == 1)
            #expect(try library.backupData() == before)
            #expect(NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:]).isEqual(to: preferences))
            try write(EditorThemeDefinition(name: "Fresh"), to: later)
            library.beforeBatchCommit = { throw DraftlyError.message("Injected folder batch failure") }
            #expect(throws: (any Error).self) { try ThemeDevelopmentFolder.refresh(in: library, defaults: defaults) }
            library.beforeBatchCommit = nil
            #expect(try library.backupData() == before)
            #expect(NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:]).isEqual(to: preferences))
            try library.reload(); #expect(try library.backupData() == before)
        }
    }

    @Test func sameNameFromAnotherSourceCannotHijackAnExistingIdentityOrFolder() throws {
        try withFolder { directory, library, defaults, suite in
            let originalFolder = directory.appendingPathComponent("Original"), otherFolder = directory.appendingPathComponent("Other")
            try FileManager.default.createDirectory(at: originalFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
            try write(EditorThemeDefinition(name: "Same café 🐼"), to: originalFolder.appendingPathComponent("one.json"))
            try ThemeDevelopmentFolder.select(originalFolder, in: library, defaults: defaults)
            let before = try library.backupData(), preferences = defaults.persistentDomain(forName: suite) ?? [:]
            try write(EditorThemeDefinition(name: "Same café 🐼", background: "123456"), to: otherFolder.appendingPathComponent("two.json"))
            #expect(throws: (any Error).self) { try ThemeDevelopmentFolder.select(otherFolder, in: library, defaults: defaults) }
            #expect(try library.backupData() == before)
            #expect(NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:]).isEqual(to: preferences))
            #expect(try ThemeDevelopmentFolder.folderName(defaults: defaults) == "Original")
        }
    }

    @Test func duplicateNamesRejectTheWholeFolderAndDoNotEnableDiscovery() throws {
        try withFolder { directory, library, defaults, suite in
            try write(EditorThemeDefinition(name: "Duplicate"), to: directory.appendingPathComponent("a.json"))
            try write(EditorThemeDefinition(name: "Duplicate"), to: directory.appendingPathComponent("b.json"))
            #expect(throws: (any Error).self) { try ThemeDevelopmentFolder.select(directory, in: library, defaults: defaults) }
            #expect(library.themes.isEmpty)
            #expect(defaults.persistentDomain(forName: suite)?.isEmpty != false)
            #expect(defaults.data(forKey: ThemeDevelopmentFolder.bookmarkKey) == nil)
        }
    }

    @Test func disabledMissingAndCorruptFolderAccessDoNotSilentlyEnableOrChangeData() throws {
        try withFolder { directory, library, defaults, suite in
            #expect(try ThemeDevelopmentFolder.refresh(in: library, defaults: defaults) == 0)
            #expect(try ThemeDevelopmentFolder.folderName(defaults: defaults) == nil)
            #expect(throws: (any Error).self) { try ThemeDevelopmentFolder.setEnabled(true, in: library, defaults: defaults) }
            #expect(!defaults.bool(forKey: ThemeDevelopmentFolder.enabledKey))
            try write(EditorThemeDefinition(name: "Retained"), to: directory.appendingPathComponent("theme.json"))
            try ThemeDevelopmentFolder.select(directory, in: library, defaults: defaults)
            let before = try library.backupData()
            #expect(try ThemeDevelopmentFolder.setEnabled(false, in: library, defaults: defaults) == 0)
            #expect(try ThemeDevelopmentFolder.refresh(in: library, defaults: defaults) == 0)
            #expect(try library.backupData() == before)
            #expect(try ThemeDevelopmentFolder.setEnabled(true, in: library, defaults: defaults) == 1)
            defaults.set(Data("corrupt".utf8), forKey: ThemeDevelopmentFolder.bookmarkKey)
            defaults.set(false, forKey: ThemeDevelopmentFolder.enabledKey)
            let preferences = defaults.persistentDomain(forName: suite) ?? [:]
            #expect(throws: (any Error).self) { try ThemeDevelopmentFolder.setEnabled(true, in: library, defaults: defaults) }
            #expect(NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:]).isEqual(to: preferences))
            #expect(try library.backupData() == before)
        }
    }

    @Test func backupExcludesFolderAccessAndAbsentSourcesAreRetainedWithoutAWrite() throws {
        try withFolder { directory, library, defaults, _ in
            let url = directory.appendingPathComponent("theme.json")
            try write(EditorThemeDefinition(name: "Local source", unknownFields: ["future": .string("café 🐼")]), to: url)
            try ThemeDevelopmentFolder.select(directory, in: library, defaults: defaults)
            let before = try library.backupData(), text = String(decoding: before, as: UTF8.self)
            #expect(!text.contains(directory.path) && !text.contains("theme.file.") && !text.contains("developmentFolder") && !text.contains("bookmark"))
            let restored = try LibraryStore(inMemory: true, seed: false)
            try restored.restore(before)
            #expect(restored.themes == library.themes)
            let otherSuite = "Draftly.ThemeFolder.Restore." + UUID().uuidString
            let other = try #require(UserDefaults(suiteName: otherSuite))
            defer { other.removePersistentDomain(forName: otherSuite) }
            #expect(try ThemeDevelopmentFolder.refresh(in: restored, defaults: other) == 0)
            let definition = try #require(restored.themes.first)
            #expect(throws: (any Error).self) { try ThemeFileAccess.read(definition, defaults: other) }
            try FileManager.default.removeItem(at: url)
            library.beforeBatchCommit = { throw DraftlyError.message("An empty discovery must not change library records.") }
            #expect(try ThemeDevelopmentFolder.refresh(in: library, defaults: defaults) == 0)
            library.beforeBatchCommit = nil
            #expect(try library.backupData() == before)
            #expect(throws: (any Error).self) { try ThemeFileAccess.read(definition, defaults: defaults) }
        }
    }
}
