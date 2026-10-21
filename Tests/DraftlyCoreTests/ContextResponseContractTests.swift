import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class ContextResponseHost: ActionHost {
    let fallback = APIContractHost()
    private(set) var responseCalls: [String] = []

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "htmlPreview" {
            responseCalls.append(operation)
            if values["html"] as? String == "failure" { throw DraftlyError.message("Neutral preview failure") }
            return ["success": true, "values": ["text": "café 🐼", "empty": NSNull(),
                "nested": ["items": [false, 3.5, "café"] as [Any]]]]
        }
        if operation == "appleScript" {
            let source = values["source"] as? String ?? ""
            responseCalls.append(source)
            switch source {
            case "record": return ["text": "café 🐼", "enabled": false, "count": 3.5]
            case "list": return ["café 🐼", false, 3.5] as [Any]
            case "null": return NSNull()
            case "failure": throw DraftlyError.message("Neutral AppleScript failure")
            default: throw DraftlyError.message("Unexpected neutral source")
            }
        }
        return try fallback.perform(operation, values: values)
    }
}

@Suite("Context response contracts") @MainActor
struct ContextResponseContractTests {
    @Test(arguments: [false, true], [false, true])
    func previewValuesExposeTypedFieldsAndResetBetweenActions(worker: Bool, step: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Neutral", host: ContextResponseHost())
        var action = makeAPIAction("check(Object.keys(context.previewValues).length===0,'fresh preview values');check(Object.keys(context.configuredValues).length===0,'unconfigured context values');")
        action.steps += step
            ? [ActionStep("htmlpreview", ["template": "<p>Neutral</p>"])]
            : makeAPIAction("check(HTMLPreview.create().show('<p>Neutral</p>')===true,'preview result');").steps
        action.steps += makeAPIAction("""
        const values=context.previewValues;
        check(Object.keys(values).length===3 && values.text==='café 🐼' && values.empty===null,'typed preview fields');
        check(Array.isArray(values.nested.items) && values.nested.items[0]===false && values.nested.items[1]===3.5 && values.nested.items[2]==='café','nested preview data');
        """).steps
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        #expect(fixture.host.responseCalls == ["htmlPreview"])
        #expect(await ActionTestExecution.succeeds(makeAPIAction("check(Object.keys(context.previewValues).length===0,'preview values reset');"),
                                                 runner: fixture.runner, worker: worker))
    }

    @Test(arguments: [false, true])
    func appleScriptResponsesPreserveMixedPathOrderTypesAndReset(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Neutral", host: ContextResponseHost())
        var action = makeAPIAction("check(Array.isArray(context.appleScriptResponses) && context.appleScriptResponses.length===0,'fresh responses');")
        action.steps.append(ActionStep("runAppleScript", ["script": "record"]))
        action.steps += makeAPIAction("check(AppleScript.create('list').execute('execute')===true,'script result');").steps
        action.steps.append(ActionStep("runAppleScript", ["script": "null"]))
        action.steps += makeAPIAction("""
        const responses=context.appleScriptResponses;
        check(responses.length===3,'response count');
        check(responses[0].text==='café 🐼' && responses[0].enabled===false && responses[0].count===3.5,'record types');
        check(Array.isArray(responses[1]) && responses[1][0]==='café 🐼' && responses[1][1]===false && responses[1][2]===3.5,'list types');
        check(responses[2]===null,'null response');
        """).steps
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        #expect(fixture.host.responseCalls == ["record", "list", "null"])
        #expect(await ActionTestExecution.succeeds(makeAPIAction("check(Array.isArray(context.appleScriptResponses) && context.appleScriptResponses.length===0,'responses reset');"),
                                                 runner: fixture.runner, worker: worker))
    }

    @Test(arguments: [false, true])
    func failedHostCallsDoNotInventContextResponseValues(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Neutral", host: ContextResponseHost())
        let action = makeAPIAction("""
        let previewFailed=false;
        try { HTMLPreview.create().show('failure'); } catch(error) { previewFailed=true; }
        check(previewFailed && Object.keys(context.previewValues).length===0,'failed preview has no returned values');
        const apple=AppleScript.create('failure');
        check(apple.execute('execute')===false && apple.lastError==='Neutral AppleScript failure','script failure result');
        check(context.appleScriptResponses.length===0,'failed script has no returned response');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        #expect(fixture.host.responseCalls == ["htmlPreview", "failure"])
        #expect(fixture.editor.content == "Neutral")
    }
}
