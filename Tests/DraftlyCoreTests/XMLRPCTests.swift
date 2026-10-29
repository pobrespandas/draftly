import Foundation
import Testing
@testable import DraftlyCore

@Suite("XML-RPC contracts")
struct XMLRPCTests {
    @Test func dateMetadataRequiresAValidExistingPath() throws {
        for values: [String: Any] in [
            ["params": ["not a date"], "__draftlyDatePaths": ["/params/0"]],
            ["params": [], "__draftlyDatePaths": ["/params/9"]]
        ] {
            #expect(throws: (any Error).self) { try ScriptXMLRPC.requestValues(values) }
        }
    }
    @Test func malformedBase64InNestedResponseCannotReportSuccess() throws {
        func response(_ value: String) -> [String: Any] {
            let xml = "<methodResponse><params><param><value><array><data><value><base64>" + value + "</base64></value></data></array></value></param></params></methodResponse>"
            return ScriptXMLRPC.response(Data(xml.utf8), statusCode: 200)
        }
        for invalid in ["%%%", "A===", "AA=A", "abcd!"] {
            let result = response(invalid)
            #expect(result["success"] as? Bool == false)
            #expect((result["params"] as? [Any])?.isEmpty == true)
            #expect(!(result["error"] as? String ?? "").isEmpty)
        }
        for valid in ["", "AP//", " YQ==\n"] {
            let result = response(valid)
            #expect(result["success"] as? Bool == true)
            let arrays = try #require(result["params"] as? [[String]])
            #expect(arrays == [[valid]])
        }
    }
    @Test func nonFiniteNumbersCannotProduceAnInvalidRequest() throws {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            #expect(throws: (any Error).self) {
                try ScriptXMLRPC.requestBody(method: "test", params: [["nested": [value]]])
            }
        }
        #expect(try ScriptXMLRPC.requestBody(method: "test", params: [1.5]).contains("<double>1.5</double>"))
    }
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
        "<methodResponse>discarded<params/></methodResponse>",
        "<methodResponse><params>discarded<param><value>kept</value></param></params></methodResponse>",
        "<methodResponse><params><param>discarded<value>kept</value></param></params></methodResponse>",
        "<methodResponse><params><param><value>discarded<string>kept</string></value></param></params></methodResponse>",
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

    @Test(arguments: [
        "<member><name>faultCode</name><value><int>42</int></value></member><member><name>faultString</name><value>Denied</value></member><member><name>discarded</name><value>extra</value></member>",
        "<member><name>faultString</name><value><string>Missing code</string></value></member>",
        "<member><name>faultCode</name><value><string>42</string></value></member><member><name>faultString</name><value><string>Wrong code type</string></value></member>",
        "<member><name>faultCode</name><value><int>42</int></value></member>",
        "<member><name>faultCode</name><value><int>42</int></value></member><member><name>faultString</name><value><int>7</int></value></member>"
    ])
    func invalidFaultFieldsAreNotPublishedAsValidFaultCodes(_ members: String) {
        let xml = "<methodResponse><fault><value><struct>" + members + "</struct></value></fault></methodResponse>"
        let result = ScriptXMLRPC.response(Data(xml.utf8), statusCode: 200)
        #expect(result["success"] as? Bool == false)
        #expect(result["faultCode"] == nil)
        #expect(!(result["error"] as? String ?? "").isEmpty)
    }

    @Test(arguments: [
        "<array/>", "<array><unexpected/></array>",
        "<array><data/><data/></array>", "<array><data><unexpected/></data></array>",
        "<array><data>discarded</data></array>",
        "<struct><unexpected><name>key</name><value>kept</value></unexpected></struct>",
        "<struct><member><name>first</name><name>discarded</name><value>kept</value></member></struct>",
        "<struct><member><name>key</name><value>first</value><value>discarded</value></member></struct>",
        "<struct><member><name><string>discarded</string></name><value>kept</value></member></struct>",
        "<struct>discarded</struct>",
        "<string><string>discarded</string></string>",
        "<int><string>discarded</string></int>",
        "<dateTime.iso8601><string>discarded</string></dateTime.iso8601>",
        "<base64><string>discarded</string></base64>",
        "<nil>discarded</nil>"
    ])
    func malformedValuesDoNotDiscardPartsAndReportSuccess(_ value: String) {
        let xml = "<methodResponse><params><param><value>" + value + "</value></param></params></methodResponse>"
        let result = ScriptXMLRPC.response(Data(xml.utf8), statusCode: 200)
        #expect(result["success"] as? Bool == false)
        #expect(result["statusCode"] as? Int == 200)
        #expect((result["params"] as? [Any])?.isEmpty == true)
        #expect(!(result["error"] as? String ?? "").isEmpty)
    }

    @Test func emptyAndNestedCompositeValuesKeepTheirTypesAndWhitespace() throws {
        let xml = """
        <methodResponse><params><param><value><struct>
          <member><name>empty array</name><value><array><data/></array></value></member>
          <member><name>empty record</name><value><struct/></value></member>
          <member><name>nested</name><value><array><data>
            <value><struct><member><name>café 🐼</name><value>  keep whitespace  </value></member></struct></value>
            <value><boolean>0</boolean></value><value><nil/></value>
          </data></array></value></member>
        </struct></value></param></params></methodResponse>
        """
        let result = ScriptXMLRPC.response(Data(xml.utf8), statusCode: 200)
        #expect(result["success"] as? Bool == true)
        let params = try #require(result["params"] as? [[String: Any]])
        let value = try #require(params.first)
        #expect((value["empty array"] as? [Any])?.isEmpty == true)
        #expect((value["empty record"] as? [String: Any])?.isEmpty == true)
        let nested = try #require(value["nested"] as? [Any])
        try #require(nested.count == 3)
        #expect((nested[0] as? [String: String])?["café 🐼"] == "  keep whitespace  ")
        #expect(nested[1] as? Bool == false && nested[2] is NSNull)
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
