import Foundation
import Testing
@testable import DraftlyCore

@Suite("Shared theme persistence") @MainActor
struct ThemePersistenceTests {
    private func theme(_ name: String = "Neutral") -> EditorThemeDefinition {
        var value = EditorThemeDefinition(); value.name = name; return value
    }

    @Test func legacyShapeAndUnknownFieldsSurviveEditingAndBackup() throws {
        let json = #"{"id":"CAA7908F-9AAF-45DA-900D-C4E070783AA2","name":"Neutral","foreground":"202020","background":"FFFFFF","heading":"007AFF","isDark":false,"grammar":{"colors":[null,true,12.25,"café 🐼"]}}"#
        var value = try JSONDecoder().decode(EditorThemeDefinition.self, from: Data(json.utf8))
        let unknown = value.unknownFields
        value.heading = "FF00FF"
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveTheme(value)
        let destination = try LibraryStore(inMemory: true, seed: false)
        try destination.restore(library.backupData())
        #expect(destination.themes == [value])
        #expect(destination.themes.first?.unknownFields == unknown)
        let roundTrip = try JSONDecoder().decode(EditorThemeDefinition.self, from: JSONEncoder().encode(value))
        #expect(roundTrip == value)
    }

    @Test func saveRejectsInvalidColorsDuplicateNamesAndIdentitiesBeforeChangingRecords() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = theme()
        try library.saveTheme(original)
        var invalid = theme("Invalid"); invalid.background = "GGGGGG"
        #expect(throws: (any Error).self) { try library.saveThemes([theme("Fresh"), invalid]) }
        #expect(throws: (any Error).self) { try library.saveThemes([theme()]) }
        #expect(throws: (any Error).self) { try library.saveThemes([original, original]) }
        #expect(throws: (any Error).self) { try library.saveTheme(theme("System")) }
        #expect(throws: (any Error).self) { try library.saveTheme(theme(" \n")) }
        #expect(library.themes == [original])
        try library.reload()
        #expect(library.themes == [original])
        // These names were valid in the previous local theme editor.
        try library.saveThemes([theme("Dark"), theme("Light"), theme("Default")])
        #expect(library.themes.count == 4)
    }

    @Test func failedBatchAndRestoreRollBackThemesAndOtherRecords() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = theme(); try library.saveTheme(original)
        var replacement = original; replacement.foreground = "000000"
        library.beforeBatchCommit = { throw DraftlyError.message("Injected write failure") }
        #expect(throws: (any Error).self) { try library.saveThemes([replacement, theme("Fresh")]) }
        #expect(library.themes == [original])
        let backup = Backup(notes: [Note(content: "Neutral backup")], revisions: [], workspaces: [], actions: [], themes: [replacement])
        #expect(throws: (any Error).self) { try library.restore(JSONEncoder().encode(backup)) }
        #expect(library.themes == [original] && library.notes.isEmpty)
        library.beforeBatchCommit = nil
        var invalid = theme("Invalid"); invalid.heading = "blue"
        let badBackup = Backup(notes: [Note(content: "Must not appear")], revisions: [], workspaces: [], actions: [], themes: [invalid])
        #expect(throws: (any Error).self) { try library.restore(JSONEncoder().encode(badBackup)) }
        #expect(library.themes == [original] && library.notes.isEmpty)
    }

    @Test func oldBackupsRemainReadableAndNameConflictsDoNotPartiallyRestore() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = theme(); try library.saveTheme(original)
        let old = Data(#"{"version":1,"notes":[],"revisions":[],"workspaces":[],"actions":[]}"#.utf8)
        try library.restore(old)
        #expect(library.themes == [original])
        let conflicting = Backup(notes: [Note(content: "Must not appear")], revisions: [], workspaces: [], actions: [], themes: [theme()])
        #expect(throws: (any Error).self) { try library.restore(JSONEncoder().encode(conflicting)) }
        #expect(library.themes == [original] && library.notes.isEmpty)
    }

    @Test func migrationIsAtomicAndRunsOnceAfterReopenEvenAfterThemeDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try LibraryStore(directory: directory, seed: false)
        let first = theme()
        library.beforeBatchCommit = { throw DraftlyError.message("Injected migration failure") }
        #expect(throws: (any Error).self) { try library.migrateThemes([first], migrationID: "local-v1") }
        #expect(library.themes.isEmpty)
        library.beforeBatchCommit = nil
        try library.migrateThemes([first], migrationID: "local-v1")
        var localOld = first; localOld.foreground = "111111"
        try library.migrateThemes([localOld, theme("Fresh")], migrationID: "another-source")
        #expect(library.themes.first(where: { $0.id == first.id }) == first)
        try library.deleteTheme(first.id)
        let reopened = try LibraryStore(directory: directory, seed: false)
        try reopened.migrateThemes([first], migrationID: "local-v1")
        #expect(!reopened.themes.contains(where: { $0.id == first.id }))
        #expect(reopened.themes.map(\.name) == ["Fresh"])
    }
}
