import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Editor Touch Bar preference") @MainActor
struct EditorTouchBarTests {
    private func model(defaults: UserDefaults) throws -> WindowModel {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "A🐼 café\nSecond line")
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.select(note.id)
        return model
    }

    @Test func customBarUsesTheSharedEditingCommandsAndOffRestoresInheritedBar() throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences(prefix: "Draftly.TouchBar.")
        defer { preferences.close() }
        let model = try model(defaults: preferences.defaults)
        let text = DraftTextView(frame: .zero)
        text.configureTouchBar(model: model, showCustom: true)
        let bar = try #require(text.touchBar)
        #expect(bar.customizationIdentifier == EditorTouchBarController.customizationIdentifier)
        #expect(bar.defaultItemIdentifiers == EditorBarCommand.allCases.map(EditorTouchBarController.identifier(for:)))
        let item = try #require(bar.item(forIdentifier: EditorTouchBarController.identifier(for: .moveRight)) as? NSCustomTouchBarItem)
        #expect(item.customizationLabel == "Move Right")
        text.configureTouchBar(model: model, showCustom: false)
        #expect(text.makeTouchBar()?.customizationIdentifier != EditorTouchBarController.customizationIdentifier)
        text.configureTouchBar(model: model, showCustom: true)
        #expect(text.touchBar?.customizationIdentifier == EditorTouchBarController.customizationIdentifier)
    }

    @Test func preferenceUpdatesReachTheExistingTextViewWithoutChangingDraftState() async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences(prefix: "Draftly.TouchBar.")
        defer { preferences.close() }
        let model = try model(defaults: preferences.defaults), session = model.editor
        let range = (session.content as NSString).range(of: "café")
        session.selection = range
        func editor(showCustom: Bool) -> NativeEditor {
            NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
                markdown: false, showCustomTouchBar: showCustom, touchBarModel: model, completionContext: { [weak model] in
                    EditorCompletionContext(currentDraft: model?.currentNote, drafts: model?.library.notes ?? [])
                }, onChange: {})
        }
        let host = NSHostingView(rootView: editor(showCustom: true))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func textView(_ view: NSView) -> DraftTextView? {
            if let view = view as? DraftTextView { return view }
            return view.subviews.lazy.compactMap { textView($0) }.first
        }
        for showCustom in [true, false, true] {
            host.rootView = editor(showCustom: showCustom)
            host.layoutSubtreeIfNeeded()
            await TestMainQueue.drain()
            let text = try #require(textView(host))
            #expect(text.showCustomTouchBar == showCustom)
            #expect((text.makeTouchBar()?.customizationIdentifier == EditorTouchBarController.customizationIdentifier) == showCustom)
            #expect(text.string == session.content && text.selectedRange() == range)
        }
    }

    @Test func editingButtonsUseComposedRangesAndKeepExistingUndo() async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences(prefix: "Draftly.TouchBar.")
        defer { preferences.close() }
        let model = try model(defaults: preferences.defaults)
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17, lineSpacing: 2,
            markdown: false, touchBarModel: model, completionContext: { [weak model] in
                EditorCompletionContext(currentDraft: model?.currentNote, drafts: model?.library.notes ?? [])
            }, onChange: { model.contentChanged() })
        let host = NSHostingView(rootView: native)
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        func textView(_ view: NSView) -> DraftTextView? {
            if let view = view as? DraftTextView { return view }
            return view.subviews.lazy.compactMap { textView($0) }.first
        }
        let text = try #require(textView(host))
        let manager = try #require(text.undoManager)
        manager.groupsByEvent = false
        let bar = try #require(text.touchBar)
        func press(_ command: EditorBarCommand) throws {
            let item = try #require(bar.item(forIdentifier: EditorTouchBarController.identifier(for: command)) as? NSCustomTouchBarItem)
            let button = try #require(item.view as? NSButton)
            NSApp.sendAction(try #require(button.action), to: button.target, from: button)
        }
        model.editor.selection = NSRange(location: 1, length: 0)
        try press(.moveRight)
        #expect(model.editor.selection == NSRange(location: 3, length: 0))
        let original = model.editor.content
        manager.beginUndoGrouping()
        try model.editor.replace(NSRange(location: 0, length: 1), with: "Changed")
        model.editor.synchronizeScriptEdit?()
        manager.endUndoGrouping()
        let edited = model.editor.content
        try press(.undo)
        #expect(model.editor.content == original && text.string == original)
        try press(.redo)
        #expect(model.editor.content == edited && text.string == edited)
    }

    @Test func configuredActionsUseSharedVisibilityOrderLabelsAndRefreshAfterChanges() async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences(prefix: "Draftly.TouchBar.")
        defer { preferences.close() }
        let model = try model(defaults: preferences.defaults)
        var first = DraftAction(name: "First café", steps: [ActionStep("insertText", ["template": "Touch Bar QA"])])
        first.group = "Touch Bar QA"; first.options = ActionPresentation()
        first.presentation.barUsesIcon = false; first.presentation.barLabel = "Run 🐼"
        var hidden = DraftAction(name: "Hidden", steps: []); hidden.group = first.group
        hidden.options = ActionPresentation(); hidden.options?.showInBar = false
        var other = DraftAction(name: "Other", steps: []); other.group = "Other"
        for action in [other, hidden, first] { try model.library.saveAction(action) }
        model.actionBarGroup = first.group
        let text = DraftTextView(frame: .zero)
        text.configureTouchBar(model: model, showCustom: true)
        let bar = try #require(text.touchBar)
        #expect(bar.defaultItemIdentifiers == [EditorTouchBarController.identifier(for: first)])
        let item = try #require(bar.item(forIdentifier: bar.defaultItemIdentifiers[0]) as? NSCustomTouchBarItem)
        let button = try #require(item.view as? NSButton)
        #expect(button.title == "Run 🐼" && button.accessibilityLabel() == first.name)
        NSApp.sendAction(try #require(button.action), to: button.target, from: button)
        await model.actionTask?.value
        #expect(model.editor.content.contains("Touch Bar QA"))
        model.actionBarGroup = "Editing"
        await TestMainQueue.drain()
        let refreshed = try #require(text.touchBar)
        #expect(refreshed !== bar)
        #expect(refreshed.defaultItemIdentifiers == EditorBarCommand.allCases.map(EditorTouchBarController.identifier(for:)))
    }
}
