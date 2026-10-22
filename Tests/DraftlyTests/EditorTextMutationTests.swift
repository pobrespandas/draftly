import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Editor text mutation routes") @MainActor
struct EditorTextMutationTests {
    @Test(arguments: EditorMutationRoute.allCases)
    func shorterUnicodeEditRestoresTextAndSelectionThroughUndoAndRedo(route: EditorMutationRoute) async throws {
        let source = "café 🐼\r\nTail"
        let fixture = try await MutationFixture(route, source: source)
        defer { fixture.close() }
        let selected = (source as NSString).range(of: "🐼")
        await fixture.refresh { $0.selection = selected }
        let replacement = "té 🐼"
        let requested = NSRange(location: 100, length: 9)
        fixture.undo.beginUndoGrouping()
        await fixture.refresh { $0.content = replacement; $0.selection = requested }
        fixture.undo.endUndoGrouping()
        #expect(fixture.text.string == replacement && fixture.session.content == replacement)
        #expect(fixture.text.selectedRange() == NSRange(location: replacement.utf16.count, length: 0))
        #expect(fixture.session.selection == requested)
        #expect(fixture.undo.canUndo && !fixture.undo.canRedo && fixture.changes.count == 0)
        await fixture.refresh { $0.selection = $0.safeSelection }
        #expect(fixture.undo.canUndo && fixture.changes.count == 0)
        fixture.undo.undo()
        await TestMainQueue.drain()
        #expect(fixture.text.string == source && fixture.session.content == source)
        #expect(fixture.text.selectedRange() == selected && fixture.session.selection == selected)
        #expect(!fixture.undo.canUndo && fixture.undo.canRedo && fixture.changes.count == 1)
        fixture.undo.redo()
        await TestMainQueue.drain()
        #expect(fixture.text.string == replacement && fixture.session.content == replacement)
        #expect(fixture.text.selectedRange() == NSRange(location: replacement.utf16.count, length: 0))
        #expect(fixture.session.selection == fixture.text.selectedRange())
        #expect(fixture.undo.canUndo && !fixture.undo.canRedo && fixture.changes.count == 2)
    }

    @Test(arguments: EditorMutationRoute.allCases, [false, true])
    func loadingAnotherDraftClearsUndoAndKeepsRouteSpecificHighlighting(route: EditorMutationRoute, sameText: Bool) async throws {
        let fixture = try await MutationFixture(route, source: "Previous café 🐼")
        defer { fixture.close() }
        let edited = "Edited 🐼"
        fixture.undo.beginUndoGrouping()
        await fixture.refresh { $0.content = edited }
        fixture.undo.endUndoGrouping()
        #expect(fixture.undo.canUndo)
        let marker = NSAttributedString.Key("DraftlyNeutralMutationMarker")
        fixture.text.textStorage?.addAttribute(marker, value: "retained", range: NSRange(location: 0, length: 1))
        var next = Note(content: sameText ? edited : "x")
        next.scriptMetadata = ["selectionStart": "1", "selectionLength": "0"]
        await fixture.refresh { $0.load(next, focusEditor: false) }
        #expect(fixture.coordinator.noteID == next.id && fixture.session.noteID == next.id)
        #expect(fixture.text.string == next.content && fixture.session.content == next.content)
        #expect(fixture.text.selectedRange() == NSRange(location: 1, length: 0))
        #expect(!fixture.undo.canUndo && !fixture.undo.canRedo && fixture.changes.count == 0)
        let retained = fixture.text.textStorage?.attribute(marker, at: 0, effectiveRange: nil) != nil
        #expect(retained == (route == .script && sameText))
    }

    @Test(arguments: EditorMutationRoute.allCases)
    func emptyStyleCacheClearsHistoryOnlyInViewRoute(route: EditorMutationRoute) async throws {
        let fixture = try await MutationFixture(route, source: "Original")
        defer { fixture.close() }
        fixture.undo.beginUndoGrouping()
        await fixture.refresh { $0.content = "Edited" }
        fixture.undo.endUndoGrouping()
        fixture.coordinator.style = ""
        await fixture.refresh { $0.focusToken = UUID() }
        #expect(fixture.undo.canUndo == (route == .script))
        #expect(fixture.coordinator.style.isEmpty == (route == .script))
        #expect((fixture.coordinator.focusToken == fixture.session.focusToken) == (route == .view))
        #expect(fixture.text.string == "Edited" && fixture.session.content == "Edited")
        #expect(fixture.changes.count == 0)
    }

    @Test func scriptReentryLeavesTextSelectionHistoryAndIdentityUntouched() async throws {
        let fixture = try await MutationFixture(.script, source: "Original 🐼")
        defer { fixture.close() }
        let previousID = fixture.coordinator.noteID
        let previousSelection = fixture.text.selectedRange()
        fixture.coordinator.updating = true
        let next = Note(content: "New")
        await fixture.refresh { $0.load(next, focusEditor: false) }
        #expect(fixture.text.string == "Original 🐼" && fixture.text.selectedRange() == previousSelection)
        #expect(fixture.coordinator.noteID == previousID && fixture.coordinator.updating)
        #expect(!fixture.undo.canUndo && fixture.changes.count == 0)
        fixture.coordinator.updating = false
        await fixture.refresh()
        #expect(fixture.text.string == next.content && fixture.coordinator.noteID == next.id)
    }
}

enum EditorMutationRoute: CaseIterable { case view, script }

@MainActor private final class MutationChanges { var count = 0 }

@MainActor private final class MutationFixture {
    let session = EditorSession()
    let changes = MutationChanges()
    let text: NSTextView
    let coordinator: NativeEditor.Coordinator
    let undo: UndoManager
    private let route: EditorMutationRoute
    private var host: NSHostingView<NativeEditor>?
    private var window: OffscreenTestWindow?

    init(_ route: EditorMutationRoute, source: String) async throws {
        self.route = route
        session.load(Note(content: source), focusEditor: false)
        let native = Self.editor(session, changes: changes)
        switch route {
        case .script:
            let text = TestUndoTextView(frame: .zero)
            text.string = source
            let coordinator = native.makeCoordinator()
            coordinator.textView = text
            text.delegate = coordinator
            self.text = text; self.coordinator = coordinator; undo = text.manager
        case .view:
            _ = NSApplication.shared
            let host = NSHostingView(rootView: native)
            let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
            let text = try #require(Self.findText(host))
            self.text = text
            coordinator = try #require(text.delegate as? NativeEditor.Coordinator)
            undo = try #require(text.undoManager)
            self.host = host; self.window = window
            #expect(!window.isVisible)
        }
        undo.groupsByEvent = false
    }

    func refresh(_ change: (EditorSession) -> Void = { _ in }) async {
        change(session)
        switch route {
        case .script: coordinator.synchronizeScriptEdit()
        case .view:
            host?.rootView = Self.editor(session, changes: changes)
            host?.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
        }
    }

    func close() {
        session.synchronizeScriptEdit = nil; session.performUndo = nil; session.focusForDictation = nil
        text.delegate = nil; coordinator.textView = nil
        undo.removeAllActions(); window?.contentView = nil
    }

    private static func editor(_ session: EditorSession, changes: MutationChanges) -> NativeEditor {
        NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
            markdown: false, isActive: false, showCustomTouchBar: false, onChange: { changes.count += 1 })
    }

    private static func findText(_ view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        return view.subviews.lazy.compactMap { findText($0) }.first
    }
}
