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
    @Test func mixedCDATAAndTextKeepUnicodeInStringsValuesAndMemberNames() throws {
        let xml = """
        <methodResponse><params>
        <param><value><string>before<![CDATA[<&🐼]]>after &amp;</string></value></param>
        <param><value><![CDATA[café <tag> 🐼]]></value></param>
        <param><value><struct><member><name><![CDATA[key café 🐼]]></name><value><string>kept</string></value></member></struct></value></param>
        </params></methodResponse>
        """
        let result = ScriptXMLRPC.response(Data(xml.utf8), statusCode: 200)
        #expect(result["success"] as? Bool == true)
        let values = try #require(result["params"] as? [Any])
        try #require(values.count == 3)
        #expect(values[0] as? String == "before<&🐼after &")
        #expect(values[1] as? String == "café <tag> 🐼")
        #expect((values[2] as? [String: String])?["key café 🐼"] == "kept")
    }

    @Test func cdataUsesTheParserEncodingAndPreservesFaultMessages() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><methodResponse><params><param><value><string><![CDATA[café <tag>]]></string></value></param></params></methodResponse>"
        let bytes = try #require(xml.data(using: .isoLatin1))
        let values = try #require(ScriptXMLRPC.response(bytes, statusCode: 200)["params"] as? [String])
        #expect(values == ["café <tag>"])
        let fault = "<methodResponse><fault><value><struct><member><name>faultCode</name><value><int>42</int></value></member><member><name>faultString</name><value><string><![CDATA[Denied café 🐼 <&]]></string></value></member></struct></value></fault></methodResponse>"
        let result = ScriptXMLRPC.response(Data(fault.utf8), statusCode: 200)
        #expect(result["success"] as? Bool == false)
        #expect(result["faultCode"] as? Int64 == 42)
        #expect(result["error"] as? String == "Denied café 🐼 <&")
    }

    @Test(arguments: [
        "<methodResponse><params/><params/></methodResponse>",
        "<methodResponse><fault/><params/></methodResponse>",
        "<methodResponse><unexpected/><params/></methodResponse>",
        "<methodResponse><params><param><value>first</value><value>ignored</value></param></params></methodResponse>",
        "<methodResponse><params><param><value><string>first</string><int>2</int></value></param></params></methodResponse>"
    ])
    func ambiguousResponseStructuresDoNotReportSuccess(_ xml: String) {
        let result = ScriptXMLRPC.response(Data(xml.utf8), statusCode: 200)
        #expect(result["success"] as? Bool == false)
        #expect(!(result["error"] as? String ?? "").isEmpty)
        #expect((result["params"] as? [Any])?.isEmpty == true)
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
