import Foundation
import Testing
@testable import AgentContracts

@Suite("Typed direct native requests")
struct AgentNativeSchemaTests {
    private func request(_ operation: String, _ parameters: [String: AgentJSONValue] = [:]) -> AgentRequest {
        .init(requestID: UUID(), libraryID: UUID(), operation: operation, parameters: parameters)
    }

    @Test func httpInputsKeepExplicitBinaryAndRejectHeaderOrURLOverrides() throws {
        let good = request("native.http", ["url": .string("https://fixture.invalid/qa"), "method": .string("PATCH"), "headersJSON": .string("{\"Authorization\":\"Bearer explicit\"}"), "bodyBase64": .string("AID/")])
        let values = try AgentNativeSchemas.validatedParameters(for: good)
        #expect(values["followRedirects"] == .bool(false) && values["bodyBase64"] == .string("AID/"))
        let textBody = request("native.http", ["url": .string("https://fixture.invalid/qa"), "bodyText": .string("café\r\n🐼")])
        #expect(try AgentNativeSchemas.validatedParameters(for: textBody)["bodyText"] == .string("café\r\n🐼"))
        for fields: [String: AgentJSONValue] in [
            ["url": .string("file:///tmp/private")], ["url": .string("https://user:password@fixture.invalid/")],
            ["method": .string("GET\r\nInjected")], ["headersJSON": .string("{\"Host\":\"other.invalid\"}")],
            ["headersJSON": .string(#"{"X-Value":"one\r\ntwo"}"#)],
            ["headersJSON": .string("{\"X-Test\":\"a\",\"x-test\":\"b\"}")],
            ["bodyText": .string("text"), "bodyBase64": .string("AID/")], ["bodyBase64": .string("AID/\n")],
            ["timeout": .integer(0)], ["bodyText": .string(String(repeating: "🐼", count: 20_000))]
        ] {
            var input = ["url": AgentJSONValue.string("https://fixture.invalid/qa")]
            input.merge(fields) { _, new in new }
            #expect(throws: (any Error).self) { try AgentNativeSchemas.validatedParameters(for: request("native.http", input)) }
        }
    }

    @Test func httpResultsAreTransientAndPreserveBinaryAndFailureStatus() throws {
        let response: AgentJSONValue = .object(["success": .bool(false), "statusCode": .integer(503), "headersJSON": .string("{}"), "responseText": .string(""), "bodyBase64": .string("AID/")])
        try AgentNativeSchemas.validateResult(["response": response, "resultAvailable": .bool(true)], for: "native.http")
        #expect(AgentNativeSchemas.unavailableResult(for: "native.http") == ["response": .null, "resultAvailable": .bool(false)])
        #expect(throws: (any Error).self) { try AgentNativeSchemas.validateResult(["response": response, "resultAvailable": .bool(false)], for: "native.http") }
    }

    @Test func concreteSchemasDoNotPublishOtherNativeContracts() {
        #expect(AgentNativeSchemas.operationNames == ["native.clipboardRead", "native.clipboardWrite", "native.htmlToMarkdown", "native.htmlPreview",
            "native.share", "native.print", "native.openURL", "native.speak", "native.dictate", "native.transcribe",
            "native.location", "native.shell", "native.appleScript", "native.shortcut", "native.http", "native.models"])
        #expect(AgentNativeSchemas.operationNames.isSubset(of: AgentOperationSchemas.operationNames))
        #expect(AgentOperationSchemas.schema(for: "native.xmlrpc") == nil)
    }

