import AppKit
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
    }
}
