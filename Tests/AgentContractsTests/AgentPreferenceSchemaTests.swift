import Foundation
import Testing
@testable import AgentContracts

@Suite("Agent typed preference contracts")
struct AgentPreferenceSchemaTests {
    private func registry() throws -> AgentPreferenceRegistry {
        try .init(fields: [
            .init(id: "editor.fontSize", title: "Font size", context: .device, value: .number(exclusiveMinimum: 0), defaultSource: .literal, defaultValue: .number(17)),
            .init(id: "editor.margin", title: "Margin", context: .device, value: .number(minimum: 0), defaultSource: .literal, defaultValue: .integer(6)),
            .init(id: "syntax.fontSize", title: "Syntax font", context: .syntax, value: .number(exclusiveMinimum: 0), defaultSource: .inherited),
            .init(id: "syntax.autocorrection", title: "Autocorrection", context: .syntax, value: .nullable(.boolean), defaultSource: .system),
            .init(id: "syntax.feature", title: "Syntax feature", context: .syntaxFeature, value: .boolean, defaultSource: .contextual),
            .init(id: "commands.shortcut", title: "Shortcut", context: .command(["New Draft", "Quick Capture"]), value: .object(.init(fields: [
                "key": .init(shape: .string(), required: true), "modifiers": .init(shape: .array(.string(choices: ["command", "option", "control", "shift"]), maximum: 4), required: true)
            ])), defaultSource: .contextual, approvalCommands: ["Quick Capture"]),
            .init(id: "application.launchAtLogin", title: "Launch at login", context: .device, value: .boolean, defaultSource: .system, requiresHumanApproval: true),
            .init(id: "application.readOnly", title: "Read-only fixture", context: .device, value: .string(), defaultSource: .contextual, writable: false)
        ], builtInSyntaxNames: ["Markdown", "TaskPaper"])
    }
    private func request(_ operation: String, _ items: [AgentJSONValue]) -> AgentRequest {
        AgentRequest(requestID: UUID(), libraryID: UUID(), operation: operation, expectedVersion: "snapshot",
            parameters: ["items": .array(items)])
    }
    private func item(_ id: String, extra: [String: AgentJSONValue] = [:]) -> AgentJSONValue {
        .object(["id": .string(id)].merging(extra, uniquingKeysWith: { _, new in new }))
    }
    private var syntax: AgentJSONValue { .object(["type": .string("builtIn"), "name": .string("Markdown")]) }

    @Test func theGatewayDoesNotInventAPreferenceCatalogOrReadRawDefaults() throws {
        let input = request("preferences.get", [item("editor.fontSize")])
        #expect(AgentOperationSchemas.schema(for: "preferences.get") == nil)
        #expect(throws: AgentErrorCode.unavailable) { try AgentOperationSchemas.validatedParameters(for: input) }
        #expect(try AgentOperationSchemas.validatedParameters(for: input, preferences: registry()) == input.parameters)
    }

    @Test func registriesRejectDuplicateIDsAndInvalidDefaults() throws {
        let field = AgentPreferenceField(id: "editor.test", title: "Fixture", context: .device, value: .boolean,
            defaultSource: .literal, defaultValue: .bool(false))
        #expect(throws: AgentSchemaError.self) { try AgentPreferenceRegistry(fields: [field, field], builtInSyntaxNames: ["Markdown"]) }
        var bad = field; bad.defaultValue = .integer(1)
        #expect(throws: AgentSchemaError.self) { try AgentPreferenceRegistry(fields: [bad], builtInSyntaxNames: ["Markdown"]) }
        bad = field; bad.defaultValue = nil
        #expect(throws: AgentSchemaError.self) { try AgentPreferenceRegistry(fields: [bad], builtInSyntaxNames: ["Markdown"]) }
        bad = field; bad.approvalCommands = ["Unknown"]
        #expect(throws: AgentSchemaError.self) { try AgentPreferenceRegistry(fields: [bad], builtInSyntaxNames: ["Markdown"]) }
    }

