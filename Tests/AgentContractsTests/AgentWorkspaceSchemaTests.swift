import Foundation
import Testing
import DraftlyCore
@testable import AgentContracts

@Suite("Agent Workspace schemas")
struct AgentWorkspaceSchemaTests {
    private func request(_ operation: String, targets: [AgentResourceReference] = [],
                         parameters: [String: AgentJSONValue] = [:]) -> AgentRequest {
        AgentRequest(requestID: UUID(), libraryID: UUID(), operation: operation,
            targets: targets, expectedVersion: "snapshot", parameters: parameters)
    }

    @Test func allWorkspaceOperationsHaveSchemas() {
        let names = Set(AgentOperationCatalog.operations.filter { $0.name.hasPrefix("workspaces.") }.map(\.name))
        #expect(names == AgentWorkspaceSchemas.operationNames)
        #expect(names.count == 9)
    }

    @Test func canonicalRoundTripPreservesMetadataAndListOptions() throws {
        var workspace = Workspace(name: "café 🐼")
        workspace.folder = .flagged; workspace.sort = .accessed
        workspace.tags = ["á"]; workspace.excludedTags = ["保留"]
        workspace.matchAnyTag = true; workspace.tagged = false
        workspace.scriptMetadata = ["api": #"{"preferredDarkTheme":"missing","future":{"keep":true}}"#, "future": "Keep"]
        var options = DraftListOptions(); options.previewLines = 99
        workspace.listOptions = options
        let value = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(workspace))
        let input = request("workspaces.update", targets: [.init(kind: .workspace, id: workspace.id)], parameters: ["workspace": value])
        let parameters = try AgentOperationSchemas.validatedParameters(for: input)
        #expect(parameters == input.parameters)
        let restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(try #require(parameters["workspace"])))
        #expect(restored == workspace)
    }

    @Test func creationLeavesExistingWorkspaceDefaultsToTheApplication() throws {
        let input = request("workspaces.create", parameters: ["workspace": .object(["name": .string("New 🐼")])])
        #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
    }

    @Test func updatesRejectWrongIdentityAndUnknownCanonicalFields() throws {
        let workspace = Workspace(name: "Neutral")
        var value = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(workspace))
        let target = AgentResourceReference(kind: .workspace, id: UUID())
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("workspaces.update", targets: [target], parameters: ["workspace": value]))
        }
        guard case .object(var fields) = value else { Issue.record("Expected a canonical object"); return }
        fields["futureTopLevel"] = .bool(true); value = .object(fields)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("workspaces.update",
                targets: [.init(kind: .workspace, id: workspace.id)], parameters: ["workspace": value]))
        }
    }

    @Test func reorderRequiresEveryTargetExactlyOnce() throws {
        let a = AgentResourceReference(kind: .workspace, id: UUID())
        let b = AgentResourceReference(kind: .workspace, id: UUID())
        let valid: [AgentJSONValue] = [.string(b.id.uuidString), .string(a.id.uuidString)]
        _ = try AgentOperationSchemas.validatedParameters(for: request("workspaces.reorder", targets: [a, b], parameters: ["order": .array(valid)]))
        for invalid in [[valid[0]], [valid[0], valid[0]], [valid[0], .string(UUID().uuidString)]] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request("workspaces.reorder", targets: [a, b], parameters: ["order": .array(invalid)]))
            }
        }
    }

    @Test func queryPaginationMatchesDraftPagesAndCannotOverrideSavedFilters() throws {
        let target = AgentResourceReference(kind: .workspace, id: UUID())
        let input = request("workspaces.query", targets: [target])
        #expect(try AgentOperationSchemas.validatedParameters(for: input)["limit"] == .integer(50))
        let page: [String: AgentJSONValue] = ["items": .array([]), "nextCursor": .null]
        try AgentOperationSchemas.validateResult(page, for: "workspaces.query")
        #expect(AgentWorkspaceSchemas.schema(for: "workspaces.query")?.result.jsonSchema == AgentReadSchemas.draftPage.jsonSchema)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("workspaces.query", targets: [target], parameters: ["query": .string("Override")]))
        }
    }

    @Test func applyResultsBindBothWindowAndWorkspace() throws {
        let workspace = AgentResourceReference(kind: .workspace, id: UUID())
        let window = AgentResourceReference(kind: .window, id: UUID())
        let input = request("workspaces.apply", targets: [window, workspace])
        var result: [String: AgentJSONValue] = ["workspaceID": .string(workspace.id.uuidString), "windowID": .string(window.id.uuidString)]
        try AgentOperationSchemas.validateResult(result, for: input)
        result["windowID"] = .string(UUID().uuidString)
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: input) }
    }

    @Test func writesDoNotReturnReadableWorkspaceDefinitions() {
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["workspace": .object(["name": .string("Private")])], for: "workspaces.create")
        }
    }
    @Test func metadataTypesAndUnsupportedEnumValuesAreNotCoerced() {
        for definition: AgentJSONValue in [
            .object(["name": .string("Neutral"), "scriptMetadata": .object(["api": .bool(true)])]),
            .object(["name": .string("Neutral"), "sort": .string("future-sort")]),
            .object(["name": .string("Neutral"), "folder": .string("future-folder")])
        ] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request("workspaces.create", parameters: ["workspace": definition]))
            }
        }
    }

    @Test func updateReceiptsCannotNameAnotherWorkspace() throws {
        let target = AgentResourceReference(kind: .workspace, id: UUID())
        let input = request("workspaces.update", targets: [target])
        var receipt: [String: AgentJSONValue] = ["id": .string(target.id.uuidString), "versionToken": .string("new")]
        try AgentOperationSchemas.validateResult(["resource": .object(receipt)], for: input)
        receipt["id"] = .string(UUID().uuidString)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["resource": .object(receipt)], for: input)
        }
    }

}
