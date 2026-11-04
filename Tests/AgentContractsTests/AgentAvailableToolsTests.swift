import Foundation
import Testing
import AgentContracts

@Suite("Shared local tool catalog")
struct AgentAvailableToolsTests {
    func capabilities(_ caps: [AgentCapability], allResources: Bool = false) -> [String: AgentJSONValue] {
        ["capabilities": .array(caps.map { .string($0.rawValue) }),
         "scope": .object(["allResources": .bool(allResources), "resources": .array([])]),
         "expiresAt": .string("2030-01-01T00:00:00Z")]
    }
    func operation(_ name: String, available: Bool = true) -> AgentJSONValue {
        .object(["name": .string(name), "available": .bool(available),
            "inputSchema": .object(["type": .string("object")]), "resultSchema": .null])
    }

    @Test func onlyAvailablePermittedToolsUseTheSharedSchema() throws {
        let catalog = try AgentAvailableTools(capabilities: capabilities([.draftsRead]), schemas: ["operations": .array([
            operation("drafts.list"), operation("drafts.get", available: false), operation("drafts.create")
        ])])
        #expect(catalog.definitions.map(\.name) == ["draftly_drafts_list"])
        let definition = try #require(catalog.definitions.first)
        let descriptor = try #require(AgentOperationCatalog.operation(named: "drafts.list"))
        #expect(definition.inputSchema == AgentToolInput.schema(for: descriptor,
            parameters: .object(["type": .string("object")])))
        let request = try catalog.request(tool: definition.name, argumentsJSON: "{\"parameters\":{\"limit\":1}}")
        #expect(request.operation == "drafts.list" && request.parameters["limit"] == .integer(1))
        #expect(throws: AgentErrorCode.permissionDenied) {
            try catalog.request(tool: "draftly_drafts_get", argumentsJSON: "{}")
        }
    }

    @Test(arguments: [false, true])
    func libraryOnlyToolsAreHiddenFromScopedWriters(allResources: Bool) throws {
        let catalog = try AgentAvailableTools(capabilities: capabilities([.draftsWrite], allResources: allResources),
            schemas: ["operations": .array([operation("drafts.create"), operation("drafts.duplicate"), operation("drafts.merge"), operation("drafts.update")])])
        #expect(catalog.definitions.contains { $0.operation == "drafts.update" })
        for name in ["drafts.create", "drafts.duplicate", "drafts.merge"] {
            #expect(catalog.definitions.contains { $0.operation == name } == allResources)
            if !allResources {
                #expect(throws: AgentErrorCode.permissionDenied) {
                    try catalog.request(tool: AgentToolInput.name(for: name), argumentsJSON: "{}")
                }
            }
        }
    }

    @Test func duplicateDescriptorsAndMalformedMetadataFailClosed() throws {
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentAvailableTools(capabilities: capabilities([.draftsRead]), schemas: ["operations": .array([
                operation("drafts.list"), operation("drafts.list", available: false)
            ])])
        }
        #expect(throws: (any Error).self) {
            try AgentAvailableTools(capabilities: [:], schemas: ["operations": .array([])])
        }
    }
}
