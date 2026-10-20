import Foundation
import Testing
@testable import DraftlyCore

@Suite("XML-RPC loopback server")
struct XMLRPCLocalServerTests {
    @Test func realHTTPPreservesXMLBodyUnicodeFaultsAndInvalidResponseErrors() async throws {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("xmlrpc-server.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", fixture.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        try output.fileHandleForWriting.close()
        defer {
            if process.isRunning { process.terminate() }
            try? output.fileHandleForReading.close()
        }
        var portData = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
            if byte == Data([10]) { break }
            portData.append(byte)
        }
        let port = try #require(Int(String(decoding: portData, as: UTF8.self)))
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
        process.waitUntilExit()
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
}
