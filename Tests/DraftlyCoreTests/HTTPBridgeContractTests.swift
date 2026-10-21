import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class HTTPBridgeCapture {
    var payloads: [String] = []
    func request(_ payload: String) -> String {
        payloads.append(payload)
        return #"{"value":{"success":true,"statusCode":200,"responseText":"","headers":{},"responseData":null}}"#
    }
}

@MainActor private final class HTTPBridgeCancellation {
    let started = AsyncStream.makeStream(of: Void.self)
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var cancelled = false

    func request(_ payload: String) async -> String {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started.continuation.yield(())
                if Task.isCancelled { finish() }
            }
        } onCancel: { Task { @MainActor in self.finish() } }
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        cancelled = true
        continuation.resume(returning: #"{"value":{"success":false,"statusCode":0,"error":"Cancelled neutral transport"}}"#)
    }
}

@Suite("HTTP worker bridge contracts") @MainActor
struct HTTPBridgeContractTests {
    @Test func factoriesAndInstanceOptionsReachTheSerializedTransport() async throws {
        let (_, _, _, runner) = try makeAPIContext()
        let capture = HTTPBridgeCapture()
        runner.httpTransport = { await capture.request($0) }
        let action = makeAPIAction("""
        const created=HTTP.create(), constructed=new HTTP();
        check(created instanceof HTTP && constructed instanceof HTTP,'HTTP factories');
        check(created.followRedirects===true && created.timeout===60 && constructed.followRedirects===true && constructed.timeout===60,'factory defaults');
        const response=created.request({url:'https://fixture.invalid/default',method:'GET'});
        check(response instanceof HTTPResponse && response.success && response.statusCode===200,'HTTPResponse instance');
        constructed.followRedirects=false; constructed.timeout=2.5;
        constructed.request({url:'https://fixture.invalid/options',method:'POST',followRedirects:true,timeout:99,headers:{'X-Neutral':'café'},data:{text:'🐼'},encoding:'json'});
        """)
        #expect((await runner.runAsync(action)).result.succeeded, Comment(rawValue: runner.message ?? ""))
        try #require(capture.payloads.count == 2)
        let payloads = try capture.payloads.map { try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        #expect(payloads[0]["followRedirects"] as? Bool == true && payloads[0]["timeout"] as? Double == 60)
        #expect(payloads[1]["followRedirects"] as? Bool == false && payloads[1]["timeout"] as? Double == 2.5)
        #expect(payloads[1]["method"] as? String == "POST" && payloads[1]["encoding"] as? String == "json")
        #expect((payloads[1]["headers"] as? [String: String])?["X-Neutral"] == "café")
        #expect((payloads[1]["data"] as? [String: String])?["text"] == "🐼")
    }

    @Test func networkFailureIsAResponseThatTheScriptCanHandle() async throws {
        let (_, _, host, runner) = try makeAPIContext()
        runner.httpTransport = { _ in #"{"value":{"success":false,"statusCode":0,"error":"Neutral network failure","responseText":"","headers":{},"responseData":null}}"# }
        let action = makeAPIAction("""
        const response=HTTP.create().request({url:'https://fixture.invalid/failure',method:'GET'});
        check(response instanceof HTTPResponse && response.success===false && response.statusCode===0,'failure response');
        check(response.error==='Neutral network failure' && response.responseText==='' && response.responseData===null,'failure details');
        app.setClipboard('Handled café 🐼');
        """)
        #expect((await runner.runAsync(action)).reason == .success)
        #expect(host.clipboard == "Handled café 🐼")
    }

    @Test func infrastructureFailureStopsTheActionWithoutSuccessEffects() async throws {
        let (library, editor, host, runner) = try makeAPIContext("Keep café 🐼")
        runner.httpTransport = { _ in #"{"error":"Neutral infrastructure failure"}"# }
        var action = makeAPIAction("context.addSuccessParameter('discard','value');HTTP.create().request({url:'https://fixture.invalid/error',method:'GET'});app.setClipboard('Must not run');")
        action.steps.append(ActionStep("insertText", ["template": "Must not run"]))
        action.afterSuccess = "archive"
        let report = await runner.runAsync(action)
        #expect(report.reason == .error && report.result == .failure("Error: Neutral infrastructure failure"))
        #expect(report.successParameters.isEmpty && host.clipboard.isEmpty)
        #expect(editor.content == "Keep café 🐼")
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
    }

    @Test func cancellationCannotBecomeARecoverableHTTPFailure() async throws {
        let (library, editor, host, runner) = try makeAPIContext("Keep café 🐼")
        let transport = HTTPBridgeCancellation()
        runner.httpTransport = { await transport.request($0) }
        var action = makeAPIAction("context.addSuccessParameter('discard','value');HTTP.create().request({url:'https://fixture.invalid/cancel',method:'GET'});app.setClipboard('Must not run');")
        action.steps.append(ActionStep("insertText", ["template": "Must not run"]))
        action.afterSuccess = "archive"
        let execution = Task {
            let report = await runner.runAsync(action)
            transport.started.continuation.finish()
            return report
        }
        defer { execution.cancel() }
        var iterator = transport.started.stream.makeAsyncIterator()
        let started = await iterator.next()
        #expect(started != nil)
        execution.cancel()
        let report = await execution.value
        #expect(report.reason == .cancelled && report.result == .cancelled)
        #expect(transport.cancelled && report.successParameters.isEmpty && host.clipboard.isEmpty)
        #expect(editor.content == "Keep café 🐼")
        #expect(library.notes.first { $0.id == editor.noteID }?.isArchived == false)
        #expect(!runner.isRunning && !ActionRunner.isExecuting(in: library))
    }
}
