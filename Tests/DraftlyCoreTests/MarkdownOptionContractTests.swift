import Foundation
import Testing
@testable import DraftlyCore

@Suite("Displayed Markdown option contracts")
struct MarkdownOptionContractTests {
    private func render(_ text: String, engine: String, values: [String: Bool]) throws -> String {
        let preferences = try TestPreferences(prefix: "MarkdownOptionContract")
        defer { preferences.close() }
        preferences.defaults.set(engine, forKey: MarkdownPreferences.engineKey)
        let data = try JSONEncoder().encode(values)
        preferences.defaults.set(String(decoding: data, as: UTF8.self),
            forKey: engine == "multi" ? MarkdownPreferences.multiKey : MarkdownPreferences.githubKey)
        return try MarkdownPreferences.render(text, defaults: preferences.defaults)
    }

    private func decodedNumericEntities(_ text: String) -> String {
        let regex = try! NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")
        let original = text as NSString
        let decoded = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
            let entity = original.substring(with: match.range(at: 1))
            let radix = entity.hasPrefix("x") ? 16 : 10
            let digits = entity.hasPrefix("x") ? String(entity.dropFirst()) : entity
            if let value = UInt32(digits, radix: radix), let scalar = UnicodeScalar(value) {
                decoded.replaceCharacters(in: match.range, with: String(scalar))
            }
        }
        return decoded as String
    }

    @Test func githubTablesProduceCellsOnlyWhenEnabled() throws {
        let text = "| Name | Value |\n| --- | --- |\n| Café 🐼 | Neutral |"
        let enabled = try render(text, engine: "github", values: ["tables": true])
        let disabled = try render(text, engine: "github", values: ["tables": false])
        #expect(enabled.contains("<table") && enabled.contains("Café 🐼</td>"), Comment(rawValue: enabled))
        #expect(!disabled.contains("<table") && disabled.contains("| Café 🐼 | Neutral |"))
    }

    @Test func githubAutoLinksConvertBareURLsOnlyWhenEnabled() throws {
        let text = "Visit https://example.com/neutral for café 🐼."
        let enabled = try render(text, engine: "github", values: ["autoLinks": true])
        let disabled = try render(text, engine: "github", values: ["autoLinks": false])
        #expect(enabled.contains("<a href=\"https://example.com/neutral\">https://example.com/neutral</a>"))
        #expect(!disabled.contains("<a ") && disabled.contains(text))
    }

    @Test func githubTaskListsRenderBothCheckboxStatesOnlyWhenEnabled() throws {
        let text = "- [ ] Pending café\n- [x] Done 🐼"
        let enabled = try render(text, engine: "github", values: ["taskLists": true])
        let disabled = try render(text, engine: "github", values: ["taskLists": false])
        #expect(enabled.contains("type=\"checkbox\"") && enabled.contains("checked=\"\""), Comment(rawValue: enabled))
        #expect(!disabled.contains("checkbox") && disabled.contains("[ ] Pending café") && disabled.contains("[x] Done 🐼"))
    }

    @Test func githubTagFilterEscapesBlockedTagsWhenRawHTMLIsAllowed() throws {
        let text = "<script>Neutral</script>"
        let filtered = try render(text, engine: "github", values: ["tagFilters": true, "safe": false, "unsafe": true])
        let raw = try render(text, engine: "github", values: ["tagFilters": false, "safe": false, "unsafe": true])
        #expect(filtered.contains("&lt;script>") && !filtered.contains("<script>"), Comment(rawValue: filtered))
        #expect(raw.contains(text))
    }

    @Test func githubFootnotesResolveDefinitionsOnlyWhenEnabled() throws {
        let text = "Body[^neutral].\n\n[^neutral]: Café 🐼 footnote."
        let enabled = try render(text, engine: "github", values: ["footnotes": true])
        let disabled = try render(text, engine: "github", values: ["footnotes": false])
        #expect(enabled.contains("footnote-ref") && enabled.contains("Café 🐼 footnote."), Comment(rawValue: enabled))
        #expect(!disabled.contains("footnote-ref") && disabled.contains("[^neutral]"))
    }

    @Test func githubSmartQuotesFollowTheirOwnEngineOption() throws {
        let text = "\"Café 🐼\""
        let smart = try render(text, engine: "github", values: ["smartQuotes": true])
        let plain = try render(text, engine: "github", values: ["smartQuotes": false])
        #expect(smart.contains("“Café 🐼”"), Comment(rawValue: smart))
        #expect(plain.contains("&quot;Café 🐼&quot;"), Comment(rawValue: plain))
    }

    @Test func githubUTF8ValidationKeepsValidUnicodeUnchanged() throws {
        // Swift String always supplies valid UTF-8. Invalid byte sequences cannot enter this API.
        let text = "Café 🐼 e\u{301} العربية"
        let checked = try render(text, engine: "github", values: ["validateUTF8": true])
        let unchecked = try render(text, engine: "github", values: ["validateUTF8": false])
        #expect(checked == unchecked && checked.contains(text))
    }

    @Test func multiMarkdownFootnotesResolveDefinitionsOnlyWhenEnabled() throws {
        let text = "Body[^neutral].\n\n[^neutral]: Café 🐼 footnote."
        let enabled = try render(text, engine: "multi", values: ["footnotesEnabled": true])
        let disabled = try render(text, engine: "multi", values: ["footnotesEnabled": false])
        #expect(enabled.contains("class=\"footnotes\"") && enabled.contains("Café 🐼 footnote."), Comment(rawValue: enabled))
        #expect(!disabled.contains("class=\"footnotes\"") && disabled.contains("[^neutral]"))
    }

    @Test func multiMarkdownMetadataCanBePreservedAsOrdinaryText() throws {
        let text = "QAValue: Neutral café 🐼\n\nBody."
        let metadata = try render(text, engine: "multi", values: ["noMetadata": false])
        let ordinary = try render(text, engine: "multi", values: ["noMetadata": true])
        #expect(!metadata.contains("QAValue:") && metadata.contains("Body."))
        #expect(ordinary.contains("QAValue: Neutral café 🐼") && ordinary.contains("Body."), Comment(rawValue: ordinary))
    }

    @Test func multiMarkdownCompatibilitySuppressesExtendedTables() throws {
        let text = "| Name | Value |\n| --- | --- |\n| Café 🐼 | Neutral |"
        let extended = try render(text, engine: "multi", values: ["markdownCompatibilityMode": false])
        let compatible = try render(text, engine: "multi", values: ["markdownCompatibilityMode": true])
        #expect(extended.contains("<table>"), Comment(rawValue: extended))
        #expect(!compatible.contains("<table") && compatible.contains("| Café 🐼 | Neutral |"))
    }

    @Test func multiMarkdownObfuscationHidesThePlainEmailAddress() throws {
        let text = "<neutral@example.com>"
        let plain = try render(text, engine: "multi", values: ["obfuscate": false])
        let encoded = try render(text, engine: "multi", values: ["obfuscate": true])
        #expect(decodedNumericEntities(plain).contains("<a href=\"mailto:neutral@example.com\">neutral@example.com</a>"))
        #expect(!encoded.contains("neutral@example.com") && encoded.contains("&#"), Comment(rawValue: encoded))
        #expect(decodedNumericEntities(encoded).contains("<a href=\"mailto:neutral@example.com\">neutral@example.com</a>"))
    }

    @Test(arguments: ["markup", "accept", "reject"])
    func multiMarkdownCriticModesControlAddedAndDeletedText(mode: String) throws {
        let text = "Keep {++added café++} {--removed 🐼--}."
        let output = try render(text, engine: "multi", values: [
            "criticMarkup": true, "criticMarkupAccept": mode == "accept", "criticMarkupReject": mode == "reject"])
        switch mode {
        case "accept":
            #expect(output.contains("added café") && !output.contains("removed 🐼") && !output.contains("<ins>"), Comment(rawValue: output))
        case "reject":
            #expect(!output.contains("added café") && output.contains("removed 🐼") && !output.contains("<del>"), Comment(rawValue: output))
        default:
            #expect(output.contains("<ins>added café</ins>") && output.contains("<del>removed 🐼</del>"), Comment(rawValue: output))
        }
        let literal = try render(text, engine: "multi", values: ["criticMarkup": false])
        #expect(literal.contains("{++added café++}") && literal.contains("{--removed 🐼--}"))
    }

    @Test func multiMarkdownProcessHTMLRetainsLiteralBlocksLikeFrozenReference() throws {
        let text = "<div markdown=\"1\">\n**Café 🐼**\n</div>"
        let processed = try render(text, engine: "multi", values: ["processHTML": true])
        let raw = try render(text, engine: "multi", values: ["processHTML": false])
        // Drafts 54.1.1 retains this literal block with either saved value.
        #expect(processed == raw)
        #expect(processed.contains(text) && !processed.contains("<strong>"), Comment(rawValue: processed))
    }
}
