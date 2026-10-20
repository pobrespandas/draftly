import Foundation
import Testing
@testable import DraftlyCore

@Suite("Draft template tag member contracts") @MainActor
struct DraftTemplateTagContractTests {
    @Test func swiftNonJSONValuesDoNotBlockUnrelatedFields() throws {
        let data: [String: Any] = ["date": Date(timeIntervalSince1970: 1_700_000_000), "label": "Café 🐼"]
        #expect(try MustacheRenderer.render("{{label}}", data: data) == "Café 🐼")
    }

    @Test(arguments: [false, true])
    func prototypeNamesSurviveBothRenderersAndLaterSteps(worker: Bool) async throws {
        let (_, _, host, runner) = try makeAPIContext()
        let first = #"""
        const names=['__proto__','constructor','toString','hasOwnProperty'];
        check(draft.getTemplateTag('toString')===draft.getTemplateTag('missing'),'no inherited tag');
        for(let i=0;i<names.length;i++){
            check(draft.setTemplateTag(names[i],'Café 🐼 '+i)===undefined,'void setter');
            check(draft.getTemplateTag(names[i])==='Café 🐼 '+i,'exact tag '+names[i]);
        }
        check(draft.processTemplate('[[__proto__]]|[[constructor]]|[[toString]]')==='Café 🐼 0|Café 🐼 1|Café 🐼 2','Draft template');
        check(draft.processMustacheTemplate('{{hasOwnProperty}}|{{hasOwnProperty}}')==='Café 🐼 3|Café 🐼 3','repeated own-key cache');
        const rendered=draft.processMustacheTemplate('{{__proto__}}|{{constructor}}|{{toString}}');check(rendered==='Café 🐼 0|Café 🐼 1|Café 🐼 2','Mustache template '+rendered);
        """#
        let later = #"""
        const next=Draft.create();
        for(let i=0;i<3;i++)check(next.getTemplateTag(['__proto__','constructor','toString'][i])==='Café 🐼 '+i,'later shared tag');
        check(next.processTemplate('[[__proto__]]|[[constructor]]|[[toString]]')==='Café 🐼 0|Café 🐼 1|Café 🐼 2','later template hydration');
        check(next.processMustacheTemplate('{{__proto__}}|{{constructor}}|{{toString}}')==='Café 🐼 0|Café 🐼 1|Café 🐼 2','later Mustache hydration');
        """#
        var action = makeAPIAction(first)
        action.steps.append(ActionStep("clipboard", ["template": "[[__proto__]]|[[constructor]]|[[toString]]"]))
        action.steps += makeAPIAction(later).steps
        let succeeded: Bool
        if worker { succeeded = await runner.runAsync(action).result.succeeded }
        else { succeeded = runner.run(action) }
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
        #expect(host.clipboard == "Café 🐼 0|Café 🐼 1|Café 🐼 2")
    }

    @Test(arguments: [false, true])
    func mustacheAdditionalValuesAndPartialsOverrideTagsWithoutMutatingThem(worker: Bool) async throws {
        let (_, _, _, runner) = try makeAPIContext()
        let action = makeAPIAction(#"""
        draft.setTemplateTag('label','Stored café 🐼');
        const values={label:'Override café 🐼'},partials={line:'{{label}}'};
        check(draft.processMustacheTemplate('{{>line}}',values,partials)==='Override café 🐼','partials and override');
        check(draft.getTemplateTag('label')==='Stored café 🐼','tag unchanged');
        check(draft.processMustacheTemplate('{{label}}')==='Stored café 🐼','default additional values');
        check(values.label==='Override café 🐼' && partials.line==='{{label}}','arguments unchanged');
        const special=JSON.parse('{"__proto__":"{{label}}"}');
        check(draft.processMustacheTemplate('{{>__proto__}}',values,special)==='Override café 🐼','prototype-named partial');
        """#)
        let succeeded: Bool
        if worker { succeeded = await runner.runAsync(action).result.succeeded }
        else { succeeded = runner.run(action) }
        #expect(succeeded, Comment(rawValue: runner.message ?? ""))
    }
}
