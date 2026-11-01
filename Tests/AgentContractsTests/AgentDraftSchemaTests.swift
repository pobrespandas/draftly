import Foundation
import Testing
import DraftlyCore
@testable import AgentContracts

@Suite("Agent draft mutation schemas")
struct AgentDraftSchemaTests {
    private let target = AgentResourceReference(kind: .draft, id: UUID())
    private func request(_ name: String, targets: [AgentResourceReference]? = nil,
                         parameters: [String: AgentJSONValue] = [:]) -> AgentRequest {
        AgentRequest(requestID: UUID(), libraryID: UUID(), operation: name,
            targets: targets ?? [target], expectedVersion: "snapshot", parameters: parameters)
    }
    private func edit(_ offset: Int64, _ length: Int64, _ text: String = "🐼") -> AgentJSONValue {
        .object(["offset": .integer(offset), "length": .integer(length), "text": .string(text)])
    }
    private func receipt(_ id: UUID) -> AgentJSONValue {
        .object(["id": .string(id.uuidString), "versionToken": .string("new")])
    }

    @Test func everyDraftMutationHasASchema() {
        let reads = AgentReadSchemas.operationNames
        let names = Set(AgentOperationCatalog.operations.filter { $0.name.hasPrefix("drafts.") }.map(\.name)).subtracting(reads)
        #expect(names == AgentDraftSchemas.operationNames)
        #expect(names.count == 13)
    }

