import AppKit
import SwiftUI
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Imported theme rendering") @MainActor
struct ThemeRenderingTests {
    private func theme(codeColor: String = "#CCAA00") throws -> EditorTheme {
        let source: [String: Any] = ["name": "Scope QA", "description": "Neutral styles", "isDark": true,
            "colors": ["editor": ["ink": "#F0F0F0"], "interface": ["textForeground": "#F0F0F0", "textBackground": "#17324D", "textCaret": "#ABCDEF", "textSelection": "#334455"]],
            "scopes": ["text.normal": ["settings": ["foreground": "ink", "fontStyle": "normal"]],
                "text.header": ["settings": ["fontStyle": "italic"]],
                "text.heading": ["settings": ["foreground": "#00FF00", "fontWeight": "bold", "fontSize": "extraLarge"]],
                "text.bold": ["settings": ["fontWeight": "bold", "fontStyle": "underline"]],
                "text.italic": ["settings": ["fontStyle": "italic"]],
                "text.strikethrough": ["settings": ["fontStyle": "strikethrough"]],
                "code.inline": ["settings": ["foreground": codeColor, "background": "#112233", "fontStyle": "monospace"]],
                "custom.neutral": ["settings": ["foreground": "#FF00FF"]]]]
        return try DraftsThemeImport.decode(data: JSONSerialization.data(withJSONObject: source))
    }
    private func hex(_ value: Any?) throws -> String {
        let color = try #require((value as? NSColor)?.usingColorSpace(.sRGB))
        return String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
    @Test func markdownAndCustomScopesApplyAttributesWithoutChangingUTF16SelectionOrText() throws {
        let session = EditorSession()
        session.load(Note(content: "# Header\n**Bold** and `code`\n*Italic*\n~~Gone~~\ncafé 🐼"), focusEditor: false)
        let unicode = (session.content as NSString).range(of: "café 🐼")
        session.selection = unicode
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: ["name": "Neutral",
            "patterns": [["match": "café 🐼", "captures": ["0": ["scope": "custom.neutral"]]]],
            "navigationPatterns": [], "linkDefinitions": [], "taskMarkDefinitions": [], "indentationPatterns": []]))
        let editor = NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
            markdown: true, syntaxDefinition: syntax, theme: try theme(), onChange: {})
        let coordinator = editor.makeCoordinator()
        let view = NSTextView(frame: .zero)
        view.string = session.content; view.setSelectedRange(unicode)
        coordinator.textView = view
        coordinator.highlight()
        let storage = try #require(view.textStorage)
        func attributes(_ text: String) -> [NSAttributedString.Key: Any] {
            storage.attributes(at: (view.string as NSString).range(of: text).location, effectiveRange: nil)
        }
        #expect(try hex(attributes("Header")[.foregroundColor]) == "00FF00")
        #expect(!NSFontManager.shared.traits(of: try #require(attributes("Header")[.font] as? NSFont)).contains(.italicFontMask))
        #expect(abs(((attributes("Header")[.font] as? NSFont)?.pointSize ?? 0) - 20.4) < 0.01)
        #expect(attributes("Bold")[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(try hex(attributes("code")[.foregroundColor]) == "CCAA00")
        #expect(try hex(attributes("code")[.backgroundColor]) == "112233")
        #expect((attributes("code")[.font] as? NSFont)?.isFixedPitch == true)
        #expect(NSFontManager.shared.traits(of: try #require(attributes("Italic")[.font] as? NSFont)).contains(.italicFontMask))
        #expect(attributes("Gone")[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(try hex(storage.attribute(.foregroundColor, at: unicode.location, effectiveRange: nil)) == "FF00FF")
        #expect(view.string == session.content && view.selectedRange() == unicode)
    }

    @Test func sourceOnlyStyleChangesInvalidateCachedHighlighting() async throws {
        _ = NSApplication.shared
        let session = EditorSession(); session.load(Note(content: "`code` 🐼"), focusEditor: false)
        session.selection = NSRange(location: 7, length: 2)
        let first = try theme()
        var second = try theme(codeColor: "#EE0099")
        second.id = first.id
        func editor(_ value: EditorTheme) -> NativeEditor {
            NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: true, theme: value, onChange: {})
        }
        let host = NSHostingView(rootView: editor(first))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        for (value, expected) in [(first, "CCAA00"), (second, "EE0099")] {
            host.rootView = editor(value); host.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
            let text = try #require(findText(host))
            #expect(try hex(text.textStorage?.attribute(.foregroundColor, at: 1, effectiveRange: nil)) == expected)
            #expect(try hex(text.insertionPointColor) == "ABCDEF")
            #expect(try hex(text.selectedTextAttributes[.backgroundColor]) == "334455")
            #expect(text.string == session.content && text.selectedRange() == session.selection)
        }
    }
}
