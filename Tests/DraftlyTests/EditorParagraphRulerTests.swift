import AppKit
import Testing
@testable import Draftly

@Suite("Editor paragraph numbers") @MainActor
struct EditorParagraphRulerTests {
    @Test(arguments: [("", [0]), ("one", [0]), ("one\n", [0, 4]),
                      ("🐼\r\ncafé\n", [0, 4, 9]), ("a\u{2028}b\u{2029}c", [0, 4])])
    func paragraphStartsUseUTF16AndParagraphSeparators(source: String, expected: [Int]) {
        #expect(EditorParagraphIndex(source).starts == expected)
    }

    @Test func lookupFindsParagraphAtBoundaries() {
        let index = EditorParagraphIndex("one\n🐼\nlast")
        #expect(index.starts == [0, 4, 7])
        #expect(index.paragraph(at: 0) == 0)
        #expect(index.paragraph(at: 3) == 0)
        #expect(index.paragraph(at: 4) == 1)
        #expect(index.paragraph(at: 6) == 1)
        #expect(index.paragraph(at: 7) == 2)
        #expect(index.paragraph(at: 99) == 2)
    }

    @Test func rulerIsAttachedWithoutChangingTextOrSelection() throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let text = DraftTextView(frame: scroll.bounds)
        text.string = "café 🐼\nsecond"
        let selection = (text.string as NSString).range(of: "🐼")
        text.setSelectedRange(selection)
        scroll.documentView = text
        let ruler = EditorParagraphRuler(scrollView: scroll, textView: text)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        #expect(ruler.clientView === text)
        #expect(text.string == "café 🐼\nsecond")
        #expect(text.selectedRange() == selection)
        scroll.rulersVisible = false
        #expect(text.string == "café 🐼\nsecond")
        #expect(text.selectedRange() == selection)
    }
    @Test func rulerDrawsLabelsWithoutAWindow() throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let text = DraftTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 300))
        text.string = "first\nsecond\nthird"
        scroll.documentView = text
        let ruler = EditorParagraphRuler(scrollView: scroll, textView: text)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        ruler.frame = NSRect(x: 0, y: 0, width: 38, height: 300)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 38, pixelsHigh: 300,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        ruler.drawHashMarksAndLabels(in: ruler.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let hasInk = (0..<300).contains { y in
            (0..<38).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        }
        #expect(hasInk)
        #expect(text.string == "first\nsecond\nthird")
    }

    @Test func typewriterScrollingPreservesHorizontalOrigin() {
        #expect(EditorTypewriterScrolling.origin(current: NSPoint(x: -38, y: 10), vertical: 70) == NSPoint(x: -38, y: 70))
        #expect(EditorTypewriterScrolling.origin(current: NSPoint(x: 0, y: 10), vertical: 70) == NSPoint(x: 0, y: 70))
    }

}
