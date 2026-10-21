import Foundation
import Testing
@testable import DraftlyCore

@Suite("HTMLPreview member contracts") @MainActor
struct HTMLPreviewContractTests {
    @Test(arguments: [false, true])
    func constructorAndFactoryCreateIndependentInstancesWithoutPresentation(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: PreviewContractHost())
        let action = makeAPIAction("""
        const first=new HTMLPreview(),second=HTMLPreview.create();
        check(first instanceof HTMLPreview&&second instanceof HTMLPreview,'typed instances');
        check(first!==second,'independent instances');
        check(first.hideInterface===false&&second.hideInterface===false,'initial interface');
        first.hideInterface=true;
        check(first.hideInterface===true&&second.hideInterface===false,'independent configuration');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.isEmpty && f.editor.content == "Keep café 🐼")
    }

    @Test(arguments: [false, true])
    func hideInterfaceForwardsEachInstancesCurrentValue(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: PreviewContractHost())
        let action = makeAPIAction("""
        const first=new HTMLPreview(),second=HTMLPreview.create();
        first.hideInterface=true;
        first.show('<html><body>café 🐼</body></html>');
        second.show('');
        first.hideInterface=false;
        first.show('<html><body>Next</body></html>');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.map { $0["hideInterface"] as? Bool } == [true, false, false])
        #expect(f.host.calls.map { $0["html"] as? String } == [
            "<html><body>café 🐼</body></html>", "", "<html><body>Next</body></html>"
        ])
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func showReturnsContinueOrCancelAndReplacesReturnedContextValues(worker: Bool) async throws {
        let host = PreviewContractHost()
        host.replies = [
            ["success": true, "values": ["answer": ["text": "café 🐼", "empty": NSNull()]]],
            ["success": false, "values": [:]]
        ]
        let f = try ScriptTestFixture(content: "Keep", host: host)
        let action = makeAPIAction("""
        const preview=HTMLPreview.create();
        const continued=preview.show('<html><body>First</body></html>');
        check(continued===true,'Continue returns boolean true');
        check(context.previewValues.answer.text==='café 🐼','returned nested values');
        check(context.previewValues.answer.empty===null,'returned null');
        const cancelled=preview.show('<html><body>Second</body></html>');
        check(cancelled===false,'Cancel returns boolean false');
        check(Object.keys(context.previewValues).length===0,'no values from preceding preview');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(host.calls.count == 2 && f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func presentationFailureStopsTheActionBeforeFollowingScriptEffects(worker: Bool) async throws {
        let host = PreviewContractHost()
        host.failure = DraftlyError.message("Neutral preview presentation failure")
        let f = try ScriptTestFixture(content: "Keep", host: host)
        let action = makeAPIAction("""
        HTMLPreview.create().show('<html><body>Neutral</body></html>');
        editor.setText('Unexpected effect');
        """)
        #expect(!(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker)))
        #expect(f.runner.message?.contains("Neutral preview presentation failure") == true)
        #expect(host.calls.count == 1 && f.editor.content == "Keep")
    }
}

@MainActor private final class PreviewContractHost: ActionHost {
    var calls: [[String: Any]] = []
    var replies: [[String: Any]] = []
    var failure: Error?

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        guard operation == "htmlPreview" else {
            throw DraftlyError.message("Unexpected preview contract operation: \(operation)")
        }
        calls.append(values)
        if let failure { throw failure }
        return replies.isEmpty ? ["success": true, "values": [:]] : replies.removeFirst()
    }
}
