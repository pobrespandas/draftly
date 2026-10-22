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
}
