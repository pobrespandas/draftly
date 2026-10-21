import Foundation
import Testing
@testable import DraftlyCore

@Suite("HTTP response contracts")
struct HTTPResponseContractTests {
    @Test(arguments: ["iso-8859-1", "utf-16le", "utf-16be"])
    func responseTextUsesTheDeclaredCharset(charset: String) throws {
        let encoding: String.Encoding = switch charset {
        case "iso-8859-1": .isoLatin1
        case "utf-16le": .utf16LittleEndian
        default: .utf16BigEndian
        }
        let body = try #require("café".data(using: encoding))
        let response = try #require(HTTPURLResponse(url: URL(string: "https://fixture.invalid/text")!,
            statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain; charset=\(charset)"]))
        #expect(response.textEncodingName?.lowercased() == charset)
        let value = ScriptHTTP.responseValue(data: body, response: response, error: nil)
        #expect(value["responseText"] as? String == "café")
        #expect(value["success"] as? Bool == true)
    }

    @Test func absentUnknownOrInvalidCharsetKeepsTheUTF8Fallback() throws {
        for contentType in ["text/plain", "text/plain; charset=neutral-unknown", "text/plain; charset=utf-8"] {
            let response = try #require(HTTPURLResponse(url: URL(string: "https://fixture.invalid/text")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType]))
            let valid = ScriptHTTP.responseValue(data: Data("café 🐼".utf8), response: response, error: nil)
            #expect(valid["responseText"] as? String == "café 🐼")
            let invalid = ScriptHTTP.responseValue(data: Data([0xFF]), response: response, error: nil)
            #expect(invalid["responseText"] as? String == "")
        }
    }

    @Test func JSONArraysAndFragmentsRemainTyped() throws {
        for json in [#"[{"text":"café 🐼"},false,3.5]"#, #""café 🐼""#, "3.5", "true", "null"] {
            let body = Data(json.utf8)
            let response = try #require(HTTPURLResponse(url: URL(string: "https://fixture.invalid/json")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]))
            let value = ScriptHTTP.responseValue(data: body, response: response, error: nil)
            let actual = try #require(value["responseData"])
            switch json {
            case "3.5": #expect(actual as? Double == 3.5)
            case "true": #expect(actual as? Bool == true)
            case "null": #expect(actual is NSNull)
            case #""café 🐼""#: #expect(actual as? String == "café 🐼")
            default:
                let array = try #require(actual as? [Any])
                try #require(array.count == 3)
                #expect((array[0] as? [String: String])?["text"] == "café 🐼")
                #expect(array[1] as? Bool == false && array[2] as? Double == 3.5)
            }
            #expect(value["responseText"] as? String == json)
            #expect(value["error"] == nil)
        }
    }

    @Test(arguments: [200, 204])
    func bodylessResponsesKeepStatusHeadersAndEmptyValues(status: Int) throws {
        let response = try #require(HTTPURLResponse(url: URL(string: "https://fixture.invalid/bodyless")!,
            statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["X-Neutral": "kept", "Set-Cookie": "neutral=value"]))
        let value = ScriptHTTP.responseValue(data: nil, response: response, error: nil)
        #expect(value["success"] as? Bool == true && value["statusCode"] as? Int == status)
        #expect(value["responseText"] as? String == "" && value["responseData"] is NSNull)
        let headers = try #require(value["headers"] as? [String: String])
        #expect(headers.first { $0.key.lowercased() == "x-neutral" }?.value == "kept")
        #expect(headers.first { $0.key.lowercased() == "set-cookie" }?.value == "neutral=value")
        #expect(value["error"] == nil)
    }

    @Test(arguments: [false, true]) @MainActor
    func responseConstructorExposesInitialFieldValues(worker: Bool) async throws {
        let (_, _, _, runner) = try makeAPIContext()
        let action = makeAPIAction("""
        const response=new HTTPResponse();
        check(response instanceof HTTPResponse && response.success===false && response.statusCode===0,'default status');
        check(response.responseText==='' && Object.keys(response.headers).length===0,'empty text and headers');
        check(response.error===undefined && response.otherData===undefined,'optional fields');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
    }

}
