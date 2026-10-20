import Foundation
import Testing
@testable import DraftlyCore

@Suite("Drafts theme import")
struct DraftsThemeImportTests {
    private func source() -> [String: Any] {
        ["name": "Neutral café 🐼", "author": "Autora Ñ", "description": "Neutral test theme",
         "isDark": true,
         "colors": ["editor": ["ink": "#dDeEfF", "heading": "#998877"],
                    "interface": ["textForeground": "#112233", "textBackground": "#101010",
                                  "textSelection": "#456789", "textCaret": "#ABCDEF"]],
         "scopes": ["text.normal": ["settings": ["foreground": "ink"]],
                    "text.header": ["settings": ["foreground": "heading", "fontWeight": "bold"]]],
         "future": ["nested": [NSNull(), true, 12.25, "Unicode 🐼"]]]
    }
    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    @Test func editorColorChangesUpdateKnownSourceFieldsAndKeepOtherScopes() throws {
        let initial = try DraftsThemeImport.decode(data: data(source()))
        #expect(try DraftsThemeImport.applyingEditorChanges(initial) == initial)
        var edited = initial
        edited.name = "Edited"; edited.foreground = "102030"; edited.background = "405060"; edited.heading = "708090"
        let saved = try DraftsThemeImport.applyingEditorChanges(edited)
        #expect(saved.scopeStyle(named: "text.normal")?.foreground == "102030")
        #expect(saved.scopeStyle(named: "text.header")?.foreground == "708090")
        #expect(saved.interfaceColor(named: "textBackground") == "405060")
        guard case .object(let source) = saved.unknownFields["draftsSource"] else { Issue.record("Missing source"); return }
        #expect(source["future"] == (try JSONDecoder().decode([String: ThemeJSONValue].self, from: data(self.source())))["future"])
        #expect(source["name"] == .string("Edited"))
    }

    @Test func namedColorsAndExplicitIdentityMapWithoutLosingTheSource() throws {
        let input = try data(source())
        let identity = UUID()
        let theme = try DraftsThemeImport.decode(data: input, id: identity)
        #expect(theme.id == identity)
        #expect(theme.name == "Neutral café 🐼" && theme.isDark)
        #expect(theme.foreground == "DDEEFF" && theme.heading == "998877" && theme.background == "101010")
        #expect(theme.unknownFields["draftsSource"] == (try JSONDecoder().decode(ThemeJSONValue.self, from: input)))
        #expect(try JSONDecoder().decode(EditorThemeDefinition.self, from: JSONEncoder().encode(theme)) == theme)
        #expect(try DraftsThemeImport.decode(data: input).id != DraftsThemeImport.decode(data: input).id)
    }

    @Test func literalColorsOverrideTheInterfaceAndMissingScopesUseDocumentedFallbacks() throws {
        var value = source()
        value["scopes"] = ["text.normal": ["settings": ["foreground": "#aAbBcC"]],
                           "text.header": ["settings": ["foreground": "ABC123"]]]
        let literals = try DraftsThemeImport.decode(data: data(value))
        #expect(literals.foreground == "AABBCC" && literals.heading == "ABC123")
        value["scopes"] = ["text.normal": ["settings": ["fontStyle": "italic"]]]
        let fallback = try DraftsThemeImport.decode(data: data(value))
        #expect(fallback.foreground == "112233" && fallback.heading == "112233")
        value["scopes"] = ["text.normal": ["settings": ["foreground": "ink"]]]
        let normal = try DraftsThemeImport.decode(data: data(value))
        #expect(normal.heading == "DDEEFF")
    }

    @Test(arguments: ["name", "description", "colors", "scopes"])
    func missingRootFieldsAreRejected(_ key: String) throws {
        var value = source(); value.removeValue(forKey: key)
        #expect(throws: (any Error).self) { try DraftsThemeImport.decode(data: data(value)) }
    }

    @Test func sampleHeadingScopeTakesPriorityOverAbbreviatedGuideScope() throws {
        var input = source()
        input["scopes"] = ["text.heading": ["settings": ["foreground": "#010203"]],
                           "text.header": ["settings": ["foreground": "heading"]]]
        #expect(try DraftsThemeImport.decode(data: data(input)).heading == "010203")
    }

    @Test func absentDarkModeUsesLightMode() throws {
        var input = source(); input.removeValue(forKey: "isDark"); input.removeValue(forKey: "author")
        #expect(try !DraftsThemeImport.decode(data: data(input)).isDark)
    }

    @Test(arguments: ["true", "false", "1"])
    func darkModeRequiresARealBoolean(_ value: String) throws {
        var input = source(); input["isDark"] = value
        #expect(throws: (any Error).self) { try DraftsThemeImport.decode(data: data(input)) }
    }

    @Test(arguments: ["missing", "#123", "#12345678", "rgb(1,2,3)", "#GGGGGG"])
    func invalidReferencesAndColorFormatsAreExplicitErrors(_ color: String) throws {
        var input = source()
        input["scopes"] = ["custom.unmapped": ["settings": ["background": color]]]
        do {
            _ = try DraftsThemeImport.decode(data: data(input))
            Issue.record("Invalid color was accepted")
        } catch {
            #expect(error.localizedDescription.contains("scopes.custom.unmapped.settings.background"))
        }
    }

    @Test func malformedContainersUnusedColorsAndNonUTF8InputAreRejected() throws {
        var input = source(); input["author"] = 123
        #expect(throws: (any Error).self) { try DraftsThemeImport.decode(data: data(input)) }
        input = source(); input["isDark"] = 1
        #expect(throws: (any Error).self) { try DraftsThemeImport.decode(data: data(input)) }
        input = source(); input["colors"] = ["editor": ["unused": "blue"], "interface": [:]]
        #expect(throws: (any Error).self) { try DraftsThemeImport.decode(data: data(input)) }
        input = source(); input["scopes"] = ["text.normal": ["settings": "invalid"]]
        #expect(throws: (any Error).self) { try DraftsThemeImport.decode(data: data(input)) }
        input = source(); input["colors"] = ["editor": [:], "interface": ["textBackground": "#FFFFFF"]]
        #expect(throws: (any Error).self) { try DraftsThemeImport.decode(data: data(input)) }
        for bytes in [Data("[]".utf8), Data("{".utf8), Data([0xFF, 0xFE])] {
            #expect(throws: (any Error).self) { try DraftsThemeImport.decode(data: bytes) }
        }
    }

    @Test @MainActor func sourceSurvivesLibraryBackupAndStableIdentityReplacement() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try DraftsThemeImport.decode(data: data(source()))
        try library.saveTheme(first)
        var revised = source(); revised["description"] = "Revised source"
        let replacement = try DraftsThemeImport.decode(data: data(revised), id: first.id)
        try library.saveTheme(replacement)
        #expect(library.themes == [replacement])
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.themes == [replacement])
        #expect(restored.themes.first?.unknownFields["draftsSource"] == replacement.unknownFields["draftsSource"])
    }
}
