import AppKit
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

}
