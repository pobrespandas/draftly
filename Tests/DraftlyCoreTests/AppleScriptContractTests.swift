import Foundation
import Testing
@testable import DraftlyCore

@Suite("AppleScript member contracts") @MainActor
struct AppleScriptContractTests {
    @Test(arguments: [false, true])
    func constructorsCreateIndependentObjectsWithoutExecuting(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: AppleScriptContractHost())
        let action = makeAPIAction("""
        const first=new AppleScript('first'),second=AppleScript.create('second');
        check(first instanceof AppleScript&&second instanceof AppleScript,'typed constructors');
        check(first!==second,'independent objects');
        check(first.lastError===undefined&&first.lastResult===undefined,'constructor optional properties');
        check(second.lastError===undefined&&second.lastResult===undefined,'create optional properties');
        first.lastError='Assigned error';first.lastResult={text:'Assigned café 🐼'};
        check(first.lastError==='Assigned error'&&first.lastResult.text==='Assigned café 🐼','writable properties');
        check(second.lastError===undefined&&second.lastResult===undefined,'properties do not cross instances');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.isEmpty && f.editor.content == "Keep café 🐼")
    }

    @Test(arguments: [false, true])
    func executeForwardsSourceSubroutineAndStructuredArguments(worker: Bool) async throws {
        let host = AppleScriptContractHost()
        host.replies = [.value(["text": "Result café 🐼", "items": [false, 3.5, NSNull()] as [Any]]), .value("Second")]
        let f = try ScriptTestFixture(content: "Keep", host: host)
        let action = makeAPIAction("""
        const first=new AppleScript('on neutral(payload)\\nreturn payload\\nend neutral');
        const args=['café 🐼\\nquoted \"text\"',false,3.5,null,{nested:['value',7]}];
        const before=JSON.stringify(args);
        check(first.execute('neutral',args)===true,'success returns Boolean true');
        check(JSON.stringify(args)===before,'arguments unchanged');
        check(first.lastResult.text==='Result café 🐼','record result');
        check(Array.isArray(first.lastResult.items)&&first.lastResult.items[0]===false&&first.lastResult.items[1]===3.5&&first.lastResult.items[2]===null,'nested result types');
        check(first.lastError===undefined,'success has no last error');
        const second=AppleScript.create('second source');
        check(second.execute('secondHandler',[])===true&&second.lastResult==='Second','second source result');
        check(first.lastResult.text==='Result café 🐼','results do not cross instances');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(host.calls.map(\.source) == ["on neutral(payload)\nreturn payload\nend neutral", "second source"])
        #expect(host.calls.map(\.subroutine) == ["neutral", "secondHandler"])
        let arguments = try #require(host.calls.first?.arguments)
        #expect(arguments.count == 5)
        #expect(arguments[0] as? String == "café 🐼\nquoted \"text\"")
        #expect(arguments[1] as? Bool == false && arguments[2] as? Double == 3.5)
        #expect(arguments[3] is NSNull)
        let nested = try #require((arguments[4] as? [String: Any])?["nested"] as? [Any])
        #expect(nested[0] as? String == "value" && nested[1] as? Int == 7)
        #expect(host.calls.last?.arguments?.isEmpty == true)
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func ordinaryFailureReturnsFalseAndLaterSuccessClearsLastError(worker: Bool) async throws {
        let host = AppleScriptContractHost()
        host.replies = [.failure(DraftlyError.message("Neutral compile failure")),
                        .failure(DraftlyError.message("Neutral runtime failure")), .value("Recovered café 🐼")]
        let f = try ScriptTestFixture(content: "Keep", host: host)
        let action = makeAPIAction("""
        const apple=AppleScript.create('neutral');
        check(apple.execute('compile',[])===false,'compile failure returns Boolean false');
        check(apple.lastError==='Neutral compile failure','compile error detail');
        check(apple.execute('runtime',[])===false,'runtime failure returns Boolean false');
        check(apple.lastError==='Neutral runtime failure','latest error detail');
        check(apple.execute('recover',[])===true,'recovery succeeds');
        check(apple.lastError===undefined,'recovery clears last error');
        check(apple.lastResult==='Recovered café 🐼','recovery result');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(host.calls.count == 3 && f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func returnedDatesKeepTheirTypeAtRootAndInsideRecords(worker: Bool) async throws {
        let host = AppleScriptContractHost()
        host.replies = [.value(Date(timeIntervalSince1970: 0)),
                        .value(["a/b~": [Date(timeIntervalSince1970: -1234.5),
                                           ["0": Date(timeIntervalSince1970: 1234.5)]] as [Any],
                                "text": "2020-01-02T03:04:05Z",
                                "appleScriptDatePaths": ["/value"], "value": 7]),
                        .value(["__proto__": Date(timeIntervalSince1970: 0)])]
        let f = try ScriptTestFixture(content: "Keep", host: host)
        let action = makeAPIAction("""
        const apple=AppleScript.create('neutral');
        check(apple.execute('root',[])&&apple.lastResult instanceof Date,'root Date result');
        check(apple.lastResult.getTime()===0,'epoch date');
        check(apple.execute('nested',[]),'nested dates succeed');
        const result=apple.lastResult;
        check(result['a/b~'][0] instanceof Date&&result['a/b~'][0].getTime()===-1234500,'negative nested date');
        check(result['a/b~'][1]['0'] instanceof Date&&result['a/b~'][1]['0'].getTime()===1234500,'numeric key date');
        check(typeof result.text==='string'&&result.text==='2020-01-02T03:04:05Z','date-like strings unchanged');
        check(result.value===7&&result.appleScriptDatePaths[0]==='/value','ordinary metadata-like fields preserved');
        check(context.appleScriptResponses[0] instanceof Date&&context.appleScriptResponses[1]===result,'typed response collection');
        check(apple.execute('prototype',[]),'prototype key succeeds');
        check(Object.hasOwn(apple.lastResult,'__proto__')&&apple.lastResult.__proto__ instanceof Date,'own prototype key preserved');
        check(Object.getPrototypeOf(apple.lastResult)===Object.prototype,'object prototype unchanged');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func nativeStepDatesReachTheSharedResponseCollection(worker: Bool) async throws {
        let host = AppleScriptContractHost()
        host.replies = [.value(["stamp": Date(timeIntervalSince1970: 0)])]
        let f = try ScriptTestFixture(content: "Keep", host: host)
        var action = makeAPIAction("""
        const result=context.appleScriptResponses[0];
        check(result.stamp instanceof Date&&result.stamp.getTime()===0,'native step Date');
        """)
        action.steps.insert(ActionStep("runAppleScript", ["script": "return neutral"]), at: 0)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [false, true], ["timeout", "cancelled", "cancellationError"])
    func controlErrorsDoNotBecomeAnOrdinaryFailureBoolean(worker: Bool, interruption: String) async throws {
        let host = AppleScriptContractHost()
        let failure: Error
        switch interruption {
        case "timeout": failure = ActionExecutionInterruption.timeout
        case "cancelled": failure = ActionExecutionInterruption.cancelled
        default: failure = CancellationError()
        }
        host.replies = [.failure(failure)]
        let f = try ScriptTestFixture(content: "Keep", host: host)
        var action = makeAPIAction("""
        AppleScript.create('neutral').execute('execute',[]);
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
}

@MainActor private final class AppleScriptContractHost: ActionHost {
    struct Call {
        let source: String?
        let subroutine: String?
        let arguments: [Any]?
    }
    enum Reply {
        case value(Any)
        case failure(Error)
    }
    var calls: [Call] = []
    var replies: [Reply] = []

    func supportsAsync(_ operation: String) -> Bool { operation == "appleScript" }

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "actionNotification" { return true }
        guard operation == "appleScript" else {
            throw DraftlyError.message("Unexpected AppleScript contract operation: \(operation)")
        }
        calls.append(Call(source: values["source"] as? String,
                          subroutine: values["subroutine"] as? String,
                          arguments: values["arguments"] as? [Any]))
        guard !replies.isEmpty else { throw DraftlyError.message("Missing AppleScript contract reply.") }
        switch replies.removeFirst() {
        case .value(let value): return value
        case .failure(let error): throw error
        }
    }
}
