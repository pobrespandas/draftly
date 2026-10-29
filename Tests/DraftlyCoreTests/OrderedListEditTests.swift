import Foundation
import Testing
@_spi(EditorImplementation) @testable import DraftlyCore

@Suite("Atomic ordered list edits")
struct OrderedListEditTests {
    @Test func combinesTypingAndRenumberingWithUnicodeCursor() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let source = "1. 🐼\n9. Dos\n\n7. Otra\n90. Final"
        let at = NSRange(location: (source as NSString).range(of: "🐼").upperBound, length: 0)
        let planned = try syntax.orderedListEdit(in: source, replacing: at, with: "x")
        let plan = try #require(planned)
        let final = (source as NSString).replacingCharacters(in: plan.range, with: plan.text)
        #expect(final == "1. 🐼x\n2. Dos\n\n7. Otra\n90. Final")
        #expect(plan.selection == NSRange(location: at.location + 1, length: 0))
    }

    @Test func adjustsCursorAfterEarlierNumbersChangeWidth() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let source = "9. Uno\n2. Dos\n3. 🐼"
        let at = NSRange(location: (source as NSString).length, length: 0)
        let planned = try syntax.orderedListEdit(in: source, replacing: at, with: "x")
        let plan = try #require(planned)
        let final = (source as NSString).replacingCharacters(in: plan.range, with: plan.text)
        #expect(final == "9. Uno\n10. Dos\n11. 🐼x")
        #expect(plan.selection.location == final.utf16.count)
    }

    @Test func leavesOrdinaryEditsAndInvalidRangesAlone() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let source = "🐼 plain"
        let range = (source as NSString).range(of: "plain")
        let planned = try syntax.orderedListEdit(in: source, replacing: range, with: "café")
        let plan = try #require(planned)
        #expect(plan.range == range && plan.text == "café")
        #expect(plan.selection == NSRange(location: range.location + 4, length: 0))
        let invalid = try syntax.orderedListEdit(in: source, replacing: NSRange(location: NSNotFound, length: 0), with: "x")
        #expect(invalid == nil)
    }

    @Test func keepsDistinctUnicodeRepresentationsWhenNumberingChanges() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let source = "1. café\n9. Dos"
        let selected = (source as NSString).range(of: "é")
        let planned = try syntax.orderedListEdit(in: source, replacing: selected, with: "e\u{301}")
        let plan = try #require(planned)
        let final = (source as NSString).replacingCharacters(in: plan.range, with: plan.text)
        #expect(Array(final.utf8) == Array("1. cafe\u{301}\n2. Dos".utf8))
        #expect(plan.selection.location == selected.location + 2)
    }
}
