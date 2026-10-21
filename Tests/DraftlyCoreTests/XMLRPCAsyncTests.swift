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

    @Test(arguments: ["ISO-8859-1", "UTF-16"])
    func decodedHTTPTextDoesNotReuseItsOriginalByteEncoding(_ encoding: String) async throws {
        let xml = """
        <?xml version="1.0" encoding="\(encoding)"?>
        <methodResponse><params><param><value><string>café &amp; mañana</string></value></param></params></methodResponse>
        """
        let transportReply = String(decoding: try JSONSerialization.data(withJSONObject: [
            "value": ["success": true, "statusCode": 200, "responseText": xml]
        ]), as: UTF8.self)
        let payload = #"{"url":"https://fixture.invalid/rpc","methodName":"echo","params":[]}"#
        let reply = await ScriptXMLRPC.requestSerialized(payload) { _ in transportReply }
        let result = try value(reply)
        #expect(result["success"] as? Bool == true)
        #expect(result["statusCode"] as? Int == 200)
        #expect(result["params"] as? [String] == ["café & mañana"])
        #expect(result["error"] == nil)

        let malformed = xml.replacingOccurrences(of: "</string>", with: "</int>")
        let malformedReply = String(decoding: try JSONSerialization.data(withJSONObject: [
            "value": ["success": true, "statusCode": 200, "responseText": malformed]
        ]), as: UTF8.self)
        let failure = try value(await ScriptXMLRPC.requestSerialized(payload) { _ in malformedReply })
        #expect(failure["success"] as? Bool == false)
        #expect(failure["statusCode"] as? Int == 200)
        #expect((failure["params"] as? [Any])?.isEmpty == true)
        #expect(!(failure["error"] as? String ?? "").isEmpty)
    }

    @Test(arguments: [false, true])
    func originalXMLBytesTakePrecedenceWhenHTTPHasNoCharset(utf16: Bool) async throws {
        let encoding = utf16 ? "UTF-16" : "ISO-8859-1"
        let expected = utf16 ? "café & mañana 🐼" : "café & mañana"
        let xml = "<?xml version=\"1.0\" encoding=\"\(encoding)\"?><methodResponse><params><param><value><string>\(expected.replacingOccurrences(of: "&", with: "&amp;"))</string></value></param></params></methodResponse>"
        let bytes: Data
        if utf16 {
            bytes = Data([0xFF, 0xFE]) + (try #require(xml.data(using: .utf16LittleEndian)))
        } else {
            bytes = try #require(xml.data(using: .isoLatin1))
        }
        let transportReply = String(decoding: try JSONSerialization.data(withJSONObject: [
            "responseBodyBase64": bytes.base64EncodedString(),
            "value": ["success": true, "statusCode": 200, "responseText": "", "headers": ["Content-Type": "text/xml"]]
        ]), as: UTF8.self)
        let payload = #"{"url":"https://fixture.invalid/rpc","methodName":"echo","params":[]}"#
        let result = try value(await ScriptXMLRPC.requestSerialized(payload) { _ in transportReply })
        #expect(result["success"] as? Bool == true)
        #expect(result["statusCode"] as? Int == 200)
        #expect(result["params"] as? [String] == [expected])
        #expect(result["error"] == nil)
        #expect(result["responseBodyBase64"] == nil)
    }

    @Test func malformedOriginalXMLByteEnvelopeDoesNotFallBackToSuccessfulText() async throws {
        let xml = "<methodResponse><params><param><value><string>Fallback must not succeed</string></value></param></params></methodResponse>"
        let transportReply = String(decoding: try JSONSerialization.data(withJSONObject: [
            "responseBodyBase64": "%%% invalid base64 %%%",
            "value": ["success": true, "statusCode": 200, "responseText": xml]
        ]), as: UTF8.self)
        let payload = #"{"url":"https://fixture.invalid/rpc","methodName":"echo","params":[]}"#
        let reply = await ScriptXMLRPC.requestSerialized(payload) { _ in transportReply }
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        #expect(envelope["value"] == nil)
        #expect(!(envelope["error"] as? String ?? "").isEmpty)
    }

    @Test(arguments: [true, false])
    func originalBytesDoNotHideEmptyXMLOrAnHTTPFailure(httpSucceeded: Bool) async throws {
        let valid = Data("<methodResponse><params/></methodResponse>".utf8).base64EncodedString()
        let reply: [String: Any] = [
            "responseBodyBase64": httpSucceeded ? "" : valid,
            "value": ["success": httpSucceeded, "statusCode": httpSucceeded ? 200 : 503,
                      "error": httpSucceeded ? "" : "HTTP failure café"]
        ]
        let result = try ScriptXMLRPC.responseEnvelope(reply)
        #expect(result["success"] as? Bool == false)
        #expect(result["statusCode"] as? Int == (httpSucceeded ? 200 : 503))
        #expect((result["params"] as? [Any])?.isEmpty == true)
        if httpSucceeded { #expect(!(result["error"] as? String ?? "").isEmpty) }
        else { #expect(result["error"] as? String == "HTTP failure café") }
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
            return #"{"value":{"success":true,"statusCode":200,"responseText":"<methodResponse><params><param><value><string><![CDATA[café 🐼]]></string></value></param></params></methodResponse>"}}"#
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
        let (_, _, _, runner) = try makeAPIContext()
        runner.httpTransport = { _ in
            #"{"value":{"success":true,"statusCode":200,"responseText":"<methodResponse><fault><value><struct><member><name>faultCode</name><value><int>-42</int></value></member><member><name>faultString</name><value><string>Denied café 🐼</string></value></member></struct></value></fault></methodResponse>"}}"#
        }
        let action = makeAPIAction("const r=XMLRPC.request('https://fixture.invalid/rpc','fault',[]);check(r instanceof XMLRPCResponse&&!r.success&&r.statusCode===200&&r.faultCode===-42&&r.error==='Denied café 🐼'&&r.params.length===0,'typed fault fields');")
        #expect((await runner.runAsync(action)).result.succeeded)
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
