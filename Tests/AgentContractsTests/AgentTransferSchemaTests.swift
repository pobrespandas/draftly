import Foundation
import Testing
@testable import AgentContracts

@Suite("Agent transfer contracts")
struct AgentTransferSchemaTests {
    private func request(_ operation: String, parameters: [String: AgentJSONValue], targets: [AgentResourceReference] = []) -> AgentRequest {
        AgentRequest(requestID: UUID(), libraryID: UUID(), operation: operation, targets: targets, parameters: parameters)
    }
    @Test func importShapeRejectsUnboundedOrAmbiguousBytes() throws {
        let hash = String(repeating: "a", count: 64)
        let valid = request("transfers.beginImport", parameters: ["byteLength": .integer(3), "sha256": .string(hash)])
        #expect(try AgentOperationSchemas.validatedParameters(for: valid)["byteLength"] == .integer(3))
        for parameters: [String: AgentJSONValue] in [
            ["byteLength": .integer(-1), "sha256": .string(hash)],
            ["byteLength": .integer(Int64(AgentTransferSchemas.maximumBytes + 1)), "sha256": .string(hash)],
            ["byteLength": .integer(3), "sha256": .string(String(repeating: "A", count: 64))],
            ["byteLength": .integer(3), "sha256": .string(hash), "path": .string("/tmp/export")]
        ] {
            #expect(throws: (any Error).self) { try AgentOperationSchemas.validatedParameters(for: request("transfers.beginImport", parameters: parameters)) }
        }
        let targets = [AgentResourceReference(kind: .operation, id: UUID())]
        for text in ["", "not base64", "YQ", "YQ==\n", Data(repeating: 1, count: AgentTransferSchemas.maximumChunkBytes + 1).base64EncodedString()] {
            #expect(throws: (any Error).self) {
                try AgentOperationSchemas.validatedParameters(for: request("transfers.appendChunk",
                    parameters: ["offset": .integer(0), "data": .string(text)], targets: targets))
            }
        }
        #expect(try AgentOperationSchemas.validatedParameters(for: request("transfers.appendChunk",
            parameters: ["offset": .integer(0), "data": .string("YQ==")], targets: targets))["data"] == .string("YQ=="))
    }
    @Test func textExportsCannotCombineDraftsOrIncludeVersions() throws {
        let targets = [UUID(), UUID()].map { AgentResourceReference(kind: .draft, id: $0) }
        for (selected, parameters) in [
            (targets, ["format": AgentJSONValue.string("text")]),
            (Array(targets.prefix(1)), ["format": .string("text"), "includeVersions": .bool(true)])
        ] {
            #expect(throws: (any Error).self) { try AgentOperationSchemas.validatedParameters(for: request("exports.drafts", parameters: parameters, targets: selected)) }
        }
        let values = try AgentOperationSchemas.validatedParameters(for: request("exports.drafts", parameters: [:], targets: targets))
        #expect(values == ["format": .string("draftly"), "includeVersions": .bool(false)])
    }
    @Test func transferRepliesCannotIdentifyADifferentTransfer() throws {
        let id = UUID(), other = UUID()
        let cancel = request("transfers.cancel", parameters: [:], targets: [.init(kind: .operation, id: id)])
        #expect(throws: (any Error).self) {
            try AgentOperationSchemas.validateResult(["transferID": .string(other.uuidString), "cancelled": .bool(true)], for: cancel)
        }
        try AgentOperationSchemas.validateResult(["transferID": .string(id.uuidString), "cancelled": .bool(true)], for: cancel)
    }
}
