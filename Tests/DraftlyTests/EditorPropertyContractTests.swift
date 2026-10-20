import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Editor property contracts") @MainActor
struct EditorPropertyContractTests {
    private func model() throws -> WindowModel {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        model.select(try model.library.createNote(content: "Alpha 🐼\nBody", tags: ["keep"]).id)
        model.editor.selection = NSRange(location: 6, length: 2)
        return model
    }

    private func action(_ source: String) -> DraftAction {
        DraftAction(name: "Editor property contract", steps: [ActionStep("script", ["script": """
        function check(value,label){if(!value)throw new Error(label);}
        \(source)
        """])])
    }

    private func checkEditorPreserved(_ model: WindowModel) {
        #expect(model.editor.content == "Alpha 🐼\nBody")
        #expect(model.editor.selection == NSRange(location: 6, length: 2))
    }

    @Test func linkModeEnabledReadsAndSetsTheWindowModeWithoutChangingTheDraft() throws {
        let model = try model()
        #expect(model.runner.run(action("""
        check(editor.linkModeEnabled===false,'initial link mode');
        editor.linkModeEnabled=true;check(editor.linkModeEnabled===true,'enable link mode');
        """)), Comment(rawValue: model.runner.message ?? ""))
        #expect(model.linksEnabled)
        checkEditorPreserved(model)
        #expect(model.runner.run(action("editor.linkModeEnabled=false;check(editor.linkModeEnabled===false,'disable link mode');")))
        #expect(!model.linksEnabled)
        checkEditorPreserved(model)
    }

    @Test func pinningEnabledReadsAndSetsTheWindowPinWithoutChangingTheDraft() throws {
        let model = try model()
        #expect(model.runner.run(action("""
        check(editor.pinningEnabled===false,'initial pin');
        editor.pinningEnabled=true;check(editor.pinningEnabled===true,'enable pin');
        """)), Comment(rawValue: model.runner.message ?? ""))
        #expect(model.isDraftPinned)
        checkEditorPreserved(model)
        #expect(model.runner.run(action("editor.pinningEnabled=false;check(editor.pinningEnabled===false,'disable pin');")))
        #expect(!model.isDraftPinned)
        checkEditorPreserved(model)
    }

    @Test func focusModeEnabledIsTheDeprecatedPinningAliasInBothDirections() throws {
        let model = try model()
        #expect(model.runner.run(action("""
        check(editor.focusModeEnabled===false,'initial focus mode');
        editor.focusModeEnabled=true;check(editor.pinningEnabled===true,'focus enables pin');
        editor.pinningEnabled=false;check(editor.focusModeEnabled===false,'pin clears focus');
        editor.pinningEnabled=true;check(editor.focusModeEnabled===true,'pin enables focus');
        """)), Comment(rawValue: model.runner.message ?? ""))
        #expect(model.isDraftPinned)
        checkEditorPreserved(model)
        #expect(model.runner.run(action("editor.focusModeEnabled=false;check(editor.pinningEnabled===false,'focus clears pin');")))
        #expect(!model.isDraftPinned)
        checkEditorPreserved(model)
    }

    @Test func typewriterScrollingEnabledReadsAndSetsTheEditorModeWithoutChangingText() throws {
        let model = try model()
        #expect(model.runner.run(action("""
        check(editor.typewriterScrollingEnabled===false,'initial typewriter');
        editor.typewriterScrollingEnabled=true;check(editor.typewriterScrollingEnabled===true,'enable typewriter');
        """)), Comment(rawValue: model.runner.message ?? ""))
        #expect(model.editor.typewriterScrollingEnabled)
        checkEditorPreserved(model)
        #expect(model.runner.run(action("editor.typewriterScrollingEnabled=false;check(editor.typewriterScrollingEnabled===false,'disable typewriter');")))
        #expect(!model.editor.typewriterScrollingEnabled)
        checkEditorPreserved(model)
    }

    @Test func preferredTabStringReturnsTheCurrentTabAndRejectsStrictAssignment() throws {
        let model = try model()
        #expect(model.runner.run(action(#"""
        check(editor.preferredTabString==='\t','current tab string');
        let rejected=false;
        try{(function(){'use strict';editor.preferredTabString='  ';})();}catch(error){rejected=error instanceof TypeError;}
        check(rejected,'readonly assignment');check(editor.preferredTabString==='\t','tab unchanged');
        """#)), Comment(rawValue: model.runner.message ?? ""))
        checkEditorPreserved(model)
    }

    @Test func recentDraftsReturnsPreviousLoadsFirstAndOmitsTrash() throws {
        let model = try model()
        let first = try #require(model.editor.noteID)
        let second = try model.library.createNote(content: "Beta")
        let third = try model.library.createNote(content: "Gamma")
        #expect(model.runner.run(action("check(Array.isArray(editor.recentDrafts)&&editor.recentDrafts.length===0,'initial recents');")))
        model.select(second.id)
        model.select(third.id)
        model.select(third.id)
        #expect(model.runner.run(action("""
        const recent=editor.recentDrafts;
        check(recent.length===2,'one entry per previous load');
        check(recent[0].uuid==='\(second.id.uuidString)'&&recent[1].uuid==='\(first.uuidString)','reverse load order');
        check(recent[0]===Draft.find(recent[0].uuid),'execution identity');
        recent.pop();check(editor.recentDrafts.length===2,'array does not mutate history');
        """)), Comment(rawValue: model.runner.message ?? ""))
        var trashed = try #require(model.library.notes.first { $0.id == first })
        trashed.trashedAt = Date()
        try model.library.saveNote(trashed)
        #expect(model.runner.run(action("check(editor.recentDrafts.length===1&&editor.recentDrafts[0].uuid==='\(second.id.uuidString)','trash omitted');")))
        #expect(model.editor.noteID == third.id)
    }

    @Test(arguments: [false, true])
    func nextDraftReturnsVoidAndUsesVisibleOrderWithoutWrappingAtTheEnd(worker: Bool) async throws {
        let model = try model()
        _ = try model.library.createNote(content: "Beta", tags: ["skip"])
        let last = try model.library.createNote(content: "Gamma 🐼 café", tags: ["keep"])
        model.sort = .title; model.ascending = true; model.tag = "keep"
        let value = action("""
        const original=editor.draft;editor.setSelectedRange(0,8);
        check(editor.nextDraft()===undefined,'next returns void');
        check(original.selectionStart===0&&original.selectionLength===8,'previous Unicode selection retained');
        check(editor.draft.uuid==='\(last.id.uuidString)','next visible draft');
        editor.setSelectedRange(2,1);
        check(editor.nextDraft()===undefined,'end returns void');
        check(editor.draft.uuid==='\(last.id.uuidString)','end stays selected');
        check(editor.getSelectedRange().join(',')==='2,1','end preserves selection');
        """)
        let succeeded: Bool
        if worker { succeeded = await model.runner.runAsync(value).result.succeeded }
        else { succeeded = model.runner.run(value) }
        #expect(succeeded, Comment(rawValue: model.runner.message ?? ""))
        #expect(model.editor.noteID == last.id)
        #expect(model.editor.content == last.content)
    }

    @Test(arguments: [false, true])
    func previousDraftReturnsVoidAndUsesVisibleOrderWithoutWrappingAtTheStart(worker: Bool) async throws {
        let model = try model()
        let first = try #require(model.editor.noteID)
        _ = try model.library.createNote(content: "Beta", tags: ["skip"])
        let last = try model.library.createNote(content: "Gamma 🐼 café", tags: ["keep"])
        model.sort = .title; model.ascending = true; model.tag = "keep"
        model.select(last.id)
        let value = action("""
        const original=editor.draft;editor.setSelectedRange(6,2);
        check(editor.previousDraft()===undefined,'previous returns void');
        check(original.selectionStart===6&&original.selectionLength===2,'previous Unicode selection retained');
        check(editor.draft.uuid==='\(first.uuidString)','previous visible draft');
        editor.setSelectedRange(0,5);
        check(editor.previousDraft()===undefined,'start returns void');
        check(editor.draft.uuid==='\(first.uuidString)','start stays selected');
        check(editor.getSelectedRange().join(',')==='0,5','start preserves selection');
        """)
        let succeeded: Bool
        if worker { succeeded = await model.runner.runAsync(value).result.succeeded }
        else { succeeded = model.runner.run(value) }
        #expect(succeeded, Comment(rawValue: model.runner.message ?? ""))
        #expect(model.editor.noteID == first)
        #expect(model.editor.content == "Alpha 🐼\nBody")
    }

    @Test func isActiveDistinguishesTheNativeEditorFromOtherTextViews() async throws {
        let model = try model()
        let fixture = try await focusFixture(model)
        defer { fixture.window.contentView = nil; model.window = nil }
        #expect(fixture.window.makeFirstResponder(fixture.editor))
        #expect(model.runner.run(action("check(editor.isActive===true,'native editor focused');")))
        #expect(fixture.window.makeFirstResponder(fixture.otherText))
        #expect(model.runner.run(action("check(editor.isActive===false,'other text control is not editor focus');")), Comment(rawValue: model.runner.message ?? ""))
        fixture.window.makeFirstResponder(nil)
        #expect(model.runner.run(action("check(editor.isActive===false,'no editor focus');")))
        checkEditorPreserved(model)
    }

    @Test func activateReturnsVoidAndRestoresTheNativeEditorFocus() async throws {
        let model = try model()
        let fixture = try await focusFixture(model)
        defer { fixture.window.contentView = nil; model.window = nil }
        #expect(fixture.window.makeFirstResponder(fixture.otherText))
        model.showPreview = true
        let previousToken = model.editor.focusToken
        #expect(model.runner.run(action("check(editor.activate()===undefined,'activate returns void');")), Comment(rawValue: model.runner.message ?? ""))
        #expect(model.editor.focusToken != previousToken)
        #expect(!model.showPreview)
        await TestMainQueue.drain()
        #expect(fixture.window.firstResponder === fixture.editor)
        checkEditorPreserved(model)
    }

    @Test func deactivateLeavesAnotherTextControlFocused() async throws {
        let model = try model()
        let fixture = try await focusFixture(model)
        defer { fixture.window.contentView = nil; model.window = nil }
        #expect(fixture.window.makeFirstResponder(fixture.otherText))
        #expect(model.runner.run(action("check(editor.deactivate()===undefined,'deactivate returns void');")), Comment(rawValue: model.runner.message ?? ""))
        #expect(fixture.window.firstResponder === fixture.otherText)
        checkEditorPreserved(model)
    }

    @Test func deactivateReturnsVoidAndResignsTheNativeEditorFocus() async throws {
        let model = try model()
        let fixture = try await focusFixture(model)
        defer { fixture.window.contentView = nil; model.window = nil }
        #expect(fixture.window.makeFirstResponder(fixture.editor))
        #expect(model.runner.run(action("""
        check(editor.deactivate()===undefined,'deactivate returns void');
        check(editor.isActive===false,'editor resigned focus');
        """)), Comment(rawValue: model.runner.message ?? ""))
        #expect(fixture.window.firstResponder !== fixture.editor)
        checkEditorPreserved(model)
    }

    private struct FocusFixture {
        let window: NSWindow
        let editor: NSTextView
        let otherText: NSTextView
    }

    private func focusFixture(_ model: WindowModel) async throws -> FocusFixture {
        _ = NSApplication.shared
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 360))
        let host = NSHostingView(rootView: NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
                                                       lineSpacing: 2, markdown: false, onChange: {}))
        host.frame = NSRect(x: 0, y: 40, width: 500, height: 320)
        let otherText = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        container.addSubview(host); container.addSubview(otherText)
        window.contentView = container; model.window = window
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        func findEditor(_ view: NSView) -> NSTextView? {
            if let editor = view as? DraftTextView { return editor }
            return view.subviews.lazy.compactMap { findEditor($0) }.first
        }
        let editor = try #require(findEditor(host))
        return FocusFixture(window: window, editor: editor, otherText: otherText)
    }
}
