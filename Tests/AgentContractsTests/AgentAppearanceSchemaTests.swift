import Foundation
import Testing
import DraftlyCore
@testable import AgentContracts

@Suite("Agent appearance contracts")
struct AgentAppearanceSchemaTests {
    private func request(_ operation: String, targets: [AgentResourceReference] = [],
                         parameters: [String: AgentJSONValue] = [:]) -> AgentRequest {
        AgentRequest(requestID: UUID(), libraryID: UUID(), operation: operation,
            targets: targets, expectedVersion: "snapshot", parameters: parameters)
    }
    private func receipt(_ id: UUID = UUID()) -> AgentJSONValue {
        .object(["id": .string(id.uuidString), "versionToken": .string("new")])
    }
    private func chunk(_ text: String) -> AgentJSONValue {
        .object(["text": .string(text), "offset": .integer(0), "length": .integer(Int64(text.utf16.count)),
            "totalLength": .integer(Int64(text.utf16.count)), "hasMore": .bool(false)])
    }

    @Test func everyAppearanceOperationHasASchemaAndBuiltInsDoNotNeedInventedUUIDs() throws {
        let names = Set(AgentOperationCatalog.operations.filter { $0.name.hasPrefix("themes.") || $0.name.hasPrefix("syntaxes.") }.map(\.name))
        #expect(names == AgentAppearanceSchemas.operationNames)
        #expect(names.count == 23)
        for name in ThemeCatalog.builtInNames {
            let input = request("themes.selectBuiltIn", parameters: ["name": .string(name), "appearance": .string("light")])
            #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
        }
        for name in ScriptSyntax.names {
            let input = request("syntaxes.getBuiltIn", parameters: ["name": .string(name)])
            #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
            let syntax = try ScriptSyntax.definition(name)
            try AgentOperationSchemas.validateResult(["name": .string(name), "source": .string(syntax.source), "versionToken": .string("built-in")], for: input)
        }
    }

    @Test func canonicalThemeRoundTripPreservesUnknownImportedObjectsAndIdentity() throws {
        let theme = EditorThemeDefinition(name: "Café 🐼", unknownFields: [
            "draftsSource": .object(["future": .array([.bool(false), .number(1.25), .string("É")])]),
            "future": .object(["keep": .bool(true)])])
        let value = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(theme))
        let input = request("themes.update", targets: [.init(kind: .theme, id: theme.id)], parameters: ["theme": value])
        let values = try AgentOperationSchemas.validatedParameters(for: input)
        #expect(values == input.parameters)
        let restored = try JSONDecoder().decode(EditorThemeDefinition.self, from: JSONEncoder().encode(try #require(values["theme"])))
        #expect(restored == theme)
        let wrong = request("themes.update", targets: [.init(kind: .theme, id: UUID())], parameters: input.parameters)
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validatedParameters(for: wrong) }
    }

