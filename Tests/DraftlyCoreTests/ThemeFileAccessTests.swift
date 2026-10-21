import Foundation
import Testing
@testable import DraftlyCore

@Suite("File theme access") @MainActor
struct ThemeFileAccessTests {
    private func withFiles(_ body: (URL, UserDefaults, String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DraftlyTheme-" + UUID().uuidString)
        let suite = "Draftly.ThemeFile." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(directory, defaults, suite)
    }

    private func write(_ definition: EditorThemeDefinition, to url: URL) throws {
        try JSONEncoder().encode(definition).write(to: url, options: .atomic)
    }

    private func officialSource(name: String = "Neutral café 🐼") -> [String: Any] {
        ["name": name, "description": "Neutral file theme", "isDark": true,
         "colors": ["editor": [:] as [String: String], "interface": ["textForeground": "#EFEFEF", "textBackground": "#102030"]],
         "scopes": ["text.normal": ["settings": ["foreground": "#EFEFEF"]]],
         "future": ["values": [false, "café 🐼"] as [Any]]]
    }

    @Test func storedTypeDefaultsToCustomAndFileSnapshotsKeepUnknownFields() throws {
        let custom = EditorThemeDefinition(name: "Older custom", unknownFields: ["future": .object(["keep": .bool(true)])])
        let encoded = try JSONEncoder().encode(custom)
        let old = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(old["type"] == nil)
        #expect(try JSONDecoder().decode(EditorThemeDefinition.self, from: encoded) == custom)
        var file = custom; file.type = "file"
        let fileData = try JSONEncoder().encode(file)
        #expect(try JSONDecoder().decode(EditorThemeDefinition.self, from: fileData) == file)
        let stored = try #require(JSONSerialization.jsonObject(with: fileData) as? [String: Any])
        #expect(stored["type"] as? String == "file")
        var invalid = custom; invalid.type = "builtIn"
        #expect(throws: (any Error).self) { try invalid.validate() }
        invalid.type = "future"
        #expect(throws: (any Error).self) { try invalid.validate() }
        var wrongType = old; wrongType["type"] = false
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EditorThemeDefinition.self, from: JSONSerialization.data(withJSONObject: wrongType))
        }
    }

    @Test func prepareAcceptsOfficialAndNativeDefinitionsWithTheSuppliedIdentity() throws {
        try withFiles { directory, _, _ in
            let url = directory.appendingPathComponent("Neutral.draftsTheme")
            let source = officialSource()
            try JSONSerialization.data(withJSONObject: source).write(to: url)
            let id = UUID()
            let prepared = try ThemeFileAccess.prepare(url, id: id)
            #expect(prepared.definition.id == id && prepared.definition.type == "file")
            #expect(prepared.definition.name == "Neutral café 🐼" && prepared.definition.background == "102030")
            #expect(!prepared.bookmark.isEmpty)
            guard case .object(let original) = prepared.definition.unknownFields["draftsSource"] else {
                Issue.record("The original Drafts definition was lost."); return
            }
            #expect(original["future"] != nil)
            let native = EditorThemeDefinition(name: "Native café 🐼", background: "ABCDEF", unknownFields: ["future": .array([.bool(false), .string("🦊")])])
            try write(native, to: url)
            let nativePrepared = try ThemeFileAccess.prepare(url, id: id)
            #expect(nativePrepared.definition.id == id && nativePrepared.definition.type == "file")
            #expect(nativePrepared.definition.background == "ABCDEF" && nativePrepared.definition.unknownFields == native.unknownFields)
        }
    }

    @Test func readReloadsExternalChangesWithoutSavingTheSnapshotOrChangingCustomThemes() throws {
        try withFiles { directory, defaults, _ in
            let url = directory.appendingPathComponent("Neutral.draftsTheme")
            var source = officialSource()
            try JSONSerialization.data(withJSONObject: source).write(to: url)
            let prepared = try ThemeFileAccess.prepare(url)
            let library = try LibraryStore(inMemory: true, seed: false)
            try ThemeFileAccess.install(prepared, in: library, defaults: defaults)
            #expect(library.themes == [prepared.definition])
            source["colors"] = ["editor": [:] as [String: String], "interface": ["textForeground": "#EFEFEF", "textBackground": "#304050"]]
            source["future"] = ["updated": "Neutral 🦊"]
            try JSONSerialization.data(withJSONObject: source).write(to: url, options: .atomic)
            let current = try ThemeFileAccess.read(prepared.definition, defaults: defaults)
            #expect(current.id == prepared.definition.id && current.type == "file" && current.background == "304050")
            guard case .object(let original) = current.unknownFields["draftsSource"] else {
                Issue.record("The updated source was lost."); return
            }
            #expect(original["future"] == .object(["updated": .string("Neutral 🦊")]))
            #expect(library.themes == [prepared.definition])
            #expect(library.notes.isEmpty && library.revisions.isEmpty && library.runs.isEmpty)
            let custom = EditorThemeDefinition(name: "No external read")
            #expect(try ThemeFileAccess.read(custom, defaults: defaults) == custom)
        }
    }

    @Test func missingInvalidDeletedAndRenamedFilesFailWithoutChangingTheSnapshotOrBookmark() throws {
        try withFiles { directory, defaults, suite in
            let url = directory.appendingPathComponent("Neutral.json")
            let original = EditorThemeDefinition(name: "Stable name")
            try write(original, to: url)
            let prepared = try ThemeFileAccess.prepare(url)
            let library = try LibraryStore(inMemory: true, seed: false)
            try ThemeFileAccess.install(prepared, in: library, defaults: defaults)
            let key = ThemeFileAccess.bookmarkKey(for: prepared.definition.id)
            let bookmark = try #require(defaults.data(forKey: key))
            defaults.removeObject(forKey: key)
            do {
                _ = try ThemeFileAccess.read(prepared.definition, defaults: defaults)
                Issue.record("A file theme without local access was read.")
            } catch { #expect(error.localizedDescription.contains("Reselect")) }
            defaults.set(Data("invalid bookmark".utf8), forKey: key)
            #expect(throws: (any Error).self) { try ThemeFileAccess.read(prepared.definition, defaults: defaults) }
            defaults.set(bookmark, forKey: key)
            var renamed = original; renamed.name = "Different name"
            try write(renamed, to: url)
            #expect(throws: (any Error).self) { try ThemeFileAccess.read(prepared.definition, defaults: defaults) }
            #expect(defaults.data(forKey: key) == bookmark)
            try Data("invalid JSON".utf8).write(to: url)
            #expect(throws: (any Error).self) { try ThemeFileAccess.read(prepared.definition, defaults: defaults) }
            #expect(defaults.data(forKey: key) == bookmark)
            var invalid = original; invalid.background = "not a color"
            try write(invalid, to: url)
            #expect(throws: (any Error).self) { try ThemeFileAccess.read(prepared.definition, defaults: defaults) }
            try FileManager.default.removeItem(at: url)
            #expect(throws: (any Error).self) { try ThemeFileAccess.read(prepared.definition, defaults: defaults) }
            #expect(library.themes == [prepared.definition])
            defaults.removePersistentDomain(forName: suite)
        }
    }

    @Test func failedInstallationKeepsThePreviousDefinitionAndLocalBookmark() throws {
        try withFiles { directory, defaults, _ in
            let firstURL = directory.appendingPathComponent("First.json"), replacementURL = directory.appendingPathComponent("Replacement.json")
            let source = EditorThemeDefinition(name: "Stable identity")
            try write(source, to: firstURL)
            let prepared = try ThemeFileAccess.prepare(firstURL)
            let library = try LibraryStore(inMemory: true, seed: false)
            try ThemeFileAccess.install(prepared, in: library, defaults: defaults)
            let key = ThemeFileAccess.bookmarkKey(for: prepared.definition.id)
            let previous = defaults.data(forKey: key)
            var replacement = source; replacement.background = "123456"
            try write(replacement, to: replacementURL)
            let candidate = try ThemeFileAccess.prepare(replacementURL, id: prepared.definition.id)
            library.beforeBatchCommit = { throw DraftlyError.message("Injected theme commit failure") }
            #expect(throws: (any Error).self) { try ThemeFileAccess.install(candidate, in: library, defaults: defaults) }
            replacement.name = "Fresh failure"
            try write(replacement, to: replacementURL)
            let newCandidate = try ThemeFileAccess.prepare(replacementURL)
            #expect(throws: (any Error).self) { try ThemeFileAccess.install(newCandidate, in: library, defaults: defaults) }
            library.beforeBatchCommit = nil
            #expect(defaults.data(forKey: key) == previous)
            #expect(defaults.data(forKey: ThemeFileAccess.bookmarkKey(for: newCandidate.definition.id)) == nil)
            #expect(library.themes == [prepared.definition])
            try library.reload(); #expect(library.themes == [prepared.definition])
            #expect(try ThemeFileAccess.read(prepared.definition, defaults: defaults).background == source.background)
        }
    }

    @Test func backupRetainsFileDefinitionsButRequiresLocalReselectionAfterRestore() throws {
        try withFiles { directory, defaults, _ in
            let url = directory.appendingPathComponent("Neutral.json")
            let source = EditorThemeDefinition(name: "Shared definition", unknownFields: ["future": .string("keep")])
            try write(source, to: url)
            let prepared = try ThemeFileAccess.prepare(url)
            let library = try LibraryStore(inMemory: true, seed: false)
            try ThemeFileAccess.install(prepared, in: library, defaults: defaults)
            let custom = EditorThemeDefinition(name: source.name)
            try library.saveTheme(custom)
            #expect(library.themes.count == 2)
            #expect(ThemeCatalog.values(in: library).contains { $0["name"] == source.name && $0["type"] == "file" })
            #expect(ThemeCatalog.values(in: library).contains { $0["name"] == source.name && $0["type"] == "custom" })
            let data = try library.backupData(), text = String(decoding: data, as: UTF8.self)
            #expect(!text.contains(directory.path) && !text.contains("theme.file.") && !text.contains("bookmark"))
            let restored = try LibraryStore(inMemory: true, seed: false)
            try restored.restore(data)
            let definition = try #require(restored.themes.first { $0.type == "file" })
            #expect(definition == prepared.definition)
            let otherSuite = "Draftly.ThemeFile.Restore." + UUID().uuidString
            let otherDefaults = try #require(UserDefaults(suiteName: otherSuite))
            defer { otherDefaults.removePersistentDomain(forName: otherSuite) }
            #expect(throws: (any Error).self) { try ThemeFileAccess.read(definition, defaults: otherDefaults) }
            let reselected = try ThemeFileAccess.prepare(url, id: definition.id)
            try ThemeFileAccess.install(reselected, in: restored, defaults: otherDefaults)
            #expect(try ThemeFileAccess.read(definition, defaults: otherDefaults) == reselected.definition)
            let duplicate = EditorThemeDefinition(name: source.name, type: "file")
            #expect(throws: (any Error).self) { try restored.saveTheme(duplicate) }
        }
    }
}
