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

    @Test(arguments: [false, true], [AgentCapability.draftsWrite, .appearanceManage])
    func libraryOnlyToolsAreHiddenFromScopedWriters(allResources: Bool, capability: AgentCapability) throws {
        let family = capability == .draftsWrite ? "drafts" : "themes"
        let creation = [family + ".create", family + ".duplicate"] + (family == "drafts" ? ["drafts.merge"] : [])
        let update = family + ".update"
        let catalog = try AgentAvailableTools(capabilities: capabilities([capability], allResources: allResources),
            schemas: ["operations": .array((creation + [update]).map { operation($0) })])
        #expect(catalog.definitions.contains { $0.operation == update })
        for name in creation {
            #expect(catalog.definitions.contains { $0.operation == name } == allResources)
            if !allResources {
                #expect(throws: AgentErrorCode.permissionDenied) {
                    try catalog.request(tool: AgentToolInput.name(for: name), argumentsJSON: "{}")
                }
            }
        }
    }

    @Test(arguments: [Set<AgentCapability>(), [.draftsRead], [.filesRead], [.filesWrite], [.filesRead, .filesWrite]])
    func transferCancellationNeedsFileAccessInDiscoveryAndPermissionPolicy(_ allowed: Set<AgentCapability>) throws {
        let catalog = try AgentAvailableTools(capabilities: capabilities(Array(allowed)),
            schemas: ["operations": .array([operation("transfers.cancel")])])
        let available = !allowed.isDisjoint(with: [.filesRead, .filesWrite])
        #expect(catalog.definitions.contains { $0.operation == "transfers.cancel" } == available)
        let connection = UUID(), library = UUID()
        let request = AgentRequest(requestID: UUID(), libraryID: library, operation: "transfers.cancel",
            targets: [.init(kind: .operation, id: UUID())])
        let grant = AgentGrant(connectionID: connection, libraryID: library,
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000), capabilities: allowed, scope: .library)
        let decision = AgentPermissionPolicy.evaluate(request, connectionID: connection, grant: grant,
            now: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(decision == (available ? .permitted(.library) : .denied(.permissionDenied)))
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
