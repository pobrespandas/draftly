import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@MainActor struct TypewriterScrollingTests {
    @Test(arguments: [false, true])
    func emptyCaretRangeScrollsToItsActualLine(trailingNewline: Bool) throws {
        let content = (0..<100).map { "Neutral line \($0) café 🐼" }.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let session = EditorSession(); session.content = content; session.typewriterScrollingEnabled = true
        let editor = NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, onChange: {})
        let coordinator = NativeEditor.Coordinator(editor)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 3000))
        text.font = .systemFont(ofSize: 17)
        text.string = content
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scroll.documentView = text
        coordinator.textView = text
        let caret = NSRange(location: content.utf16.count, length: 0)
        text.setSelectedRange(caret)
        scroll.contentView.scroll(to: .zero)
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
        #expect(scroll.contentView.bounds.origin.y > 500)
        #expect(session.selection == caret)
        #expect(session.content == content && text.string == content)
    }
    @Test func disabledModeKeepsTheViewportAndTogglingKeepsTextAndSelection() {
        let content = (0..<100).map { "Neutral line \($0) café 🐼" }.joined(separator: "\n")
        let session = EditorSession(); session.content = content
        let editor = NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, onChange: {})
        let coordinator = NativeEditor.Coordinator(editor)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 3000))
        text.font = .systemFont(ofSize: 17); text.string = content
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scroll.documentView = text; coordinator.textView = text
        let caret = NSRange(location: content.utf16.count, length: 0)
        text.setSelectedRange(caret)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
        let notification = Notification(name: NSTextView.didChangeSelectionNotification, object: text)
        coordinator.textViewDidChangeSelection(notification)
        #expect(scroll.contentView.bounds.origin.y == 120)
        session.typewriterScrollingEnabled = true
        coordinator.textViewDidChangeSelection(notification)
        #expect(scroll.contentView.bounds.origin.y > 500)
        let enabledOrigin = scroll.contentView.bounds.origin
        session.typewriterScrollingEnabled = false
        coordinator.textViewDidChangeSelection(notification)
        #expect(scroll.contentView.bounds.origin == enabledOrigin)
        #expect(session.selection == caret && text.selectedRange() == caret)
        #expect(session.content == content && text.string == content)
    }


    @Test(arguments: [0, 2, 100], [false, true])
    func nativeEditorCentersTheEndCaretWithoutArtificialDocumentHeight(lineCount: Int, trailingNewline: Bool) async throws {
        _ = NSApplication.shared
        let content = (0..<lineCount).map { "Neutral line \($0) café 🐼" }.joined(separator: "\n")
            + (trailingNewline ? "\n" : "")
        let session = EditorSession()
        session.load(Note(content: content), focusEditor: false)
        session.typewriterScrollingEnabled = true
        let host = NSHostingView(rootView: NativeEditor(session: session, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: {}))
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
        let coordinator = try #require(text.delegate as? NativeEditor.Coordinator)
        let scroll = try #require(text.enclosingScrollView)
        let layout = try #require(text.layoutManager), container = try #require(text.textContainer)
        let caret = NSRange(location: content.utf16.count, length: 0)
        text.setSelectedRange(caret)
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
        layout.ensureLayout(for: container)
        let line: NSRect
        if trailingNewline || content.isEmpty {
            #expect(layout.extraLineFragmentTextContainer === container)
            line = layout.extraLineFragmentRect
        } else {
            let glyph = layout.glyphIndexForCharacter(at: max(0, caret.location - 1))
            line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        let caretCenter = text.textContainerOrigin.y + line.midY
        #expect(abs(caretCenter - scroll.contentView.bounds.midY) <= 1,
            Comment(rawValue: "Caret center \(caretCenter), viewport center \(scroll.contentView.bounds.midY), document height \(text.bounds.height)"))
        #expect(text.string == content && session.content == content)
        #expect(text.selectedRange() == caret && session.selection == caret)
        for height in [600, 240] {
            window.setContentSize(NSSize(width: 500, height: height))
            host.layoutSubtreeIfNeeded()
            await TestMainQueue.drain()
            coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
            layout.ensureLayout(for: container)
            #expect(abs(text.textContainerOrigin.y + line.midY - scroll.contentView.bounds.midY) <= 1)
            #expect(text.string == content && text.selectedRange() == caret)
        }

        let manager = try #require(text.undoManager)
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        try session.replace(NSRange(location: 0, length: min(7, content.utf16.count)), with: "Changed café 🐼")
        session.synchronizeScriptEdit?()
        manager.endUndoGrouping()
        let edited = session.content
        let selected = (edited as NSString).range(of: "café 🐼")
        session.selection = selected
        session.synchronizeScriptEdit?()
        for enabled in [false, true] {
            session.typewriterScrollingEnabled = enabled
            host.layoutSubtreeIfNeeded()
            await TestMainQueue.drain()
            #expect(text.typewriterScrollingEnabled == enabled)
            if !enabled { #expect(Double(text.textContainerInset.height) == EditorTextLayout.verticalMargin) }
            #expect(text.string == edited && session.content == edited)
            #expect(text.selectedRange() == selected && session.selection == selected)
            #expect(manager.canUndo)
        }
        manager.undo()
        #expect(text.string == content && session.content == content)
        manager.redo()
        #expect(text.string == edited && session.content == edited)
    }

}
