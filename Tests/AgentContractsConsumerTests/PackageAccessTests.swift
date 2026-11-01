import Foundation
import Testing
// Keep a normal import to check the package boundary.
import AgentContracts

@Suite("Agent contract package consumer")
struct PackageAccessTests {
    @Test func applicationCodeCanBuildTypedPreferenceFieldsWithoutTestableAccess() throws {
        let binding = AgentValueShape.object(AgentObjectShape(fields: [
            "key": AgentFieldShape(shape: .string(), required: true),
            "modifiers": AgentFieldShape(shape: .array(.string(), maximum: 4), required: true)
        ]))
        let field = AgentPreferenceField(id: "fixture.shortcut", title: "Shortcut fixture",
            context: .command(["Fixture Command"]), value: binding, defaultSource: .contextual)
        let registry = try AgentPreferenceRegistry(fields: [field], builtInSyntaxNames: ["Markdown"])
        let input = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "preferences.get", parameters: [
            "items": .array([.object(["id": .string("fixture.shortcut"), "command": .string("Fixture Command")])])
        ])
        let values = try AgentOperationSchemas.validatedParameters(for: input, preferences: registry)
        #expect(values == input.parameters)
    }
}
