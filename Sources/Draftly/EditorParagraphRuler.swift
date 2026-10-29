import AppKit

/// Stores paragraph starts as UTF-16 offsets, including the final empty paragraph.
struct EditorParagraphIndex {
    let starts: [Int]

    init(_ text: String) {
        let source = text as NSString
        var result = [0]
        var offset = 0
        while offset < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
            let next = NSMaxRange(paragraph)
            guard next > offset else { break }
            if next < source.length || source.paragraphRange(for: NSRange(location: next, length: 0)).length == 0 {
                result.append(next)
            }
            offset = next
        }
        starts = result
    }

    func paragraph(at offset: Int) -> Int {
        var lower = 0, upper = starts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if starts[middle] <= offset { lower = middle + 1 } else { upper = middle }
        }
        return max(0, lower - 1)
    }
}

final class EditorParagraphRuler: NSRulerView {
    private var cachedText: String?
    private var index = EditorParagraphIndex("")
    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 38
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        (clientView as? NSTextView)?.backgroundColor.setFill()
        dirtyRect.intersection(bounds).fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let view = clientView as? NSTextView, let layout = view.layoutManager,
              let container = view.textContainer else { return }
        let source = view.string
        if source != cachedText { index = EditorParagraphIndex(source); cachedText = source }
        layout.ensureLayout(for: container)
        let origin = view.textContainerOrigin
        let visible = view.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layout.glyphRange(forBoundingRect: visible, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let first = index.paragraph(at: chars.location)
        let last = index.paragraph(at: min((source as NSString).length, NSMaxRange(chars)))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        for paragraph in first...last {
            let offset = index.starts[paragraph]
            let line: NSRect
            if offset == (source as NSString).length {
                guard layout.extraLineFragmentTextContainer === container else { continue }
                line = layout.extraLineFragmentRect
            } else {
                let glyph = layout.glyphIndexForCharacter(at: offset)
                guard glyph < layout.numberOfGlyphs else { continue }
                line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let point = convert(NSPoint(x: origin.x, y: line.minY + origin.y), from: view)
            let label = String(paragraph + 1) as NSString
            let size = label.size(withAttributes: attributes)
            let verticalOffset = max(0, (line.height - size.height) / 2)
            label.draw(at: NSPoint(x: bounds.maxX - size.width - 6, y: point.y + verticalOffset), withAttributes: attributes)
        }
    }
}
