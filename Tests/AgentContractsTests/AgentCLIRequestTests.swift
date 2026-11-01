import Foundation
import Testing
import AgentContracts

@Suite("Agent CLI request preparation")
struct AgentCLIRequestTests {
    @Test(arguments: ["status", "capabilities"])
    func generatedRequestsDoNotReadInput(mode: String) throws {
        let request = try AgentCLIRequest.make(mode: mode) {
            Issue.record("This mode must not read stdin")
            throw AgentErrorCode.storageError
        }
        #expect(request.operation == "server." + mode)
        #expect(request.libraryID == nil && request.targets.isEmpty)
        #expect(request.parameters.isEmpty && request.expectedVersion == nil)
    }

    @Test func jsonModePreservesTheCompleteEnvelopeAndReadsOnce() throws {
        let original = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "drafts.update",
            targets: [.init(kind: .draft, id: UUID())], expectedVersion: "opaque",
            parameters: ["content": .string("e\u{0301} 🐼"), "future": .bool(true)])
        var reads = 0
        let request = try AgentCLIRequest.make(mode: "json") {
            reads += 1
            return try JSONEncoder().encode(original)
        }
        #expect(request == original && reads == 1)
    }

    @Test func callModeUsesTheNamedOperationAndExistingToolConversion() throws {
        let requestID = UUID(), draftID = UUID()
        let arguments: [String: AgentJSONValue] = [
            "requestID": .string(requestID.uuidString), "expectedVersion": .string("version"),
            "targets": .array([.object(["kind": .string("draft"), "id": .string(draftID.uuidString)])]),
            "parameters": .object(["content": .string("Texto 🐼")])
        ]
        var reads = 0
        let request = try AgentCLIRequest.make(mode: "call", operationName: "drafts.update") {
            reads += 1
            return try JSONEncoder().encode(AgentJSONValue.object(arguments))
        }
        #expect(reads == 1 && request.requestID == requestID)
        #expect(request.operation == "drafts.update" && request.libraryID == nil)
        #expect(request.targets == [.init(kind: .draft, id: draftID)])
        #expect(request.expectedVersion == "version")
        #expect(request.parameters == ["content": .string("Texto 🐼")])
    }

    @Test func unknownOrMissingOperationsFailBeforeReadingInput() {
        for operation in [nil, "not.an.operation"] as [String?] {
            #expect(throws: AgentErrorCode.invalidInput) {
                try AgentCLIRequest.make(mode: "call", operationName: operation) {
                    Issue.record("Invalid operations must not read stdin")
                    return Data()
                }
            }
        }
    }

    @Test func invalidModesFailBeforeReadingInput() {
        for mode in ["mcp", "connect", "discover", ""] {
            #expect(throws: AgentErrorCode.invalidInput) {
                try AgentCLIRequest.make(mode: mode) {
                    Issue.record("Stream and setup modes do not prepare a request")
                    return Data()
                }
            }
        }
    }

    @Test func decodingAndInputFailuresKeepTheirExistingErrorTypes() {
        for mode in ["json", "call"] {
            #expect(throws: AgentErrorCode.storageError) {
                try AgentCLIRequest.make(mode: mode, operationName: "server.status") {
                    throw AgentErrorCode.storageError
                }
            }
        }
        #expect(throws: DecodingError.self) {
            try AgentCLIRequest.make(mode: "call", operationName: "server.status") { Data("{".utf8) }
        }
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentCLIRequest.make(mode: "call", operationName: "server.status") { Data("[]".utf8) }
        }
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentCLIRequest.make(mode: "json") { Data("{}".utf8) }
        }
    }
}
