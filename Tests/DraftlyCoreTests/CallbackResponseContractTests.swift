import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class OrderedCallbackResponseHost: ActionHost {
    let fallback = APIContractHost()
    private(set) var received: [String] = []
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "callbackURL" {
            let source = URLComponents(string: values["url"] as? String ?? "")?.host ?? ""
            received.append(source)
            return ["status": "success", "parameters": ["source": source]]
        }
        if operation == "shortcut" {
            let name = values["name"] as? String ?? ""
            received.append(name)
            return name
        }
        return try fallback.perform(operation, values: values)
    }
}

@Suite("Callback response collection contracts") @MainActor
struct CallbackResponseContractTests {
    @Test(arguments: [false, true], [false, true])
    func noWaitLaunchDoesNotPublishAResponseOrShiftTheNextReply(worker: Bool, step: Bool) async throws {
        let (_, _, host, runner) = try makeAPIContext()
        defer { withExtendedLifetime(host) {} }
        var steps = [ActionStep("script", ["script": "function check(value,message){if(!value)throw new Error(message);}draft.setTemplateTag('callback_result','Initial');"])]
        if step {
            steps.append(ActionStep("callbackUrl", ["url": "fixture://no-wait", "waitForResponse": "false"]))
        } else {
            steps.append(ActionStep("script", ["script": """
            var launched=CallbackURL.create();launched.baseURL='fixture://no-wait';launched.waitForResponse=false;
            check(launched.open()===true,'launch return');
            check(Object.keys(launched.callbackResponse).length===0,'no-wait has no response data');
            """]))
        }
        steps.append(ActionStep("script", ["script": """
        check(context.callbackResponses.length===0,'no synthetic response');
        check(draft.processTemplate('[[callback_result]]')==='Initial','no-wait leaves callback tags unchanged');
        var waited=CallbackURL.create();waited.baseURL='fixture://wait';
        check(waited.open()===true,'wait return');
        check(context.callbackResponses.length===1,'only actual reply');
        check(context.callbackResponses[0].result==='Returned + café','actual response is first');
        check(waited.callbackResponse.result==='Returned + café','instance response');
        """]))
        let action = DraftAction(name: "No-wait response collection", steps: steps)
        if worker { #expect((await runner.runAsync(action)).result.succeeded, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
    }
    @Test(arguments: [false, true])
    func parameterNamesRemainDataAndRepeatedKeysReplaceTheirValue(worker: Bool) async throws {
        let (_, editor, host, runner) = try makeAPIContext()
        defer { withExtendedLifetime(host) {} }
        let action = makeAPIAction("""
        var callback=CallbackURL.create();callback.baseURL='fixture://reply?existing=kept';
        for(var key of ['__proto__','constructor','toString','café 🐼']) {
            if(callback.addParameter(key,'old')!==undefined)throw new Error('void return');
            callback.addParameter(key,'Returned + café 🐼');
        }
        editor.setText(callback.url);
        """)
        if worker { #expect((await runner.runAsync(action)).result.succeeded, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
        let components = try #require(URLComponents(string: editor.content))
        let items = components.queryItems ?? []
        #expect(items.count == 5)
        #expect(items.first(where: { $0.name == "existing" })?.value == "kept")
        for key in ["__proto__", "constructor", "toString", "café 🐼"] {
            #expect(items.filter { $0.name == key }.count == 1, Comment(rawValue: key))
            #expect(items.first(where: { $0.name == key })?.value == "Returned + café 🐼", Comment(rawValue: key))
        }
    }

    @Test(arguments: [false, true], [false, true])
    func returnedParameterNamesRemainOwnProperties(worker: Bool, step: Bool) async throws {
        let (_, _, host, runner) = try makeAPIContext()
        defer { withExtendedLifetime(host) {} }
        host.callbackParameters = ["__proto__": "café 🐼", "constructor": "kept", "quoted": "Line \"one\"\nLine two"]
        let callback = step
            ? ActionStep("callbackUrl", ["url": "fixture://reply"])
            : ActionStep("script", ["script": "var cb=CallbackURL.create();cb.baseURL='fixture://reply';if(!cb.open())throw new Error('callback failed');"])
        let check = ActionStep("script", ["script": """
        if(context.callbackResponses.length!==1)throw new Error('response count');
        var response=context.callbackResponses[0];
        if(!Object.prototype.hasOwnProperty.call(response,'__proto__')||response.__proto__!=='café 🐼')throw new Error('prototype key lost');
        if(response.constructor!=='kept')throw new Error('constructor key lost');
        if(response.quoted!==('Line \"one\"'+String.fromCharCode(10)+'Line two'))throw new Error('quoted value changed');
        if(Object.keys(response).length!==3)throw new Error('response keys');
        if(draft.processTemplate('[[callback___proto__]]')!=='café 🐼')throw new Error('callback tag lost');
        """])
        let action = DraftAction(name: "Callback response keys", steps: [callback, check])
        if worker { #expect((await runner.runAsync(action)).result.succeeded, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
    }

    @Test(arguments: [false, true])
    func mixedCallbackAndShortcutResponsesKeepExecutionOrderAndReset(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Neutral", host: OrderedCallbackResponseHost())
        var action = makeAPIAction("check(Array.isArray(context.callbackResponses) && context.callbackResponses.length===0,'fresh responses');")
        action.steps.append(ActionStep("callbackUrl", ["url": "fixture://step"]))
        action.steps.append(ActionStep("runShortcut", ["name": "Step café 🐼"]))
        action.steps += makeAPIAction("""
        const callback=CallbackURL.create();callback.baseURL='fixture://script';
        check(callback.open()===true,'script callback');
        check(Shortcut.create('Script café 🐼').run()===true,'script shortcut');
        const responses=context.callbackResponses;
        check(responses.length===4,'mixed response count');
        check(responses[0].source==='step' && responses[1].result==='Step café 🐼' && responses[2].source==='script' && responses[3].result==='Script café 🐼','mixed response order');
        """).steps
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        #expect(fixture.host.received == ["step", "Step café 🐼", "script", "Script café 🐼"])
        #expect(await ActionTestExecution.succeeds(makeAPIAction("check(Array.isArray(context.callbackResponses) && context.callbackResponses.length===0,'responses reset');"),
                                                 runner: fixture.runner, worker: worker))
    }

    @Test(arguments: [false, true], ["error", "cancelled"])
    func unsuccessfulScriptCallbacksDoNotPublishReturnedParameters(worker: Bool, status: String) async throws {
        let (_, _, host, runner) = try makeAPIContext()
        defer { withExtendedLifetime(host) {} }
        host.callbackStatus = status
        host.callbackParameters = ["discard": "Not a successful response café 🐼"]
        let action = makeAPIAction("""
        check(context.callbackResponses.length===0,'initial responses');
        const callback=CallbackURL.create();callback.baseURL='fixture://unsuccessful';
        check(callback.open()===false,'unsuccessful callback return');
        check(context.callbackResponses.length===0,'no fabricated success response');
        app.setClipboard('Script continued');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: runner, worker: worker),
                Comment(rawValue: runner.message ?? ""))
        #expect(host.clipboard == "Script continued")
    }

}
