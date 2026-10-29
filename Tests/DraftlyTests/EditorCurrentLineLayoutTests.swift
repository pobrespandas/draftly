import AppKit
import Testing
@testable import Draftly

@Suite("Editor insertion line") @MainActor
struct EditorCurrentLineLayoutTests {
    @Test func lineGeometryUsesUTF16AndPreservesEditorState() throws {
        let text = DraftTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let storage = try #require(text.textStorage)
        let container = try #require(text.textContainer)
        let layout = try #require(text.layoutManager)
        text.string = "first\n🐼 café\nlast"
        let selection = (text.string as NSString).range(of: "café")
        text.setSelectedRange(selection)
        let first = try #require(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: NSRange(location: 0, length: 0)))
        let second = try #require(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: selection))
        #expect(second.minY > first.minY)
        let end = try #require(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: NSRange(location: (text.string as NSString).length, length: 0)))
        let finalGlyph = layout.glyphIndexForCharacter(at: (text.string as NSString).length - 1)
        #expect(end == layout.lineFragmentRect(forGlyphAt: finalGlyph, effectiveRange: nil))
        #expect(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: NSRange(location: NSNotFound, length: 0)) == nil)
        #expect(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: NSRange(location: (text.string as NSString).length + 1, length: 0)) == nil)
        text.highlightInsertionPoint = true
        #expect(text.textStorage === storage)
        #expect(text.string == "first\n🐼 café\nlast")
        #expect(text.selectedRange() == selection)
    }

    @Test func trailingNewlineAndEmptyDocumentHaveInsertionGeometry() throws {
        let text = DraftTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let container = try #require(text.textContainer)
        let layout = try #require(text.layoutManager)
        text.string = "one\n"
        let first = try #require(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: NSRange(location: 0, length: 0)))
        let last = try #require(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: NSRange(location: 4, length: 0)))
        #expect(last.minY > first.minY)
        text.string = ""
        #expect(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: NSRange(location: 0, length: 0)) != nil)
    }
    @Test func wrappedLineUsesVisualFragmentInsteadOfParagraph() throws {
        let text = DraftTextView(frame: NSRect(x: 0, y: 0, width: 110, height: 300))
        let container = try #require(text.textContainer)
        let layout = try #require(text.layoutManager)
        text.string = "first words followed by several more words and café 🐼"
        let first = try #require(EditorCurrentLineGeometry.rect(layout: layout, container: container,
            selection: NSRange(location: 0, length: 0)))
        let panda = (text.string as NSString).range(of: "🐼")
        let last = try #require(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: panda))
        #expect(last.minY > first.minY)
        let glyph = layout.glyphIndexForCharacter(at: panda.location)
        #expect(last == layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil))
    }

    @Test(arguments: ["\r", "\r\n", "\u{2028}", "\u{2029}"])
    func insertionAfterLineTerminatorUsesExtraFragment(terminator: String) throws {
        let text = DraftTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let container = try #require(text.textContainer)
        let layout = try #require(text.layoutManager)
        text.string = "one" + terminator
        layout.ensureLayout(for: container)
        let expected = layout.extraLineFragmentRect
        #expect(layout.extraLineFragmentTextContainer === container)
        let actual = try #require(EditorCurrentLineGeometry.rect(layout: layout, container: container,
            selection: NSRange(location: (text.string as NSString).length, length: 0)))
        #expect(actual == expected)
    }
    @Test func backgroundDrawingFillsEmptyInsertionLineWithoutChangingText() throws {
        let text = DraftTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        text.backgroundColor = .white
        text.string = ""
        text.highlightInsertionPoint = true
        text.currentLineColor = .red
        let container = try #require(text.textContainer)
        let layout = try #require(text.layoutManager)
        let line = try #require(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: text.selectedRange()))
            .offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        text.drawBackground(in: text.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let pixel = try #require(bitmap.colorAt(x: Int(line.midX), y: 99 - Int(line.midY))?.usingColorSpace(.deviceRGB))
        #expect(pixel.redComponent > 0.9 && pixel.greenComponent < 0.1)
        #expect(text.string.isEmpty && text.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test(arguments: [(NSAppearance.Name.aqua, false), (.darkAqua, true)])
    func defaultLineColorContrastsWithEditorBackground(appearanceName: NSAppearance.Name, dark: Bool) throws {
        let text = DraftTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let appearance = try #require(NSAppearance(named: appearanceName))
        text.appearance = appearance
        text.backgroundColor = dark ? .black : .white
        text.highlightInsertionPoint = true
        let layout = try #require(text.layoutManager)
        let container = try #require(text.textContainer)
        let line = try #require(EditorCurrentLineGeometry.rect(layout: layout, container: container, selection: text.selectedRange()))
            .offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        appearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            text.drawBackground(in: text.bounds)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
        }
        let pixel = try #require(bitmap.colorAt(x: Int(line.midX), y: 99 - Int(line.midY))?.usingColorSpace(.deviceRGB))
        #expect(dark ? pixel.redComponent > 0.01 : pixel.redComponent < 0.99)
    }

}
