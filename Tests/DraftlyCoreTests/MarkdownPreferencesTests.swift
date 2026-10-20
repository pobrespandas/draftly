import Foundation
import Testing
@testable import DraftlyCore

@Suite("Markdown preferences")
struct MarkdownPreferencesTests {
    @Test func enginesAndOptionsChangeTheRenderedOutputWithoutChangingTheInput() throws {
        let preferences = try TestPreferences(prefix: "Draftly-MarkdownPreferences")
        defer { preferences.close() }
        let defaults = preferences.defaults
        let text = "\"Café 🐼\""
        let smart = try MarkdownPreferences.render(text, defaults: defaults)
        #expect(smart.contains("&#8220;Café 🐼&#8221;"), Comment(rawValue: smart))
        defaults.set(#"{"smartQuotesEnabled":false}"#, forKey: MarkdownPreferences.multiKey)
        let plain = try MarkdownPreferences.render(text, defaults: defaults)
        #expect(plain.contains("&quot;Café 🐼&quot;"), Comment(rawValue: plain))
        defaults.set("github", forKey: MarkdownPreferences.engineKey)
        defaults.set(#"{"strikethrough":false}"#, forKey: MarkdownPreferences.githubKey)
        #expect(try !MarkdownPreferences.render("~~text~~", defaults: defaults).contains("<del>"))
        defaults.set(#"{"strikethrough":true}"#, forKey: MarkdownPreferences.githubKey)
        #expect(try MarkdownPreferences.render("~~text~~", defaults: defaults).contains("<del>text</del>"))
        #expect(try MarkdownPreferences.render(text, syntax: "MultiMarkdown", defaults: defaults) == plain)
        #expect(text == "\"Café 🐼\"")
    }

    @Test func multiMarkdownHeaderLabelsFollowTheSavedOption() throws {
        let preferences = try TestPreferences()
        defer { preferences.close() }
        let defaults = preferences.defaults
        defaults.set(#"{"noLabels":false}"#, forKey: MarkdownPreferences.multiKey)
        #expect(try MarkdownPreferences.render("# Heading", defaults: defaults).contains("id=\"heading\""))
        defaults.set(#"{"noLabels":true}"#, forKey: MarkdownPreferences.multiKey)
        #expect(try !MarkdownPreferences.render("# Heading", defaults: defaults).contains("id="))
    }

    @Test func githubHardBreaksAndSourcePositionsFollowSavedOptions() throws {
        let preferences = try TestPreferences()
        defer { preferences.close() }
        let defaults = preferences.defaults
        defaults.set("github", forKey: MarkdownPreferences.engineKey)
        defaults.set(#"{"hardBreaks":true,"sourcePOS":true}"#, forKey: MarkdownPreferences.githubKey)
        let enabled = try MarkdownPreferences.render("One\nTwo", defaults: defaults)
        #expect(enabled.contains("<br />"))
        #expect(enabled.contains("data-sourcepos="))
        defaults.set(#"{"hardBreaks":false,"sourcePOS":false}"#, forKey: MarkdownPreferences.githubKey)
        let disabled = try MarkdownPreferences.render("One\nTwo", defaults: defaults)
        #expect(!disabled.contains("<br") && !disabled.contains("data-sourcepos="))
    }

    @Test func githubSafeModeOverridesUnsafeAndRawHTMLRemainsExplicit() throws {
        let preferences = try TestPreferences()
        defer { preferences.close() }
        let defaults = preferences.defaults
        defaults.set("github", forKey: MarkdownPreferences.engineKey)
        let input = "<div>Neutral HTML</div>"
        defaults.set(#"{"safe":true,"unsafe":true}"#, forKey: MarkdownPreferences.githubKey)
        #expect(try !MarkdownPreferences.render(input, defaults: defaults).contains(input))
        defaults.set(#"{"safe":false,"unsafe":true}"#, forKey: MarkdownPreferences.githubKey)
        #expect(try MarkdownPreferences.render(input, defaults: defaults).contains(input))
    }

    @Test func configuredTemplatesUsePreferencesForDirectAndIncludedMarkdown() throws {
        let preferences = try TestPreferences()
        defer { preferences.close() }
        let defaults = preferences.defaults
        defaults.set("github", forKey: MarkdownPreferences.engineKey)
        defaults.set(#"{"strikethrough":true,"sourcePOS":false}"#, forKey: MarkdownPreferences.githubKey)
        let note = Note(content: "~~Café 🐼~~")
        let direct = try Templates.renderConfigured("%%[[draft]]%%", note: note, defaults: defaults)
        #expect(direct.contains("<del>Café 🐼</del>"))
        let included = try Templates.renderConfigured("[[template|neutral.txt]]", note: note, defaults: defaults, loadTemplate: { _ in "%%[[draft]]%%" })
        #expect(included == direct)
        let escaped = try Templates.renderConfigured(#"\%%[[draft]]%%"#, note: note, defaults: defaults)
        #expect(escaped == "%%~~Café 🐼~~%%")
        defaults.set(#"{"strikethrough":false,"sourcePOS":false}"#, forKey: MarkdownPreferences.githubKey)
        #expect(try !Templates.renderConfigured("%%[[draft]]%%", note: note, defaults: defaults).contains("<del>"))
        #expect(note.content == "~~Café 🐼~~")
    }

    @Test func malformedOptionsUseDefaultsAndUnknownBooleanOptionsSurvive() {
        #expect(MarkdownPreferences.options(engine: "multi", json: "invalid")["noLabels"] == true)
        #expect(MarkdownPreferences.options(engine: "github", json: #"{"futureOption":true,"tables":false}"#)["futureOption"] == true)
        #expect(MarkdownPreferences.options(engine: "github", json: #"{"tables":false}"#)["tables"] == false)
    }
}
