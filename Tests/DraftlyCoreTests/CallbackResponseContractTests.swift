import Foundation
import Testing
@testable import DraftlyCore

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

}
