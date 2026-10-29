import AppKit
import Testing
@testable import Draftly

@Suite("HTML preferences") @MainActor
struct HTMLPreferencesTests {
    init() { _ = NSApplication.shared }

    @Test func codeBlocksPreserveBlankLinesAndMarkupAsText() throws {
        let html = "<p>Before</p><pre><code>let a = &lt;tag&gt;\n\n\nlet b = &amp;value;\n```\nend</code></pre><p>After</p>"
        let result = try NativeHTMLConversion().htmlToMarkdown(html, options: [:])
        #expect(result == "Before\n\n````\nlet a = <tag>\n\n\nlet b = &value;\n```\nend\n````\n\nAfter")
    }

    @Test func imageConversionPreservesAlternateTextAndAttributeOrder() throws {
        let html = "<p><img alt='Café &amp; 🐼' src='neutral.png'><img data-src='wrong.png' src=actual.png alt=Diagram></p>"
        let converter = NativeHTMLConversion()
        let result = try converter.htmlToMarkdown(html, options: [:])
        #expect(result == "![Café & 🐼](neutral.png)![Diagram](actual.png)")
        #expect(try converter.htmlToMarkdown(html, options: ["ignoreImages": true]).isEmpty)
    }

    @Test func imageMarkdownEscapesDecodedLabelsAndDestinations() throws {
        let html = "<img alt='Café &#93; &amp; *panda*' src='folder/a(b).png?x=1&amp;y=2'>"
        let result = try NativeHTMLConversion().htmlToMarkdown(html, options: [:])
        #expect(result == #"![Café \] & \*panda\*](folder/a\(b\).png?x=1&y=2)"#)
    }

    @Test(arguments: [false, true])
    func linkConversionReadsHrefRatherThanDataHref(inline: Bool) throws {
        let html = "<p><a data-href='wrong' href=actual>Uno 🐼</a> <a title='a > b' href = 'two'>Dos</a></p>"
        let result = try NativeHTMLConversion().htmlToMarkdown(html, options: ["inlineLinks": inline])
        if inline {
            #expect(result == "[Uno 🐼](actual) [Dos](two)")
        } else {
            #expect(result.contains("[Uno 🐼][1] [Dos][2]"))
            #expect(result.contains("[1]: actual") && result.contains("[2]: two"))
        }
        #expect(!result.contains("wrong"))
    }

    @Test func ignoredLinksAndImageAttributesHandleQuotedGreaterThan() throws {
        let html = "<p><a title='a > b' href='neutral'>Café</a> <img alt='a > b' src='neutral.png'></p>"
        let converter = NativeHTMLConversion()
        #expect(try converter.htmlToMarkdown(html, options: ["ignoreLinks": true]) == "Café ![a > b](neutral.png)")
        #expect(try converter.htmlToMarkdown(html, options: ["ignoreLinks": true, "ignoreImages": true]) == "Café")
    }

    @Test func orderedAndNestedListsKeepTheirMarkersAndStart() throws {
        let html = "<ul><li>Parent<ol start='3'><li>First 🐼</li><li>Second</li></ol></li><li>Next</li></ul>"
        let result = try NativeHTMLConversion().htmlToMarkdown(html, options: ["ulItemMark": "-"])
        #expect(result == "- Parent\n    3. First 🐼\n    4. Second\n- Next")
        let reverse = "<ol start=9><li>One<ul><li>Child</li></ul></li><li>Two</li></ol>"
        #expect(try NativeHTMLConversion().htmlToMarkdown(reverse, options: [:]) == "9. One\n    * Child\n10. Two")
    }

    @Test func marksAndIgnoreOptionsReachTheConverter() throws {
        let host = NativeActionHost()
        let html = "<p><strong>Café 🐼</strong> <em>text</em> <a href='https://example.com'>link</a><img src='neutral.png'></p><ul><li>item</li></ul>"
        let value = try #require(host.performAPI("htmlToMarkdown", values: ["text": html, "options": ["strongMark": "__", "emphasisMark": "*", "ulItemMark": "-"]]) as? String)
        #expect(value.contains("__Café 🐼__"))
        #expect(value.contains("*text*"))
        #expect(value.contains("- item"))
        #expect(value.contains("[link](https://example.com)"))
        let ignored = try #require(host.performAPI("htmlToMarkdown", values: ["text": html, "options": ["ignoreLinks": true, "ignoreImages": true, "ignoreEmphasis": true]]) as? String)
        #expect(ignored.contains("Café 🐼 text link"))
        #expect(!ignored.contains("example.com") && !ignored.contains("neutral.png"))
        #expect(!ignored.contains("**") && !ignored.contains("_text_"))
    }

    @Test func referenceLinksCanFollowEachParagraphOrTheWholeDocument() throws {
        let host = NativeActionHost()
        let html = "<p><a href='https://example.com/one'>First</a></p><p><a href='https://example.com/two'>Second</a></p>"
        func render(_ each: Bool) throws -> String {
            try #require(host.performAPI("htmlToMarkdown", values: ["text": html, "options": ["inlineLinks": false, "linksEachParagraph": each]]) as? String)
        }
        let each = try render(true)
        #expect(each.contains("[First][1]") && each.contains("[Second][2]"))
        #expect(try #require(each.range(of: "[1]:")).lowerBound < #require(each.range(of: "[Second][2]")).lowerBound)
        let end = try render(false)
        #expect(try #require(end.range(of: "[1]:")).lowerBound > #require(end.range(of: "[Second][2]")).lowerBound)
    }

