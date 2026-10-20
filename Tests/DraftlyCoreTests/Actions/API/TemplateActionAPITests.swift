import Foundation
import Testing
@testable import DraftlyCore

@Suite("Template scripting API") @MainActor
struct TemplateActionAPITests {
    @Test func mustacheDirectoryLoadsNamedTemplateAndPartials() throws {
        let (_, _, host, runner) = try makeAPIContext()
        host.templateFiles = ["/Library/Templates/Letters/main.mustache": "Hello {{name}} {{> footer}}", "/Library/Templates/Letters/footer.mustache": "{{value}}"]
        #expect(runner.run(makeAPIAction("let t=MustacheTemplate.createWithPath('Letters'); t.contentType='text'; check(t.renderTemplate('main',{name:'café',value:'<&'})==='Hello café <&','directory partial');")), Comment(rawValue: runner.message ?? ""))
        #expect(!host.calls.contains { $0.0 == "fileAPI" && $0.1["operation"] as? String == "readString" && $0.1["path"] as? String == "/Library/Templates/Letters" })
    }
    @Test func templateRangesEscapesDatesAndMarkup() {
        let note = Note(content: "# Title\nOne\nTwo\nThree")
        let value = Templates.render(#"[[title]]|[[display_title]]|[[line|2..-1]]|[[selection]]|\[[title]]|{{a+b & café}}"#, note: note)
        #expect(value == "# Title|Title|One\nTwo\nThree|# Title\nOne\nTwo\nThree|[[title]]|a%2Bb%20%26%20caf%C3%A9")
        #expect(Templates.render("[[date|+1 day|%Y-%m-%d]]", note: note, now: Date(timeIntervalSince1970: 0)).contains("1970-01-0"))
        #expect(Templates.render("[[line|..2]]", note: note) == "# Title\nOne")
    }
    @Test func mustacheUsesNestedContextsAndEscaping() throws {
        let data: [String: Any] = ["name": "<World>", "items": [["value": "one"], ["value": "two"]]]
        let rendered = try MustacheRenderer.render("{{name}}|{{{name}}}|{{#items}}{{value}}/{{name}};{{/items}}{{^missing}}empty{{/missing}}", data: data)
        #expect(rendered == "&lt;World&gt;|<World>|one/&lt;World&gt;;two/&lt;World&gt;;empty")
    }
    @Test func markdownEnginesRenderRepeatedDocuments() throws {
        for _ in 0..<20 {
            let multi = try ScriptMarkdown.render("# Heading\n\nText[^1]\n\n[^1]: Footnote", engine: "multi")
            #expect(multi.contains("<h1") && multi.contains("Footnote"))
            let github = try ScriptMarkdown.render("- [x] Done\n\n~~Removed~~", engine: "github")
            #expect(github.contains("checkbox") && github.contains("<del>Removed</del>"))
        }
    }
}
