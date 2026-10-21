import AppKit
import SwiftUI
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
        let editorFixture = ScriptUndoEditorFixture(native, content: note.content)
        defer { editorFixture.close() }
        let text = editorFixture.text
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

    @Test func normalScopeBackgroundAppliesWithoutReplacingCanvasOrForegroundAndKeepsUndo() async throws {
        _ = NSApplication.shared
        let source: [String: Any] = [
            "name": "Normal paper QA", "description": "Neutral theme contract", "isDark": false,
            "colors": [
                "editor": ["ink": "#102030", "paper": "#A1B2C3", "codePaper": "#D4E5F6"],
                "interface": ["textForeground": "#FF0000", "textBackground": "#17324D"]
            ],
            "scopes": [
                "text.normal": ["settings": ["foreground": "ink", "background": "paper"]],
                "code.inline": ["settings": ["background": "codePaper"]]
            ]
        ]
        let theme = try DraftsThemeImport.decode(data: JSONSerialization.data(withJSONObject: source))
        let session = EditorSession()
        let original = "Original café 🐼 `code`"
        session.load(Note(content: original), focusEditor: false)
        func editor(_ theme: EditorTheme?) -> NativeEditor {
            NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
                markdown: true, theme: theme, onChange: {})
        }
        let host = NSHostingView(rootView: editor(nil))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        func textView(_ view: NSView) -> DraftTextView? {
            if let text = view as? DraftTextView { return text }
            return view.subviews.lazy.compactMap { textView($0) }.first
        }
        let text = try #require(textView(host))
        let manager = try #require(text.undoManager)
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        try session.replace(NSRange(location: 0, length: 8), with: "Edited")
        session.synchronizeScriptEdit?()
        manager.endUndoGrouping()
        let edited = session.content
        let selected = (edited as NSString).range(of: "café 🐼")
        session.selection = selected
        session.synchronizeScriptEdit?()
        host.rootView = editor(theme)
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        func hex(_ value: Any?) throws -> String {
            let color = try #require((value as? NSColor)?.usingColorSpace(.sRGB))
            return String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
        }
        let storage = try #require(text.textStorage)
        #expect(try hex(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil)) == "A1B2C3")
        #expect(try hex(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil)) == "102030")
        let code = (edited as NSString).range(of: "code").location
        #expect(try hex(storage.attribute(.backgroundColor, at: code, effectiveRange: nil)) == "D4E5F6")
        #expect(try hex(text.backgroundColor) == "17324D")
        #expect(try hex(text.enclosingScrollView?.backgroundColor) == "17324D")
        #expect(text.string == edited && text.selectedRange() == selected && session.selection == selected)
        #expect(manager.canUndo)
        manager.undo()
        #expect(text.string == original && session.content == original)
        manager.redo()
        #expect(text.string == edited && session.content == edited)
        #expect(try hex(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil)) == "A1B2C3")
        #expect(try hex(text.backgroundColor) == "17324D")
    }

}
