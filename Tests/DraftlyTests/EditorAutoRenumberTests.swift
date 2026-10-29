import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Editor ordered list edits") @MainActor
struct EditorAutoRenumberTests {
    @Test func typingAndRenumberingAreOneUndoableEdit() throws {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.allowsUndo = true; text.autoRenumber = true
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        let window = OffscreenTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = text
        defer { window.contentView = nil }
        let undo = try #require(text.undoManager)
        undo.groupsByEvent = false
        let original = "1. 🐼\n9. Dos\n\n7. Otro\n90. Final"
        text.string = original
        let cursor = (original as NSString).range(of: "🐼").upperBound
        text.setSelectedRange(NSRange(location: cursor, length: 0))
        undo.beginUndoGrouping()
        text.insertText("x", replacementRange: text.selectedRange())
        undo.endUndoGrouping()
        let expected = "1. 🐼x\n2. Dos\n\n7. Otro\n90. Final"
        #expect(text.string == expected)
        #expect(text.selectedRange() == NSRange(location: cursor + 1, length: 0))
        undo.undo()
        #expect(text.string == original)
        undo.redo()
        #expect(text.string == expected && !window.isVisible)
    }

    @Test func disablingRenumberKeepsOtherNumbers() throws {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.autoRenumber = false
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        text.string = "1. Uno\n9. Dos"
        let cursor = (text.string as NSString).range(of: "Uno").upperBound
        text.setSelectedRange(NSRange(location: cursor, length: 0))
        text.insertText("x", replacementRange: text.selectedRange())
        #expect(text.string == "1. Unox\n9. Dos" && text.window == nil)
    }

    @Test func newlineCreatesAndRenumbersAnOrderedItem() throws {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.autoRenumber = true
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        text.string = "1. Uno\n2. Dos\n3. Tres"
        let cursor = (text.string as NSString).range(of: "Uno").upperBound
        text.setSelectedRange(NSRange(location: cursor, length: 0))
        text.insertNewline(nil)
        #expect(text.string == "1. Uno\n2. \n3. Dos\n4. Tres")
        #expect(text.selectedRange() == NSRange(location: cursor + 4, length: 0))
        text.insertNewline(nil)
        #expect(text.string == "1. Uno\n\n3. Dos\n4. Tres")
        #expect(text.selectedRange() == NSRange(location: cursor + 1, length: 0))
    }

    @Test func leavingEmptyItemAtEndKeepsCursorOnBlankLine() throws {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.autoRenumber = true
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        text.string = "1. Uno\n2. "
        text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        text.insertNewline(nil)
        #expect(text.string == "1. Uno\n\n")
        #expect(text.selectedRange() == NSRange(location: 7, length: 0))
        text.insertText("x", replacementRange: text.selectedRange())
        #expect(text.string == "1. Uno\nx\n")
    }

    @Test(arguments: ["\n", "\r\n"], [false, true])
    func leavingEmptyItemPreservesLineEndingsAndUndo(separator: String, renumber: Bool) throws {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.allowsUndo = true; text.autoRenumber = renumber
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        let window = OffscreenTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = text
        defer { window.contentView = nil }
        let undo = try #require(text.undoManager)
        undo.groupsByEvent = false
        let original = "1. 🐼" + separator + "2. " + separator + "3. Dos"
        text.string = original
        let marker = (original as NSString).range(of: "2. ")
        text.setSelectedRange(NSRange(location: marker.upperBound, length: 0))
        undo.beginUndoGrouping()
        text.insertNewline(nil)
        undo.endUndoGrouping()
        let expected = "1. 🐼" + separator + separator + "3. Dos"
        #expect(text.string == expected)
        #expect(text.selectedRange() == NSRange(location: marker.location, length: 0))
        undo.undo()
        #expect(text.string == original)
        undo.redo()
        #expect(text.string == expected && !window.isVisible)
    }

