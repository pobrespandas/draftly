import Foundation
import Testing
@testable import DraftlyCore

@Suite("XML-RPC contracts")
struct XMLRPCTests {
    @Test func nestedValuesEscapeAndRoundTrip() throws {
        let body = try ScriptXMLRPC.requestBody(method: "example<&", params: [true, 7, 1.5, "ñ<&", ["items": ["🐼", false]]])
        #expect(body.contains("<methodName>example&lt;&amp;</methodName>"))
        #expect(body.contains("<boolean>1</boolean>"))
        #expect(body.contains("<double>1.5</double>"))
        let params = try #require(body.range(of: "<params>"))
        let xml = "<methodResponse>" + body[params.lowerBound...].replacingOccurrences(of: "</methodCall>", with: "</methodResponse>")
        let result = ScriptXMLRPC.response(Data(xml.utf8), statusCode: 200)
        #expect(result["success"] as? Bool == true)
        let values = try #require(result["params"] as? [Any])
        #expect(values.count == 5)
        #expect(values[3] as? String == "ñ<&")
        #expect((values[4] as? [String: Any])?["items"] as? [Any] != nil)
    }
    @Test func faultsAndMalformedResponsesNeverReportSuccess() {
        let fault = "<methodResponse><fault><value><struct><member><name>faultCode</name><value><int>42</int></value></member><member><name>faultString</name><value><string>Denied</string></value></member></struct></value></fault></methodResponse>"
        let result = ScriptXMLRPC.response(Data(fault.utf8), statusCode: 200)
        #expect(result["success"] as? Bool == false)
        #expect(result["faultCode"] as? Int64 == 42)
        #expect(result["error"] as? String == "Denied")
        #expect(ScriptXMLRPC.response(Data("<broken>".utf8), statusCode: 200)["success"] as? Bool == false)
        #expect(ScriptXMLRPC.response(Data("<methodResponse><params/></methodResponse>".utf8), statusCode: 500)["success"] as? Bool == false)
    }
}
