import Foundation
import Testing
@testable import DraftlyCore

@Suite("Shortcut response contracts") @MainActor
struct ShortcutResponseContractTests {
    @Test(arguments: [false, true], [(false, "omitted"), (false, "true"), (false, "false"), (true, "omitted"), (true, "true"), (true, "false")])
    func waitOptionReachesTheHostAndControlsResponses(worker: Bool, options: (Bool, String)) async throws {
        let (step, mode) = options
        let (_, _, host, runner) = try makeAPIContext()
        defer { withExtendedLifetime(host) {} }
        let waits = mode != "false"
        var steps = [ActionStep("defineTemplateTag", ["name": "shortcut_result", "template": "Initial"])]
        if step {
            var values = ["name": "Neutral fixture", "template": "Input café 🐼"]
            if mode != "omitted" { values["waitForResponse"] = mode }
            steps.append(ActionStep("runShortcut", values))
        } else {
            let option = mode == "omitted" ? "" : "shortcut.waitForResponse=\(mode);"
            steps.append(ActionStep("script", ["script": """
            var shortcut=Shortcut.create('Neutral fixture','Input café 🐼');
            if(shortcut.waitForResponse!==true)throw new Error('default wait');
            \(option)
            if(shortcut.run()!==true||shortcut.status!=='success')throw new Error('launch result');
            if(\(waits ? "true" : "false")) {
                if(shortcut.result!=='Shortcut output')throw new Error('waiting result');
            } else {
                if(shortcut.result!==undefined||Object.keys(shortcut.response).length!==0)throw new Error('synthetic no-wait result');
            }
            """]))
        }
        let count = waits ? 1 : 0
        let expectedTag = waits ? "Shortcut output" : "Initial"
        steps.append(ActionStep("script", ["script": """
        if(context.callbackResponses.length!==\(count))throw new Error('response collection');
        if(draft.processTemplate('[[shortcut_result]]')!=='\(expectedTag)')throw new Error('shortcut result tag');
        """]))
        let action = DraftAction(name: "Shortcut wait option", steps: steps)
        if worker { #expect((await runner.runAsync(action)).result.succeeded, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
        let call = try #require(host.calls.first(where: { $0.0 == "shortcut" }))
        #expect(call.1["waitForResponse"] as? Bool == waits)
        #expect(call.1["name"] as? String == "Neutral fixture")
        #expect(call.1["text"] as? String == "Input café 🐼")
    }
    @Test(arguments: [false, true], [false, true])
    func failedShortcutDoesNotPublishAResultAndStopsFollowingSteps(worker: Bool, step: Bool) async throws {
        let (library, editor, host, runner) = try makeAPIContext()
        defer { withExtendedLifetime(host) {} }
        host.shortcutFailureMessage = "Denied café 🐼"
        var steps = [ActionStep("defineTemplateTag", ["name": "shortcut_result", "template": "Initial"]),
            ActionStep("script", ["script": "app.setClipboard('Completed effect');"])]
        if step {
            steps.append(ActionStep("runShortcut", ["name": "Neutral failure"]))
        } else {
            steps.append(ActionStep("script", ["script": """
            var failed=Shortcut.create('Neutral failure');
            if(failed.status!=='created'||Object.keys(failed.response).length!==0||failed.result!==undefined)throw new Error('initial result');
            if(failed.run()!==false||failed.status!=='error'||failed.response.error!=='Denied café 🐼')throw new Error('failure return');
            if(failed.result!==undefined||context.callbackResponses.length!==0)throw new Error('failure result published');
            if(draft.processTemplate('[[shortcut_result]]')!=='Initial')throw new Error('failure tag changed');
            context.fail('Denied café 🐼');
            """]))
        }
        steps.append(ActionStep("clipboard", ["template": "Must not run"]))
        var action = DraftAction(name: "Shortcut failure", steps: steps)
        action.afterSuccess = "archive"
        let report = worker ? await runner.runAsync(action) : runner.runReport(action)
        #expect(report.reason == .error && report.result == .failure("Denied café 🐼"))
        #expect(host.clipboard == "Completed effect")
        #expect(host.calls.filter { $0.0 == "shortcut" }.count == 1)
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
        #expect(editor.content == "# Source\nBody")
    }

}
