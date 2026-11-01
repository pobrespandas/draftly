import Foundation
import Testing
import DraftlyCore
@testable import AgentContracts

@Suite("Agent Action definition schemas")
struct AgentActionSchemaTests {
    private func request(_ name: String, targets: [AgentResourceReference] = [],
                         parameters: [String: AgentJSONValue] = [:]) -> AgentRequest {
        AgentRequest(requestID: UUID(), libraryID: UUID(), operation: name, targets: targets,
            expectedVersion: "snapshot", parameters: parameters)
    }

    @Test func canonicalActionRoundTripPreservesUnknownFieldsAndIndependentStepIdentities() throws {
        let includedID = UUID()
        var included = ActionStep("includeAction", ["uuid": includedID.uuidString, "name": "Imported", "template": "[[draft]]"])
        included.unknownFields["futureStep"] = .object(["keep": .bool(false)])
        var unknown = ActionStep("futureStep", ["futureOption": "false"]); unknown.isEnabled = false
        var legacyEmpty = ActionStep("", [:]); legacyEmpty.isEnabled = false
        var action = DraftAction(name: "café 🐼", steps: [included, unknown, legacyEmpty])
        action.unknownFields["futureAction"] = .array([.string("Keep"), .number(0)])
        var options = ActionPresentation()
        options.unknownFields["futureOption"] = .object(["keep": .bool(true)])
        options.logLevel = 99
        action.options = options; action.rawPayload = #"{"original":"Keep unchanged"}"#
        action.shortcutModifiers = ["futureModifier"]
        let definition = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(action))
        let input = request("actions.update", targets: [.init(kind: .action, id: action.id)], parameters: ["action": definition])
        let parameters = try AgentOperationSchemas.validatedParameters(for: input)
        #expect(parameters == input.parameters)
        let restored = try JSONDecoder().decode(DraftAction.self, from: JSONEncoder().encode(try #require(parameters["action"])))
        #expect(restored == action)
        #expect(restored.steps[0].id != includedID)
        #expect(restored.steps[0].values["uuid"] == includedID.uuidString)
    }

    @Test func creationDoesNotFillMissingImportedOptionsOrEnableUnknownSteps() throws {
        let definition: AgentJSONValue = .object(["name": .string("New café 🐼"), "steps": .array([
            .object(["type": .string("futureStep"), "isEnabled": .bool(false), "future": .bool(true)])
        ])])
        let input = request("actions.create", parameters: ["action": definition])
        #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
    }

    @Test func stepValuesRemainStringsRatherThanCoercingImportedBooleans() {
        let input = request("actions.create", parameters: ["action": .object([
            "name": .string("Neutral"), "steps": .array([.object([
                "type": .string("script"), "values": .object(["allowAsync": .bool(false)])
            ])])
        ])])
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validatedParameters(for: input) }
    }

    @Test func updateCannotChangeTheTargetResourceIdentity() throws {
        let action = DraftAction(name: "Neutral", steps: [])
        let definition = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(action))
        let input = request("actions.update", targets: [.init(kind: .action, id: UUID())], parameters: ["action": definition])
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validatedParameters(for: input) }
    }

    @Test func manualOrderMustMatchEveryTargetExactlyOnce() throws {
        let first = AgentResourceReference(kind: .action, id: UUID())
        let second = AgentResourceReference(kind: .action, id: UUID())
        let order = [second.id, first.id].map { AgentJSONValue.string($0.uuidString) }
        let valid = request("actions.reorder", targets: [first, second], parameters: ["order": .array(order)])
        #expect(try AgentOperationSchemas.validatedParameters(for: valid) == valid.parameters)
        for ids in [[first.id], [first.id, first.id], [first.id, UUID()]] {
            let input = request("actions.reorder", targets: [first, second], parameters: ["order": .array(ids.map { .string($0.uuidString) })])
            #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validatedParameters(for: input) }
        }
    }

    @Test func groupMetadataSurvivesSchemaValidationAndIdentityBinding() throws {
        let id = UUID()
        let group: AgentJSONValue = .object(["id": .string(id.uuidString), "name": .string("Group 🐼"),
            "symbol": .string("future.symbol"), "order": .integer(-1),
            "importedMetadata": .object(["future": .array([.string("Keep"), .bool(false)])])])
        let input = request("actionGroups.update", targets: [.init(kind: .actionGroup, id: id)], parameters: ["group": group])
        #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
    }

    @Test func writeReceiptsDoNotIncludeReadableActionContent() throws {
        try AgentOperationSchemas.validateResult(["resource": .object([
            "id": .string(UUID().uuidString), "versionToken": .string("saved")
        ])], for: "actions.update")
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["resource": .object([
                "id": .string(UUID().uuidString), "versionToken": .string("saved"), "script": .string("Private")
            ])], for: "actions.update")
        }
    }

    @Test func everyActionOperationHasASchemaButNoHandler() throws {
        let names = Set(AgentOperationCatalog.operations.filter {
            $0.name.hasPrefix("actions.") || $0.name.hasPrefix("actionGroups.")
        }.map(\.name))
        #expect(AgentActionSchemas.operationNames == names)
        #expect(AgentReadSchemas.operationNames.isDisjoint(with: names))
        for name in names { #expect(try #require(AgentOperationCatalog.operation(named: name)).hasHandler == false) }
    }

    @Test func unsupportedOperationsDoNotReceiveAnEmptyFallbackSchema() {
        #expect(AgentOperationSchemas.schema(for: "native.shell") == nil)
        #expect(throws: AgentErrorCode.unavailable) {
            try AgentOperationSchemas.validatedParameters(for: request("future.operation"))
        }
    }
}
