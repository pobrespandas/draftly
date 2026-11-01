import Foundation
import Testing
@testable import AgentContracts

@Suite("Agent bookmark contracts")
struct AgentBookmarkSchemaTests {
    private func request(_ name: String, targets: [AgentResourceReference] = [], parameters: [String: AgentJSONValue] = [:]) -> AgentRequest {
        AgentRequest(requestID: UUID(), libraryID: UUID(), operation: name, targets: targets, expectedVersion: "snapshot", parameters: parameters)
    }
    @Test func listingReturnsMetadataWithoutPathsOrPermissionData() throws {
        let input = request("bookmarks.list")
        #expect(try AgentOperationSchemas.validatedParameters(for: input)["limit"] == .integer(50))
        var bookmark: [String: AgentJSONValue] = ["id": .string(UUID().uuidString), "name": .string("Café 🐼"), "versionToken": .string("version")]
        try AgentOperationSchemas.validateResult(["items": .array([.object(bookmark)]), "nextCursor": .null], for: input)
        bookmark["bookmarkData"] = .string("Not a permission")
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(["items": .array([.object(bookmark)]), "nextCursor": .null], for: input) }
    }
    @Test func addingPreservesUnicodeAndNeverChoosesAnArbitraryPathOrApprovesItself() throws {
        let input = request("bookmarks.requestAdd", parameters: ["name": .string(" Café 🐼 ")])
        let values = try AgentOperationSchemas.validatedParameters(for: input)
        #expect(values["name"] == input.parameters["name"])
        #expect(values["interactive"] == .bool(false))
        let longName = String(repeating: "é", count: 5000)
        let long = try AgentOperationSchemas.validatedParameters(for: request("bookmarks.requestAdd", parameters: ["name": .string(longName)]))
        #expect(long["name"] == .string(longName))
        for parameters: [String: AgentJSONValue] in [["name": .string(" \n")], ["name": .string("Neutral"), "path": .string("/tmp")], ["name": .string("Neutral"), "approved": .bool(true)]] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request("bookmarks.requestAdd", parameters: parameters))
            }
        }
    }
    @Test func addAndForgetRepliesBindTheirRequestedNameAndIdentity() throws {
        let id = UUID()
        let value: AgentJSONValue = .object(["id": .string(id.uuidString), "name": .string("Neutral"), "versionToken": .string("new")])
        try AgentOperationSchemas.validateResult(["bookmark": value], for: request("bookmarks.requestAdd", parameters: ["name": .string("Neutral")]))
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["bookmark": value], for: request("bookmarks.requestAdd", parameters: ["name": .string("Other")]))
        }
        let input = request("bookmarks.forget", targets: [.init(kind: .bookmark, id: id)])
        try AgentOperationSchemas.validateResult(["deletedIDs": .array([.string(id.uuidString)])], for: input)
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(["deletedIDs": .array([.string(UUID().uuidString)])], for: input) }
    }
}
