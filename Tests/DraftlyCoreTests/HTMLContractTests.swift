import Foundation
import Testing
@testable import DraftlyCore

@Suite("HTML member contracts") @MainActor
struct HTMLContractTests {
    @Test(arguments: [false, true])
    func constructorCreatesIndependentObjectsWithoutHostWork(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: HTMLContractHost())
        let action = makeAPIAction("""
        const first=new HTML(),second=new HTML();
        check(first instanceof HTML&&second instanceof HTML,'constructor type');
        check(first!==second,'constructor instances');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.isEmpty && f.editor.content == "Keep café 🐼")
    }

    @Test(arguments: [false, true])
    func escapeProtectsMarkupAndPreservesOrdinaryText(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: HTMLContractHost())
        let action = makeAPIAction(#"""
        const cases=[
          ['', ''], ['café 🐼\nSecond line','café 🐼\nSecond line'],
          ['<One> & Two','&lt;One&gt; &amp; Two'],
          ['"double" and \'single\'','&quot;double&quot; and &#39;single&#39;'],
          ['&lt;existing&gt;','&amp;lt;existing&amp;gt;'],
          ['<script>alert("x")</script>','&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;']
        ];
        for(const [source,expected] of cases){
          const before=source,result=HTML.escape(source);
          check(typeof result==='string','escape return type');
          check(result===expected,'escape safe entity output');
          check(source===before,'escape source unchanged');
        }
        """#)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.isEmpty)
        #expect(f.editor.content == "Keep café 🐼" && f.library.notes.first?.content == "Keep café 🐼")
    }

    @Test(arguments: [false, true])
    func unescapeForwardsTheExactStringAndReturnsTheDecodedHostValue(worker: Bool) async throws {
        let host = HTMLContractHost()
        host.replies = ["", "<One> & Two", "café 🐼", "<b>literal</b>\nNext"]
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: host)
        let action = makeAPIAction(#"""
        const cases=[
          ['', ''], ['&lt;One&gt; &amp; Two','<One> & Two'],
          ['caf&#233; &#x1F43C;','café 🐼'],
          ['<b>literal</b>\nNext','<b>literal</b>\nNext']
        ];
        for(const [source,expected] of cases){
          const before=source,result=HTML.unescape(source);
          check(typeof result==='string','unescape return type');
          check(result===expected,'unescape returns host value');
          check(source===before,'unescape source unchanged');
        }
        """#)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(host.calls == ["", "&lt;One&gt; &amp; Two", "caf&#233; &#x1F43C;", "<b>literal</b>\nNext"])
        #expect(f.editor.content == "Keep café 🐼" && f.library.notes.first?.content == "Keep café 🐼")
    }
}

@MainActor private final class HTMLContractHost: ActionHost {
    var calls: [String] = []
    var replies: [String] = []

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        guard operation == "htmlUnescape", let text = values["text"] as? String else {
            throw DraftlyError.message("Unexpected HTML contract operation: \(operation)")
        }
        calls.append(text)
        guard !replies.isEmpty else { throw DraftlyError.message("Missing HTML contract reply.") }
        return replies.removeFirst()
    }
}
