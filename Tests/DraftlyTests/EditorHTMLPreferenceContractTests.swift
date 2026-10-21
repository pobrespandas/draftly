import AppKit
import Testing
@testable import Draftly

@Suite("Persisted editor HTML preferences") @MainActor
struct EditorHTMLPreferenceContractTests {
    @Test(arguments: ["marks", "ignoreEmphasis", "ignoreLinks", "ignoreImages", "inlineLinks", "documentReferences", "paragraphReferences"])
    func reopenedOptionsControlActualPasteWithoutChangingClipboardAndUndo(option: String) throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences(prefix: "Draftly-HTMLPasteOptions-")
        defer { preferences.close() }
        let defaults = preferences.defaults
        defaults.set(true, forKey: HTMLPreferences.pasteKey)
        let html: String
        let converted: String
        switch option {
        case "marks":
            defaults.set("__", forKey: "html.strongMark")
            defaults.set("*", forKey: "html.emphasisMark")
            html = "<strong>Café 🐼</strong> <em>neutral</em>"
            converted = "__Café 🐼__ *neutral*"
        case "ignoreEmphasis":
            defaults.set(true, forKey: "html.ignoreEmphasis")
            html = "<strong>Café 🐼</strong> <em>neutral</em>"
            converted = "Café 🐼 neutral"
        case "ignoreLinks":
            defaults.set(true, forKey: "html.ignoreLinks")
            defaults.set(false, forKey: "html.inlineLinks")
            defaults.set(true, forKey: "html.linksEachParagraph")
            html = "<a href='https://example.com'>Café 🐼</a>"
            converted = "Café 🐼"
        case "ignoreImages":
            defaults.set(true, forKey: "html.ignoreImages")
            html = "<p>Café 🐼<img src='neutral.png'></p>"
            converted = "Café 🐼"
        case "inlineLinks":
            defaults.set(true, forKey: "html.inlineLinks")
            defaults.set(true, forKey: "html.linksEachParagraph")
            html = "<a href='https://example.com'>Café 🐼</a>"
            converted = "[Café 🐼](https://example.com)"
        default:
            defaults.set(false, forKey: "html.inlineLinks")
            defaults.set(option == "paragraphReferences", forKey: "html.linksEachParagraph")
            html = "<p><a href='https://example.com/one'>Café 🐼</a></p><p><a href='https://example.com/two'>Second</a></p>"
            converted = option == "paragraphReferences"
                ? "[Café 🐼][1]\n\n[1]: https://example.com/one\n\n[Second][2]\n\n[2]: https://example.com/two"
                : "[Café 🐼][1]\n\n[Second][2]\n\n[1]: https://example.com/one\n[2]: https://example.com/two"
        }
        let reopened = try #require(UserDefaults(suiteName: preferences.name))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString(html, forType: .html)
        pasteboard.setString("Keep clipboard text", forType: .string)
        let changeCount = pasteboard.changeCount
        let view = DraftTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.isRichText = false; view.allowsUndo = true
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
        let expected = original.replacingOccurrences(of: "XX", with: converted)
        #expect(view.string == expected)
        #expect(view.selectedRange() == NSRange(location: selection.location + (converted as NSString).length, length: 0))
        #expect(pasteboard.changeCount == changeCount)
        #expect(pasteboard.string(forType: .html) == html && pasteboard.string(forType: .string) == "Keep clipboard text")
        undo.undo()
        #expect(view.string == original)
        undo.redo()
        #expect(view.string == expected)
    }
}
