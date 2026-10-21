import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("File theme application") @MainActor
struct FileThemeApplicationTests {
    @Test func fileReferencesReloadForAppAndWorkspaceWithoutEditingTheDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let domain = "Draftly.FileTheme.Application.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let file = root.appendingPathComponent("neutral.json")
        var source = EditorThemeDefinition(name: "Live café 🐼", background: "123456", isDark: true)
        try JSONEncoder().encode(source).write(to: file)
        let prepared = try ThemeFileAccess.prepare(file)
        let library = try LibraryStore(inMemory: true, seed: false)
        try ThemeFileAccess.install(prepared, in: library, defaults: defaults)
        try library.saveTheme(EditorThemeDefinition(name: source.name))
        let model = WindowModel(library: library, dependencies: WindowDependencies(preferences: WindowPreferences(defaults: defaults)))
        let note = try library.createNote(content: "Keep café 🐼"); model.select(note.id)
        model.editor.selection = NSRange(location: 5, length: 4)
        let focus = model.editor.focusToken
        let action = DraftAction(name: "File theme", steps: [ActionStep("script", ["script": """
        const t=Theme.find('file','Live café 🐼');
        if(!t||t.type!=='file'||Theme.find('custom',t.name).uuid===t.uuid)throw Error('typed lookup');
        app.darkTheme=t;
        if(app.darkTheme.type!=='file'||app.darkTheme.uuid!==t.uuid)throw Error('typed assignment');
        """])])
        #expect(model.runner.run(action), Comment(rawValue: model.runner.message ?? ""))
        let report = await model.runner.runAsync(action); #expect(report.result.succeeded)
        let first = model.editorThemePresentation(systemIsDark: true)
        #expect(first.theme?.id == prepared.definition.id && first.theme?.background == "123456" && first.error == nil)
        let revision = defaults.integer(forKey: EditorThemePreferences.revisionKey)
        source.background = "654321"; try JSONEncoder().encode(source).write(to: file)
        #expect(model.editorThemePresentation(systemIsDark: true).theme?.background == "123456")
        try model.setConfiguredThemeReference(model.configuredThemeReference(dark: true), dark: true)
        #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == revision + 1)
        #expect(model.editorThemePresentation(systemIsDark: true).theme?.background == "654321")
        #expect(library.themes.first { $0.id == prepared.definition.id }?.background == "123456")
        var workspace = Workspace(name: "File override")
        workspace.scriptMetadata = ["api": String(decoding: try JSONSerialization.data(withJSONObject: ["preferredDarkTheme": ["type": "file", "uuid": prepared.definition.id.uuidString]]), as: UTF8.self)]
        try model.applyScriptWorkspace(workspace)
        #expect(model.editorThemePresentation(systemIsDark: true).theme?.background == "654321")
        #expect(model.editor.content == note.content && model.editor.selection == NSRange(location: 5, length: 4))
        #expect(model.editor.focusToken == focus && model.editor.noteID == note.id)
        try Data("invalid".utf8).write(to: file)
        let beforePreferences = defaults.data(forKey: EditorThemePreferences.key)
        let beforeRevision = defaults.integer(forKey: EditorThemePreferences.revisionKey)
        #expect(throws: (any Error).self) { try model.setConfiguredThemeReference(model.configuredThemeReference(dark: true), dark: true) }
        #expect(defaults.data(forKey: EditorThemePreferences.key) == beforePreferences)
        #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == beforeRevision)
        #expect(model.editorThemePresentation(systemIsDark: true).theme?.background == "654321")
        let reopened = WindowModel(library: library, dependencies: WindowDependencies(preferences: WindowPreferences(defaults: defaults)))
        let bad = reopened.editorThemePresentation(systemIsDark: true)
        #expect(bad.theme == nil && bad.error != nil)
        model.folder = .archive; model.query = "Keep query"
        #expect(throws: (any Error).self) { try model.applyScriptWorkspace(workspace) }
        #expect(model.folder == .archive && model.query == "Keep query")
        #expect(model.editor.content == note.content && model.editor.selection == NSRange(location: 5, length: 4))
    }
}
