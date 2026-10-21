import Foundation
import Testing
@testable import DraftlyCore

@Suite("MultiMarkdown random footnote destinations")
struct MultiMarkdownRandomFootnoteTests {
    private func render(_ text: String, random: Bool) throws -> String {
        let preferences = try TestPreferences(prefix: "RandomFootnoteContract")
        defer { preferences.close() }
        let json = try JSONEncoder().encode(["randomFootnotes": random])
        preferences.defaults.set(String(decoding: json, as: UTF8.self), forKey: MarkdownPreferences.multiKey)
        return try MarkdownPreferences.render(text, defaults: preferences.defaults)
    }

    @Test func sequentialFootnoteHTMLKeepsItsPreFixBytes() throws {
        let text = "Body[^neutral].\n\n[^neutral]: Neutral footnote."
        let expected = """
<p>Body<a href="#fn:1" id="fnref:1" title="see footnote" class="footnote"><sup>1</sup></a>.</p>

<div class="footnotes">
<hr />
<ol>

<li id="fn:1">
<p>Neutral footnote. <a href="#fnref:1" title="return to body" class="reversefootnote">&#160;&#8617;&#xfe0e;</a></p>
</li>

</ol>
</div>

"""
        #expect(try render(text, random: false) == expected)
    }

    @Test(arguments: [1, 3])
    func randomFootnoteLinksHaveMatchingDestinationsAndBacklinks(count: Int) throws {
        let body = (1...count).map { "Body[^note\($0)]." }.joined(separator: " ")
        let definitions = (1...count).map { "[^note\($0)]: Neutral footnote \($0)." }.joined(separator: "\n")
        let output = try render(body + "\n\n" + definitions, random: true)
        let regex = try NSRegularExpression(pattern: "href=\"#fn:([0-9]+)\"")
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        #expect(matches.count == count)
        for (ordinal, match) in matches.enumerated() {
            let numberRange = try #require(Range(match.range(at: 1), in: output))
            let identifier = String(output[numberRange])
            let number = try #require(Int(identifier))
            #expect((1...32000).contains(number))
            #expect(output.contains("id=\"fnref:" + identifier + "\""))
            #expect(output.contains("href=\"#fnref:" + identifier + "\""))
            #expect(output.contains("<li id=\"fn:" + identifier + "\">\n<p>Neutral footnote \(ordinal + 1)."), Comment(rawValue: output))
            #expect(output.contains("<sup>\(ordinal + 1)</sup>"))
        }
    }
}
