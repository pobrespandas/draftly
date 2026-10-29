import AppKit
import DraftlyCore

@MainActor enum ThemeTextAttributes {
    static func monospaceFont(name: String, size: CGFloat) -> NSFont {
        if name != "System Monospace", let font = NSFont(name: name, size: size) { return font }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func make(_ style: ThemeScopeStyle, currentFont: NSFont, baseFont: NSFont, monospaceFontName: String = "System Monospace") -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let value = style.foreground.flatMap(EditorTheme.color) { attributes[.foregroundColor] = value }
        if let value = style.background.flatMap(EditorTheme.color) { attributes[.backgroundColor] = value }
        var font = currentFont
        if let styles = style.fontStyles {
            if styles.isEmpty { font = baseFont }
            if styles.contains("monospace"), !font.isFixedPitch || monospaceFontName != "System Monospace" {
                font = monospaceFont(name: monospaceFontName, size: font.pointSize)
            }
            font = styles.contains("italic")
                ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                : NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
            attributes[.underlineStyle] = styles.contains("underline") ? NSUnderlineStyle.single.rawValue : 0
            attributes[.strikethroughStyle] = styles.contains("strikethrough") ? NSUnderlineStyle.single.rawValue : 0
        }
        if let name = style.fontWeight {
            let weights: [String: NSFont.Weight] = ["ultraLight": .ultraLight, "thin": .thin, "light": .light,
                "regular": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black]
            if let weight = weights[name] {
                var traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any] ?? [:]
                traits[.weight] = weight.rawValue
                font = NSFont(descriptor: font.fontDescriptor.addingAttributes([.traits: traits]), size: font.pointSize) ?? font
            }
        }
        if let name = style.fontSize {
            let scale: [String: CGFloat] = ["extraSmall": 0.8, "small": 0.9, "normal": 1, "large": 1.1, "extraLarge": 1.2]
            if let factor = scale[name] { font = NSFontManager.shared.convert(font, toSize: baseFont.pointSize * factor) }
        }
        attributes[.font] = font
        return attributes
    }
}
