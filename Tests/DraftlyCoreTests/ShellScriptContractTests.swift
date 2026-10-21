import Foundation
import Testing
@testable import DraftlyCore

@Suite("ShellScript member contracts") @MainActor
struct ShellScriptContractTests {
    @Test(arguments: [false, true])
    func constructorsCreateIndependentRunnersWithUndefinedStreams(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: ShellScriptContractHost())
        let action = makeAPIAction("""
        const first=new ShellScript('#!/bin/sh\\nprintf first');
        const second=ShellScript.create('#!/bin/sh\\nprintf second');
        check(first instanceof ShellScript&&second instanceof ShellScript,'typed constructors');
        check(first!==second,'independent runners');
        check(first.standardOutput===undefined&&first.standardError===undefined,'constructor optional streams');
        check(second.standardOutput===undefined&&second.standardError===undefined,'create optional streams');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.isEmpty)
        #expect(f.editor.content == "Keep café 🐼")
    }

    @Test(arguments: [false, true])
    func executePreservesSourceAndLiteralArgumentsAndReturnsStatusBoolean(worker: Bool) async throws {
        let host = ShellScriptContractHost()
        host.replies = [.init(status: 0), .init(status: 7), .init(status: 0)]
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: host)
        let action = makeAPIAction("""
        const first=new ShellScript('#!/bin/sh\\nprintf first');
        const second=ShellScript.create('#!/usr/bin/env ruby\\nputs ARGV');
        const args=['$(not-a-command)','café 🐼','two words','',"a'b\\\"c"];
        check(first.execute(args)===true,'zero status returns true');
        check(second.execute(args)===false,'nonzero status returns false');
        check(first.execute([])===true,'explicit empty arguments');
        check(args.join('|')==='$(not-a-command)|café 🐼|two words||a\\\'b\\\"c','arguments unchanged');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(host.calls.map(\.source) == ["#!/bin/sh\nprintf first", "#!/usr/bin/env ruby\nputs ARGV", "#!/bin/sh\nprintf first"])
        let expected = ["$(not-a-command)", "café 🐼", "two words", "", "a'b\"c"]
        #expect(host.calls.map(\.arguments) == [expected, expected, []])
        #expect(f.editor.content == "Keep café 🐼")
    }

    @Test(arguments: [false, true])
    func optionalStreamsContainTheLatestExecutionOutputWithoutCrossingInstances(worker: Bool) async throws {
        let host = ShellScriptContractHost()
        host.replies = [
            .init(status: 0, stdout: "First café 🐼\nSecond line\n", stderr: "Warning 🐼\n"),
            .init(status: 0),
            .init(status: 7, stdout: "Failure output\n", stderr: "Failure café\n"),
            .init(status: 0, stdout: "Other runner", stderr: "Other error")
        ]
        let f = try ScriptTestFixture(content: "Keep", host: host)
        let action = makeAPIAction("""
        const first=ShellScript.create('first'),second=new ShellScript('second');
        first.execute([]);
        check(first.standardOutput==='First café 🐼\\nSecond line\\n','stdout Unicode and line endings');
        check(first.standardError==='Warning 🐼\\n','stderr Unicode and line endings');
        check(second.standardOutput===undefined&&second.standardError===undefined,'unexecuted runner');
        first.standardOutput='Assigned café 🐼';first.standardError='Assigned warning';
        check(first.standardOutput==='Assigned café 🐼'&&first.standardError==='Assigned warning','writable stream properties');
        first.execute([]);
        check(first.standardOutput===''&&first.standardError==='','empty streams replace prior output');
        first.execute([]);
        check(first.standardOutput==='Failure output\\n','nonzero stdout');
        check(first.standardError==='Failure café\\n','nonzero stderr');
        second.execute([]);
        check(second.standardOutput==='Other runner'&&second.standardError==='Other error','second streams');
        check(first.standardOutput==='Failure output\\n'&&first.standardError==='Failure café\\n','independent streams');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(host.calls.count == 4)
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func ordinaryExecutionFailureReturnsFalseInsteadOfThrowing(worker: Bool) async throws {
        let host = ShellScriptContractHost()
        host.failure = DraftlyError.message("The neutral interpreter could not start.")
        let f = try ScriptTestFixture(content: "Keep", host: host)
        let action = makeAPIAction("""
        const runner=ShellScript.create('#!/neutral/missing-interpreter');
        check(runner.execute([])===false,'ordinary execution failure returns false');
        context.addSuccessParameter('handled','false');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(host.calls.count == 1)
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [false, true], ["timeout", "cancelled", "cancellationError"])
    func uncaughtControlErrorsNeverBecomeAnExecutionBoolean(worker: Bool, interruption: String) async throws {
        let host = ShellScriptContractHost()
        switch interruption {
        case "timeout": host.failure = ActionExecutionInterruption.timeout
        case "cancelled": host.failure = ActionExecutionInterruption.cancelled
        default: host.failure = CancellationError()
        }
        let f = try ScriptTestFixture(content: "Keep", host: host)
        var action = makeAPIAction("""
        ShellScript.create('neutral').execute([]);
        editor.setText('Late script edit');
        context.addSuccessParameter('late','must not publish');
        """)
        action.steps.append(ActionStep("insertText", ["template": "Late step"]))
        action.afterSuccess = "archive"
        let report = worker ? await f.runner.runAsync(action) : f.runner.runReport(action)
        let expected: ActionTerminationReason = worker ? (interruption == "timeout" ? .timeout : .cancelled) : .error
        #expect(report.reason == expected && !report.result.succeeded)
        #expect(report.successParameters.isEmpty && host.calls.count == 1)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.content == "Keep")
        #expect(f.library.notes.first?.isArchived == false)
    }

    @Test(arguments: [false, true])
    func catchingShellInterruptionCannotRunLaterEffects(timeout: Bool) async throws {
        let host = ShellScriptContractHost()
        host.failure = timeout ? ActionExecutionInterruption.timeout : .cancelled
        let f = try ScriptTestFixture(content: "Keep", host: host)
        var action = makeAPIAction("""
        try{ShellScript.create('neutral').execute([]);}catch(error){}
        try{editor.setText('Late script edit');}catch(error){}
        context.addSuccessParameter('late','must not publish');
        """)
        action.steps.append(ActionStep("insertText", ["template": "Late step"]))
        action.afterSuccess = "archive"
        let report = await f.runner.runAsync(action)
        #expect(report.reason == (timeout ? .timeout : .cancelled))
        #expect(report.successParameters.isEmpty && host.calls.count == 1)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.content == "Keep")
        #expect(f.library.notes.first?.isArchived == false)
    }
}

@MainActor private final class ShellScriptContractHost: ActionHost {
    struct Call {
        let source: String?
        let arguments: [String]?
    }
    struct Reply {
        let status: Int
        var stdout = ""
        var stderr = ""
    }
    var calls: [Call] = []
    var replies: [Reply] = []
    var failure: Error?

    func supportsAsync(_ operation: String) -> Bool { operation == "shellScript" }

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "actionNotification" { return true }
        guard operation == "shellScript" else {
            throw DraftlyError.message("Unexpected ShellScript contract operation: \(operation)")
        }
        calls.append(Call(source: values["source"] as? String, arguments: values["arguments"] as? [String]))
        if let failure { throw failure }
        guard !replies.isEmpty else { throw DraftlyError.message("Missing ShellScript contract reply.") }
        let reply = replies.removeFirst()
        return ["status": reply.status, "stdout": reply.stdout, "stderr": reply.stderr]
    }
}