    @Test(arguments: ["native.clipboardWrite", "native.share", "native.print", "native.speak"])
    func textInputsAreBoundedAndRejectHostOverrides(operation: String) throws {
        _ = try AgentOperationSchemas.validatedParameters(for: request(operation, ["text": .string("café 🐼 é")]))
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: request(operation, ["text": .string("Neutral"), "operation": .string("shellScript")]))
        }
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: request(operation, ["text": .string(String(repeating: "x", count: 65_537))]))
        }
    }

    @Test(arguments: ["file:///tmp/private", "javascript:alert(1)", "data:text/plain,private", "relative/path", "https:"])
    func unsafeOrIncompleteURLsFailBeforeReview(url: String) {
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: request("native.openURL", ["url": .string(url)]))
        }
    }

    @Test(arguments: ["native.clipboardRead", "native.htmlToMarkdown", "native.dictate", "native.transcribe", "native.shortcut"])
    func textResultAvailabilityIsExplicitAndConsistent(operation: String) throws {
        try AgentOperationSchemas.validateResult(["text": .string("café 🐼"), "resultAvailable": .bool(true)], for: operation)
        try AgentOperationSchemas.validateResult(["text": .null, "resultAvailable": .bool(false)], for: operation)
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validateResult(["text": .string("PRIVATE"), "resultAvailable": .bool(false)], for: operation)
        }
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validateResult(["text": .null, "resultAvailable": .bool(true)], for: operation)
        }
    }

    @Test(arguments: ["native.dictate", "native.transcribe", "native.location"])
    func captureRequestsCannotInjectAPathOrAuthorization(operation: String) throws {
        _ = try AgentOperationSchemas.validatedParameters(for: request(operation))
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: request(operation, ["path": .string("/private/audio")]))
        }
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: request(operation, ["authorized": .bool(true)]))
        }
    }

    @Test func automationInputsKeepLiteralDataAndRejectIgnoredArguments() throws {
        _ = try AgentOperationSchemas.validatedParameters(for: request("native.shell", ["source": .string("printf '%s' \"$1\""),
            "arguments": .array([.string("café 🐼 $(literal)\n")])]))
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: request("native.shell", ["source": .string("neutral"), "arguments": .array([.string("bad\0argument")])]))
        }
        _ = try AgentOperationSchemas.validatedParameters(for: request("native.appleScript", ["source": .string("neutral"),
            "subroutine": .string("qa"), "argumentsJSON": .string(#"["café 🐼",{"list":[true,null,1e100]}]"#)]))
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: request("native.appleScript", ["source": .string("neutral"), "argumentsJSON": .string("[1]")]))
        }
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: request("native.appleScript", ["source": .string("neutral"), "argumentsJSON": .string("{}")]))
        }
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: request("native.shortcut", ["name": .string("QA"), "waitForResponse": .bool(false)]))
        }
    }

    @Test func privateStructuredResultsValidateShapeAndAvailability() throws {
        let coordinates: AgentJSONValue = .object(["latitude": .integer(90), "longitude": .integer(-180)])
        try AgentOperationSchemas.validateResult(["coordinates": coordinates, "resultAvailable": .bool(true)], for: "native.location")
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validateResult(["coordinates": .object(["latitude": .integer(91), "longitude": .integer(0)]), "resultAvailable": .bool(true)], for: "native.location")
        }
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validateResult(["coordinates": coordinates, "resultAvailable": .bool(false)], for: "native.location")
        }
        try AgentOperationSchemas.validateResult(["process": .object(["status": .integer(7), "stdout": .string("café 🐼"), "stderr": .string("")]), "resultAvailable": .bool(true)], for: "native.shell")
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validateResult(["process": .object(["status": .integer(Int64.max), "stdout": .string(""), "stderr": .string("")]), "resultAvailable": .bool(true)], for: "native.shell")
        }
        try AgentOperationSchemas.validateResult(["valueJSON": .string(#"{"value":null}"#), "resultAvailable": .bool(true)], for: "native.appleScript")
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validateResult(["valueJSON": .string(#"{"error":"neutral"}"#), "resultAvailable": .bool(true)], for: "native.appleScript")
        }
    }

    @Test func serializedAppleScriptDataHasDepthAndNodeBounds() {
        let deep = String(repeating: "[", count: 18) + "0" + String(repeating: "]", count: 18)
        #expect(throws: (any Error).self) { try AgentNativeSchemas.boundedJSON(deep) }
        let wide = "[" + Array(repeating: "0", count: 4097).joined(separator: ",") + "]"
        #expect(throws: (any Error).self) { try AgentNativeSchemas.boundedJSON(wide) }
    }

    @Test func nativeRequestsRejectExtraTargetsAndPreparedKeys() {
        let value = request("native.clipboardRead")
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: AgentRequest(requestID: value.requestID, libraryID: value.libraryID,
                operation: value.operation, targets: [.init(kind: .draft, id: UUID())]))
        }
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validatedParameters(for: AgentRequest(requestID: value.requestID, libraryID: value.libraryID,
                operation: value.operation, retryKey: "not authority"))
        }
    }
}
