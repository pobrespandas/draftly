import Foundation
import Testing
@testable import AgentContracts

@Suite("Agent backup contracts")
struct AgentBackupSchemaTests {
    private func request(_ parameters: [String: AgentJSONValue]) -> AgentRequest {
        .init(requestID: UUID(), libraryID: UUID(), operation: "backups.validate", parameters: parameters)
    }
    @Test func backupSourcesRejectMixedInputsTraversalAndInstallationLinks() throws {
        for source: AgentJSONValue in [
            .object(["kind": .string("inline"), "text": .string("{}")]),
            .object(["kind": .string("transfer"), "transferID": .string(UUID().uuidString)]),
            .object(["kind": .string("bookmark"), "bookmarkID": .string(UUID().uuidString), "path": .string("backups/file.json")]),
            .object(["kind": .string("https"), "url": .string("https://example.invalid/backup.json")])
        ] { #expect(try AgentOperationSchemas.validatedParameters(for: request(["source": source]))["source"] == source) }
        for source: AgentJSONValue in [
            .object(["kind": .string("inline"), "text": .string("{}"), "transferID": .string(UUID().uuidString)]),
            .object(["kind": .string("bookmark"), "bookmarkID": .string(UUID().uuidString), "path": .string("../backup.json")]),
            .object(["kind": .string("https"), "url": .string("https://user:secret@example.invalid/file")]),
            .object(["kind": .string("installationURL"), "url": .string("draftly://syntax?name=Markdown")])
        ] { #expect(throws: (any Error).self) { try AgentOperationSchemas.validatedParameters(for: request(["source": source])) } }
    }
    @Test func backupReportsCannotHideUnknownCollectionsOrUseNegativeCounts() throws {
        var counts = Dictionary(uniqueKeysWithValues: AgentBackupSchemas.collectionNames.map { ($0, AgentJSONValue.integer(0)) })
        try AgentOperationSchemas.validateResult(["valid": .bool(true), "counts": .object(counts)], for: "backups.validate")
        counts["drafts"] = .integer(-1)
        #expect(throws: (any Error).self) { try AgentOperationSchemas.validateResult(["valid": .bool(true), "counts": .object(counts)], for: "backups.validate") }
        counts["drafts"] = .integer(0); counts["credentials"] = .integer(1)
        #expect(throws: (any Error).self) { try AgentOperationSchemas.validateResult(["valid": .bool(true), "counts": .object(counts)], for: "backups.validate") }
    }
}
