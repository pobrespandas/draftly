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
}
