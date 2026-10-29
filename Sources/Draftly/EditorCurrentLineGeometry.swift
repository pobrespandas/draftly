import AppKit

/// Finds the visual line that contains the insertion point.
enum EditorCurrentLineGeometry {
    static func rect(layout: NSLayoutManager, container: NSTextContainer, selection: NSRange) -> NSRect? {
        guard let storage = layout.textStorage, selection.location != NSNotFound,
              selection.location <= storage.length else { return nil }
        layout.ensureLayout(for: container)
        if selection.location == storage.length && layout.extraLineFragmentTextContainer === container {
            return layout.extraLineFragmentRect
        }
        guard storage.length > 0 else { return nil }
        let character = min(selection.location, storage.length - 1)
        let glyph = layout.glyphIndexForCharacter(at: character)
        guard glyph < layout.numberOfGlyphs, layout.textContainer(forGlyphAt: glyph, effectiveRange: nil) === container else { return nil }
        return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    }
}
