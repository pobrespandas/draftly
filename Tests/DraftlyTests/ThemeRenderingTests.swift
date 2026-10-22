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
                "text.linkModeLink": ["settings": ["foreground": "#0099EE", "fontStyle": "underline"]],
                "custom.neutral": ["settings": ["foreground": "#FF00FF"]]]]
        return try DraftsThemeImport.decode(data: JSONSerialization.data(withJSONObject: source))
    }
    private func hex(_ value: Any?) throws -> String {
        let color = try #require((value as? NSColor)?.usingColorSpace(.sRGB))
        return String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
    @Test func customSyntaxLinksRespectLinkModeAndCapturedUTF16Range() throws {
        let text = "🐼 <<web:café &/>>"
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Neutral links", "patterns": [], "navigationPatterns": [],
            "indentationPatterns": [], "taskMarkDefinitions": [],
            "linkDefinitions": [["match": #"(<<)((web):([^>]+))(>>)"#,
                "captures": ["key": "3", "value": "4", "link": "2"],
                "templates": ["web": "https://example.invalid/?q=[[value]]"]]]]))
        let session = EditorSession(); session.load(Note(content: text), focusEditor: false)
        let selected = (text as NSString).range(of: "🐼")
        session.selection = selected
        let view = NSTextView(frame: .zero); view.string = text; view.setSelectedRange(selected)
        for enabled in [true, false, true] {
            let editor = NativeEditor(session: session, fontName: "System", fontSize: 17,
                lineSpacing: 2, markdown: false, syntaxDefinition: syntax, linksEnabled: enabled, onChange: {})
            let coordinator = editor.makeCoordinator(); coordinator.textView = view
            coordinator.highlight()
            let storage = try #require(view.textStorage)
            let range = (text as NSString).range(of: "web:café &/")
            let url = storage.attribute(.link, at: range.location, effectiveRange: nil) as? URL
            #expect(url?.absoluteString == (enabled ? "https://example.invalid/?q=caf%C3%A9%20%26%2F" : nil))
            #expect(storage.attribute(.link, at: range.location - 1, effectiveRange: nil) == nil)
            #expect(storage.attribute(.link, at: NSMaxRange(range), effectiveRange: nil) == nil)
            #expect(view.string == text && view.selectedRange() == selected)
        }
    }

    @Test func taskAndLinkCaptureScopesApplyWithoutTaskForegroundOrTextChanges() throws {
        let text = "🐼 [ ] task <<note:café>>"
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Neutral capture scopes", "patterns": [], "navigationPatterns": [], "indentationPatterns": [],
            "taskMarkDefinitions": [["match": #"(\[[ x]\])"#, "rangeType": "task", "captures": ["state": "1", "interactive": "1"],
                "states": ["[ ]", "[x]"], "scopes": ["interactive": "text.monospace.bold, color.red"]]],
            "linkDefinitions": [["match": #"(<<)((note):([^>]+))(>>)"#,
                "captures": ["key": "3", "value": "4", "prefix": "1", "suffix": "5", "link": "2"],
                "scopes": ["key": "text.bold", "value": "custom.neutral"]]]]))
        let session = EditorSession(); session.load(Note(content: text), focusEditor: false)
        let selection = (text as NSString).range(of: "café"); session.selection = selection
        let view = NSTextView(frame: .zero); view.string = text; view.setSelectedRange(selection)
        let themed = try DraftsThemeImport.decode(data: JSONSerialization.data(withJSONObject: [
            "name": "Neutral task styles", "description": "Neutral capture style test", "isDark": false,
            "colors": ["editor": [:], "interface": ["textForeground": "#222222", "textBackground": "#FFFFFF"]],
            "scopes": ["text.monospace.bold": ["settings": ["foreground": "#FF0000", "fontWeight": "bold", "fontStyle": "monospace, underline"]],
                "custom.neutral": ["settings": ["foreground": "#FF00FF", "fontStyle": "italic"]]]]))
        for theme in [Optional<EditorTheme>.none, themed] {
            let editor = NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
                markdown: false, syntaxDefinition: syntax, theme: theme, onChange: {})
            let coordinator = editor.makeCoordinator(); coordinator.textView = view; coordinator.highlight()
            let storage = try #require(view.textStorage)
            let taskRange = (text as NSString).range(of: "[ ]")
            let attributes = storage.attributes(at: taskRange.location, effectiveRange: nil)
            #expect((attributes[.font] as? NSFont)?.isFixedPitch == true)
            #expect(NSFontManager.shared.traits(of: try #require(attributes[.font] as? NSFont)).contains(.boldFontMask))
            #expect(try hex(attributes[.foregroundColor]) != "FF0000")
            if theme != nil {
                #expect(attributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
                #expect(try hex(storage.attribute(.foregroundColor, at: selection.location, effectiveRange: nil)) == "FF00FF")
                #expect(NSFontManager.shared.traits(of: try #require(storage.attribute(.font, at: selection.location, effectiveRange: nil) as? NSFont)).contains(.italicFontMask))
            }
            #expect(view.string == text && view.selectedRange() == selection && session.content == text)
            #expect(storage.attribute(.link, at: selection.location, effectiveRange: nil) == nil)
        }
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
        #expect(!NSFontManager.shared.traits(of: try #require(attributes("Italic")[.font] as? NSFont)).contains(.boldFontMask))
        #expect(attributes("Gone")[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(try hex(storage.attribute(.foregroundColor, at: unicode.location, effectiveRange: nil)) == "FF00FF")
        #expect(view.string == session.content && view.selectedRange() == unicode)
    }

    @Test func linkThemeChangesAndLinkModeRestoreNativeAttributesWithoutChangingText() async throws {
        _ = NSApplication.shared
        let session = EditorSession()
        session.load(Note(content: "café 🐼 https://example.invalid/test"), focusEditor: false)
        let selected = (session.content as NSString).range(of: "café 🐼")
        session.selection = selected
        let value = try theme()
        func editor(_ theme: EditorTheme?, links: Bool) -> NativeEditor {
            NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
                markdown: false, theme: theme, linksEnabled: links, onChange: {})
        }
        let host = NSHostingView(rootView: editor(nil, links: true))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        host.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
        let initial = try #require(findText(host))
        let originalAttributes = (initial.linkTextAttributes ?? [:]) as NSDictionary
        let originalWasNil = initial.linkTextAttributes == nil
        let linkStart = (session.content as NSString).range(of: "https://").location
        for (theme, links) in [(Optional(value), true), (nil, true), (Optional(value), false), (Optional(value), true)] {
            host.rootView = editor(theme, links: links); host.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
            let text = try #require(findText(host))
            #expect((text.textStorage?.attribute(.link, at: linkStart, effectiveRange: nil) != nil) == links)
            if theme != nil && links {
                #expect(try hex(text.linkTextAttributes?[.foregroundColor]) == "0099EE")
                #expect(try hex(text.textStorage?.attribute(.foregroundColor, at: linkStart, effectiveRange: nil)) == "0099EE")
            } else {
                #expect(((text.linkTextAttributes ?? [:]) as NSDictionary).isEqual(originalAttributes))
                #expect((text.linkTextAttributes == nil) == originalWasNil)
            }
            #expect(text.string == session.content && text.selectedRange() == selected)
        }
    }

    @Test func featureChangesInvalidateStylesWithoutChangingTextSelectionOrUndo() async throws {
        _ = NSApplication.shared
        let session = EditorSession(); session.load(Note(content: "café 🐼"), focusEditor: false)
        session.selection = NSRange(location: 0, length: 4)
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Neutral feature styles", "navigationPatterns": [], "taskMarkDefinitions": [], "linkDefinitions": [], "indentationPatterns": [],
            "featureKeys": [["id": "highlight", "name": "Highlight", "description": "Neutral feature", "defaultValue": true]],
            "patterns": [["match": "café", "featureKeys": "highlight", "captures": ["0": ["scope": "custom.neutral"]]]]]))
        let theme = try theme()
        func editor(_ enabled: Bool) -> NativeEditor {
            NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false,
                syntaxDefinition: syntax.resolvingFeatures(["highlight": enabled]), theme: theme, onChange: {})
        }
        let host = NSHostingView(rootView: editor(true))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func textView(_ view: NSView) -> NSTextView? {
            if let view = view as? NSTextView { return view }
            return view.subviews.lazy.compactMap { textView($0) }.first
        }
        for enabled in [true, false, true] {
            host.rootView = editor(enabled); host.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
            let text = try #require(textView(host))
            #expect(try hex(text.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil)) == (enabled ? "FF00FF" : "F0F0F0"))
            #expect(text.string == session.content && text.selectedRange() == session.selection)
            #expect(text.undoManager?.canUndo != true && !window.isVisible)
        }
        let text = try #require(textView(host))
        let undo = try #require(text.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        session.content = "café 🐼 edited"
        host.rootView = editor(true)
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        undo.endUndoGrouping()
        for enabled in [false, true] {
            host.rootView = editor(enabled)
            host.layoutSubtreeIfNeeded()
            await TestMainQueue.drain()
            #expect(text.string == "café 🐼 edited" && session.content == text.string)
            #expect(text.selectedRange() == session.selection)
            #expect(undo.canUndo && !window.isVisible)
        }
        undo.undo()
        #expect(text.string == "café 🐼" && session.content == text.string)
        #expect(undo.canRedo)
        undo.redo()
        #expect(text.string == "café 🐼 edited" && session.content == text.string)
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
    @Test func hangingIndentationChangesWrappingWithoutChangingSourceOrSelection() async throws {
        _ = NSApplication.shared
        let source = "🐼  café text that wraps\nplain"
        let session = EditorSession(); session.load(Note(content: source), focusEditor: false)
        let selected = NSRange(location: 4, length: 4); session.selection = selected
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Neutral indentation", "patterns": [], "navigationPatterns": [], "taskMarkDefinitions": [], "linkDefinitions": [],
            "indentationPatterns": [["match": #"^(🐼 +).*"#, "indentCapture": "1", "indentScope": "text.normal", "featureKeys": "indent"]],
            "featureKeys": [["id": "indent", "name": "Indent", "description": "Neutral wrapping", "defaultValue": true]]]))
        func editor(_ enabled: Bool) -> NativeEditor {
            NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false,
                lineHeightMultiple: 1.2, paragraphSpacing: 3, syntaxDefinition: syntax.resolvingFeatures(["indent": enabled]), onChange: {})
        }
        let host = NSHostingView(rootView: editor(true))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        for enabled in [true, false, true] {
            host.rootView = editor(enabled); host.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
            let text = try #require(findText(host)), storage = try #require(text.textStorage)
            let style = try #require(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            let normal = try #require(storage.attribute(.paragraphStyle, at: source.utf16.count - 1, effectiveRange: nil) as? NSParagraphStyle)
            let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            let expected = ("🐼  " as NSString).size(withAttributes: [.font: font, .paragraphStyle: normal]).width
            #expect(abs(style.headIndent - (enabled ? expected : 0)) < 0.01)
            #expect(style.firstLineHeadIndent == 0 && normal.headIndent == 0)
            #expect(style.lineHeightMultiple == normal.lineHeightMultiple && style.paragraphSpacing == normal.paragraphSpacing)
            #expect(text.string == source && session.content == source && text.selectedRange() == selected)
            #expect(text.undoManager?.canUndo != true && !window.isVisible)
        }
    }
    @Test(arguments: ["  - ", "\t- "], ["text.normal", "text.heading"])
    func hangingIndentationAlignsWrappedGlyphsWithStyledPrefix(prefix: String, scope: String) async throws {
        _ = NSApplication.shared
        let source = prefix + String(repeating: "neutral café ", count: 15)
        let session = EditorSession(); session.load(Note(content: source), focusEditor: false)
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Neutral metrics", "patterns": [["match": "^(" + NSRegularExpression.escapedPattern(for: prefix) + ")", "captures": ["1": ["scope": scope]]]],
            "navigationPatterns": [], "taskMarkDefinitions": [], "linkDefinitions": [],
            "indentationPatterns": [["match": "^(" + NSRegularExpression.escapedPattern(for: prefix) + ").*", "indentCapture": "1", "indentScope": scope]]]))
        let editor = NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false,
            syntaxDefinition: syntax, theme: try theme(), onChange: {})
        let host = NSHostingView(rootView: editor)
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        let text = try #require(findText(host)), layout = try #require(text.layoutManager), container = try #require(text.textContainer)
        container.widthTracksTextView = false
        container.containerSize = NSSize(width: 200, height: 10000)
        layout.ensureLayout(for: container)
        let labelGlyph = layout.glyphIndexForCharacter(at: prefix.utf16.count)
        var firstLine = NSRange()
        let firstRect = layout.lineFragmentRect(forGlyphAt: labelGlyph, effectiveRange: &firstLine)
        let nextGlyph = NSMaxRange(firstLine)
        #expect(nextGlyph < layout.numberOfGlyphs)
        let nextRect = layout.lineFragmentRect(forGlyphAt: nextGlyph, effectiveRange: nil)
        let labelX = firstRect.minX + layout.location(forGlyphAt: labelGlyph).x
        let wrappedX = nextRect.minX + layout.location(forGlyphAt: nextGlyph).x
        #expect(abs(labelX - wrappedX) <= 1)
        #expect(text.string == source && session.content == source && !window.isVisible)
    }
    @Test func builtInQuotationUsesItalicBodyAndRetainsPlainTextDefaults() async throws {
        _ = NSApplication.shared
        let source = "> café 🐼\nplain"
        let session = EditorSession(); session.load(Note(content: source), focusEditor: false)
        session.selection = NSRange(location: 2, length: 4)
        func editor(_ name: String) throws -> NativeEditor {
            NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false,
                syntax: name, syntaxDefinition: try ScriptSyntax.definition(name), onChange: {})
        }
        let host = NSHostingView(rootView: try editor("Markdown"))
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        for name in ["Markdown", "MultiMarkdown", "GitHub Markdown", "Plain Text", "Markdown"] {
            host.rootView = try editor(name); host.layoutSubtreeIfNeeded(); await TestMainQueue.drain()
            let text = try #require(findText(host)), storage = try #require(text.textStorage)
            let body = try #require(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
            let plain = try #require(storage.attribute(.font, at: source.utf16.count - 1, effectiveRange: nil) as? NSFont)
            #expect(NSFontManager.shared.traits(of: body).contains(.italicFontMask) == (name != "Plain Text"))
            #expect(!NSFontManager.shared.traits(of: plain).contains(.italicFontMask))
            #expect(text.string == source && text.selectedRange() == session.selection && text.undoManager?.canUndo != true)
            #expect(!window.isVisible)
        }
    }
    @Test func exclusiveCodeCaptureKeepsItsFontWhileSurroundingTextGetsLaterStyles() throws {
        let source = "🐼 before `café` after"
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Neutral exclusive styles", "navigationPatterns": [], "taskMarkDefinitions": [], "linkDefinitions": [], "indentationPatterns": [],
            "patterns": [["match": "`([^`]+)`", "captures": ["1": ["scope": "code.inline", "exclusive": true]]],
                ["match": "^(.+)$", "captures": ["0": ["scope": "text.italic"]]]]]))
        let session = EditorSession(); session.load(Note(content: source), focusEditor: false)
        let selected = (source as NSString).range(of: "café"); session.selection = selected
        let view = NSTextView(frame: .zero); view.string = source; view.setSelectedRange(selected)
        let editor = NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false,
            syntaxDefinition: syntax, theme: try theme(), onChange: {})
        let coordinator = editor.makeCoordinator(); coordinator.textView = view; coordinator.highlight()
        let storage = try #require(view.textStorage)
        let code = try #require(storage.attribute(.font, at: selected.location, effectiveRange: nil) as? NSFont)
        #expect(code.isFixedPitch && !NSFontManager.shared.traits(of: code).contains(.italicFontMask))
        for index in [0, source.utf16.count - 1] {
            let font = try #require(storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
            #expect(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
        }
        #expect(view.string == source && view.selectedRange() == selected && session.content == source)
    }

    @Test func overlappingStylesKeepCustomScopesAndActiveLinksLast() throws {
        let source = "# **café** `code` https://example.invalid/🐼"
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Neutral overlap", "navigationPatterns": [], "taskMarkDefinitions": [],
            "linkDefinitions": [], "indentationPatterns": [],
            "patterns": [["match": "café|code|https://[^ ]+", "captures": ["0": ["scope": "custom.neutral"]]]]]))
        let session = EditorSession(); session.load(Note(content: source), focusEditor: false)
        let selected = (source as NSString).range(of: "🐼"); session.selection = selected
        let view = NSTextView(frame: .zero); view.string = source; view.setSelectedRange(selected)
        let editor = NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
            markdown: true, syntaxDefinition: syntax, theme: try theme(), linksEnabled: true, onChange: {})
        let coordinator = editor.makeCoordinator(); coordinator.textView = view; coordinator.highlight()
        let storage = try #require(view.textStorage)
        for word in ["café", "code"] {
            let index = (source as NSString).range(of: word).location
            #expect(try hex(storage.attribute(.foregroundColor, at: index, effectiveRange: nil)) == "FF00FF")
        }
        let bold = storage.attributes(at: (source as NSString).range(of: "café").location, effectiveRange: nil)
        #expect(bold[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(NSFontManager.shared.traits(of: try #require(bold[.font] as? NSFont)).contains(.boldFontMask))
        let code = storage.attributes(at: (source as NSString).range(of: "code").location, effectiveRange: nil)
        #expect((code[.font] as? NSFont)?.isFixedPitch == true)
        #expect(try hex(code[.backgroundColor]) == "112233")
        let link = (source as NSString).range(of: "https://").location
        #expect(storage.attribute(.link, at: link, effectiveRange: nil) != nil)
        #expect(try hex(storage.attribute(.foregroundColor, at: link, effectiveRange: nil)) == "0099EE")
        #expect(view.string == source && session.content == source && view.selectedRange() == selected)
    }

    @Test func removingStylesRetainsNativeUndoAndUnicodeSelection() throws {
        let source = "`café` 🐼"
        let session = EditorSession(); session.load(Note(content: source), focusEditor: false)
        let selected = (source as NSString).range(of: "🐼"); session.selection = selected
        var changes = 0
        func editor(themed: Bool) throws -> NativeEditor {
            NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
                markdown: themed, theme: themed ? try theme() : nil, onChange: { changes += 1 })
        }
        let view = TestUndoTextView(frame: .zero); view.string = source; view.setSelectedRange(selected)
        view.manager.groupsByEvent = false
        let coordinator = try editor(themed: true).makeCoordinator(); coordinator.textView = view
        coordinator.highlight()
        #expect(!view.manager.canUndo && changes == 0)
        view.manager.beginUndoGrouping()
        coordinator.restore(source + " edited", selection: selected)
        view.manager.endUndoGrouping()
        for themed in [false, true, false] {
            coordinator.parent = try editor(themed: themed); coordinator.highlight()
            let storage = try #require(view.textStorage)
            let attributes = storage.attributes(at: 1, effectiveRange: nil)
            #expect((attributes[.backgroundColor] != nil) == themed)
            #expect((attributes[.font] as? NSFont)?.isFixedPitch == themed)
            #expect(view.string == source + " edited" && session.content == view.string)
            #expect(view.selectedRange() == selected && session.selection == selected)
            #expect(view.manager.canUndo && !view.manager.canRedo && changes == 1)
        }
        view.manager.undo()
        #expect(view.string == source && session.content == source && view.selectedRange() == selected)
        #expect(!view.manager.canUndo && view.manager.canRedo)
        view.manager.redo()
        #expect(view.string == source + " edited" && session.content == view.string && view.selectedRange() == selected)
        #expect(view.manager.canUndo && !view.manager.canRedo && changes == 3)
    }

    @Test func emptyTextRestoresBaseTypingAttributesWithoutUndo() throws {
        let session = EditorSession(); session.load(Note(content: ""), focusEditor: false)
        let view = TestUndoTextView(frame: .zero)
        var changes = 0
        let editor = NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
            markdown: true, lineHeightMultiple: 1.25, paragraphSpacing: 3, theme: try theme(),
            linksEnabled: true, onChange: { changes += 1 })
        let coordinator = editor.makeCoordinator(); coordinator.textView = view
        for themed in [true, false, true] {
            coordinator.parent.theme = themed ? try theme() : nil
            coordinator.highlight()
            #expect(view.textStorage?.length == 0 && view.string.isEmpty && session.content.isEmpty)
            #expect(view.selectedRange() == NSRange(location: 0, length: 0))
            #expect((view.typingAttributes[.font] as? NSFont)?.pointSize == 17)
            let paragraph = try #require(view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
            #expect(paragraph.lineHeightMultiple == 1.25 && paragraph.paragraphSpacing == 3)
            #expect(!view.manager.canUndo && changes == 0)
        }
    }


    @Test func stylerRestoresExplicitLinkDefaultsIndependentlyForEachView() throws {
        let themed = try theme()
        func styler(_ theme: EditorTheme?, links: Bool) -> EditorSyntaxStyler {
            EditorSyntaxStyler(fontName: "System", fontSize: 17, lineSpacing: 2,
                markdown: false, lineHeightMultiple: 0, paragraphSpacing: 0,
                syntax: "Plain Text", syntaxDefinition: nil, theme: theme, linksEnabled: links)
        }
        let views = [NSTextView(frame: .zero), NSTextView(frame: .zero)]
        let defaults: [[NSAttributedString.Key: Any]?] = [nil,
            [.foregroundColor: NSColor.systemRed, .underlineStyle: NSUnderlineStyle.double.rawValue]]
        let active = styler(themed, links: true)
        for (index, view) in views.enumerated() {
            view.string = "https://example.invalid/"
            view.linkTextAttributes = [.foregroundColor: NSColor.systemOrange]
            active.apply(to: view, defaultLinkAttributes: defaults[index])
            #expect(try hex(view.linkTextAttributes?[.foregroundColor]) == "0099EE")
        }
        let plain = styler(nil, links: false)
        for index in views.indices.reversed() {
            let view = views[index]
            plain.apply(to: view, defaultLinkAttributes: defaults[index])
            #expect((view.linkTextAttributes == nil) == (defaults[index] == nil))
            #expect(((view.linkTextAttributes ?? [:]) as NSDictionary).isEqual(defaults[index] ?? [:]))
            #expect(view.textStorage?.attribute(.link, at: 0, effectiveRange: nil) == nil)
            #expect(view.string == "https://example.invalid/")
        }
    }

}
