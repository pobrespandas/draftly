import Foundation
import Testing
@testable import DraftlyCore

@Suite("HTTP loopback contracts")
struct ScriptHTTPLocalServerTests {
    private func request(_ values: [String: Any], worker: Bool) async throws -> [String: Any] {
        if !worker { return ScriptHTTP.request(values) }
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
        let encoded = await ScriptHTTP.requestSerialized(payload)
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        return try #require(envelope["value"] as? [String: Any])
    }

    @Test(arguments: [false, true], [(false, 301), (false, 302), (true, 301), (true, 302)])
    func redirectOptionControlsActualDestination(worker: Bool, option: (Bool, Int)) async throws {
        let (follow, status) = option
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let path = status == 301 ? "/redirect-permanent" : "/redirect"
        let response = try await request(["url": server.url(path), "followRedirects": follow], worker: worker)
        #expect(response["statusCode"] as? Int == (follow ? 200 : status))
        #expect(response["success"] as? Bool == follow)
        #expect(try server.event()["path"] as? String == path)
        if follow {
            #expect((response["responseData"] as? [String: String])?["text"] == "café 🐼")
            #expect(try server.event()["path"] as? String == "/json")
        } else {
            #expect(response["responseText"] as? String == "")
            #expect(response["responseData"] is NSNull)
        }
    }

    @Test(arguments: [false, true], ["json", "form"])
    func actualRequestPreservesBodyQueryHeadersAndAuthentication(worker: Bool, encoding: String) async throws {
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let text = "café 🐼 +&=\"\nText"
        let response = try await request(["url": server.url("/echo?existing=one+two&literal=one%2Btwo"), "method": "POST",
            "parameters": ["q": text, "empty": ""], "headers": ["X-Neutral": "fixture"],
            "username": "neutral", "password": "fixture", "encoding": encoding, "data": ["text": text]], worker: worker)
        #expect(response["success"] as? Bool == true)
        let echo = try #require(response["responseData"] as? [String: Any])
        #expect(echo["query"] as? [String: [String]] == ["existing": ["one two"], "literal": ["one+two"], "q": [text], "empty": [""]])
        #expect(echo["method"] as? String == "POST" && echo["custom"] as? String == "fixture")
        #expect(echo["authorization"] as? String == "Basic " + Data("neutral:fixture".utf8).base64EncodedString())
        let body = try #require(echo["body"] as? String)
        if encoding == "json" {
            #expect(echo["contentType"] as? String == "application/json")
            #expect(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: String] == ["text": text])
        } else {
            #expect(echo["contentType"] as? String == "application/x-www-form-urlencoded")
            let decoded = URLComponents(string: "http://neutral.invalid/?" + body)?.queryItems
            #expect(decoded == [URLQueryItem(name: "text", value: text)])
        }
    }

    @Test(arguments: [false, true], ["/error", "/invalid-json", "/disconnect"])
    func actualErrorsDoNotFabricateParsedData(worker: Bool, path: String) async throws {
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let response = try await request(["url": server.url(path)], worker: worker)
        #expect(response["success"] as? Bool == (path == "/invalid-json"))
        #expect(response["responseData"] is NSNull)
        if path == "/disconnect" {
            #expect(response["statusCode"] as? Int == 0)
            #expect(!(response["error"] as? String ?? "").isEmpty)
        } else {
            #expect(response["statusCode"] as? Int == (path == "/error" ? 503 : 200))
            #expect(response["responseText"] as? String == (path == "/error" ? "Unavailable café 🐼" : "{invalid café 🐼"))
            #expect(response["error"] == nil)
        }
    }

    @Test(arguments: [false, true], ["/latin1", "/utf16-json"])
    func actualResponseTextUsesDeclaredEncoding(worker: Bool, path: String) async throws {
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let response = try await request(["url": server.url(path)], worker: worker)
        #expect(response["success"] as? Bool == true)
        if path == "/latin1" {
            #expect(response["responseText"] as? String == "café")
        } else {
            #expect((response["responseText"] as? String)?.contains("café 🐼") == true)
            #expect((response["responseData"] as? [String: String])?["text"] == "café 🐼")
        }
    }

    @Test(arguments: [false, true], [("GET", "/bodyless", 204), ("HEAD", "/json", 200)])
    func actualBodylessResponsesPreserveMetadata(worker: Bool, target: (String, String, Int)) async throws {
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let response = try await request(["url": server.url(target.1), "method": target.0], worker: worker)
        #expect(response["success"] as? Bool == true && response["statusCode"] as? Int == target.2)
        #expect(response["responseText"] as? String == "" && response["responseData"] is NSNull)
        #expect(response["error"] == nil)
        let headers = try #require(response["headers"] as? [String: String])
        #expect(headers.first { $0.key.lowercased() == "x-neutral" }?.value == "yes")
        #expect(headers.first { $0.key.lowercased() == "set-cookie" }?.value == "neutral=fixture")
    }

