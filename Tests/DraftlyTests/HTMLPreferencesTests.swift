import AppKit
import Testing
@testable import Draftly

@Suite("HTML preferences") @MainActor
struct HTMLPreferencesTests {
    init() { _ = NSApplication.shared }

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
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
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

    @Test func entityDecodingPreservesUnicodeAndWhitespaceWithoutLoadingHTML() throws {
        let host = NativeActionHost()
        for text in ["", "Café 🐼", "one\n\ntwo", " \t\n", "<img src='https://example.com/private'>"] {
            #expect(try host.decodeHTML(text) == text)
        }
        #expect(try host.decodeHTML("A &amp; B &lt;tag&gt;") == "A & B <tag>")
        let html = "<p>One</p><p>Two</p>"
        #expect(try host.performAPI("htmlToMarkdown", values: ["text": html]) as? String == "One\n\nTwo")
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