    @Test func creationLeavesModelDefaultsAndColorValidationToTheExistingType() throws {
        let input = request("themes.create", parameters: ["theme": .object([:])])
        #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
        try EditorThemeDefinition().validate()
        let invalid = EditorThemeDefinition(foreground: "invalid")
        #expect(throws: (any Error).self) { try invalid.validate() }
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("themes.create", parameters: ["theme": .object(["type": .string("file")])]))
        }
    }

    @Test func customGrammarRoundTripKeepsUnknownSourceFields() throws {
        var source = try ScriptSyntax.definition("Markdown").object
        source["name"] = "Café Grammar 🐼"; source["future"] = ["keep": [false, "É"]]
        let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: source, options: [.sortedKeys]))
        let value = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(syntax))
        let input = request("syntaxes.get", targets: [.init(kind: .syntax, id: syntax.id)])
        try AgentOperationSchemas.validateResult(["definition": value, "versionToken": .string("snapshot")], for: input)
        let restored = try JSONDecoder().decode(SyntaxDefinition.self, from: JSONEncoder().encode(value))
        #expect(restored == syntax)
        #expect(restored.source == syntax.source)
        #expect(throws: (any Error).self) { try SyntaxDefinition(data: Data(#"{"name":"Missing rules"}"#.utf8)) }
    }

    @Test func inlineImportsRetainTheExactTextAndDoNotSelectByDefault() throws {
        let source: AgentJSONValue = .object(["kind": .string("inline"), "text": .string("{\n  \"future\": \"É🐼\"\n}")])
        for name in ["themes.install", "syntaxes.install"] {
            let values = try AgentOperationSchemas.validatedParameters(for: request(name, parameters: ["source": source]))
            #expect(values["source"] == source)
            #expect(values["mode"] == .string("custom"))
            #expect(values["selectAppearance"] == nil)
        }
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("themes.install", parameters: ["source": source, "selectAppearance": .string("dark")]))
        }
    }

    @Test func sourceVariantsCannotSmuggleAnotherPathOrUseTransfersAsLiveFiles() throws {
        let source: AgentJSONValue = .object(["kind": .string("transfer"), "transferID": .string(UUID().uuidString)])
        _ = try AgentOperationSchemas.validatedParameters(for: request("syntaxes.install", parameters: ["source": source]))
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("syntaxes.install", parameters: ["source": source, "mode": .string("file")]))
        }
        let extra: AgentJSONValue = .object(["kind": .string("inline"), "text": .string("{}"), "path": .string("secret")])
        #expect(throws: AgentSchemaError.self) { try AgentImportSource.validate(extra) }
        let bookmark: AgentJSONValue = .object(["kind": .string("bookmark"), "bookmarkID": .string(UUID().uuidString), "path": .string("é/🐼.json")])
        _ = try AgentOperationSchemas.validatedParameters(for: request("themes.install", parameters: ["source": bookmark, "mode": .string("file")]))
    }

    @Test func installReportsDistinguishExistingBuiltInsFromNewResources() throws {
        let source: AgentJSONValue = .object(["kind": .string("installationURL"), "url": .string(try ThemeInstallation.builtIn("Dark").url.absoluteString)])
        let input = request("themes.install", parameters: ["source": source])
        let result: [String: AgentJSONValue] = ["resource": .null, "builtInName": .string("Dark"), "selection": .null]
        try AgentOperationSchemas.validateResult(result, for: input)
        var ambiguous = result; ambiguous["resource"] = receipt()
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(ambiguous, for: input) }
        var wrong = result; wrong["builtInName"] = .string("Light")
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(wrong, for: input) }
    }

    @Test func themeSelectionSeparatesTheLocalSlotFromTheDefinitionVersion() throws {
        let id = UUID()
        let input = request("themes.select", targets: [.init(kind: .theme, id: id)], parameters: ["appearance": .string("dark"), "expectedThemeVersion": .string("theme-snapshot")])
        #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
        let result: [String: AgentJSONValue] = ["themeID": .string(id.uuidString), "appearance": .string("dark"), "versionToken": .string("new-slot")]
        try AgentOperationSchemas.validateResult(result, for: input)
        var wrong = result; wrong["appearance"] = .string("light")
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(wrong, for: input) }
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("themes.select", targets: input.targets, parameters: ["appearance": .string("dark")]))
        }
    }

    @Test func selectionReferencesKeepBuiltInNamesSeparateFromInstalledUUIDs() throws {
        let input = request("themes.selection", parameters: ["appearance": .string("light")])
        var result: [String: AgentJSONValue] = ["appearance": .string("light"), "reference": .object(["type": .string("builtIn"), "name": .string("Light")]), "versionToken": .string("slot")]
        try AgentOperationSchemas.validateResult(result, for: input)
        result["reference"] = .null
        try AgentOperationSchemas.validateResult(result, for: input)
        result["reference"] = .object(["type": .string("file"), "name": .string("External")])
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: input) }
    }

    @Test func replacementAndDeletionRepliesCannotNameAnotherResource() throws {
        for family in ["themes", "syntaxes"] {
            let kind: AgentResourceKind = family == "themes" ? .theme : .syntax
            let target = AgentResourceReference(kind: kind, id: UUID())
            var result: [String: AgentJSONValue] = ["resource": receipt(target.id)]
            if family == "themes" { result["selection"] = .null }
            try AgentOperationSchemas.validateResult(result, for: request(family + ".replace", targets: [target]))
            result["resource"] = receipt()
            #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: request(family + ".replace", targets: [target])) }
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validateResult(["deletedIDs": .array([.string(UUID().uuidString)])], for: request(family + ".delete", targets: [target]))
            }
        }
    }

    @Test func exportsBindTheResourceFormatAndUTF16ChunkLength() throws {
        let target = AgentResourceReference(kind: .theme, id: UUID())
        let input = request("themes.export", targets: [target])
        var result: [String: AgentJSONValue] = ["resourceID": .string(target.id.uuidString), "versionToken": .string("snapshot"), "format": .string("native"), "content": chunk("É🐼")]
        try AgentOperationSchemas.validateResult(result, for: input)
        result["format"] = .string("drafts")
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: input) }
        result["format"] = .string("native"); result["resourceID"] = .string(UUID().uuidString)
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: input) }
    }
    @Test func builtInCatalogsMatchCoreAndCannotSilentlyOmitNames() throws {
        for (operation, names) in [("themes.list", ThemeCatalog.builtInNames), ("syntaxes.list", ScriptSyntax.names)] {
            let input = request(operation)
            var result: [String: AgentJSONValue] = ["items": .array([]), "nextCursor": .null,
                "builtInNames": .array(names.map(AgentJSONValue.string))]
            try AgentOperationSchemas.validateResult(result, for: input)
            result["builtInNames"] = .array([])
            #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: input) }
        }
    }

    @Test func optionalInstallSelectionRequiresItsOwnVersionAndReceipt() throws {
        let source: AgentJSONValue = .object(["kind": .string("inline"),
            "text": .string(String(decoding: try JSONEncoder().encode(EditorThemeDefinition()), as: UTF8.self))])
        let input = request("themes.install", parameters: ["source": source, "selectAppearance": .string("dark"),
            "expectedSelectionVersion": .string("slot-snapshot")])
        _ = try AgentOperationSchemas.validatedParameters(for: input)
        var result: [String: AgentJSONValue] = ["resource": receipt(), "builtInName": .null,
            "selection": .object(["appearance": .string("dark"), "versionToken": .string("new-slot")])]
        try AgentOperationSchemas.validateResult(result, for: input)
        result["selection"] = .null
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: input) }
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("themes.install", parameters: ["source": source,
                "expectedSelectionVersion": .string("slot-snapshot")]))
        }
    }
}
