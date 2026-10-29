import Foundation
import Testing
@testable import DraftlyCore

@Suite("Syntax ordered list renumbering")
struct OrderedListRenumberingTests {
    private func normalized(_ source: String, using syntax: SyntaxDefinition) -> String {
        let result = NSMutableString(string: source)
        for edit in syntax.orderedListRenumbering(in: source).reversed() {
            result.replaceCharacters(in: edit.range, with: edit.text)
        }
        return result as String
    }

    @Test func continuesFromFirstNumberAndStopsAtTextOrEmptyLine() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let input = "7. siete\n77. ocho\n9. nueve\ntexto\n8. otro\n\n4. aislado"
        #expect(normalized(input, using: syntax) == "7. siete\n8. ocho\n9. nueve\ntexto\n8. otro\n\n4. aislado")
    }

    @Test func retainsNestedSequencesAndUTF16Offsets() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let input = "1. 🐼\n2. \n    1. Subuno\n    2. Subdos\n2. Dos\n3. Tres\n\n7. Otro"
        let expected = "1. 🐼\n2. \n    1. Subuno\n    2. Subdos\n3. Dos\n4. Tres\n\n7. Otro"
        #expect(normalized(input, using: syntax) == expected)
        let child = "1. Uno\n    1. Subuno\n    2. \n    2. Subdos\n2. Dos\n3. Tres"
        #expect(normalized(child, using: syntax) == "1. Uno\n    1. Subuno\n    2. \n    3. Subdos\n2. Dos\n3. Tres")
    }

    @Test func ignoresSyntaxWithoutOrderedListGrammar() throws {
        let syntax = try ScriptSyntax.definition("Plain Text")
        #expect(syntax.orderedListRenumbering(in: "1. Uno\n9. Dos").isEmpty)
    }
    @Test func nestedUnorderedItemsDoNotEndParentSequence() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let source = "1. Uno\n2. \n    - Hijo\n2. Dos\n3. Tres"
        #expect(normalized(source, using: syntax) == "1. Uno\n2. \n    - Hijo\n3. Dos\n4. Tres")
        let peer = "1. Uno\n- Viñeta\n7. Otra\n9. Última"
        #expect(normalized(peer, using: syntax) == "1. Uno\n- Viñeta\n7. Otra\n8. Última")
        let child = "1. Uno\n    1. Uno\n        - Viñeta\n    9. Dos\n2. Dos"
        #expect(normalized(child, using: syntax) == "1. Uno\n    1. Uno\n        - Viñeta\n    2. Dos\n2. Dos")
    }
    @Test func customGrammarPaddingAndDisabledRuleAreRespected() throws {
        func definition(enabled: Bool) throws -> SyntaxDefinition {
            let rule: [String: Any] = ["match": #"^(\h*)((\d+)\) )(.*)$"#,
                "captures": ["indent": "1", "prefix": "2", "sequence": "3", "line": "4"],
                "sequencePadding": "1", "enabled": enabled]
            return try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
                "name": "Custom QA", "patterns": [], "navigationPatterns": [],
                "linkDefinitions": [], "taskMarkDefinitions": [], "indentationPatterns": [],
                "listCompletionDefinitions": [rule]]))
        }
        let source = "01) café\n09) 🐼"
        #expect(normalized(source, using: try definition(enabled: true)) == "01) café\n02) 🐼")
        #expect(normalized(source, using: try definition(enabled: false)) == source)
    }

    @Test func numericOverflowIsNotRenumbered() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let source = "\(Int.max). maximum\n4. next"
        #expect(normalized(source, using: syntax) == source)
    }

    @Test func limitsRenumberingToEditedLists() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let source = "1. Unox\n9. Dos\n\n10. Otra\n90. Final"
        let edited = (source as NSString).range(of: "Unox")
        let result = NSMutableString(string: source)
        for edit in syntax.orderedListRenumbering(in: source, affectedRange: edited).reversed() {
            result.replaceCharacters(in: edit.range, with: edit.text)
        }
        #expect(result as String == "1. Unox\n2. Dos\n\n10. Otra\n90. Final")
        let second = (source as NSString).range(of: "Otra")
        #expect(syntax.orderedListRenumbering(in: source, affectedRange: second).map(\.text) == ["11"])
        let caret = NSRange(location: NSMaxRange(second), length: 0)
        #expect(syntax.orderedListRenumbering(in: source, affectedRange: caret).map(\.text) == ["11"])
        let all = NSRange(location: 0, length: (source as NSString).length)
        #expect(syntax.orderedListRenumbering(in: source, affectedRange: all).map(\.text) == ["2", "11"])
        #expect(syntax.orderedListRenumbering(in: source, affectedRange: NSRange(location: NSNotFound, length: 0)).isEmpty)
        let mixed = "- Puntox\n1. Uno\n9. Dos"
        let bullet = (mixed as NSString).range(of: "Puntox")
        #expect(syntax.orderedListRenumbering(in: mixed, affectedRange: bullet).map(\.text) == ["2"])
    }

    @Test func preservesCRLFAndUTF16Offsets() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let source = "1. 🐼\r\n9. Dos\r\n\r\n10. Otra\r\n99. Final"
        let range = (source as NSString).range(of: "🐼")
        let result = NSMutableString(string: source)
        for edit in syntax.orderedListRenumbering(in: source, affectedRange: range).reversed() {
            result.replaceCharacters(in: edit.range, with: edit.text)
        }
        #expect(result as String == "1. 🐼\r\n2. Dos\r\n\r\n10. Otra\r\n99. Final")
    }

}
