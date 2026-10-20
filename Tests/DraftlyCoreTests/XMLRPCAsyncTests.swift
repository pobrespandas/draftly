import Foundation
import Testing
@testable import DraftlyCore

private func xmlRPCIsMainThread() -> Bool { Thread.isMainThread }

@MainActor private final class XMLRPCWaitTransport {
    let started = AsyncStream.makeStream(of: String.self)
    private(set) var cancelled = false
    func request(_ payload: String) async -> String {
        started.continuation.yield(payload)
        do { try await Task.sleep(for: .seconds(30)) }
        catch { cancelled = Task.isCancelled }
        return #"{"value":{"success":false,"statusCode":0,"error":"Cancelled fixture"}}"#
    }
}

@Suite("Async XML-RPC transport") @MainActor
struct XMLRPCAsyncTests {
    private func value(_ text: String) throws -> [String: Any] {
        let decoded = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require((decoded as? [String: Any])?["value"] as? [String: Any])
    }

    @Test func requestAndReplyUseTheSharedXMLContract() async throws {
        let transport: @Sendable (String) async -> String = { payload in
            #expect(!xmlRPCIsMainThread())
            let decoded = try? JSONSerialization.jsonObject(with: Data(payload.utf8))
            let request = decoded as? [String: Any] ?? [:]
            #expect(request["method"] as? String == "POST")
            #expect(request["encoding"] as? String == "raw")
            #expect((request["headers"] as? [String: String])?["Content-Type"] == "text/xml; charset=utf-8")
            let body = request["data"] as? String ?? ""
            #expect(body.contains("<methodName>echo&lt;&amp;</methodName>"))
            #expect(body.contains("<string>café 🐼</string>") && body.contains("<boolean>1</boolean>"))
            return #"{"value":{"success":true,"statusCode":200,"responseText":"<methodResponse><params><param><value><string>café 🐼</string></value></param></params></methodResponse>"}}"#
        }
        let response = await ScriptXMLRPC.requestSerialized(#"{"url":"https://fixture.invalid/rpc","methodName":"echo<&","params":["café 🐼",true,7]}"#, transport: transport)
        let result = try value(response)
        #expect(result["success"] as? Bool == true)
        #expect(result["params"] as? [String] == ["café 🐼"])
        let (_, _, _, runner) = try makeAPIContext()
        runner.httpTransport = transport
        let action = makeAPIAction("const r=XMLRPC.request('https://fixture.invalid/rpc','echo<&',['café 🐼',true,7]);check(r instanceof XMLRPCResponse&&r.success&&r.statusCode===200&&r.params[0]==='café 🐼','script reply');")
        let report = await runner.runAsync(action)
        #expect(report.result.succeeded, Comment(rawValue: runner.message ?? ""))
    }

    @Test func faultsHTTPFailuresAndInvalidEnvelopesRemainExplicit() async throws {
        let request = #"{"url":"https://fixture.invalid/rpc","methodName":"echo","params":[]}"#
        let fault = await ScriptXMLRPC.requestSerialized(request) { _ in
            #"{"value":{"success":true,"statusCode":200,"responseText":"<methodResponse><fault><value><struct><member><name>faultCode</name><value><int>42</int></value></member><member><name>faultString</name><value><string>Denied</string></value></member></struct></value></fault></methodResponse>"}}"#
        }
        #expect(try value(fault)["faultCode"] as? Int == 42)
        let failed = await ScriptXMLRPC.requestSerialized(request) { _ in #"{"value":{"success":false,"statusCode":503}}"# }
        #expect(try value(failed)["success"] as? Bool == false)
        #expect(try value(failed)["statusCode"] as? Int == 503)
        for reply in ["not JSON", "{}", #"{"error":"Transport failed"}"#] {
            let result = await ScriptXMLRPC.requestSerialized(request) { _ in reply }
            let decoded = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
            #expect(decoded?["error"] is String)
        }
    }

    @Test(arguments: [false, true])
    func actionInterruptionCancelsTransportAndStopsLaterSteps(cancelled: Bool) async throws {
        let (library, editor, host, runner) = try makeAPIContext("Keep café 🐼")
        let original = editor.content
        let transport = XMLRPCWaitTransport()
        runner.httpTransport = { await transport.request($0) }
        runner.hostOperationTimeout = cancelled ? 10 : 5
        let action = makeAPIAction("XMLRPC.request('https://fixture.invalid/rpc','wait',[]);app.setClipboard('Must not run');")
        let execution = Task {
            let report = await runner.runAsync(action)
            transport.started.continuation.finish()
            return report
        }
        defer { execution.cancel() }
        var iterator = transport.started.stream.makeAsyncIterator()
        let next = await iterator.next()
        if next == nil {
            let report = await execution.value
            Issue.record(Comment(rawValue: "XML-RPC did not reach its transport: " + String(describing: report)))
        }
        let payload = try #require(next)
        #expect(payload.contains("methodCall"))
        let mainActorTurn = Task { @MainActor in true }
        #expect(await mainActorTurn.value)
        if cancelled { execution.cancel() }
        let report = await execution.value
        #expect(report.reason == (cancelled ? .cancelled : .timeout))
        #expect(transport.cancelled)
        #expect(host.clipboard.isEmpty && editor.content == original)
        #expect(library.notes.contains { $0.id == editor.noteID && $0.content == original })
        #expect(!runner.isRunning && !ActionRunner.isExecuting(in: library))
    }
}
