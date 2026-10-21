import Foundation
import Testing
@testable import DraftlyCore

@Suite("URL member contracts") @MainActor
struct URLContractTests {
    @Test(arguments: [false, true])
    func constructorCreatesIndependentURLObjects(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        let action = makeAPIAction("""
        const first=new URL(),second=new URL();
        check(first instanceof URL&&second instanceof URL,'constructor type');
        check(first!==second,'independent constructor objects');
        first.hostname='first.example';
        check(second.hostname!=='first.example','independent hostname values');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.isEmpty && f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func parseSupportsAbsoluteURLsAndRelativeReferencesWithABase(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        let action = makeAPIAction("""
        const source='http://getdrafts.com?q=boo';
        const parsed=URL.parse(source);
        check(parsed instanceof URL,'parse returns URL');
        check(parsed.host==='getdrafts.com'&&parsed.searchParams.q==='boo','official parsing example');
        check(parsed.hostname==='getdrafts.com'&&parsed.fragment==='','hostname and absent fragment');
        check(parsed.href===source,'absolute source');
        const base='https://example.com/folder/page';
        const relative=URL.parse('../next?q=caf%C3%A9#section',base);
        check(relative instanceof URL,'relative result type');
        check(relative.href==='https://example.com/next?q=caf%C3%A9#section','base resolution');
        check(relative.hostname==='example.com'&&relative.fragment==='#section','relative components');
        check(source==='http://getdrafts.com?q=boo'&&base==='https://example.com/folder/page','source and base unchanged');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.isEmpty && f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func fragmentSetterAddsOneHashAndKeepsItsValueOnTheSameObject(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        let action = makeAPIAction("""
        const first=URL.parse('https://example.com/path#old');
        const second=URL.parse('https://example.com/path#other');
        check(first.fragment==='#old','initial fragment');
        first.fragment='new';check(first.fragment==='#new','setter adds hash');
        first.fragment='#next';check(first.fragment==='#next','setter preserves hash');
        check(second.fragment==='#other','fragment does not cross objects');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func fragmentMutationKeepsTheSerializedURLCoherent(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        let action = makeAPIAction("""
        const parsed=URL.parse('https://example.com/path?q=one#old');
        parsed.fragment='new';
        check(parsed.href==='https://example.com/path?q=one#new','fragment updates URL');
        check(String(parsed)==='https://example.com/path?q=one#new','fragment updates serialization');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func hostnameMutationPreservesTheOtherURLComponents(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: APIContractHost())
        let action = makeAPIAction("""
        const parsed=URL.parse('https://old.example:8443/path?q=one#section');
        check(parsed.hostname==='old.example','initial hostname excludes port');
        parsed.hostname='new.example';
        check(parsed.hostname==='new.example','hostname is writable');
        check(parsed.host==='new.example:8443','hostname updates host and preserves port');
        check(parsed.href==='https://new.example:8443/path?q=one#section','hostname updates URL');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.editor.content == "Keep")
    }
}
