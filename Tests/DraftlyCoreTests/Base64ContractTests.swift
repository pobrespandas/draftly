import Foundation
import Testing
@testable import DraftlyCore

@Suite("Base64 member contracts") @MainActor
struct Base64ContractTests {
    @Test(arguments: [false, true])
    func encodeMatchesStandardAndUTF8VectorsWithoutChangingTheSource(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: APIContractHost())
        let action = makeAPIAction(#"""
        const vectors=[
          ['', ''], ['f','Zg=='], ['fo','Zm8='], ['foo','Zm9v'],
          ['foob','Zm9vYg=='], ['fooba','Zm9vYmE='], ['foobar','Zm9vYmFy'],
          ['café 🐼','Y2Fmw6kg8J+QvA=='],
          ['line 1\r\nline 2\n','bGluZSAxDQpsaW5lIDIK'],
          ['\u0000🐼é','APCfkLzDqQ==']
        ];
        for(const [source,expected] of vectors){
          const before=source;
          const result=Base64.encode(source);
          check(typeof result==='string','encode string return');
          check(result===expected,'encode independent vector '+expected);
          check(source===before,'encode source unchanged');
        }
        """#)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.editor.content == "Keep café 🐼" && f.library.notes.first?.content == "Keep café 🐼")
        #expect(f.host.calls.isEmpty)
    }

    @Test(arguments: [false, true])
    func decodeMatchesStandardAndUTF8VectorsWithoutChangingTheSource(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: APIContractHost())
        let action = makeAPIAction(#"""
        const vectors=[
          ['', ''], ['Zg==','f'], ['Zm8=','fo'], ['Zm9v','foo'],
          ['Zm9vYg==','foob'], ['Zm9vYmE=','fooba'], ['Zm9vYmFy','foobar'],
          ['Y2Fmw6kg8J+QvA==','café 🐼'],
          ['bGluZSAxDQpsaW5lIDIK','line 1\r\nline 2\n'],
          ['APCfkLzDqQ==','\u0000🐼é']
        ];
        for(const [source,expected] of vectors){
          const before=source;
          const result=Base64.decode(source);
          check(typeof result==='string','decode string return');
          check(result===expected,'decode independent vector '+source);
          check(source===before,'decode source unchanged');
        }
        """#)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.editor.content == "Keep café 🐼" && f.library.notes.first?.content == "Keep café 🐼")
        #expect(f.host.calls.isEmpty)
    }
}
