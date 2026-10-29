import Foundation
import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Syntax text input preferences")
struct EditorTextInputPreferencesTests {
    @Test func defaultsAndInvalidFieldsKeepTheExistingNativeConfiguration() throws {
        let fixture = try TestPreferences(prefix: "Draftly-TextInput-")
        defer { fixture.close() }
        for source in ["{}", "invalid", "[]", "null", #"{"Markdown":[]}"#,
                       #"{"Markdown":{"spelling":0,"grammar":"true"}}"#] {
            #expect(EditorTextInputPreferences.configuration(for: "Markdown", encoded: source) == .init())
        }
        #expect(fixture.defaults.object(forKey: EditorTextInputPreferences.key) == nil)
    }

    @Test func optionsPatchIndependentlyAndResetRetainsFutureFields() throws {
        let source = #"{"Café 🐼":{"future":[42,null]},"TaskPaper":{"grammar":true},"future":false}"#
        var edited = source
        for option in EditorTextInputPreferences.Option.allCases {
            edited = try EditorTextInputPreferences.setting(option, enabled: !option.defaultValue,
                for: "Café 🐼", encoded: edited)
            #expect(EditorTextInputPreferences.value(option, for: "Café 🐼", encoded: edited) == !option.defaultValue)
        }
        #expect(EditorTextInputPreferences.configuration(for: "Café 🐼", encoded: edited) ==
            .init(spelling: false, grammar: true, smartQuotes: true, smartDashes: true, autoMatch: true))
        #expect(EditorTextInputPreferences.value(.grammar, for: "TaskPaper", encoded: edited))
        let reset = try EditorTextInputPreferences.reset(for: "Café 🐼", encoded: edited)
        #expect(!EditorTextInputPreferences.hasOverrides(for: "Café 🐼", encoded: reset))
        #expect(try JSONDecoder().decode([String: JSONValue].self, from: Data(reset.utf8)) ==
            JSONDecoder().decode([String: JSONValue].self, from: Data(source.utf8)))
    }

    @Test func invalidWritesRejectAndValidValuesPersistOnReopen() throws {
        for source in ["invalid", "[]", "null", #"{"Markdown":false}"#] {
            for option in EditorTextInputPreferences.Option.allCases {
                #expect(throws: (any Error).self) {
                    try EditorTextInputPreferences.setting(option, enabled: true, for: "Markdown", encoded: source)
                }
            }
            #expect(throws: (any Error).self) { try EditorTextInputPreferences.reset(for: "Markdown", encoded: source) }
        }
        let fixture = try TestPreferences(prefix: "Draftly-TextInput-")
        defer { fixture.close() }
        fixture.defaults.set(try EditorTextInputPreferences.setting(.smartDashes, enabled: true,
            for: "Markdown", encoded: "{}"), forKey: EditorTextInputPreferences.key)
        let reopened = try #require(UserDefaults(suiteName: fixture.name))
        let source = reopened.string(forKey: EditorTextInputPreferences.key) ?? "{}"
        #expect(EditorTextInputPreferences.configuration(for: "Markdown", encoded: source).smartDashes)
        #expect(EditorTextInputPreferences.configuration(for: "TaskPaper", encoded: source) == .init())
    }
    @Test func systemOptionsInheritWithoutWritesAndPersistExplicitChoices() throws {
        let fixture = try TestPreferences(prefix: "Draftly-SystemInput-")
        defer { fixture.close() }
        for option in EditorTextInputPreferences.SystemOption.allCases {
            for source in ["{}", "invalid", "[]", #"{"Markdown":[]}"#,
                           #"{"Markdown":{"autocorrection":0,"writingTools":"true"}}"#] {
                #expect(EditorTextInputPreferences.override(option, for: "Markdown", encoded: source) == nil)
            }
            let source = #"{"Markdown":{"future":[null,"café 🐼"]},"TaskPaper":{"spelling":false},"future":42}"#
            for enabled in [false, true] {
                let edited = try EditorTextInputPreferences.setting(option, enabled: enabled, for: "Markdown", encoded: source)
                fixture.defaults.set(edited, forKey: EditorTextInputPreferences.key)
                let reopened = try #require(UserDefaults(suiteName: fixture.name))
                let stored = reopened.string(forKey: EditorTextInputPreferences.key) ?? "{}"
                #expect(EditorTextInputPreferences.override(option, for: "Markdown", encoded: stored) == enabled)
                #expect(EditorTextInputPreferences.override(option, for: "TaskPaper", encoded: stored) == nil)
                #expect(EditorTextInputPreferences.hasOverrides(for: "Markdown", encoded: stored))
                let inherited = try EditorTextInputPreferences.setting(option, enabled: nil, for: "Markdown", encoded: stored)
                let reset = try EditorTextInputPreferences.reset(for: "Markdown", encoded: stored)
                for restored in [inherited, reset] {
                    #expect(try JSONDecoder().decode([String: JSONValue].self, from: Data(restored.utf8)) ==
                        JSONDecoder().decode([String: JSONValue].self, from: Data(source.utf8)))
                }
            }
            for source in ["invalid", "[]", #"{"Markdown":false}"#] {
                #expect(throws: (any Error).self) {
                    try EditorTextInputPreferences.setting(option, enabled: true, for: "Markdown", encoded: source)
                }
                #expect(throws: (any Error).self) {
                    try EditorTextInputPreferences.setting(option, enabled: nil, for: "Markdown", encoded: source)
                }
            }
        }
    }

    @Test @MainActor func changingTextInputOptionsPreservesSelectionContentAndScriptUndo() async throws {
        _ = NSApplication.shared
        let fixture = try TestPreferences(prefix: "Draftly-TextInputEditor-")
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
        let initialCorrection = text.isAutomaticSpellingCorrectionEnabled
        let initialWritingTools = text.writingToolsBehavior
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
        for option in EditorTextInputPreferences.Option.allCases {
            options = try EditorTextInputPreferences.setting(option, enabled: !option.defaultValue,
                for: "Markdown", encoded: options)
        }
        options = try EditorTextInputPreferences.setting(.autocorrection, enabled: !initialCorrection,
            for: "Markdown", encoded: options)
        options = try EditorTextInputPreferences.setting(.writingTools, enabled: false,
            for: "Markdown", encoded: options)
        fixture.defaults.set(options, forKey: EditorTextInputPreferences.key)
        host.rootView = editor()
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        #expect(text.isAutomaticSpellingCorrectionEnabled == !initialCorrection)
        #expect(text.writingToolsBehavior == .none)
        #expect(!text.isContinuousSpellCheckingEnabled && text.isGrammarCheckingEnabled)
        #expect(text.isAutomaticQuoteSubstitutionEnabled && text.isAutomaticDashSubstitutionEnabled)
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
        options = try EditorTextInputPreferences.setting(.writingTools, enabled: true, for: "Markdown", encoded: options)
        fixture.defaults.set(options, forKey: EditorTextInputPreferences.key)
        host.rootView = editor()
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        let systemView = NSTextView()
        systemView.writingToolsBehavior = .default
        #expect(text.writingToolsBehavior == systemView.writingToolsBehavior)
        fixture.defaults.set(try EditorTextInputPreferences.reset(for: "Markdown", encoded: options),
            forKey: EditorTextInputPreferences.key)
        host.rootView = editor()
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        #expect(text.isAutomaticSpellingCorrectionEnabled == initialCorrection)
        #expect(text.writingToolsBehavior == initialWritingTools)
        #expect(text.string == edited && model.editor.content == edited && undo.canUndo)
    }


}