    @Test func plainPasteRenumbersAndPreservesClipboardAndUndo() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("Draftly.ListPaste." + UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents()
        let clipboard = "1. 🐼\n9. Dos\n3. Tres"
        #expect(board.setString(clipboard, forType: .string))
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.allowsUndo = true; text.autoRenumber = true
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        let window = OffscreenTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = text
        defer { window.contentView = nil }
        let undo = try #require(text.undoManager)
        undo.groupsByEvent = false
        text.string = "Reemplazar 🐼"
        text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
        undo.beginUndoGrouping()
        #expect(text.pasteRenumberedText(from: board))
        undo.endUndoGrouping()
        let expected = "1. 🐼\n2. Dos\n3. Tres"
        #expect(text.string == expected)
        #expect(text.selectedRange() == NSRange(location: expected.utf16.count, length: 0))
        #expect(board.string(forType: .string) == clipboard)
        undo.undo()
        #expect(text.string == "Reemplazar 🐼")
        undo.redo()
        #expect(text.string == expected && board.string(forType: .string) == clipboard && !window.isVisible)
        text.autoRenumber = false
        #expect(!text.pasteRenumberedText(from: board))
    }

    @Test func filePasteboardRemainsOnNativePastePath() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        #expect(item.setString("file:///tmp/draftly-neutral.txt", forType: .fileURL))
        #expect(item.setString("1. Uno\n9. Dos", forType: .string))
        #expect(board.writeObjects([item]))
        let text = DraftTextView(frame: .zero)
        text.autoRenumber = true
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        text.string = "Keep 🐼"
        text.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(!text.pasteRenumberedText(from: board))
        #expect(text.string == "Keep 🐼")
        #expect(text.selectedRange() == NSRange(location: 5, length: 0))
        #expect(board.string(forType: .string) == "1. Uno\n9. Dos")
    }

    @Test(arguments: [false, true], ["\n", "\r\n"])
    func deletingListBoundaryRenumbersAsOneUndoableEdit(forward: Bool, separator: String) throws {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.allowsUndo = true; text.autoRenumber = true
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        let window = OffscreenTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = text
        defer { window.contentView = nil }
        let undo = try #require(text.undoManager)
        undo.groupsByEvent = false
        let original = "1. 🐼" + separator + separator + "3. Tres" + separator + "4. Cuatro"
        text.string = original
        let next = (original as NSString).range(of: "3. Tres").location
        let boundary = next - separator.utf16.count
        text.setSelectedRange(NSRange(location: forward ? boundary : next, length: 0))
        undo.beginUndoGrouping()
        if forward { text.deleteForward(nil) } else { text.deleteBackward(nil) }
        undo.endUndoGrouping()
        let expected = "1. 🐼" + separator + "2. Tres" + separator + "3. Cuatro"
        #expect(text.string == expected)
        #expect(text.selectedRange() == NSRange(location: boundary, length: 0))
        undo.undo()
        #expect(text.string == original)
        undo.redo()
        #expect(text.string == expected && !window.isVisible)
    }

    @Test func deletingUnicodeCharacterKeepsItsSequenceIntact() throws {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.autoRenumber = true
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        text.string = "1. 🐼a\n9. Dos"
        let panda = (text.string as NSString).range(of: "🐼")
        text.setSelectedRange(NSRange(location: panda.upperBound, length: 0))
        text.deleteBackward(nil)
        #expect(text.string == "1. a\n2. Dos")
        #expect(text.selectedRange() == NSRange(location: panda.location, length: 0))
        #expect(text.window == nil)
    }

    @Test func excessivePaddingReportsAfterKeepingUserEdit() throws {
        let rule: [String: Any] = ["match": #"^(\h*)((\d+)\) )(.*)$"#,
            "captures": ["indent": "1", "prefix": "2", "sequence": "3", "line": "4"],
            "sequencePadding": String(Int.max - 1)]
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Large padding QA", "patterns": [], "navigationPatterns": [],
            "linkDefinitions": [], "taskMarkDefinitions": [], "indentationPatterns": [],
            "listCompletionDefinitions": [rule]]))
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.allowsUndo = true; text.autoRenumber = true; text.syntaxDefinition = syntax
        let window = OffscreenTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = text
        defer { window.contentView = nil }
        let undo = try #require(text.undoManager)
        undo.groupsByEvent = false
        text.string = "1) Uno\n9) Dos"
        let cursor = (text.string as NSString).range(of: "Uno").upperBound
        text.setSelectedRange(NSRange(location: cursor, length: 0))
        var reports: [(String, String)] = []
        text.onListEditingError = { [weak text] in reports.append(($0, text?.string ?? "")) }
        undo.beginUndoGrouping()
        text.insertText("x", replacementRange: text.selectedRange())
        undo.endUndoGrouping()
        #expect(text.string == "1) Unox\n9) Dos")
        #expect(reports.count == 1 && reports[0].1 == text.string)
        #expect(reports.first?.0.contains("list") == true && !window.isVisible)
        undo.undo()
        #expect(text.string == "1) Uno\n9) Dos")
        undo.redo()
        #expect(text.string == "1) Unox\n9) Dos" && reports.count == 1)
        text.string = "1) Uno\n\n9) Dos"
        let next = (text.string as NSString).range(of: "9) Dos").location
        text.setSelectedRange(NSRange(location: next, length: 0))
        undo.beginUndoGrouping()
        text.deleteBackward(nil)
        undo.endUndoGrouping()
        #expect(text.string == "1) Uno\n9) Dos")
        #expect(reports.count == 2 && reports[1].1 == text.string)
        text.string = "1) Uno"
        text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        undo.beginUndoGrouping()
        text.insertNewline(nil)
        undo.endUndoGrouping()
        #expect(text.string == "1) Uno\n")
        #expect(reports.count == 3 && reports[2].1 == text.string)
    }

    @Test func editorConnectsListFailureToItsErrorHandler() async throws {
        let rule: [String: Any] = ["match": #"^(\h*)((\d+)\) )(.*)$"#,
            "captures": ["indent": "1", "prefix": "2", "sequence": "3", "line": "4"],
            "sequencePadding": String(Int.max - 1)]
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
            "name": "Large padding QA", "patterns": [], "navigationPatterns": [],
            "linkDefinitions": [], "taskMarkDefinitions": [], "indentationPatterns": [],
            "listCompletionDefinitions": [rule]]))
        let session = EditorSession()
        session.load(Note(content: "1) Uno\n9) Dos"), focusEditor: false)
        var message: String?
        let editor = NativeEditor(session: session, fontName: "System", fontSize: 17, lineSpacing: 2,
            markdown: false, syntaxDefinition: syntax, onListEditingError: { message = $0 }, onChange: {})
        let host = NSHostingView(rootView: editor)
        let window = OffscreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        await TestMainQueue.drain()
        func findText(_ view: NSView) -> DraftTextView? {
            if let text = view as? DraftTextView { return text }
            return view.subviews.lazy.compactMap { findText($0) }.first
        }
        let text = try #require(findText(host))
        let cursor = (text.string as NSString).range(of: "Uno").upperBound
        text.setSelectedRange(NSRange(location: cursor, length: 0))
        text.insertText("x", replacementRange: text.selectedRange())
        #expect(session.content == "1) Unox\n9) Dos")
        #expect(message?.contains("Your edit was kept") == true && !window.isVisible)
    }

    @Test func markedTextRemainsIntactDuringComposition() throws {
        let text = DraftTextView(frame: .zero)
        text.isRichText = false; text.autoRenumber = true
        text.syntaxDefinition = try ScriptSyntax.definition("Markdown")
        text.string = "1. Uno\n9. Dos"
        let cursor = (text.string as NSString).range(of: "Uno").upperBound
        text.setSelectedRange(NSRange(location: cursor, length: 0))
        text.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: text.selectedRange())
        #expect(text.hasMarkedText())
        #expect(text.string == "1. Unoに\n9. Dos")
        text.insertText("日本", replacementRange: text.markedRange())
        #expect(!text.hasMarkedText())
        #expect(text.string.hasPrefix("1. Uno日本\n") && text.string.hasSuffix(". Dos"))
        #expect(text.window == nil)
    }
}
