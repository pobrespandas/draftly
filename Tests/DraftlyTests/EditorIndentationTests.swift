import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Syntax indentation preferences") @MainActor
struct EditorIndentationTests {
    @Test func preferencesPersistPerSyntaxWithoutChangingLibraryData() throws {
        let domain = "Draftly.IndentationTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Keep café 🐼")
        let before = try library.backupData()
        #expect(EditorIndentationPreferences.text(for: "Markdown", defaults: defaults) == "\t")
        let encoded = EditorIndentationPreferences.setting(.fourSpaces, for: "Markdown", encoded: "{\"Future\":\"unknown\"}")
        defaults.set(encoded, forKey: EditorIndentationPreferences.key)
        let reopened = try #require(UserDefaults(suiteName: domain))
        #expect(EditorIndentationPreferences.text(for: "Markdown", defaults: reopened) == "    ")
        #expect(EditorIndentationPreferences.text(for: "TaskPaper", defaults: reopened) == "\t")
        let next = EditorIndentationPreferences.setting(.twoSpaces, for: "TaskPaper", encoded: encoded)
        #expect(EditorIndentationPreferences.style(for: "Markdown", encoded: next) == .fourSpaces)
        #expect(next.contains("unknown"))
        #expect(EditorIndentationPreferences.style(for: "Future", encoded: next) == .tabs)
        #expect(EditorIndentationPreferences.style(for: "Markdown", encoded: "invalid") == .tabs)
        #expect(try library.backupData() == before)
    }

    @Test(arguments: EditorIndentationStyle.allCases, [false, true])
    func editingActionsAndScriptingUseTheCurrentSyntaxPreference(style: EditorIndentationStyle, worker: Bool) async throws {
        let domain = "Draftly.IndentationTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(EditorIndentationPreferences.setting(style, for: "Markdown", encoded: "{}"), forKey: EditorIndentationPreferences.key)
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "café\n🐼")
        let model = WindowModel(library: library, dependencies: WindowDependencies(preferences: WindowPreferences(defaults: defaults)))
        model.select(note.id)
        let original = model.editor.content
        model.editor.selection = NSRange(location: 0, length: (original as NSString).length)
        let tabJSON = String(decoding: try JSONSerialization.data(withJSONObject: [style.text]), as: UTF8.self)
        let indent = DraftAction(name: "Indent", steps: [ActionStep("script", ["script": "if(editor.preferredTabString!==\(tabJSON)[0])throw new Error('wrong indentation');if(Reflect.set(editor,'preferredTabString','wrong')!==false)throw new Error('indentation is readonly');" + EditingScripts.indent])])
        let result = worker ? await model.runner.runAsync(indent).result : model.runner.runResult(indent)
        #expect(result.succeeded)
        #expect(model.editor.content == style.text + "café\n" + style.text + "🐼")
        model.editor.selection = NSRange(location: 0, length: (model.editor.content as NSString).length)
        let outdent = DraftAction(name: "Outdent", steps: [ActionStep("script", ["script": EditingScripts.outdent])])
        let removed = worker ? await model.runner.runAsync(outdent).result : model.runner.runResult(outdent)
        #expect(removed.succeeded)
        #expect(model.editor.content == original)
        let selection = model.editor.selection
        var changed = try #require(library.notes.first { $0.id == note.id })
        changed.syntax = "TaskPaper"
        try library.saveNote(changed)
        #expect(try model.actionUIOperation(["operation": "get", "key": "preferredTabString"]) as? String == "\t")
        #expect(model.editor.content == original && model.editor.selection == selection)
    }

    @Test func nativeNewlineUsesGrammarAndRetainsUndoWithoutShowingAWindow() throws {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.allowsUndo = true
        let window = OffscreenTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = text
        defer { window.contentView = nil }
        let manager = try #require(text.undoManager)
        manager.groupsByEvent = false
        text.string = "🐼\n9. [x] café"
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        let original = text.string
        text.setSelectedRange(NSRange(location: original.utf16.count, length: 0))
        manager.beginUndoGrouping()
        text.insertNewline(nil)
        manager.endUndoGrouping()
        #expect(text.string == original + "\n10. [ ] ")
        #expect(text.selectedRange() == NSRange(location: text.string.utf16.count, length: 0))
        manager.undo()
        #expect(text.string == original)
        manager.redo()
        #expect(text.string == original + "\n10. [ ] ")
        text.syntaxDefinition = try ScriptSyntax.definition("Plain Text")
        text.string = "- café"; text.setSelectedRange(NSRange(location: 6, length: 0))
        manager.beginUndoGrouping()
        text.insertNewline(nil)
        manager.endUndoGrouping()
        #expect(text.string == "- café\n" && !window.isVisible)
    }

    @Test(arguments: EditorIndentationStyle.allCases)
    func nativeTabReplacesTheUTF16SelectionWithoutAWindow(style: EditorIndentationStyle) {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false
        text.string = "🐼café"
        text.indentation = style.text
        text.setSelectedRange(NSRange(location: 2, length: 4))
        text.insertTab(nil)
        #expect(text.string == "🐼" + style.text)
        #expect(text.selectedRange() == NSRange(location: 2 + style.text.utf16.count, length: 0))
        #expect(text.window == nil)
    }
}