    @Test(arguments: [false, true], [
        "/xml-latin1", "/xml-utf16", "/xml-latin1-no-charset", "/xml-utf16-no-charset",
        "/xml-utf16le-no-charset", "/xml-utf16be-no-charset"
    ])
    @MainActor
    func actualXMLRPCResponsePreservesTheDecodedHTTPCharset(worker: Bool, path: String) async throws {
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let fixture = try ScriptTestFixture(content: "Neutral XML-RPC", host: APIContractHost())
        let action = ScriptTestAction.make("""
        check(new XMLRPC() instanceof XMLRPC,'XML-RPC constructor');
        const initial=new XMLRPCResponse();
        check(initial instanceof XMLRPCResponse && initial.success===false && initial.statusCode===0,'response constructor status');
        check(Array.isArray(initial.params) && initial.params.length===0 && initial.error===undefined && initial.faultCode===undefined,'response constructor fields');
        initial.params.push('Local mutation');
        check(new XMLRPCResponse().params.length===0,'independent response instances');
        const r=XMLRPC.request('\(server.url(path))','example.echo',[]);
        check(r instanceof XMLRPCResponse && r.success && r.statusCode===200,'typed XML-RPC response');
        check(r.params.length===1 && r.params[0]==='café & mañana','HTTP and XML encodings agree');
        check(r.error===undefined && r.faultCode===undefined,'no fabricated error or fault');
        """, name: "Encoded XML-RPC")
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
    }

    @Test(arguments: [false, true], [-42, 0, 42])
    @MainActor
    func actualXMLRPCFaultKeepsTypedFields(worker: Bool, code: Int) async throws {
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let fixture = try ScriptTestFixture(content: "Neutral XML-RPC", host: APIContractHost())
        let action = ScriptTestAction.make("""
        const r=XMLRPC.request('\(server.url("/xml-fault?code=\(code)"))','example.fault',[]);
        check(r instanceof XMLRPCResponse && r.success===false && r.statusCode===200,'HTTP success with XML fault');
        check(typeof r.faultCode==='number' && r.faultCode===\(code),'fault code type and sign');
        check(r.error==='Denied café 🐼','fault message');
        check(Array.isArray(r.params) && r.params.length===0,'no success parameters on a fault');
        """, name: "XML-RPC fault")
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
    }

    @Test(arguments: [false, true], [
        "/xml-malformed-array", "/xml-malformed-struct", "/xml-malformed-fault",
        "/xml-http-failure", "/bodyless", "/disconnect"
    ])
    @MainActor
    func actualXMLRPCMalformedOrFailedResponsesDoNotReportSuccess(worker: Bool, path: String) async throws {
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let fixture = try ScriptTestFixture(content: "Neutral XML-RPC", host: APIContractHost())
        let status = ["/xml-http-failure": 503, "/bodyless": 204, "/disconnect": 0][path] ?? 200
        let action = ScriptTestAction.make("""
        const r=XMLRPC.request('\(server.url(path))','example.invalid',[]);
        check(r instanceof XMLRPCResponse && r.success===false && r.statusCode===\(status),'failed response preserves HTTP status');
        check(typeof r.error==='string' && r.error.length>0,'explicit response error');
        check(r.faultCode===undefined,'no invented fault code');
        check(Array.isArray(r.params) && r.params.length===0,'no fabricated success parameters');
        """, name: "XML-RPC invalid response")
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
    }

