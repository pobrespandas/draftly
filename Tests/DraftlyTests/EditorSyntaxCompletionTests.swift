import AppKit
import SwiftUI
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Editor syntax completions") @MainActor
struct EditorSyntaxCompletionTests {
    private func request(_ source: String, selection: NSRange) throws -> SyntaxCompletionRequest {
        try #require(try completion(source, selection: selection))
    }
    private func completion(_ source: String, selection: NSRange) throws -> SyntaxCompletionRequest? {
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Neutral completion", "patterns": [], "navigationPatterns": [], "taskMarkDefinitions": [], "linkDefinitions": [], "indentationPatterns": [],
            "autocompleteDefinitions": [["trigger": "!!", "type": "static", "items": [
                ["label": "Same label", "value": "First café"], ["label": "Same label", "value": "Second 🐼"]]]]]))
        return syntax.completion(in: source, selection: selection, drafts: [], current: Note(content: source))
    }
    @Test func navigationRetainsDuplicateIdentityAndCancelNeverProducesAnEdit() throws {
        let source = "🐼 !!", selection = NSRange(location: source.utf16.count, length: 0), id = UUID()
        let state = EditorSyntaxCompletions()
        state.begin(try request(source, selection: selection), source: source, selection: selection, noteID: id)
        state.move(-1); #expect(state.selectedIndex == 0)
        state.move(1); state.move(1); #expect(state.selectedIndex == 1)
        #expect(state.value(source: source, selection: selection, noteID: id)?.1 == "Second 🐼")
        #expect(state.value(source: source, selection: selection, noteID: id, index: 0)?.1 == "First café")
        #expect(state.value(source: source, selection: selection, noteID: id, index: 99) == nil)
        state.dismiss()
        #expect(state.value(source: source, selection: selection, noteID: id) == nil)
    }
    @Test func staleSourceSelectionAndDraftCannotApplyACompletion() throws {
        let source = "🐼 !!", selection = NSRange(location: source.utf16.count, length: 0), id = UUID()
        let state = EditorSyntaxCompletions()
        state.begin(try request(source, selection: selection), source: source, selection: selection, noteID: id)
        #expect(state.value(source: source + "x", selection: selection, noteID: id) == nil)
        #expect(state.value(source: source, selection: NSRange(location: 0, length: 0), noteID: id) == nil)
        #expect(state.value(source: source, selection: selection, noteID: UUID()) == nil)
        state.invalidate(source: source, selection: selection, noteID: id)
        #expect(state.request != nil)
        state.invalidate(source: source, selection: selection, noteID: UUID())
        #expect(state.request == nil)
    }
    @Test func acceptanceReplacesOnlyTheTriggerQueryAndRetainsNativeUndo() throws {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.allowsUndo = true
        let window = OffscreenTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = text
        defer { window.contentView = nil }
        let manager = try #require(text.undoManager); manager.groupsByEvent = false
        let source = "🐼 !!a", selection = NSRange(location: source.utf16.count, length: 0)
        text.string = "🐼 !!"; text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0)); text.completionNoteID = UUID()
        manager.beginUndoGrouping(); text.insertText("a", replacementRange: text.selectedRange()); manager.endUndoGrouping()
        #expect(text.string == source && text.selectedRange() == selection)
        let state = text.syntaxCompletions
        state.begin(try request(source, selection: selection), source: source, selection: selection, noteID: text.completionNoteID)
        manager.beginUndoGrouping(); state.accept(in: text, index: 1); manager.endUndoGrouping()
        #expect(text.string == "🐼 Second 🐼")
        #expect(text.selectedRange() == NSRange(location: text.string.utf16.count, length: 0))
        #expect(state.request == nil && !window.isVisible)
        manager.undo(); #expect(text.string == source)
        manager.redo(); #expect(text.string == "🐼 Second 🐼")
    }
    @Test func textInputRefreshesSuggestionsButAcceptanceDoesNotOpenAnotherRequest() async throws {
        let text = DraftTextView(frame: .zero); text.isRichText = false
        text.string = "🐼 !"; text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        var requested = 0
        text.completionProvider = { source, selection in
            requested += 1
            return try? completion(source, selection: selection)
        }
        text.insertText("!", replacementRange: text.selectedRange())
        await TestMainQueue.drain()
        #expect(requested == 1 && text.syntaxCompletions.request?.items.count == 2)
        text.syntaxCompletions.accept(in: text, index: 1)
        await TestMainQueue.drain()
        #expect(text.string == "🐼 Second 🐼" && requested == 1)
        #expect(text.syntaxCompletions.request == nil && text.window == nil)
    }

    @Test func deletionRefreshesSuggestionsAndRemovingTriggerDismissesThem() async throws {
        let text = DraftTextView(frame: .zero); text.isRichText = false
        text.string = "🐼 !!x"; text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        text.completionProvider = { source, selection in try? completion(source, selection: selection) }
        #expect(!text.refreshSyntaxCompletions())
        text.deleteBackward(nil); await TestMainQueue.drain()
        #expect(text.string == "🐼 !!")
        #expect(text.syntaxCompletions.request?.items.count == 2)
        text.deleteBackward(nil); await TestMainQueue.drain()
        #expect(text.string == "🐼 !" && text.syntaxCompletions.request == nil)
        #expect(text.window == nil)
    }

    @Test func forwardDeletionRefreshesTheQueryAtTheFinalInsertionPoint() async throws {
        let text = DraftTextView(frame: .zero); text.isRichText = false
        text.string = "🐼 !!x"; text.setSelectedRange(NSRange(location: text.string.utf16.count - 1, length: 0))
        var queries: [NSRange] = []
        text.completionProvider = { source, selection in
            queries.append(selection)
            return try? completion(source, selection: selection)
        }
        text.deleteForward(nil); await TestMainQueue.drain()
        #expect(text.string == "🐼 !!")
        #expect(queries == [NSRange(location: text.string.utf16.count, length: 0)])
        #expect(text.syntaxCompletions.request?.items.count == 2 && text.window == nil)
    }

    @Test(arguments: ["cancel", "selection", "draft", "source"])
    func queuedRefreshIgnoresAChangedEditingContext(_ change: String) async throws {
        let text = DraftTextView(frame: .zero); text.isRichText = false
        text.string = "🐼 !!x"; text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        text.completionNoteID = UUID()
        var requested = 0
        text.completionProvider = { source, selection in
            requested += 1
            return try? completion(source, selection: selection)
        }
        text.deleteBackward(nil)
        switch change {
        case "cancel": text.cancelSyntaxCompletions()
        case "selection": text.setSelectedRange(NSRange(location: 0, length: 0))
        case "draft": text.completionNoteID = UUID()
        default: text.string = "Other source"
        }
        await TestMainQueue.drain()
        #expect(requested == 0 && text.syntaxCompletions.request == nil && text.window == nil)
    }

    @Test func equivalentBuiltInDefinitionsRetainSuggestionsAcrossViewUpdates() async throws {
        _ = NSApplication.shared
        let session = EditorSession(); session.load(Note(content: "🐼 [[caf"), focusEditor: false)
        session.selection = NSRange(location: session.content.utf16.count, length: 0)
        func editor() throws -> NativeEditor {
            NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
                markdown: true, syntaxDefinition: try ScriptSyntax.definition("Markdown"), onChange: {})
        }
        let host = NSHostingView(rootView: try editor())
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func find(_ view: NSView) -> DraftTextView? {
            if let view = view as? DraftTextView { return view }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        host.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
        let text = try #require(find(host)), syntax = try ScriptSyntax.definition("Markdown")
        let result = try #require(syntax.completion(in: session.content, selection: session.selection, drafts: [Note(content: "Café")], current: Note(content: session.content)))
        text.syntaxCompletions.begin(result, source: session.content, selection: session.selection, noteID: session.noteID)
        host.rootView = try editor(); host.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
        #expect(text.syntaxCompletions.request == result)
        #expect(text.string == session.content && !window.isVisible)
    }

    @Test func builtInMarkdownTriggersReturnTitlesAndFullDrafts() throws {
        let target = Note(content: "# Café 🐼\nBody"), current = Note(content: "Current")
        for name in ["Markdown", "MultiMarkdown", "GitHub Markdown"] {
            let syntax = try ScriptSyntax.definition(name)
            let title = syntax.completion(in: "[[caf", selection: NSRange(location: 5, length: 0), drafts: [target], current: current)
            let full = syntax.completion(in: "<<caf", selection: NSRange(location: 5, length: 0), drafts: [target], current: current)
            #expect(title?.items.first?.value == "[[Café 🐼]]")
            #expect(full?.items.first?.value == target.content)
        }
        #expect(try ScriptSyntax.definition("Plain Text").completion(in: "[[caf", selection: NSRange(location: 5, length: 0), drafts: [target], current: current) == nil)
    }
}