    @Test func pasteConvertsTheSelectionAndPreservesThePasteboardAndUndo() throws {
        let suite = "Draftly-HTMLPreferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let html = "<strong>Café 🐼</strong>"
        pasteboard.setString(html, forType: .html)
        let view = DraftTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.isRichText = false
        view.allowsUndo = true
        let window = OffscreenTestWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        view.string = "Before XX after"
        view.setSelectedRange(NSRange(location: 7, length: 2))
        let undo = try #require(view.undoManager)
        undo.beginUndoGrouping()
        #expect(try view.pasteHTML(from: pasteboard, defaults: defaults))
        undo.endUndoGrouping()
        #expect(view.string == "Before **Café 🐼** after")
        #expect(pasteboard.string(forType: .html) == html)
        undo.undo()
        #expect(view.string == "Before XX after")
        undo.redo()
        #expect(view.string == "Before **Café 🐼** after")
        undo.undo()
        defaults.set(false, forKey: HTMLPreferences.pasteKey)
        #expect(try !view.pasteHTML(from: pasteboard, defaults: defaults))
        #expect(view.string == "Before XX after")
    }

    @Test(arguments: ["*", "-"])
    func savedListMarkSurvivesReopeningAndControlsUnicodePaste(mark: String) throws {
        let preferences = try TestPreferences(prefix: "Draftly-HTMLListMark-")
        defer { preferences.close() }
        preferences.defaults.set(mark, forKey: "html.ulItemMark")
        preferences.defaults.set(true, forKey: HTMLPreferences.pasteKey)
        let reopened = try #require(UserDefaults(suiteName: preferences.name))
        #expect(reopened.persistentDomain(forName: preferences.name)?["html.ulItemMark"] as? String == mark)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let html = "<ul><li>Café 🐼</li></ul>"
        pasteboard.setString(html, forType: .html)
        let changeCount = pasteboard.changeCount
        let view = DraftTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.isRichText = false
        view.allowsUndo = true
        let window = OffscreenTestWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        let original = "Before 🦊 XX after"
        view.string = original
        let selection = (original as NSString).range(of: "XX")
        view.setSelectedRange(selection)
        let undo = try #require(view.undoManager)
        defer { undo.removeAllActions(); window.contentView = nil }
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(try view.pasteHTML(from: pasteboard, defaults: reopened))
        undo.endUndoGrouping()
        let converted = mark + " Café 🐼"
        let expected = original.replacingOccurrences(of: "XX", with: converted)
        #expect(view.string == expected)
        #expect(view.selectedRange() == NSRange(location: selection.location + (converted as NSString).length, length: 0))
        #expect(pasteboard.changeCount == changeCount)
        #expect(pasteboard.string(forType: .html) == html)
        undo.undo()
        #expect(view.string == original)
        undo.redo()
        #expect(view.string == expected)
    }

    @Test func entityDecodingPreservesUnicodeAndWhitespaceWithoutLoadingHTML() throws {
        let host = NativeActionHost()
        for text in ["", "Café 🐼", "one\n\ntwo", " \t\n", "<img src='https://example.com/private'>"] {
            #expect(try host.decodeHTML(text) == text)
        }
        #expect(try host.decodeHTML("A &amp; B &lt;tag&gt;") == "A & B <tag>")
        let html = "<p>One</p><p>Two</p>"
        #expect(try host.performAPI("htmlToMarkdown", values: ["text": html]) as? String == "One\n\nTwo")
    }

    @Test func entityUnescapeChangesOnlyEntitiesAndKeepsLiteralTextBytes() throws {
        let host = NativeActionHost()
        for text in ["A\r\nB\rC\nD", "before\0after", "  &amp;\r\n\t&lt;tag&gt;  "] {
            let expected = text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            #expect(Array(try host.decodeHTML(text).utf8) == Array(expected.utf8))
        }
    }

    @Test func plainTextPasteboardLeavesConversionAndSelectionUntouched() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Plain café 🐼", forType: .string)
        let view = DraftTextView(frame: .zero)
        view.string = "Keep this"
        view.setSelectedRange(NSRange(location: 5, length: 4))
        #expect(try !view.pasteHTML(from: pasteboard))
        #expect(view.string == "Keep this")
        #expect(view.selectedRange() == NSRange(location: 5, length: 4))
        #expect(pasteboard.string(forType: .string) == "Plain café 🐼")
    }

    @Test func tagNamesDoNotMatchLongerElementNames() throws {
        let host = NativeActionHost()
        let cases = [
            ("<body>Before <b>Bold</b> after</body>", "Before **Bold** after"),
            ("<input>Before <i>Italic</i> after", "Before _Italic_ after"),
            ("<link href='style.css'><ul><li>Item</li></ul>", "* Item"),
            ("<aside>Before <a href='https://example.com'>Link</a> after</aside>", "Before [Link](https://example.com) after")
        ]
        for (html, expected) in cases {
            #expect(try host.performAPI("htmlToMarkdown", values: ["text": html]) as? String == expected)
        }
    }

    @Test func invalidStoredMarksUseSupportedDefaults() throws {
        let name = "Draftly-HTMLMarks-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("invalid", forKey: "html.strongMark")
        #expect(HTMLPreferences.options(defaults: defaults)["strongMark"] as? String == "**")
        #expect(HTMLPreferences.options(defaults: defaults)["inlineLinks"] as? Bool == true)
    }
}
