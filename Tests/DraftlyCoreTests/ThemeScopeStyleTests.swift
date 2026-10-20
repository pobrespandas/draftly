import Foundation
import Testing
@testable import DraftlyCore

@Suite("Imported theme scope styles")
struct ThemeScopeStyleTests {
    private func theme(settings: [String: ThemeJSONValue]) -> EditorThemeDefinition {
        EditorThemeDefinition(unknownFields: ["draftsSource": .object([
            "colors": .object([
                "editor": .object(["ink": .string("#aAbBcC")]),
                "interface": .object(["textSelection": .string("#123456"),
                                      "textCaret": .string("ABCDEF"),
                                      "textBackground": .string("#101010")])]),
            "scopes": .object(["custom.scope": .object(["settings": .object(settings)])]),
            "future": .array([.bool(true), .string("café 🐼")])])])
    }

    @Test(arguments: ["ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"])
    func allDocumentedWeightsResolve(_ weight: String) {
        #expect(theme(settings: ["fontWeight": .string(weight)]).scopeStyle(named: "custom.scope")?.fontWeight == weight)
    }

    @Test(arguments: ["extraSmall", "small", "normal", "large", "extraLarge"])
    func allDocumentedSizesResolve(_ size: String) {
        #expect(theme(settings: ["fontSize": .string(size)]).scopeStyle(named: "custom.scope")?.fontSize == size)
    }

    @Test func commaSeparatedTraitsAreIndependentAndNormalClearsTraits() {
        for (source, expected) in [("normal", []), ("", []), ("italic", ["italic"]),
                                   ("underline", ["underline"]), ("strikethrough", ["strikethrough"]),
                                   ("monospace", ["monospace"]),
                                   ("italic, underline, strikethrough, monospace", ["italic", "underline", "strikethrough", "monospace"]),
                                   ("italic,italic, future", ["italic"])] {
            #expect(theme(settings: ["fontStyle": .string(source)]).scopeStyle(named: "custom.scope")?.fontStyles == expected)
        }
        #expect(theme(settings: [:]).scopeStyle(named: "custom.scope") == ThemeScopeStyle())
    }

    @Test(arguments: Array(0..<16))
    func everyTraitCombinationResolves(_ mask: Int) {
        let traits = ["italic", "underline", "strikethrough", "monospace"]
        let expected = traits.enumerated().compactMap { index, trait in
            mask & (1 << index) == 0 ? nil : trait
        }
        let source = expected.joined(separator: ", ")
        #expect(theme(settings: ["fontStyle": .string(source)]).scopeStyle(named: "custom.scope")?.fontStyles == expected)
    }

    @Test func colorsUseEditorNamesOrSixDigitLiteralsAndInterfaceUsesItsOwnPalette() {
        let value = theme(settings: ["foreground": .string("ink"), "background": .string("#00fFaA")])
        #expect(value.scopeStyle(named: "custom.scope") == ThemeScopeStyle(foreground: "AABBCC", background: "00FFAA"))
        #expect(value.interfaceColor(named: "textSelection") == "123456")
        #expect(value.interfaceColor(named: "textCaret") == "ABCDEF")
        #expect(value.interfaceColor(named: "textBackground") == "101010")
        #expect(value.interfaceColor(named: "ink") == nil)
        #expect(theme(settings: ["foreground": .string("FEDCBA")]).scopeStyle(named: "custom.scope")?.foreground == "FEDCBA")
    }

    @Test func missingAndMalformedScopesDoNotInheritOrMutateTheOriginal() throws {
        var value = theme(settings: ["foreground": .string("unknown"), "background": .string("#123"),
                                     "fontWeight": .string("future"), "fontSize": .bool(true),
                                     "fontStyle": .string("future"), "futureStyle": .array([.null])])
        let original = value
        #expect(value.scopeStyle(named: "custom.scope") == ThemeScopeStyle())
        #expect(value.scopeStyle(named: "custom.scope.child") == nil)
        #expect(value.scopeStyle(named: "custom") == nil)
        #expect(value == original)
        #expect(try JSONDecoder().decode(EditorThemeDefinition.self, from: JSONEncoder().encode(value)) == original)
        value.unknownFields["draftsSource"] = .object(["scopes": .object(["custom.scope": .object(["settings": .bool(true)])])])
        #expect(value.scopeStyle(named: "custom.scope") == nil)
        #expect(value.interfaceColor(named: "textCaret") == nil)
        value.unknownFields["draftsSource"] = .array([])
        #expect(value.scopeStyle(named: "custom.scope") == nil)
        #expect(EditorThemeDefinition().interfaceColor(named: "textSelection") == nil)
    }
}
