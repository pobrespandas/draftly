import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Installed theme commands") @MainActor
struct InstalledThemeCommandsTests {
    private func withCommands(_ body: (LibraryStore, UserDefaults, InstalledThemeCommands) throws -> Void) throws {
        let preferences = try TestPreferences(prefix: "Draftly.InstalledThemeCommands.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        try body(library, preferences.defaults, InstalledThemeCommands(library: library, defaults: preferences.defaults))
    }

    private func withPreparedFile(_ body: (URL, ThemeFileAccess.Prepared) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DraftlyInstalledTheme-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Neutral.json")
        let theme = EditorTheme(name: "Neutral café 🐼", isDark: true,
                                unknownFields: ["future": .array([.bool(false), .string("🦊")])])
        try JSONEncoder().encode(theme).write(to: url)
        try body(url, ThemeFileAccess.prepare(url))
    }

    @Test func saveAppliesEditorChangesAndSelectsTheRequestedSlotWithoutChangingDrafts() throws {
        try withCommands { library, defaults, commands in
            let source: [String: Any] = ["name": "Imported café 🐼", "description": "Neutral theme", "isDark": true,
                "colors": ["editor": [:] as [String: String],
                           "interface": ["textForeground": "#112233", "textBackground": "#101010"]],
                "scopes": ["text.normal": ["settings": ["foreground": "#112233"]]],
                "future": ["keep": "🦊"]]
            var theme = try DraftsThemeImport.decode(data: JSONSerialization.data(withJSONObject: source))
            theme.foreground = "ABCDEF"
            let note = try library.createNote(content: "Keep café 🐼")
            try commands.select(reference: ["type": "builtIn", "name": "Dark"], dark: true)
            try commands.saveEditorTheme(theme, dark: false)
            let saved = try #require(library.themes.first)
            #expect(saved.id == theme.id && saved.foreground == "ABCDEF")
            #expect(saved.scopeStyle(named: "text.normal")?.foreground == "ABCDEF")
            guard case .object(let original) = saved.unknownFields["draftsSource"] else {
                Issue.record("The original theme fields were lost."); return
            }
            #expect(original["future"] == .object(["keep": .string("🦊")]))
            let preferences = EditorThemePreferences(defaults: defaults)
            #expect(preferences.reference(dark: false, themes: library.themes)["uuid"] as? String == theme.id.uuidString)
            #expect(preferences.reference(dark: true, themes: library.themes)["name"] as? String == "Dark")
            #expect(library.notes == [note])
            try library.reload()
            #expect(library.themes == [saved])
        }
    }

    @Test func saveFailureLeavesTheLibraryAndSelectionUnchanged() throws {
        try withCommands { library, defaults, commands in
            let theme = EditorTheme(name: "Before")
            try commands.saveEditorTheme(theme)
            let before = try library.backupData()
            let preferenceData = defaults.data(forKey: EditorThemePreferences.key)
            let revision = defaults.integer(forKey: EditorThemePreferences.revisionKey)
            var changed = theme; changed.name = "After"; changed.background = "123456"
            library.beforeBatchCommit = { throw DraftlyError.message("Injected theme save failure") }
            defer { library.beforeBatchCommit = nil }
            #expect(throws: (any Error).self) { try commands.saveEditorTheme(changed) }
            #expect(try library.backupData() == before)
            #expect(defaults.data(forKey: EditorThemePreferences.key) == preferenceData)
            #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == revision)
        }
    }

    @Test func saveDoesNotUndoPersistenceWhenTheFollowingSelectionFails() throws {
        try withCommands { library, defaults, commands in
            try commands.select(reference: ["type": "builtIn", "name": "Light"], dark: false)
            let before = defaults.data(forKey: EditorThemePreferences.key)
            let revision = defaults.integer(forKey: EditorThemePreferences.revisionKey)
            let theme = EditorTheme(name: "File snapshot", type: "file")
            #expect(throws: (any Error).self) { try commands.saveEditorTheme(theme) }
            #expect(library.themes == [theme])
            try library.reload(); #expect(library.themes == [theme])
            #expect(defaults.data(forKey: EditorThemePreferences.key) == before)
            #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == revision)
        }
    }

    @Test(arguments: [false, true])
    func installSavesTheBookmarkAndSelectsTheDefaultOrExplicitSlot(overrideSlot: Bool) throws {
        try withCommands { library, defaults, commands in
            try withPreparedFile { _, prepared in
                try commands.install(prepared, dark: overrideSlot ? false : nil)
                #expect(library.themes == [prepared.definition])
                #expect(defaults.data(forKey: ThemeFileAccess.bookmarkKey(for: prepared.definition.id)) == prepared.bookmark)
                let dark = !overrideSlot
                let preferences = EditorThemePreferences(defaults: defaults)
                #expect(preferences.reference(dark: dark, themes: library.themes)["uuid"] as? String == prepared.definition.id.uuidString)
                #expect(preferences.reference(dark: !dark, themes: library.themes)["type"] as? String == "builtIn")
                #expect(library.themes.first?.unknownFields == prepared.definition.unknownFields)
            }
        }
    }

    @Test func failedInstallDoesNotWriteABookmarkOrSelection() throws {
        try withCommands { library, defaults, commands in
            try withPreparedFile { _, prepared in
                try commands.select(reference: ["type": "builtIn", "name": "Dark"], dark: true)
                let before = defaults.data(forKey: EditorThemePreferences.key)
                let revision = defaults.integer(forKey: EditorThemePreferences.revisionKey)
                library.beforeBatchCommit = { throw DraftlyError.message("Injected theme install failure") }
                defer { library.beforeBatchCommit = nil }
                #expect(throws: (any Error).self) { try commands.install(prepared) }
                #expect(library.themes.isEmpty)
                #expect(defaults.data(forKey: ThemeFileAccess.bookmarkKey(for: prepared.definition.id)) == nil)
                #expect(defaults.data(forKey: EditorThemePreferences.key) == before)
                #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == revision)
            }
        }
    }

    @Test func installKeepsTheSnapshotAndBookmarkIfFileSelectionFails() throws {
        try withCommands { library, defaults, commands in
            try withPreparedFile { url, prepared in
                try commands.select(reference: ["type": "builtIn", "name": "Dark"], dark: true)
                let before = defaults.data(forKey: EditorThemePreferences.key)
                let revision = defaults.integer(forKey: EditorThemePreferences.revisionKey)
                try FileManager.default.removeItem(at: url)
                #expect(throws: (any Error).self) { try commands.install(prepared) }
                #expect(library.themes == [prepared.definition])
                #expect(defaults.data(forKey: ThemeFileAccess.bookmarkKey(for: prepared.definition.id)) == prepared.bookmark)
                #expect(defaults.data(forKey: EditorThemePreferences.key) == before)
                #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == revision)
                try library.reload(); #expect(library.themes == [prepared.definition])
            }
        }
    }

    @Test func selectingAgainReloadsFileAccessWithoutSavingTheSnapshot() throws {
        try withCommands { library, defaults, commands in
            try withPreparedFile { url, prepared in
                try commands.install(prepared)
                let reference: [String: Any] = ["type": "file", "uuid": prepared.definition.id.uuidString]
                let before = try library.backupData()
                let revision = defaults.integer(forKey: EditorThemePreferences.revisionKey)
                try commands.select(reference: reference, dark: true)
                #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == revision + 1)
                #expect(try library.backupData() == before)
                let selection = defaults.data(forKey: EditorThemePreferences.key)
                try Data("Invalid theme".utf8).write(to: url)
                #expect(throws: (any Error).self) { try commands.select(reference: reference, dark: true) }
                #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == revision + 1)
                #expect(defaults.data(forKey: EditorThemePreferences.key) == selection)
                #expect(try library.backupData() == before)
            }
        }
    }

    @Test(arguments: ["custom", "file"])
    func deletionKeepsBookmarksOnFailureAndRemovesOnlySuccessfulFileAccess(type: String) throws {
        try withCommands { library, defaults, commands in
            let theme = EditorTheme(name: "Delete neutral", type: type)
            try library.saveTheme(theme)
            let key = ThemeFileAccess.bookmarkKey(for: theme.id)
            let otherKey = ThemeFileAccess.bookmarkKey(for: UUID())
            let bookmark = Data("Neutral access marker".utf8)
            defaults.set(bookmark, forKey: key); defaults.set(bookmark, forKey: otherKey)
            try commands.select(reference: ["type": "builtIn", "name": "Light"], dark: false)
            let before = defaults.data(forKey: EditorThemePreferences.key)
            library.beforeBatchCommit = { throw DraftlyError.message("Injected theme delete failure") }
            #expect(throws: (any Error).self) { try commands.delete(theme) }
            library.beforeBatchCommit = nil
            #expect(library.themes == [theme])
            #expect(defaults.data(forKey: key) == bookmark)
            try commands.delete(theme)
            #expect(library.themes.isEmpty)
            #expect(defaults.data(forKey: key) == (type == "file" ? nil : bookmark))
            #expect(defaults.data(forKey: otherKey) == bookmark)
            #expect(defaults.data(forKey: EditorThemePreferences.key) == before)
            try library.reload(); #expect(library.themes.isEmpty)
        }
    }
    @Test func restoredThemeRendersThroughItsLocalIdentityWithoutChangingEditorState() throws {
        try withCommands { source, defaults, commands in
            var theme = EditorTheme()
            theme.name = "Restored café 🐼"
            theme.background = "123456"
            theme.unknownFields["future"] = .array([.null, .string("retained")])
            try commands.saveEditorTheme(theme, dark: false)
            let references = defaults.data(forKey: EditorThemePreferences.key)
            let restored = try LibraryStore(inMemory: true, seed: false)
            try restored.restore(source.backupData())
            let model = WindowModel(library: restored,
                dependencies: WindowDependencies(preferences: WindowPreferences(defaults: defaults)))
            let note = try restored.createNote(content: "Keep café 🐼")
            model.select(note.id)
            let range = (note.content as NSString).range(of: "🐼")
            model.editor.selection = range
            let focus = model.editor.focusToken
            let presentation = model.editorThemePresentation(systemIsDark: false)
            #expect(presentation.theme?.id == theme.id)
            #expect(presentation.theme?.background == "123456")
            #expect(presentation.theme?.unknownFields == theme.unknownFields)
            #expect(presentation.error == nil)
            #expect(defaults.data(forKey: EditorThemePreferences.key) == references)
            #expect(model.editor.content == note.content && model.editor.selection == range)
            #expect(model.editor.focusToken == focus)
        }
    }

}
