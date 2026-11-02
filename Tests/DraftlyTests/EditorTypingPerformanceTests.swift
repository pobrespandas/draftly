import AppKit
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Editor typing performance") @MainActor
struct EditorTypingPerformanceTests {
    private let document = Array(repeating:
        "# Heading\nParagraph with **bold**, `code`, and [link](https://example.com).\n- [ ] Task\n",
        count: 1_500).joined()

    private func duration(markedText: Bool) -> TimeInterval {
        let session = EditorSession()
        session.load(Note(content: document), focusEditor: false)
        let editor = NativeEditor(session: session, fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: true, linksEnabled: true, onChange: {})
        let coordinator = editor.makeCoordinator()
        let view = DraftTextView(frame: .zero)
        view.string = document
        view.setSelectedRange(NSRange(location: (document as NSString).length, length: 0))
        if markedText {
            view.setMarkedText("é", selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            view.insertText("e", replacementRange: view.selectedRange())
        }
        coordinator.textView = view
        let start = CFAbsoluteTimeGetCurrent()
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        return CFAbsoluteTimeGetCurrent() - start
    }

    @Test func markedTextAvoidsFullDocumentStylingCost() {
        var committed: [TimeInterval] = []
        var composing: [TimeInterval] = []
        for _ in 0..<5 {
            committed.append(duration(markedText: false))
            composing.append(duration(markedText: true))
        }
        committed.sort(); composing.sort()
        let committedMedian = committed[committed.count / 2]
        let composingMedian = composing[composing.count / 2]
        print(String(format: "Editor typing median for %d UTF-16 units: committed %.2f ms; composing %.2f ms",
            (document as NSString).length, committedMedian * 1_000, composingMedian * 1_000))
        #expect(composingMedian < committedMedian * 0.5)
    }
}
