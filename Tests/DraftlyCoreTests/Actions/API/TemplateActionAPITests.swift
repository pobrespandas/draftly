import Foundation
import Testing
@testable import DraftlyCore

@Suite("Template scripting API") @MainActor
struct TemplateActionAPITests {
    @Test(arguments: [false, true])
    func mustacheDirectoryLoadsNamedTemplateAndPartials(worker: Bool) async throws {
        let (_, _, host, runner) = try makeAPIContext()
        host.templateFiles = [
            "/Library/Templates/Letters/main.mustache": "Hello {{name}} {{> footer}}",
            "/Library/Templates/Letters/footer.mustache": "{{value}}",
            "/Library/Templates/Letters/__proto__.mustache": "{{value}}",
            "/Library/Templates/Letters/special.mustache": "{{>__proto__}}|{{>__proto__}}"
        ]
        let action = makeAPIAction(#"""
        const factory=new MustacheTemplate();
        const t=factory.createWithPath('Letters');check(t!==factory&&t.contentType==='html','new directory instance and default HTML');t.contentType='text';
        check(MustacheTemplate.createWithPath('Letters').renderTemplate('footer',{value:'Static'})==='Static','static compatibility');
        const made=factory.createWithTemplate('{{value}}');check(made!==factory&&made.contentType==='html','new template instance and default HTML');
        check(made.render({value:'Instance café 🐼'})==='Instance café 🐼','instance template factory');
        check(t.renderTemplate('main',{name:'café',value:'<&'})==='Hello café <&','directory partial');
        check(t.renderTemplate('__proto__',{value:'café 🐼'})==='café 🐼','prototype template name');
        check(t.renderTemplate('special',{value:'café 🐼'})==='café 🐼|café 🐼','repeated prototype partial');
        t.contentType='html';check(t.renderTemplate('special',{value:'<&'})==='&lt;&amp;|&lt;&amp;','HTML partial escaping');
        let missing=false;try{t.renderTemplate('absent',{})}catch(e){missing=String(e).includes('not found')}
        check(missing,'explicit missing template');
        for(const name of ['../main','Letters/main']){
            let rejected=false;try{t.renderTemplate(name,{})}catch(e){rejected=true}
            check(rejected,'reject template traversal');
        }
        let rejected=false;try{MustacheTemplate.createWithPath('Letters/../Other')}catch(e){rejected=true}
        check(rejected,'reject directory traversal');
        """#)
        let succeeded: Bool
        if worker { succeeded = await runner.runAsync(action).result.succeeded }
        else { succeeded = runner.run(action) }
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
        #expect(!host.calls.contains { $0.0 == "fileAPI" && $0.1["operation"] as? String == "readString" && $0.1["path"] as? String == "/Library/Templates/Letters" })
        #expect(!host.calls.contains { $0.0 == "fileAPI" && ($0.1["path"] as? String ?? "").contains("..") })
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
