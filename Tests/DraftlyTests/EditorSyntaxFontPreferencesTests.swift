import Foundation
import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Syntax font preferences")
struct EditorSyntaxFontPreferencesTests {
    @Test func missingAndInvalidOptionsReadDefaultsWithoutWriting() throws {
        let fixture = try TestPreferences(prefix: "Draftly-SyntaxFonts-")
        defer { fixture.close() }
        #expect(fixture.defaults.object(forKey: EditorSyntaxFontPreferences.key) == nil)
        for encoded in ["{}", "invalid", "[]", "null", #"{"Markdown":[]}"#, #"{"Markdown":{"fontSize":-3,"fontName":42}}"#] {
            #expect(EditorSyntaxFontPreferences.font(for: "Markdown", encoded: encoded, defaultName: "Menlo-Regular", defaultSize: 19) == .init(name: "Menlo-Regular", size: 19))
        }
        #expect(fixture.defaults.object(forKey: EditorSyntaxFontPreferences.key) == nil)
    }

    @Test func eachFieldInheritsIndependentlyAndResetsWithoutLosingUnknownData() throws {
        let source = #"{"Markdown":{"future":[null,"café 🐼"]},"TaskPaper":{"fontName":"Missing Nerd Font 🐼","fontSize":23},"future":42}"#
        let named = try EditorSyntaxFontPreferences.settingName("Menlo-Regular", for: "Markdown", encoded: source)
        #expect(EditorSyntaxFontPreferences.font(for: "Markdown", encoded: named, defaultName: "System", defaultSize: 17) == .init(name: "Menlo-Regular", size: 17))
        let sized = try EditorSyntaxFontPreferences.settingSize(21, for: "Markdown", encoded: named)
        #expect(EditorSyntaxFontPreferences.hasOverrides(for: "Markdown", encoded: sized))
        #expect(EditorSyntaxFontPreferences.font(for: "TaskPaper", encoded: sized, defaultName: "System", defaultSize: 17) == .init(name: "Missing Nerd Font 🐼", size: 23))
        let reset = try EditorSyntaxFontPreferences.reset(for: "Markdown", encoded: sized)
        #expect(!EditorSyntaxFontPreferences.hasOverrides(for: "Markdown", encoded: reset))
        #expect(try JSONDecoder().decode([String: JSONValue].self, from: Data(reset.utf8)) == JSONDecoder().decode([String: JSONValue].self, from: Data(source.utf8)))
        #expect(EditorSyntaxFontPreferences.font(for: "Markdown", encoded: reset, defaultName: "System", defaultSize: 18) == .init(name: "System", size: 18))
        let sizeOnly = try EditorSyntaxFontPreferences.settingSize(22, for: "HTML", encoded: "{}")
        #expect(EditorSyntaxFontPreferences.font(for: "HTML", encoded: sizeOnly, defaultName: "System", defaultSize: 17) == .init(name: "System", size: 22))
        #expect(try EditorSyntaxFontPreferences.reset(for: "HTML", encoded: sizeOnly) == "{}")
    }

    @Test func monospaceInheritsAndResetPreservesUnknownFields() throws {
        let source = #"{"Markdown":{"future":[null,"🐼"]},"TaskPaper":{"monospaceFontName":"Other"}}"#
        #expect(EditorSyntaxFontPreferences.monospace(for: "Markdown", encoded: source, defaultName: "System Monospace") == "System Monospace")
        let changed = try EditorSyntaxFontPreferences.settingMonospace("Menlo-Regular", for: "Markdown", encoded: source)
        #expect(EditorSyntaxFontPreferences.monospace(for: "Markdown", encoded: changed, defaultName: "Other") == "Menlo-Regular")
        #expect(EditorSyntaxFontPreferences.monospace(for: "TaskPaper", encoded: changed, defaultName: "Other") == "Other")
        #expect(EditorSyntaxFontPreferences.hasOverrides(for: "Markdown", encoded: changed))
        let reset = try EditorSyntaxFontPreferences.reset(for: "Markdown", encoded: changed)
        #expect(try JSONDecoder().decode([String: JSONValue].self, from: Data(reset.utf8)) == JSONDecoder().decode([String: JSONValue].self, from: Data(source.utf8)))
        #expect(throws: (any Error).self) { try EditorSyntaxFontPreferences.settingMonospace("Menlo", for: "Markdown", encoded: #"{"Markdown":[]}"#) }
    }

