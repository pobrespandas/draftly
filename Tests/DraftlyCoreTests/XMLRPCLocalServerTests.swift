import Foundation
import Testing
@testable import DraftlyCore

@Suite("XML-RPC loopback server")
struct XMLRPCLocalServerTests {
    @Test func cancellationClosesTheRealPendingHTTPConnection() async throws {
        let server = try LocalXMLRPCServer(wait: true)
        defer { server.stop() }
        let payload = #"{"url":"http://127.0.0.1:\#(server.port)/wait","methodName":"wait","params":[]}"#
        let request = Task { await ScriptXMLRPC.requestSerialized(payload) }
        defer { request.cancel() }
        let received = try #require(try JSONSerialization.jsonObject(with: server.readLine()) as? [String: Any])
        #expect(received["path"] as? String == "/wait")
        request.cancel()
        let reply = await request.value
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        #expect(envelope["value"] == nil)
        #expect(!(envelope["error"] as? String ?? "").isEmpty)
        let event = try #require(try JSONSerialization.jsonObject(with: server.readLine()) as? [String: Bool])
        #expect(event["disconnected"] == true)
        try server.waitForExit()
        #expect(server.process.terminationStatus == 0)
    }

    @Test func realHTTPPreservesXMLBodyUnicodeFaultsAndInvalidResponseErrors() async throws {
        let server = try LocalXMLRPCServer()
        defer { server.stop() }
        let process = server.process
        let output = server.output
        let port = server.port
        for path in ["/echo", "/fault", "/invalid"] {
            let request: [String: Any] = ["url": "http://127.0.0.1:\(port)\(path)",
                "methodName": "example.echo", "params": ["café 🐼 <&", true, 7]]
            let payload = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
            let reply = await ScriptXMLRPC.requestSerialized(payload)
            let envelope = try #require(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
            let value = try #require(envelope["value"] as? [String: Any])
            #expect(value["statusCode"] as? Int == 200)
            if path == "/echo" {
                #expect(value["success"] as? Bool == true)
                #expect(value["params"] as? [String] == ["café 🐼 <&"])
            } else {
                #expect(value["success"] as? Bool == false)
                #expect(!(value["error"] as? String ?? "").isEmpty)
                if path == "/fault" {
                    #expect(value["faultCode"] as? Int == 42)
                    #expect(value["error"] as? String == "Denied café 🐼")
                }
            }
        }
        try server.waitForExit()
        #expect(process.terminationStatus == 0)
        let requests = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n")
        try #require(requests.count == 3)
        for line in requests {
            let request = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String])
            #expect(request["contentType"] == "text/xml; charset=utf-8")
            let body = request["body"] ?? ""
            #expect(body.contains("<methodName>example.echo</methodName>"))
            #expect(body.contains("<string>café 🐼 &lt;&amp;</string>"))
            #expect(body.contains("<boolean>1</boolean>") && body.contains("<i8>7</i8>"))
        }
    }

    @Test func serverExitBeforeWaitingIsRetainedAndAnExpiredWaitIsNotAnExit() throws {
        let exit = LocalServerExitSignal()
        #expect(throws: LocalServerExitSignal.WaitError.deadline) { try exit.wait(until: .now()) }
        exit.signal()
        try exit.wait(until: .now())
        try exit.wait(until: .now())
    }
}

private final class LocalServerExitSignal: Sendable {
    enum WaitError: Error { case deadline }
    private let completion = DispatchSemaphore(value: 0)

    func signal() { completion.signal() }

    func wait(until deadline: DispatchTime) throws {
        guard completion.wait(timeout: deadline) == .success else { throw WaitError.deadline }
        // Keep the exit event available for another observer.
        completion.signal()
    }
}

private final class LocalXMLRPCServer {
    let process = Process()
    let output = Pipe()
    private let exit = LocalServerExitSignal()
    private(set) var port = 0

    init(wait: Bool = false) throws {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("xmlrpc-server.py")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", fixture.path] + (wait ? ["--wait"] : [])
        process.standardOutput = output
        process.standardError = Pipe()
        let exit = exit
        process.terminationHandler = { _ in exit.signal() }
        try process.run()
        try output.fileHandleForWriting.close()
        do { port = try #require(Int(String(decoding: readLine(), as: UTF8.self))) }
        catch { stop(); throw error }
    }

    func readLine() throws -> Data {
        var line = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
            if byte == Data([10]) { break }
            line.append(byte)
        }
        return line
    }

    func waitForExit() throws { try exit.wait(until: .now() + 2) }

    func stop() {
        if process.isRunning { process.terminate() }
        try? output.fileHandleForReading.close()
    }
}