    @Test func unknownPrivateAndRawStorageNamesCannotBecomeRegisteredFields() throws {
        let catalog = try registry()
        for id in ["agents.credentials", "cloud.identifier", "bookmark.Secret", "SUFeedURL", "AppleID.Password"] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request("preferences.get", [item(id)]), preferences: catalog)
            }
        }
        var input = item("editor.fontSize", extra: ["value": .integer(18)])
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("preferences.get", [input]), preferences: catalog)
        }
        input = item("editor.fontSize", extra: ["value": .integer(18), "defaultsKey": .string("agents.credentials")])
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("preferences.update", [input]), preferences: catalog)
        }
    }

    @Test func numericPreferencesRejectCoercionNaNAndInvalidBounds() throws {
        let catalog = try registry()
        for value in [AgentJSONValue.integer(18), .number(18.5)] {
            let values = try AgentOperationSchemas.validatedParameters(for: request("preferences.update", [item("editor.fontSize", extra: ["value": value])]), preferences: catalog)
            #expect(values["interactive"] == .bool(false))
        }
        for value in [AgentJSONValue.bool(false), .string("18"), .integer(0), .integer(-1), .number(.nan)] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request("preferences.update", [item("editor.fontSize", extra: ["value": value])]), preferences: catalog)
            }
        }
        _ = try AgentOperationSchemas.validatedParameters(for: request("preferences.update", [item("editor.margin", extra: ["value": .integer(0)])]), preferences: catalog)
    }

    @Test func syntaxAndFeatureContextsAreExplicitAndSystemInheritanceStaysNull() throws {
        let catalog = try registry()
        let input = request("preferences.update", [item("syntax.autocorrection", extra: ["syntax": syntax, "value": .null])])
        let values = try AgentOperationSchemas.validatedParameters(for: input, preferences: catalog)
        #expect(values["items"] == input.parameters["items"])
        for invalid in [item("syntax.fontSize"), item("syntax.feature", extra: ["syntax": syntax]),
            item("editor.fontSize", extra: ["syntax": syntax])] {
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request("preferences.get", [invalid]), preferences: catalog)
            }
        }
        _ = try AgentOperationSchemas.validatedParameters(for: request("preferences.get", [item("syntax.feature", extra: ["syntax": syntax, "feature": .string("é🐼")])]), preferences: catalog)
    }

    @Test func duplicateAddressesCannotHideBehindUUIDCaseOrUnicodeAliases() throws {
        let catalog = try registry(), id = UUID()
        let first = item("syntax.fontSize", extra: ["syntax": .object(["type": .string("installed"), "id": .string(id.uuidString)])])
        let alias = item("syntax.fontSize", extra: ["syntax": .object(["type": .string("installed"), "id": .string(id.uuidString.lowercased())])])
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("preferences.get", [first, alias]), preferences: catalog)
        }
        let feature = item("syntax.feature", extra: ["syntax": syntax, "feature": .string("é")])
        let normalized = item("syntax.feature", extra: ["syntax": syntax, "feature": .string("e\u{301}")])
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("preferences.reset", [feature, normalized]), preferences: catalog)
        }
    }

    @Test func globalAndLocalCommandsHaveDifferentApprovalRequirements() throws {
        let catalog = try registry()
        let binding: AgentJSONValue = .object(["key": .string("n"), "modifiers": .array([.string("command")])])
        let local = request("preferences.update", [item("commands.shortcut", extra: ["command": .string("New Draft"), "value": binding])])
        let global = request("preferences.update", [item("commands.shortcut", extra: ["command": .string("Quick Capture"), "value": binding])])
        #expect(try !AgentPreferenceSchemas.mutationRequiresHumanApproval(local, registry: catalog))
        #expect(try AgentPreferenceSchemas.mutationRequiresHumanApproval(global, registry: catalog))
        #expect(try AgentPreferenceSchemas.mutationRequiresHumanApproval(request("preferences.update", [item("application.launchAtLogin", extra: ["value": .bool(true)])]), registry: catalog))
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("preferences.get", [item("commands.shortcut", extra: ["command": .string("Unknown")])]), preferences: catalog)
        }
    }

    @Test func readOnlyFieldsCannotBeWrittenOrResetAndNoDefaultIsWrittenByReading() throws {
        let catalog = try registry()
        let before = catalog.descriptor(try catalog.field("editor.fontSize"))
        _ = try AgentOperationSchemas.validatedParameters(for: request("preferences.get", [item("editor.fontSize")]), preferences: catalog)
        #expect(catalog.descriptor(try catalog.field("editor.fontSize")) == before)
        for name in ["preferences.update", "preferences.reset"] {
            var extra: [String: AgentJSONValue] = [:]
            if name == "preferences.update" { extra["value"] = .string("Changed") }
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request(name, [item("application.readOnly", extra: extra)]), preferences: catalog)
            }
        }
    }

    @Test func resultAddressesMustMatchTheCompleteRequestedSetWithoutReturningValuesToWriters() throws {
        let catalog = try registry()
        let input = request("preferences.update", [item("editor.fontSize", extra: ["value": .integer(18)])])
        let receipt = item("editor.fontSize", extra: ["versionToken": .string("new-field")])
        try AgentOperationSchemas.validateResult(["items": .array([receipt]), "versionToken": .string("new-batch")], for: input, preferences: catalog)
        let foreign = item("editor.margin", extra: ["versionToken": .string("new-field")])
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["items": .array([foreign]), "versionToken": .string("new-batch")], for: input, preferences: catalog)
        }
        let leaked = item("editor.fontSize", extra: ["versionToken": .string("new-field"), "effectiveValue": .integer(18)])
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["items": .array([leaked]), "versionToken": .string("new-batch")], for: input, preferences: catalog)
        }
    }

    @Test func readResultsSeparateStoredDefaultAndSystemValues() throws {
        let catalog = try registry()
        let input = request("preferences.get", [item("editor.fontSize")])
        let value = item("editor.fontSize", extra: ["effectiveValue": .integer(17), "valueOrigin": .string("default"), "hasOverride": .bool(false), "versionToken": .string("field")])
        try AgentOperationSchemas.validateResult(["items": .array([value]), "versionToken": .string("batch")], for: input, preferences: catalog)
        let systemInput = request("preferences.get", [item("syntax.autocorrection", extra: ["syntax": syntax])])
        let system = item("syntax.autocorrection", extra: ["syntax": syntax, "effectiveValue": .null,
            "valueOrigin": .string("system"), "hasOverride": .bool(false), "versionToken": .string("field")])
        try AgentOperationSchemas.validateResult(["items": .array([system]), "versionToken": .string("batch")], for: systemInput, preferences: catalog)
        let wrong = item("editor.fontSize", extra: ["effectiveValue": .integer(17), "valueOrigin": .string("stored"), "hasOverride": .bool(false), "versionToken": .string("field")])
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["items": .array([wrong]), "versionToken": .string("batch")], for: input, preferences: catalog)
        }
    }

    @Test func exportedDescriptorsRoundTripNumbersAndCannotChangeTheirTypeOrDefault() throws {
        let catalog = try registry()
        let input = AgentRequest(requestID: UUID(), libraryID: UUID(), operation: "preferences.schema", parameters: ["ids": .array([.string("editor.fontSize")])])
        let descriptor = catalog.descriptor(try catalog.field("editor.fontSize"))
        let wire = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(descriptor))
        try AgentOperationSchemas.validateResult(["items": .array([wire]), "nextCursor": .null], for: input, preferences: catalog)
        guard case .object(var changed) = wire else { return }
        changed["defaultValue"] = .integer(99)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["items": .array([.object(changed)]), "nextCursor": .null], for: input, preferences: catalog)
        }
    }
    @Test func inheritedOrSystemValuesCannotBecomeUntypedNullSuccess() throws {
        let catalog = try registry()
        for (id, origin, context) in [("syntax.fontSize", "inherited", ["syntax": syntax]),
                                      ("application.launchAtLogin", "system", [:])] {
            let input = request("preferences.get", [item(id, extra: context)])
            let value = item(id, extra: context.merging(["effectiveValue": .null, "valueOrigin": .string(origin),
                "hasOverride": .bool(false), "versionToken": .string("field")], uniquingKeysWith: { _, new in new }))
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validateResult(["items": .array([value]), "versionToken": .string("batch")], for: input, preferences: catalog)
            }
        }
    }

}