    @Test func invalidEditsRejectBeforeChangingStoredValues() throws {
        for encoded in ["invalid", "[]", "null", #"{"Markdown":null}"#] {
            #expect(throws: (any Error).self) { try EditorSyntaxFontPreferences.settingName("Menlo-Regular", for: "Markdown", encoded: encoded) }
            #expect(throws: (any Error).self) { try EditorSyntaxFontPreferences.reset(for: "Markdown", encoded: encoded) }
        }
        for size in [Double.nan, .infinity, -.infinity, 0, -1] {
            #expect(throws: (any Error).self) { try EditorSyntaxFontPreferences.settingSize(size, for: "Markdown", encoded: "{}") }
        }
    }

    @Test func overridesPersistLocallyWithoutChangingGlobalPreferences() throws {
        let fixture = try TestPreferences(prefix: "Draftly-SyntaxFonts-")
        defer { fixture.close() }
        fixture.defaults.set("System", forKey: "editor.fontName")
        fixture.defaults.set(17, forKey: "editor.fontSize")
        let encoded = try EditorSyntaxFontPreferences.settingSize(24, for: "Café 🐼", encoded: "{}")
        fixture.defaults.set(encoded, forKey: EditorSyntaxFontPreferences.key)
        let reopened = try #require(UserDefaults(suiteName: fixture.name))
        #expect(EditorSyntaxFontPreferences.font(for: "Café 🐼", encoded: reopened.string(forKey: EditorSyntaxFontPreferences.key) ?? "{}", defaultName: "System", defaultSize: 17).size == 24)
        #expect(reopened.string(forKey: "editor.fontName") == "System" && reopened.double(forKey: "editor.fontSize") == 17)
    }
    @Test @MainActor func changingSyntaxFontRefreshesTheEditorWithoutChangingSelectionOrScriptUndo() async throws {
        _ = NSApplication.shared
        let fixture = try TestPreferences(prefix: "Draftly-SyntaxFontEditor-")
        defer { fixture.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library,
            dependencies: WindowDependencies(preferences: WindowPreferences(defaults: fixture.defaults)))
        let note = try library.createNote(content: "Keep café 🐼")
        model.select(note.id)
        func editor() -> some View {
            EditorBody(model: model, session: model.editor, fontName: "System", fontSize: 17,
                lineSpacing: 2, markdown: false, horizontalMargin: 6, verticalMargin: 26,
                maximumWidth: 0, theme: nil).defaultAppStorage(fixture.defaults)
        }
        let host = NSHostingView(rootView: editor())
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer {
            model.editor.synchronizeScriptEdit = nil
            model.editor.performUndo = nil
            window.contentView = nil
        }
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        func textView(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { textView($0) }.first
        }
        let text = try #require(textView(host))
        window.makeFirstResponder(text)
        let undo = try #require(text.undoManager)
        undo.groupsByEvent = false
        defer { undo.removeAllActions() }
        undo.beginUndoGrouping()
        try model.editor.replace(NSRange(location: model.editor.content.utf16.count, length: 0), with: "!")
        model.editor.synchronizeScriptEdit?()
        undo.endUndoGrouping()
        await TestMainQueue.drain()
        let edited = note.content + "!"
        #expect(text.string == edited && model.editor.content == edited)
        let selection = (edited as NSString).range(of: "café 🐼")
        text.setSelectedRange(selection)
        await TestMainQueue.drain()
        var options = try EditorSyntaxFontPreferences.settingName("Menlo-Regular", for: "Markdown", encoded: "{}")
        options = try EditorSyntaxFontPreferences.settingSize(23, for: "Markdown", encoded: options)
        fixture.defaults.set(options, forKey: EditorSyntaxFontPreferences.key)
        host.rootView = editor()
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        let font = try #require(text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.fontName == "Menlo-Regular" && font.pointSize == 23)
        #expect(text.string == edited && model.editor.content == edited)
        #expect(text.selectedRange() == selection && model.editor.selection == selection)
        #expect(undo.canUndo)
        undo.undo()
        await TestMainQueue.drain()
        #expect(text.string == note.content)
        #expect(model.editor.content == note.content)
        undo.redo()
        await TestMainQueue.drain()
        #expect(text.string == edited && model.editor.content == edited)
    }

}
