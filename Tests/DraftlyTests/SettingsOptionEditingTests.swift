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
}
