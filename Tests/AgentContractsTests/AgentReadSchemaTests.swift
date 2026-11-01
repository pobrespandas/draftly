import Foundation
import Testing
@testable import AgentContracts

@Suite("Agent discovery and read schemas")
struct AgentReadSchemaTests {
    @Test func theInitialReadContractSetCannotShrinkSilently() {
        #expect(AgentReadSchemas.operationNames == Set([
            "server.status", "server.capabilities", "server.schemas", "library.summary",
            "drafts.list", "drafts.search", "drafts.get", "drafts.versions"
        ]))
    }
    private func schema(_ name: String) throws -> AgentOperationSchema {
        try #require(AgentReadSchemas.schema(for: name))
    }

    @Test func listDefaultsAreRequestValuesAndDoNotRelaxUnknownFields() throws {
        let values = try schema("drafts.list").validatedParameters([:])
        #expect(values["folder"] == .string("all"))
        #expect(values["limit"] == .integer(50))
        #expect(values["ascending"] == .bool(false))
        #expect(values["cursor"] == nil)
        #expect(throws: AgentSchemaError.self) {
            try schema("drafts.list").validatedParameters(["includeSecrets": .bool(true)])
        }
    }

    @Test(arguments: [AgentJSONValue.integer(0), .integer(201), .bool(true), .string("50"), .number(1.5)])
    func limitsRejectInvalidRangesAndCoercion(value: AgentJSONValue) throws {
        #expect(throws: AgentSchemaError.self) { try schema("drafts.list").validatedParameters(["limit": value]) }
    }

    @Test func searchRequiresAQueryAndRetainsUnicodeAndExplicitFalse() throws {
        #expect(throws: AgentSchemaError.self) { try schema("drafts.search").validatedParameters([:]) }
        #expect(throws: AgentSchemaError.self) { try schema("drafts.search").validatedParameters(["query": .string("")]) }
        let input: [String: AgentJSONValue] = ["query": .string("café 🐼"), "caseSensitive": .bool(false), "folder": .string("trash")]
        let output = try schema("drafts.search").validatedParameters(input)
        #expect(output["query"] == input["query"] && output["caseSensitive"] == .bool(false))
        #expect(output["folder"] == .string("trash"))
    }

    @Test func discoveryCannotSmuggleOperationParametersOrInventSchemas() throws {
        #expect(throws: AgentSchemaError.self) { try schema("server.status").validatedParameters(["query": .string("all")]) }
        #expect(AgentReadSchemas.schema(for: "actions.run") == nil)
        #expect(AgentReadSchemas.schema(for: "missing.operation") == nil)
        #expect(throws: AgentErrorCode.unavailable) { try AgentReadSchemas.validateResult([:], for: "actions.run") }
        for name in AgentReadSchemas.operationNames {
            #expect(try #require(AgentOperationCatalog.operation(named: name)).name == name)
        }
    }

    @Test func metadataCannotAccidentallyReturnFullContentOrUnrelatedLibraryCounts() throws {
        let item = draftSummary()
        try schema("drafts.list").result.validate(["items": .array([.object(item)]), "nextCursor": .null])
        var leaked = item; leaked["content"] = .string("Unexpected full content")
        #expect(throws: AgentSchemaError.self) {
            try schema("drafts.list").result.validate(["items": .array([.object(leaked)]), "nextCursor": .null])
        }
        #expect(throws: AgentSchemaError.self) {
            try schema("library.summary").result.validate(["draftCount": .integer(1), "actionCount": .integer(3)])
        }
    }

    @Test func chunkResultsUseUTF16AndRejectInconsistentLengthsAndOverflow() throws {
        var chunk: [String: AgentJSONValue] = ["text": .string("🐼"), "offset": .integer(0),
            "length": .integer(2), "totalLength": .integer(3), "hasMore": .bool(true)]
        func check() throws {
            try AgentReadSchemas.validateResult(["draft": .object(draftSummary()), "content": .object(chunk)], for: "drafts.get")
        }
        try check()
        chunk["length"] = .integer(1)
        #expect(throws: AgentSchemaError.self) { try check() }
        chunk["length"] = .integer(2); chunk["hasMore"] = .bool(false)
        #expect(throws: AgentSchemaError.self) { try check() }
        chunk["offset"] = .integer(Int64.max); chunk["totalLength"] = .integer(Int64.max)
        #expect(throws: AgentSchemaError.self) { try check() }
    }

    @Test func shapeExportSharesRequiredDefaultsAndAdditionalFieldRules() throws {
        let shape = try schema("drafts.search").parameters
        guard case .object(let exported) = shape.jsonSchema,
              case .array(let required) = exported["required"],
              case .object(let properties) = exported["properties"],
              case .object(let limit) = properties["limit"] else { Issue.record("Missing JSON Schema fields"); return }
        #expect(required == [.string("query")])
        #expect(exported["additionalProperties"] == .bool(false))
        #expect(limit["minimum"] == .integer(1) && limit["maximum"] == .integer(200))
        #expect(limit["default"] == .integer(50))
    }

    @Test func stringBoundsUseUnicodeScalarsAndDatesRequireUTC() throws {
        let shape = AgentValueShape.string(maximum: 1)
        try shape.validate(.string("🐼"))
        #expect(throws: AgentSchemaError.self) { try shape.validate(.string("e\u{301}")) }
        try AgentValueShape.utcDate.validate(.string("2026-10-31T22:00:00.125Z"))
        #expect(throws: AgentSchemaError.self) { try AgentValueShape.utcDate.validate(.string("2026-10-31T19:00:00-03:00")) }
        #expect(throws: AgentSchemaError.self) { try AgentValueShape.uuid.validate(.string("not-a-uuid")) }
    }

    @Test(arguments: ["2026-02-31T22:00:00Z", "2026-10-31T22:00:00ZextraZ"])
    func invalidCalendarDatesAndTrailingTextAreRejected(value: String) {
        #expect(throws: AgentSchemaError.self) { try AgentValueShape.utcDate.validate(.string(value)) }
    }

    @Test func validLeapDaysAndFractionalPrecisionAreRetained() throws {
        for value in ["2024-02-29T23:59:59Z", "2026-10-31T23:59:59.999999999Z"] {
            try AgentValueShape.utcDate.validate(.string(value))
        }
    }

    private func draftSummary() -> [String: AgentJSONValue] {
        ["id": .string(UUID().uuidString), "title": .string("café 🐼"), "preview": .string("Text"),
         "tags": .array([.string("neutral")]), "flag": .integer(0), "isArchived": .bool(false),
         "trashedAt": .null, "syntax": .string("Markdown"), "createdAt": .string("2026-10-31T22:00:00Z"),
         "modifiedAt": .string("2026-10-31T22:00:00Z"), "accessedAt": .null, "versionToken": .string("v1")]
    }
}
