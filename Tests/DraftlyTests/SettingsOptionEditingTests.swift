import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Settings option editing")
struct SettingsOptionEditingTests {
    @Test func markdownEditPreservesUnknownValuesWithoutWritingDefaults() throws {
        let original = #"{"smartQuotesEnabled":false,"future":{"name":"café 🐼","values":[null,3,true]}}"#
        let changed = try SettingsOptionEditing.markdownOption("footnotesEnabled", enabled: false, configuration: original)
        let values = try JSONDecoder().decode([String: JSONValue].self, from: Data(changed.utf8))
        let old = try JSONDecoder().decode([String: JSONValue].self, from: Data(original.utf8))
        #expect(values["future"] == old["future"])
        #expect(values["smartQuotesEnabled"] == .bool(false))
        #expect(values["footnotesEnabled"] == .bool(false))
        #expect(values["noLabels"] == nil)
        #expect(MarkdownPreferences.options(engine: "multi", json: changed)["smartQuotesEnabled"] == false)
    }

    @Test func invalidConfigurationCannotBeSilentlyReplaced() {
        for value in ["invalid", "[]", "null"] {
            #expect(throws: (any Error).self) {
                try SettingsOptionEditing.markdownOption("tables", enabled: true, configuration: value)
            }
        }
    }

    @Test func changedOptionPersistsAfterReopeningWithoutAffectingOtherPreferences() throws {
        let preferences = try TestPreferences(prefix: "Draftly-SettingsOption-")
        defer { preferences.close() }
        preferences.defaults.set("retained", forKey: "future.local")
        let changed = try SettingsOptionEditing.markdownOption("tables", enabled: false, configuration: "{}")
        preferences.defaults.set(changed, forKey: MarkdownPreferences.githubKey)
        let reopened = try #require(UserDefaults(suiteName: preferences.name))
        #expect(reopened.string(forKey: "future.local") == "retained")
        #expect(MarkdownPreferences.options(engine: "github", json: reopened.string(forKey: MarkdownPreferences.githubKey) ?? "")["tables"] == false)
        #expect(reopened.object(forKey: MarkdownPreferences.multiKey) == nil)
    }
    @Test func shortcutSaveClearAndResetRetainUnknownFieldsAndOtherCommands() throws {
        let source = #"{"future":{"values":[null,"café 🐼"]},"Quick Search":{"key":"k","modifiers":["command"],"keyCode":40,"future":true},"Import":{"key":"i","modifiers":["control"]}}"#
        let changed = try SettingsOptionEditing.command("Quick Search",
            binding: CommandBinding(key: "é", modifiers: ["command", "shift"], keyCode: 14), configuration: source)
        let values = try JSONDecoder().decode([String: JSONValue].self, from: Data(changed.utf8))
        let original = try JSONDecoder().decode([String: JSONValue].self, from: Data(source.utf8))
        #expect(values["future"] == original["future"] && values["Import"] == original["Import"])
        guard case .object(let fields) = values["Quick Search"] else { Issue.record("Missing shortcut"); return }
        #expect(fields["future"] == .bool(true))
        #expect(CommandShortcuts.binding("Quick Search", configuration: changed).keyCode == 14)
        let cleared = try SettingsOptionEditing.command("Quick Search", binding: CommandBinding(key: "", modifiers: []), configuration: changed)
        #expect(CommandShortcuts.binding("Quick Search", configuration: cleared).key.isEmpty)
        let reset = try SettingsOptionEditing.command("Quick Search", binding: nil, configuration: cleared)
        #expect(CommandShortcuts.binding("Quick Search", configuration: reset).key == "f")
        let remaining = try JSONDecoder().decode([String: JSONValue].self, from: Data(reset.utf8))
        #expect(remaining["future"] == original["future"] && remaining["Import"] == original["Import"])
        #expect(remaining["Quick Search"] == nil)
        #expect(throws: (any Error).self) {
            try SettingsOptionEditing.command("Quick Search", binding: nil, configuration: "invalid")
        }
    }

    @Test func syntaxFeatureEditsRetainOtherSyntaxesUnknownFieldsAndAbsentDefaults() throws {
        let fixture = try TestPreferences(prefix: "Draftly-SyntaxFeatureSettings-")
        defer { fixture.close() }
        let source = #"{"Café 🐼":{"tasks":true,"future":{"keep":[null,42,"🦊"]}},"Other":{"tasks":false},"future":[false,3]}"#
        fixture.defaults.set(source, forKey: SyntaxFeaturePreferences.key)
        fixture.defaults.set("Keep", forKey: "unrelated")
        let changed = try SettingsOptionEditing.syntaxFeature("tasks", syntax: "Café 🐼", enabled: false, configuration: source)
        #expect(fixture.defaults.string(forKey: SyntaxFeaturePreferences.key) == source)
        var expected = try JSONDecoder().decode([String: JSONValue].self, from: Data(source.utf8))
        guard case .object(var fields) = expected["Café 🐼"] else { Issue.record("Missing syntax options"); return }
        fields["tasks"] = .bool(false); expected["Café 🐼"] = .object(fields)
        #expect(try JSONDecoder().decode([String: JSONValue].self, from: Data(changed.utf8)) == expected)
        fixture.defaults.set(changed, forKey: SyntaxFeaturePreferences.key)
        let reopened = try #require(UserDefaults(suiteName: fixture.name))
        let saved = try #require(reopened.string(forKey: SyntaxFeaturePreferences.key))
        #expect(SyntaxFeaturePreferences.values(for: "Café 🐼", encoded: saved)["tasks"] == false)
        #expect(SyntaxFeaturePreferences.values(for: "Other", encoded: saved)["tasks"] == false)
        #expect(reopened.string(forKey: "unrelated") == "Keep")
        let initial = try SettingsOptionEditing.syntaxFeature("tasks", syntax: "New", enabled: true, configuration: "{}")
        #expect(SyntaxFeaturePreferences.values(for: "New", encoded: initial) == ["tasks": true])
    }

    @Test func invalidSyntaxFeatureEditsReportAnErrorInsteadOfReplacingSavedData() {
        for source in ["invalid", "[]", "null", #"{"Neutral":[]}"#, #"{"Neutral":null}"#, #"{"Neutral":"future format"}"#] {
            do {
                _ = try SettingsOptionEditing.syntaxFeature("tasks", syntax: "Neutral", enabled: false, configuration: source)
                Issue.record("An invalid syntax configuration was accepted.")
            } catch {
                #expect(error.localizedDescription == "The saved syntax feature options are invalid. They were kept unchanged.")
            }
        }
    }

}
