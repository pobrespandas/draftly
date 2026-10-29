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

    @Test func mapsRenumberingAcrossInsertedAndReplacedRanges() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let source = "Antes 🐼\n\n1. Uno\n9. Dos\n\nDespués"
        let selected = (source as NSString).range(of: "Uno\n9.")
        let proposed = try syntax.orderedListEdit(in: source, replacing: selected, with: "Hola\n88.")
        let plan = try #require(proposed)
        let final = (source as NSString).replacingCharacters(in: plan.range, with: plan.text)
        #expect(final == "Antes 🐼\n\n1. Hola\n2. Dos\n\nDespués")
        #expect(plan.selection == NSRange(location: (final as NSString).range(of: "2.").upperBound, length: 0))
        let marker = (source as NSString).range(of: "9")
        let markerPlan = try syntax.orderedListEdit(in: source, replacing: marker, with: "76")
        let markerEdit = try #require(markerPlan)
        let markerFinal = (source as NSString).replacingCharacters(in: markerEdit.range, with: markerEdit.text)
        #expect(markerFinal == "Antes 🐼\n\n1. Uno\n2. Dos\n\nDespués")
        #expect(markerEdit.selection == NSRange(location: marker.location + 1, length: 0))
    }

    @Test func plannedReplacementMatchesDirectEditsAcrossInputRanges() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        for source in ["1. One\n9. Two\n\n3. Three\n7. Four", "Intro\n1. One\n    - Child\n9. Two\nEnd"] {
            let original = source as NSString
            for position in 0...original.length {
                for length in 0...min(2, original.length - position) {
                    for inserted in ["", "x", "7. ", "\n"] {
                        let range = NSRange(location: position, length: length)
                        let proposed = original.replacingCharacters(in: range, with: inserted)
                        let affected = NSRange(location: position, length: inserted.utf16.count)
                        let direct = NSMutableString(string: proposed)
                        for edit in try syntax.orderedListRenumbering(in: proposed, affectedRange: affected).reversed() {
                            direct.replaceCharacters(in: edit.range, with: edit.text)
                        }
                        let planned = try syntax.orderedListEdit(in: source, replacing: range, with: inserted)
                        let plan = try #require(planned)
                        #expect(original.replacingCharacters(in: plan.range, with: plan.text) == direct as String)
                    }
                }
            }
        }
    }
}
