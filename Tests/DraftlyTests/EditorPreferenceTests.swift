import AppKit
import Testing
@testable import Draftly

@Suite("Editor layout preferences") @MainActor
struct EditorPreferenceTests {
    @Test func maximumWidthCentersTextAndKeepsMarginsWhenNarrow() {
        #expect(EditorTextLayout.inset(width: 1000, margin: 20, maximumWidth: 600) == 200)
        #expect(EditorTextLayout.inset(width: 500, margin: 20, maximumWidth: 600) == 20)
        #expect(EditorTextLayout.inset(width: 1000, margin: 20, maximumWidth: 0) == 20)
    }
    @Test func resizingTextMarginsDoesNotChangeTextOrSelection() {
        let view = DraftTextView(frame: NSRect(x: 0, y: 0, width: 1000, height: 500))
        view.string = "Unicode ñ 🐼\nPreserve this text"
        view.setSelectedRange(NSRange(location: 3, length: 4))
        let before = view.string, selection = view.selectedRange()
        view.maximumLineWidth = 600; view.horizontalMargin = 20; view.updateTextInsets()
        #expect(view.string == before)
        #expect(view.selectedRange() == selection)
        #expect(view.textContainerInset.width == 200)
        #expect(EditorTheme.color("#00AAFF") != nil)
        #expect(EditorTheme.color("broken") == nil)
    }
}
