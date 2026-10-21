import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class ShareContractHost: ActionHost {
    var result = true
    var failure: Error?
    var calls: [(String, [String: Any])] = []

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        guard ["share", "shareFile", "shareURL"].contains(operation) else {
            throw DraftlyError.message("Unexpected Share fixture operation: \(operation)")
        }
        calls.append((operation, values))
        if let failure { throw failure }
        return result
    }
}

@Suite("Share scripting contracts") @MainActor
struct ShareActionContractTests {
    @Test(arguments: [false, true])
    func filenamePrecedesUnicodeContentsOnBothRunners(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep original 🐼", host: ShareContractHost())
        let action = makeAPIAction("""
        check(Share.shareAsFile('Resumen café 🐼.txt','First café 🐼\\nSecond <&>')===true,'file share result');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        let call = try #require(fixture.host.calls.first)
        #expect(fixture.host.calls.count == 1 && call.0 == "shareFile")
        #expect(call.1["name"] as? String == "Resumen café 🐼.txt")
        #expect(call.1["text"] as? String == "First café 🐼\nSecond <&>")
        #expect(fixture.editor.content == "Keep original 🐼")
    }

    @Test(arguments: [false, true], [false, true])
    func textAndURLForwardExactValuesAndCompletionResult(worker: Bool, completed: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep original 🐼", host: ShareContractHost())
        fixture.host.result = completed
        let action = makeAPIAction("""
        const expected=\(completed ? "true" : "false");
        check(Share.shareAsText('café 🐼\\n<&>')===expected,'text result');
        check(Share.shareAsURL('https://example.invalid/caf%C3%A9?q=%F0%9F%90%BC')===expected,'URL result');
        check(Share.shareAsFile('café.txt','body 🐼')===expected,'file result');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        try #require(fixture.host.calls.count == 3)
        #expect(fixture.host.calls.map { $0.0 } == ["share", "shareURL", "shareFile"])
        #expect(fixture.host.calls[0].1["text"] as? String == "café 🐼\n<&>")
        #expect(fixture.host.calls[1].1["url"] as? String == "https://example.invalid/caf%C3%A9?q=%F0%9F%90%BC")
        #expect(fixture.host.calls[2].1["name"] as? String == "café.txt")
        #expect(fixture.host.calls[2].1["text"] as? String == "body 🐼")
        #expect(fixture.editor.content == "Keep original 🐼")
    }

    @Test(arguments: [false, true])
    func constructorCreatesDistinctShareInstancesWithoutHostEffects(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep original 🐼", host: ShareContractHost())
        let action = makeAPIAction("""
        const first=new Share(),second=new Share();
        check(first instanceof Share && second instanceof Share && first!==second,'constructor identity');
        check(typeof Share.shareAsFile==='function' && typeof Share.shareAsText==='function' && typeof Share.shareAsURL==='function','static methods');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        #expect(fixture.host.calls.isEmpty)
    }

    @Test(arguments: [false, true])
    func nonStringInputsReturnFalseBeforeCallingTheHost(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep original 🐼", host: ShareContractHost())
        let action = makeAPIAction("""
        for(const text of [undefined,null,42,{},[]]){
            check(Share.shareAsURL(text)===false,'invalid URL type');
            check(Share.shareAsFile(text,'body 🐼')===false,'invalid filename type');
            check(Share.shareAsText(text)===false,'invalid text type');
            check(Share.shareAsFile('neutral.txt',text)===false,'invalid file contents type');
        }
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        #expect(fixture.host.calls.isEmpty)
        #expect(fixture.editor.content == "Keep original 🐼")
    }

    @Test(arguments: [false, true])
    func unsuccessfulNativeSharingReturnsFalseInsteadOfThrowing(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep original 🐼", host: ShareContractHost())
        fixture.host.failure = DraftlyError.message("Neutral sharing service failure")
        let action = makeAPIAction("""
        check(Share.shareAsText('neutral café 🐼')===false,'text service failure');
        check(Share.shareAsFile('neutral.txt','neutral café 🐼')===false,'file service failure');
        check(Share.shareAsURL('https://example.invalid/')===false,'URL service failure');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        #expect(fixture.host.calls.map { $0.0 } == ["share", "shareFile", "shareURL"])
        #expect(fixture.editor.content == "Keep original 🐼")
    }
}
