import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("App configured theme contracts") @MainActor
struct AppThemeContractTests {
    @Test(arguments: [false, true])
    func scriptingPersistsTypedThemesAcrossWindowsAndKeepsEditorUndo(fileTheme: Bool) async throws {
        let domain = "Draftly.AppTheme.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        var theme = EditorTheme(name: "Night café 🐼", isDark: true)
        theme.background = "162839"; theme.foreground = "F1F2F3"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly.ThemeUndo.\(UUID()).json")
        defer { if fileTheme { try? FileManager.default.removeItem(at: file) } }
        if fileTheme {
            try JSONEncoder().encode(theme).write(to: file)
            let prepared = try ThemeFileAccess.prepare(file, id: theme.id)
            try ThemeFileAccess.install(prepared, in: library, defaults: defaults)
            theme = prepared.definition
        } else { try library.saveTheme(theme) }
        let dependencies = WindowDependencies(preferences: WindowPreferences(defaults: defaults))
        let model = WindowModel(library: library, dependencies: dependencies)
        let note = try library.createNote(content: "Original 🐼"); model.select(note.id)
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, onChange: {})
        let coordinator = NativeEditor.Coordinator(native), text = TestUndoTextView(frame: .zero)
        text.string = note.content; coordinator.textView = text; text.manager.groupsByEvent = false
        model.editor.synchronizeScriptEdit = {
            text.manager.beginUndoGrouping(); coordinator.synchronizeScriptEdit(); text.manager.endUndoGrouping()
        }
        model.editor.performUndo = { redo in if redo { text.manager.redo() } else { text.manager.undo() } }
        for async in [false, true] {
            model.editor.selection = NSRange(location: 0, length: 8)
            text.setSelectedRange(model.editor.selection)
            let action = DraftAction(name: "Configured themes", steps: [ActionStep("script", ["script": """
            function check(v,label){if(!v)throw Error(label);}
            editor.setSelectedText('Edited');const selection=editor.getSelectedRange().join(',');
            app.darkTheme=Theme.find('\(theme.type)','Night café 🐼');
            app.lightTheme=Theme.find('builtIn','Light');
            check(app.darkTheme instanceof Theme,'typed dark');
            check(app.lightTheme instanceof Theme,'typed light');
            check(app.darkTheme.name==='Night café 🐼'&&app.darkTheme.type==='\(theme.type)','dark selection');
            check(app.lightTheme.name==='Light','light selection');
            check(editor.getSelectedRange().join(',')===selection,'selection');
            editor.undo();check(editor.getText()==='Original 🐼','theme kept undo');
            editor.redo();check(editor.getText()==='Edited 🐼','theme kept redo');
            """])])
            if async { let report = await model.runner.runAsync(action); #expect(report.result.succeeded) }
            else { #expect(model.runner.run(action), Comment(rawValue: model.runner.message ?? "")) }
            #expect(text.string == "Edited 🐼")
            #expect(model.library.notes.first { $0.id == note.id }?.content == "Edited 🐼")
            text.manager.undo(); #expect(model.editor.content == "Original 🐼")
        }
        let other = WindowModel(library: library, dependencies: dependencies)
        #expect(other.configuredThemeReference(dark: true)["uuid"] as? String == theme.id.uuidString)
        #expect(other.editorThemePresentation(systemIsDark: true).theme == theme)
        #expect(other.editorThemePresentation(systemIsDark: false).theme == nil)
        #expect(other.editorThemePresentation(systemIsDark: false).dark == false)
        theme.name = "Renamed night"
        if fileTheme { try JSONEncoder().encode(theme).write(to: file) }
        try library.saveTheme(theme)
        #expect(model.configuredThemeReference(dark: true)["name"] as? String == theme.name)
        #expect(other.editorThemePresentation(systemIsDark: true).theme == theme)
    }

    @Test func workspaceOverridesRenderingWithoutChangingTheConfiguredPair() throws {
        let domain = "Draftly.AppTheme.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let theme = EditorTheme(name: "Local night", isDark: true)
        try library.saveTheme(theme)
        let model = WindowModel(library: library, dependencies: WindowDependencies(preferences: WindowPreferences(defaults: defaults)))
        try model.setConfiguredThemeReference(["type": "custom", "uuid": theme.id.uuidString], dark: true)
        let saved = defaults.data(forKey: EditorThemePreferences.key)
        var workspace = Workspace(name: "Window only")
        let values = ["preferredDarkTheme": ["type": "builtIn", "name": "Light", "uuid": theme.id.uuidString]]
        workspace.scriptMetadata = ["api": String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)]
        try model.applyScriptWorkspace(workspace)
        #expect(model.editorThemePresentation(systemIsDark: true).theme == nil)
        #expect(model.editorThemePresentation(systemIsDark: true).dark == false)
        #expect(model.configuredThemeReference(dark: true)["uuid"] as? String == theme.id.uuidString)
        #expect(defaults.data(forKey: EditorThemePreferences.key) == saved)
        try model.applyScriptWorkspace(Workspace(name: "Plain"))
        #expect(model.editorThemePresentation(systemIsDark: true).theme == theme)
        #expect(throws: (any Error).self) {
            try model.actionUIOperation(["operation": "set", "key": "darkTheme", "value": ["type": "custom", "uuid": UUID().uuidString, "name": theme.name]])
        }
        #expect(defaults.data(forKey: EditorThemePreferences.key) == saved)
    }
}
