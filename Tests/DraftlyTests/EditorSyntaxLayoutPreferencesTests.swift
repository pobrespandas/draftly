import Foundation
import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Syntax layout preferences")
struct EditorSyntaxLayoutPreferencesTests {
    private let defaults = EditorSyntaxLayoutPreferences.Layout(lineHeightMultiple: 0,
        paragraphSpacing: 2, horizontalMargin: 6, verticalMargin: 26, maximumWidth: 0)

    @Test func missingOrInvalidFieldsInheritWithoutWriting() throws {
        let fixture = try TestPreferences(prefix: "Draftly-SyntaxLayout-")
        defer { fixture.close() }
        for source in ["{}", "invalid", "[]", "null", #"{"Markdown":[]}"#,
                       #"{"Markdown":{"paragraphSpacing":-1,"horizontalMargin":"6"}}"#] {
            #expect(EditorSyntaxLayoutPreferences.layout(for: "Markdown", encoded: source, defaults: defaults) == defaults)
        }
        #expect(fixture.defaults.object(forKey: EditorSyntaxLayoutPreferences.key) == nil)
    }

    @Test func eachFieldInheritsIndependentlyAndResetPreservesUnknownData() throws {
        let source = #"{"Café 🐼":{"future":[null,42]},"TaskPaper":{"maximumWidth":240},"future":false}"#
        var edited = source
        for (index, field) in EditorSyntaxLayoutPreferences.Field.allCases.enumerated() {
            edited = try EditorSyntaxLayoutPreferences.setting(field, value: Double(index + 1), for: "Café 🐼", encoded: edited)
            let result = EditorSyntaxLayoutPreferences.layout(for: "Café 🐼", encoded: edited, defaults: defaults)
            for (otherIndex, other) in EditorSyntaxLayoutPreferences.Field.allCases.enumerated() {
                #expect(result[other] == (otherIndex <= index ? Double(otherIndex + 1) : defaults[other]))
            }
        }
        #expect(EditorSyntaxLayoutPreferences.hasOverrides(for: "Café 🐼", encoded: edited))
        #expect(EditorSyntaxLayoutPreferences.layout(for: "TaskPaper", encoded: edited, defaults: defaults).maximumWidth == 240)
        let reset = try EditorSyntaxLayoutPreferences.reset(for: "Café 🐼", encoded: edited)
        #expect(!EditorSyntaxLayoutPreferences.hasOverrides(for: "Café 🐼", encoded: reset))
        #expect(try JSONDecoder().decode([String: JSONValue].self, from: Data(reset.utf8)) == JSONDecoder().decode([String: JSONValue].self, from: Data(source.utf8)))
        let zero = try EditorSyntaxLayoutPreferences.setting(.lineHeightMultiple, value: 0, for: "Markdown", encoded: "{}")
        var changedDefaults = defaults
        changedDefaults.lineHeightMultiple = 1.5
        #expect(EditorSyntaxLayoutPreferences.layout(for: "Markdown", encoded: zero, defaults: changedDefaults).lineHeightMultiple == 0)
        #expect(try EditorSyntaxLayoutPreferences.reset(for: "Markdown", encoded: zero) == "{}")
    }

    @Test func invalidWritesAndResetRejectWithoutDestroyingSavedOptions() throws {
        for source in ["invalid", "[]", "null", #"{"Markdown":null}"#] {
            for field in EditorSyntaxLayoutPreferences.Field.allCases {
                #expect(throws: (any Error).self) {
                    try EditorSyntaxLayoutPreferences.setting(field, value: 1, for: "Markdown", encoded: source)
                }
            }
            #expect(throws: (any Error).self) { try EditorSyntaxLayoutPreferences.reset(for: "Markdown", encoded: source) }
        }
        for field in EditorSyntaxLayoutPreferences.Field.allCases {
            for value in [Double.nan, .infinity, -.infinity, -1] {
                #expect(throws: (any Error).self) {
                    try EditorSyntaxLayoutPreferences.setting(field, value: value, for: "Markdown", encoded: "{}")
                }
            }
        }
    }

    @Test func overridesReopenWithoutChangingGlobalLayout() throws {
        let fixture = try TestPreferences(prefix: "Draftly-SyntaxLayout-")
        defer { fixture.close() }
        fixture.defaults.set(6, forKey: "editor.horizontalMargin")
        fixture.defaults.set(try EditorSyntaxLayoutPreferences.setting(.horizontalMargin, value: 24,
            for: "Markdown", encoded: "{}"), forKey: EditorSyntaxLayoutPreferences.key)
        let reopened = try #require(UserDefaults(suiteName: fixture.name))
        let stored = reopened.string(forKey: EditorSyntaxLayoutPreferences.key) ?? "{}"
        #expect(EditorSyntaxLayoutPreferences.layout(for: "Markdown", encoded: stored, defaults: defaults).horizontalMargin == 24)
        #expect(EditorSyntaxLayoutPreferences.layout(for: "HTML", encoded: stored, defaults: defaults) == defaults)
        #expect(reopened.double(forKey: "editor.horizontalMargin") == 6)
    }
    @Test @MainActor func changingSyntaxLayoutRefreshesTheEditorWithoutChangingSelectionOrScriptUndo() async throws {
        _ = NSApplication.shared
        let fixture = try TestPreferences(prefix: "Draftly-SyntaxLayoutEditor-")
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
        var options = "{}"
        for (field, value) in [(EditorSyntaxLayoutPreferences.Field.lineHeightMultiple, 1.6),
                              (.paragraphSpacing, 12), (.horizontalMargin, 24), (.verticalMargin, 30),
                              (.maximumWidth, 240)] {
            options = try EditorSyntaxLayoutPreferences.setting(field, value: value, for: "Markdown", encoded: options)
        }
        fixture.defaults.set(options, forKey: EditorSyntaxLayoutPreferences.key)
        host.rootView = editor()
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        let style = try #require(text.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(abs(style.lineHeightMultiple - 1.6) < 0.001 && style.paragraphSpacing == 12)
        #expect(text.textContainerInset.height == 30)
        let draftText = try #require(text as? DraftTextView)
        #expect(draftText.horizontalMargin == 24 && draftText.verticalMargin == 30)
        #expect(draftText.maximumLineWidth == 240)
        #expect(text.textContainerInset.width >= 24)
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
        fixture.defaults.set(try EditorSyntaxLayoutPreferences.reset(for: "Markdown", encoded: options),
            forKey: EditorSyntaxLayoutPreferences.key)
        host.rootView = editor()
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        let resetStyle = try #require(text.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(resetStyle.lineHeightMultiple == 0 && resetStyle.lineSpacing == 2 && resetStyle.paragraphSpacing == 0)
        #expect(draftText.horizontalMargin == 6 && draftText.verticalMargin == 26 && draftText.maximumLineWidth == 0)
        #expect(text.string == edited && model.editor.content == edited && undo.canUndo)
    }

}
