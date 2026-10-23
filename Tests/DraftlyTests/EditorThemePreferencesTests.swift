import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Device theme reference preferences") @MainActor
struct EditorThemePreferencesTests {
    @Test func resolverUsesIdentityBeforeNameAndKeepsUnknownFields() throws {
        let theme = EditorTheme(name: "Renamed café 🐼", isDark: true)
        let other = EditorTheme(name: "Old name", isDark: true)
        let reference: [String: Any] = ["type": "custom", "uuid": theme.id.uuidString, "name": other.name,
                                        "future": ["items": [false, "café 🐼"] as [Any]]]
        let resolved = try ThemeReferenceResolver.resolve(reference, themes: [other, theme])
        #expect(resolved["uuid"] as? String == theme.id.uuidString && resolved["name"] as? String == theme.name)
        #expect((resolved["future"] as? [String: [Any]])?["items"]?.last as? String == "café 🐼")
        let legacy = try ThemeReferenceResolver.resolve(["type": "custom", "name": theme.name], themes: [theme])
        #expect(legacy["uuid"] as? String == theme.id.uuidString)
        for reference in [["type": "custom", "uuid": UUID().uuidString, "name": theme.name],
                          ["type": "custom", "uuid": "invalid", "name": theme.name],
                          ["type": "builtIn", "name": "Missing"], ["type": "unknown", "name": "Dark"]] {
            do {
                _ = try ThemeReferenceResolver.resolve(reference, themes: [theme], errorMessage: "Specific missing reference")
                Issue.record("An invalid theme reference resolved.")
            } catch { #expect(error.localizedDescription == "Specific missing reference") }
        }
        do {
            _ = try ThemeReferenceResolver.resolve(["type": "file", "name": "Dark"], themes: [])
            Issue.record("A file theme resolved without support.")
        } catch { #expect(error.localizedDescription == "The theme was not found.") }
    }

    @Test func localPairSeedsTheLegacySlotAndDoesNotChangeModeOrOtherDevices() throws {
        let suite = "Draftly.ThemePair.\(UUID())", otherSuite = "Draftly.ThemePair.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let otherDefaults = try #require(UserDefaults(suiteName: otherSuite))
        defer { defaults.removePersistentDomain(forName: suite); otherDefaults.removePersistentDomain(forName: otherSuite) }
        let legacy = EditorTheme(name: "Legacy day", isDark: false)
        let night = EditorTheme(name: "Night", isDark: true)
        defaults.set(legacy.name, forKey: "editor.theme")
        defaults.set("automatic", forKey: "editor.themeMode")
        let preferences = EditorThemePreferences(defaults: defaults)
        #expect(!preferences.hasConfiguredPair)
        #expect(preferences.reference(dark: false, themes: [legacy])["uuid"] as? String == legacy.id.uuidString)
        #expect(preferences.reference(dark: true, themes: [legacy])["name"] as? String == "Dark")
        #expect(defaults.data(forKey: EditorThemePreferences.key) == nil)
        try preferences.set(reference: ["type": "custom", "uuid": night.id.uuidString, "name": night.name], dark: true, themes: [legacy, night])
        #expect(preferences.hasConfiguredPair)
        #expect(preferences.reference(dark: false, themes: [legacy, night])["uuid"] as? String == legacy.id.uuidString)
        #expect(EditorThemePreferences(defaults: defaults).reference(dark: true, themes: [legacy, night])["uuid"] as? String == night.id.uuidString)
        #expect(EditorThemePreferences(defaults: otherDefaults).reference(dark: true, themes: [night])["name"] as? String == "Dark")
        #expect(otherDefaults.data(forKey: EditorThemePreferences.key) == nil)
        #expect(defaults.string(forKey: "editor.theme") == legacy.name && defaults.string(forKey: "editor.themeMode") == "automatic")
    }

    @Test func renamedDeletedAndRestoredThemesKeepTheirStoredIdentity() throws {
        let suite = "Draftly.ThemePair.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EditorThemePreferences(defaults: defaults)
        var theme = EditorTheme(name: "Before", isDark: true)
        try preferences.set(reference: ["type": "custom", "uuid": theme.id.uuidString, "name": theme.name,
                                        "future": ["kept": true]], dark: true, themes: [theme])
        let before = defaults.data(forKey: EditorThemePreferences.key)
        theme.name = "After café 🐼"
        #expect(preferences.reference(dark: true, themes: [theme])["name"] as? String == theme.name)
        #expect(defaults.data(forKey: EditorThemePreferences.key) == before)
        #expect(preferences.reference(dark: true, themes: [])["name"] as? String == "Dark")
        try preferences.set(reference: ["type": "builtIn", "name": "Light"], dark: false, themes: [])
        let data = try #require(defaults.data(forKey: EditorThemePreferences.key))
        let stored = try #require(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        #expect(stored["dark"]?["uuid"] as? String == theme.id.uuidString)
        #expect((stored["dark"]?["future"] as? [String: Bool])?["kept"] == true)
        #expect(preferences.reference(dark: true, themes: [theme])["name"] as? String == theme.name)
    }

    @Test func invalidReferencesAndUnserializableFieldsLeavePreferencesUntouched() throws {
        let suite = "Draftly.ThemePair.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = EditorThemePreferences(defaults: defaults)
        try preferences.set(reference: ["type": "builtIn", "name": "Dark"], dark: true, themes: [])
        let before = defaults.data(forKey: EditorThemePreferences.key)
        let references: [[String: Any]] = [["type": "custom", "uuid": UUID().uuidString, "name": "Missing"],
                                          ["type": "file", "name": "Dark"],
                                          ["type": "builtIn", "name": "Light", "future": Date()]]
        for reference in references {
            #expect(throws: (any Error).self) { try preferences.set(reference: reference, dark: false, themes: []) }
            #expect(defaults.data(forKey: EditorThemePreferences.key) == before)
        }
    }
    @Test func editingOneSlotRetainsStructuredSiblingsAndUnknownFieldsAfterReopening() throws {
        let fixture = try TestPreferences(prefix: "Draftly.ThemePair.Fields.")
        defer { fixture.close() }
        let defaults = fixture.defaults
        let night = EditorTheme(name: "Night café 🐼", isDark: true)
        let fields: [String: Any] = [
            "dark": ["type": "custom", "uuid": night.id.uuidString,
                     "future": ["keep": [false, "🦊", NSNull()] as [Any]]],
            "light": ["type": "builtIn", "name": "Light"],
            "futureArray": [false, "café 🐼", NSNull()] as [Any],
            "futureObject": ["nested": ["keep": true]], "futureNumber": 42
        ]
        let original = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        defaults.set(original, forKey: EditorThemePreferences.key)
        defaults.set(7, forKey: EditorThemePreferences.revisionKey)
        defaults.set("automatic", forKey: "editor.themeMode")
        let preferences = EditorThemePreferences(defaults: defaults)
        #expect(preferences.hasConfiguredPair)
        #expect(preferences.reference(dark: true, themes: [night])["uuid"] as? String == night.id.uuidString)
        #expect(defaults.data(forKey: EditorThemePreferences.key) == original)
        #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == 7)
        try preferences.set(reference: ["type": "builtIn", "name": "Dark"], dark: false, themes: [night])
        let saved = try #require(defaults.data(forKey: EditorThemePreferences.key))
        let patched = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        var expected = fields
        expected["light"] = ["type": "builtIn", "name": "Dark"]
        #expect(try JSONSerialization.data(withJSONObject: patched, options: [.sortedKeys]) ==
            JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys]))
        #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == 8)
        #expect(defaults.string(forKey: "editor.themeMode") == "automatic")
        let reopened = try #require(UserDefaults(suiteName: fixture.name))
        let restored = EditorThemePreferences(defaults: reopened)
        #expect(restored.reference(dark: true, themes: [night])["uuid"] as? String == night.id.uuidString)
        #expect(restored.reference(dark: false, themes: [night])["name"] as? String == "Dark")
        #expect(reopened.data(forKey: EditorThemePreferences.key) == saved)
    }

    @Test func invalidStoredDataRejectsWritesWithoutChangingDataOrRevision() throws {
        let fixture = try TestPreferences(prefix: "Draftly.ThemePair.Invalid.")
        defer { fixture.close() }
        let defaults = fixture.defaults
        let preferences = EditorThemePreferences(defaults: defaults)
        for value: Any in [Data("{invalid".utf8), Data("[]".utf8), Data("null".utf8), "wrong storage type"] {
            defaults.set(value, forKey: EditorThemePreferences.key)
            defaults.set(11, forKey: EditorThemePreferences.revisionKey)
            let before = try #require(defaults.object(forKey: EditorThemePreferences.key) as? NSObject)
            #expect(!preferences.hasConfiguredPair)
            #expect(preferences.reference(dark: true, themes: [])["name"] as? String == "Dark")
            #expect(throws: (any Error).self) {
                try preferences.set(reference: ["type": "builtIn", "name": "Light"], dark: true, themes: [])
            }
            #expect((defaults.object(forKey: EditorThemePreferences.key) as? NSObject)?.isEqual(before) == true)
            #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == 11)
        }
        defaults.removeObject(forKey: EditorThemePreferences.key)
        #expect(!preferences.hasConfiguredPair)
        #expect(defaults.object(forKey: EditorThemePreferences.key) == nil)
        try preferences.set(reference: ["type": "builtIn", "name": "Light"], dark: false, themes: [])
        #expect(preferences.hasConfiguredPair)
        #expect(defaults.integer(forKey: EditorThemePreferences.revisionKey) == 12)
    }

}