    @Test func createDefaultsMatchANewNoteWithoutInventingIdentityOrDates() throws {
        let note = Note()
        let values = try AgentOperationSchemas.validatedParameters(for: request("drafts.create", targets: []))
        #expect(values == ["content": .string(note.content), "tags": .array(note.tags.map(AgentJSONValue.string)),
            "flag": .integer(Int64(note.flag)), "syntax": .string(note.syntax),
            "folder": .string(note.isArchived ? "archive" : "inbox")])
        let fields: [String: AgentJSONValue] = ["content": .string("café\n🐼"), "tags": .array([.string("Á")]),
            "flag": .integer(7), "folder": .string("archive"), "scriptMetadata": .object(["future": .string("Keep")])]
        let result = try AgentOperationSchemas.validatedParameters(for: request("drafts.create", targets: [], parameters: fields))
        for (key, value) in fields { #expect(result[key] == value) }
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("drafts.create", targets: [], parameters: ["accessedAt": .string("2026-10-31T12:00:00Z")]))
        }
    }

    @Test func updatesRequireAnExplicitNonemptyChangeAndRetainNulls() throws {
        let changes: AgentJSONValue = .object(["content": .string(""), "trashedAt": .null,
            "scriptMetadata": .object(["api": .string("future")])])
        let input = request("drafts.update", parameters: ["changes": changes])
        #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
        for invalid: AgentJSONValue in [.object([:]), .object(["accessedAt": .null]),
            .object(["id": .string(UUID().uuidString)]), .object(["flag": .integer(8)]),
            .object(["futureField": .bool(true)]), .object(["scriptMetadata": .object(["api": .bool(true)])])] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request("drafts.update", parameters: ["changes": invalid]))
            }
        }
    }

    @Test func patchPreservesOriginalUTF16OffsetsAndDoesNotReorderThePayload() throws {
        let edits: AgentJSONValue = .array([edit(4, 2, "é"), edit(0, 0, "🐼"), edit(2, 1, "")])
        let input = request("drafts.patch", parameters: ["edits": edits])
        #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
    }

    @Test func patchesRejectEmptyOverlappingDuplicateAndOverflowingRanges() {
        for edits: [AgentJSONValue] in [[], [edit(0, 3), edit(2, 1)], [edit(2, 0), edit(2, 0)],
            [edit(-1, 1)], [edit(1, -1)], [edit(.max, 1)],
            [.object(["offset": .number(1.5), "length": .integer(0), "text": .string("")])]] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request("drafts.patch", parameters: ["edits": .array(edits)]))
            }
        }
    }

    @Test func mergeDefaultsPreserveArchiveAndRequireTheExactOrderedSources() throws {
        let other = AgentResourceReference(kind: .draft, id: UUID())
        let order: AgentJSONValue = .array([.string(other.id.uuidString), .string(target.id.uuidString)])
        let values = try AgentOperationSchemas.validatedParameters(for: request("drafts.merge", targets: [target, other], parameters: ["order": order]))
        #expect(values["order"] == order)
        #expect(values["destination"] == .string("archive"))
        #expect(values["separator"] == .string(""))
        #expect(values["includeBlankLine"] == .bool(false))
        #expect(MergeDestination.allCases.map { String(describing: $0) } == ["archive", "trash", "keep"])
        for invalid in [AgentJSONValue.array([.string(target.id.uuidString)]),
            .array([.string(target.id.uuidString), .string(target.id.uuidString)])] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request("drafts.merge", targets: [target, other], parameters: ["order": invalid]))
            }
        }
    }

    @Test func syntaxRequiresExactlyOneNameOrIdentity() throws {
        _ = try AgentOperationSchemas.validatedParameters(for: request("drafts.syntax", parameters: ["name": .string("TaskPaper")]))
        _ = try AgentOperationSchemas.validatedParameters(for: request("drafts.syntax", parameters: ["syntaxID": .string(UUID().uuidString)]))
        for values: [String: AgentJSONValue] in [[:], ["name": .string("")], ["name": .string("Markdown"), "syntaxID": .string(UUID().uuidString)]] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request("drafts.syntax", parameters: values))
            }
        }
    }

    @Test func tagModesAndFlagValuesAreExplicit() throws {
        for mode in ["add", "remove", "replace"] {
            let input = request("drafts.tags", parameters: ["mode": .string(mode), "tags": .array([.string("É/🐼")])])
            #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
        }
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("drafts.flag", parameters: ["flag": .integer(8)]))
        }
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("drafts.tags", parameters: ["tags": .array([])]))
        }
    }

    @Test func restoreAndPurgeCannotSmuggleOrganizationOrApprovalChanges() throws {
        for name in ["drafts.archive", "drafts.trash", "drafts.restore", "drafts.purge"] {
            #expect(try AgentOperationSchemas.validatedParameters(for: request(name)).isEmpty)
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request(name, parameters: ["approved": .bool(true)]))
            }
        }
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("drafts.restore", parameters: ["isArchived": .bool(false)]))
        }
    }

    @Test func batchReceiptsCannotOmitRepeatOrReplaceTargets() throws {
        let other = AgentResourceReference(kind: .draft, id: UUID())
        let input = request("drafts.archive", targets: [target, other])
        try AgentOperationSchemas.validateResult(["resources": .array([receipt(other.id), receipt(target.id)])], for: input)
        for values in [[receipt(target.id)], [receipt(target.id), receipt(target.id)], [receipt(target.id), receipt(UUID())]] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validateResult(["resources": .array(values)], for: input)
            }
        }
    }

    @Test func newDraftsCannotReuseSourceIdentitiesAndRevisionsBindTheDraft() throws {
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["resource": receipt(target.id)], for: request("drafts.duplicate"))
        }
        let other = AgentResourceReference(kind: .draft, id: UUID())
        let merge = request("drafts.merge", targets: [target, other])
        let merged = receipt(UUID())
        try AgentOperationSchemas.validateResult(["resource": merged,
            "originals": .array([receipt(target.id), receipt(other.id)])], for: merge)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["resource": receipt(target.id),
                "originals": .array([receipt(target.id), receipt(other.id)])], for: merge)
        }
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["resource": merged,
                "originals": .array([receipt(target.id), receipt(target.id)])], for: merge)
        }
        let revision = AgentResourceReference(kind: .revision, id: UUID())
        let input = request("drafts.restoreVersion", targets: [revision, target])
        try AgentOperationSchemas.validateResult(["resource": receipt(target.id)], for: input)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["resource": receipt(revision.id)], for: input)
        }
    }

    @Test func exportedSchemasCarryTheSameNonemptyBounds() throws {
        let schema = try #require(AgentDraftSchemas.schema(for: "drafts.patch"))
        guard case .object(let root) = schema.parameters.jsonSchema,
              case .object(let properties) = root["properties"], case .object(let edits) = properties["edits"] else {
            Issue.record("Expected the exported edits schema"); return
        }
        #expect(edits["minItems"] == .integer(1))
        let changes = AgentObjectShape(fields: ["content": .init(shape: .string())], minimumFields: 1)
        guard case .object(let exported) = changes.jsonSchema else { return }
        #expect(exported["minProperties"] == .integer(1))
        #expect(throws: AgentSchemaError.self) { try changes.validate([:]) }
    }
}
