import Foundation
import Testing
@testable import AgentContracts

@Suite("Typed direct native requests")
struct AgentNativeSchemaTests {
    private func request(_ operation: String, _ parameters: [String: AgentJSONValue] = [:]) -> AgentRequest {
        .init(requestID: UUID(), libraryID: UUID(), operation: operation, parameters: parameters)
    }

    @Test func concreteSchemasDoNotPublishOtherNativeContracts() {
        #expect(AgentNativeSchemas.operationNames == ["native.clipboardRead", "native.clipboardWrite", "native.htmlToMarkdown",
            "native.share", "native.print", "native.openURL", "native.speak"])
        #expect(AgentNativeSchemas.operationNames.isSubset(of: AgentOperationSchemas.operationNames))
        #expect(AgentOperationSchemas.schema(for: "native.shell") == nil)
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

    @Test(arguments: ["native.clipboardRead", "native.htmlToMarkdown"])
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