    @Test(arguments: [false, true], [false, true])
    func responseBytesRequireAnOptInAndStayOutsideThePublicValue(worker: Bool, charset: Bool) async throws {
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let path = charset ? "/xml-latin1" : "/xml-latin1-no-charset"
        for include in [false, true] {
            let values: [String: Any] = ["url": server.url(path), "includeResponseBytes": include]
            let envelope: [String: Any]
            if worker {
                let payload = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
                envelope = try #require(JSONSerialization.jsonObject(with: Data(await ScriptHTTP.requestSerialized(payload).utf8)) as? [String: Any])
            } else { envelope = ScriptHTTP.requestEnvelope(values) }
            let value = try #require(envelope["value"] as? [String: Any])
            #expect(value["success"] as? Bool == true && value["statusCode"] as? Int == 200)
            #expect(value["responseBodyBase64"] == nil)
            if include && !charset {
                let encoded = try #require(envelope["responseBodyBase64"] as? String)
                let bytes = try #require(Data(base64Encoded: encoded))
                #expect(String(data: bytes, encoding: .isoLatin1)?.contains("café") == true)
            } else { #expect(envelope["responseBodyBase64"] == nil) }
        }
        let fixture = try await ScriptTestFixture(content: "Neutral HTTP", host: APIContractHost())
        let action = ScriptTestAction.make("""
        const r=HTTP.create().request({url:'\(server.url(path))',includeResponseBytes:true});
        check(r instanceof HTTPResponse && r.success,'public HTTP response');
        check(!Object.prototype.hasOwnProperty.call(r,'responseBodyBase64'),'transport bytes stay private');
        """, name: "Private response bytes")
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker))
    }

    @Test(arguments: ["cancel", "timeout"])
    func interruptedRequestClosesTheActualConnection(_ interruption: String) async throws {
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let payload = #"{"url":"\#(server.url("/wait"))","timeout":\#(interruption == "timeout" ? 0.2 : 5)}"#
        let task = Task { await ScriptHTTP.requestSerialized(payload) }
        defer { task.cancel() }
        #expect(try server.event()["path"] as? String == "/wait")
        if interruption == "cancel" { task.cancel() }
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(await task.value.utf8)) as? [String: Any])
        let response = try #require(envelope["value"] as? [String: Any])
        #expect(response["success"] as? Bool == false && response["statusCode"] as? Int == 0)
        #expect(!(response["error"] as? String ?? "").isEmpty)
        #expect(try server.event()["disconnected"] as? Bool == true)
    }

    @Test(arguments: [false, true]) @MainActor
    func actualScriptingRequestsReturnHTTPResponseAndUseClientOptions(worker: Bool) async throws {
        let server = try LoopbackHTTPServer(); defer { server.stop() }
        let fixture = try ScriptTestFixture(content: "Neutral HTTP", host: APIContractHost())
        let action = ScriptTestAction.make("""
        const client=\(worker ? "HTTP.create()" : "new HTTP()");
        check(client instanceof HTTP && client.timeout===60 && client.followRedirects===true,'constructor defaults');
        check(HTTP.create() instanceof HTTP,'factory type');
        client.timeout=5;client.followRedirects=false;
        const stopped=client.request({url:'\(server.url("/redirect"))',method:'GET'});
        check(stopped instanceof HTTPResponse && stopped.statusCode===302 && stopped.success===false,'redirect disabled');
        client.followRedirects=true;client.timeout=900;
        const response=client.request({url:'\(server.url("/redirect"))',method:'GET'});
        check(response instanceof HTTPResponse && response.success && response.statusCode===200,'redirect followed');
        check(response.responseData.text==='café 🐼' && response.responseText.includes('café 🐼'),'Unicode JSON');
        check(Object.entries(response.headers).some(([key,value])=>key.toLowerCase()==='x-neutral' && value==='yes'),'response headers');
        check(response.error===undefined && response.otherData===undefined,'no invented error or extra data');
        client.timeout=0;
        const invalid=client.request({url:'\(server.url("/must-not-open"))',method:'GET'});
        check(invalid instanceof HTTPResponse && invalid.success===false && invalid.statusCode===0,'invalid timeout response');
        check(invalid.error==='The HTTP timeout must be positive and finite.','explicit timeout error');
        """, name: "Loopback HTTP")
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
    }
}

private final class LoopbackHTTPServer {
    let process = Process()
    private let output = Pipe()
    private let terminated = DispatchSemaphore(value: 0)
    private let port: Int

    init() throws {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("http-server.py")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", fixture.path]
        process.standardOutput = output; process.standardError = Pipe()
        let terminated = terminated
        process.terminationHandler = { _ in terminated.signal() }
        try process.run()
        try output.fileHandleForWriting.close()
        do { port = try #require(Int(String(decoding: Self.readLine(output.fileHandleForReading), as: UTF8.self))) }
        catch { process.terminate(); throw error }
    }

    func url(_ path: String) -> String { "http://127.0.0.1:\(port)" + path }

    func event() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Self.readLine(output.fileHandleForReading)) as? [String: Any])
    }

    private static func readLine(_ file: FileHandle) throws -> Data {
        var line = Data()
        while let byte = try file.read(upToCount: 1), !byte.isEmpty {
            if byte == Data([10]) { break }
            line.append(byte)
        }
        return line
    }

    func stop() {
        if process.isRunning { process.terminate() }
        if terminated.wait(timeout: .now() + 2) == .timedOut {
            Issue.record("The loopback server did not report termination within two seconds.")
        }
        try? output.fileHandleForReading.close()
    }
}
