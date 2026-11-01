import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent encoded preference preparation") @MainActor
struct AgentEncodedPreferenceAccessTests {
    private func syntaxAddress(_ name: String, syntax: String = "Markdown") -> AgentJSONValue {
        .object(["id": .string("syntax." + name),
                 "syntax": .object(["type": .string("builtIn"), "name": .string(syntax)])])
    }
    private func object(_ text: String) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8))
    }

    @Test func allSyntaxEditsUseExistingConsumersAndResetOnlyOneField() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let changes: [(String, AgentJSONValue)] = [
            ("fontName", .string("未知 Nerd Font")), ("monospaceFontName", .string("Mono 🐼")), ("fontSize", .integer(23)),
            ("lineHeightMultiple", .number(Decimal(string: "1.7")!)), ("paragraphSpacing", .integer(5)),
            ("horizontalMargin", .integer(11)), ("verticalMargin", .integer(16)), ("maximumWidth", .integer(900)),
            ("spelling", .bool(false)), ("grammar", .bool(true)), ("smartQuotes", .bool(true)), ("smartDashes", .bool(true)),
            ("autoMatch", .bool(true)), ("autoRenumber", .bool(false)), ("autocorrection", .bool(false)),
            ("writingTools", .bool(false)), ("paragraphNumbers", .bool(true)), ("highlightInsertionPoint", .bool(true))
        ]
        let original = #"{"Markdown":{"future":{"label":"保持🐼"},"other":true},"TaskPaper":{"future":17}}"#
        for (field, value) in changes {
            let address = syntaxAddress(field)
            let edit = try AgentEncodedPreferenceAccess.prepare(address: address, value: value, configuration: original, syntax: syntax)
            let saved = try object(edit.configuration)
            guard case .object(let fields) = saved["Markdown"] else { Issue.record("Missing syntax fields"); continue }
            let expected = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
            #expect(fields[field] == expected)
            #expect(fields["future"] == .object(["label": .string("保持🐼")]))
            #expect(saved["TaskPaper"] == .object(["future": .number(17)]))
            let read = try AgentEncodedPreferenceAccess.read(address: address, configuration: edit.configuration,
                syntax: syntax, inherited: value)
            #expect(read.effectiveValue == value && read.origin == "stored" && read.hasOverride)
            let reset = try AgentEncodedPreferenceAccess.prepare(address: address, value: nil, configuration: edit.configuration, syntax: syntax)
            #expect(try object(reset.configuration) == object(original))
            #expect(!edit.requiresHumanApproval)
        }
        let name = try AgentEncodedPreferenceAccess.prepare(address: syntaxAddress("fontName"), value: .string("Nerd Font"), configuration: "{}", syntax: syntax)
        #expect(EditorSyntaxFontPreferences.font(for: "Markdown", encoded: name.configuration, defaultName: "System", defaultSize: 17).name == "Nerd Font")
        let size = try AgentEncodedPreferenceAccess.prepare(address: syntaxAddress("fontSize"), value: .integer(23), configuration: "{}", syntax: syntax)
        #expect(EditorSyntaxFontPreferences.font(for: "Markdown", encoded: size.configuration, defaultName: "System", defaultSize: 17).size == 23)
    }

    @Test func systemInheritanceAndIndentationKeepDistinctStorage() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let original = #"{"Markdown":{"autocorrection":false,"writingTools":true,"future":7}}"#
        let edit = try AgentEncodedPreferenceAccess.prepare(address: syntaxAddress("autocorrection"), value: .null, configuration: original, syntax: syntax)
        #expect(EditorTextInputPreferences.override(.autocorrection, for: "Markdown", encoded: edit.configuration) == nil)
        #expect(EditorTextInputPreferences.override(.writingTools, for: "Markdown", encoded: edit.configuration) == true)
        let indentation = try AgentEncodedPreferenceAccess.prepare(address: syntaxAddress("indentation"), value: .string("fourSpaces"), configuration: #"{"TaskPaper":"twoSpaces","future":{"v":true}}"#, syntax: syntax)
        #expect(EditorIndentationPreferences.style(for: "Markdown", encoded: indentation.configuration) == .fourSpaces)
        let reset = try AgentEncodedPreferenceAccess.prepare(address: syntaxAddress("indentation"), value: nil, configuration: indentation.configuration, syntax: syntax)
        #expect(try object(reset.configuration) == object(#"{"TaskPaper":"twoSpaces","future":{"v":true}}"#))
    }

    @Test func everyMarkdownOptionPreservesUnknownDataAndResetsPrecisely() throws {
        let original = #"{"future":{"v":"🐼"},"unrelated":false}"#
        for (engine, options) in [("multi", MarkdownPreferences.multiOptions), ("github", MarkdownPreferences.githubOptions)] {
            for option in options {
                let address = AgentJSONValue.object(["id": .string("markdown." + engine + "." + option.id)])
                let edit = try AgentEncodedPreferenceAccess.prepare(address: address, value: .bool(!option.defaultValue), configuration: original)
                #expect(MarkdownPreferences.options(engine: engine, json: edit.configuration)[option.id] == !option.defaultValue)
                #expect(edit.storageKey == (engine == "multi" ? MarkdownPreferences.multiKey : MarkdownPreferences.githubKey))
                let reset = try AgentEncodedPreferenceAccess.prepare(address: address, value: nil, configuration: edit.configuration)
                #expect(try object(reset.configuration) == object(original))
            }
        }
    }

    @Test func rejectsMalformedStoresWrongSyntaxAndUnknownFeatureWithoutWriting() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        for configuration in ["not JSON", "[]", #"{"Markdown":false}"#] {
            #expect(throws: (any Error).self) {
                try AgentEncodedPreferenceAccess.prepare(address: syntaxAddress("fontName"), value: .string("X"), configuration: configuration, syntax: syntax)
            }
            #expect(throws: (any Error).self) {
                try AgentEncodedPreferenceAccess.prepare(address: syntaxAddress("fontName"), value: nil, configuration: configuration, syntax: syntax)
            }
        }
        #expect(throws: AgentErrorCode.notFound) {
            try AgentEncodedPreferenceAccess.prepare(address: syntaxAddress("fontName", syntax: "TaskPaper"), value: .string("X"), configuration: "{}", syntax: syntax)
        }
        var feature: [String: AgentJSONValue] = ["id": .string("syntax.feature"), "feature": .string("not-declared"),
            "syntax": .object(["type": .string("builtIn"), "name": .string("Markdown")])]
        #expect(throws: AgentErrorCode.notFound) {
            try AgentEncodedPreferenceAccess.prepare(address: .object(feature), value: .bool(true), configuration: "{}", syntax: syntax)
        }
        feature["id"] = .string("private.token")
        #expect(throws: (any Error).self) {
            try AgentEncodedPreferenceAccess.prepare(address: .object(feature), value: nil, configuration: "{}", syntax: syntax)
        }
        #expect(throws: AgentErrorCode.unavailable) {
            try AgentEncodedPreferenceAccess.prepare(address: .object(["id": .string("application.launchAtLogin")]), value: .bool(true), configuration: "{}")
        }
    }

    @Test func shortcutChangesPreserveImportedFieldsAndFlagGlobalApproval() throws {
        let local = AgentJSONValue.object(["id": .string("commands.shortcut"), "command": .string("New Draft")])
        let original = #"{"New Draft":{"key":"n","modifiers":["command"],"future":17},"future":{"v":"保持"}}"#
        let edit = try AgentEncodedPreferenceAccess.prepare(address: local,
            value: .object(["key": .string(""), "modifiers": .array([])]), configuration: original)
        #expect(CommandShortcuts.binding("New Draft", configuration: edit.configuration).key.isEmpty)
        guard case .object(let fields) = try object(edit.configuration)["New Draft"] else { Issue.record("Missing binding"); return }
        #expect(fields["future"] == .number(17))
        #expect(!edit.requiresHumanApproval)
        let reset = try AgentEncodedPreferenceAccess.prepare(address: local, value: nil, configuration: edit.configuration)
        #expect(CommandShortcuts.binding("New Draft", configuration: reset.configuration).key == "n")
        #expect(try object(reset.configuration)["New Draft"] == .object(["future": .number(17)]))
        let resetRead = try AgentEncodedPreferenceAccess.read(address: local, configuration: reset.configuration)
        #expect(resetRead.origin == "default" && !resetRead.hasOverride)
        #expect(try object(reset.configuration)["future"] == .object(["v": .string("保持")]))
        let global = AgentJSONValue.object(["id": .string("commands.shortcut"), "command": .string("Quick Capture")])
        #expect(try AgentEncodedPreferenceAccess.prepare(address: global, value: nil, configuration: "{}").requiresHumanApproval)
        #expect(throws: (any Error).self) {
            try AgentEncodedPreferenceAccess.prepare(address: local, value: .object(["key": .string("ab"), "modifiers": .array([])]), configuration: original)
        }
    }
    @Test func readsDistinguishStoredInheritedSystemAndInvalidValues() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let address = syntaxAddress("fontSize")
        let missing = try AgentEncodedPreferenceAccess.read(address: address, configuration: "{}", syntax: syntax, inherited: .integer(17))
        #expect(missing.effectiveValue == .integer(17))
        #expect(missing.origin == "inherited" && !missing.hasOverride)
        let stored = try AgentEncodedPreferenceAccess.read(address: address, configuration: #"{"Markdown":{"fontSize":23,"future":"private"}}"#, syntax: syntax, inherited: .integer(17))
        #expect(stored.effectiveValue == .integer(23))
        #expect(stored.origin == "stored" && stored.hasOverride)
        for configuration in ["invalid", #"{"Markdown":false}"#, #"{"Markdown":{"fontSize":-1}}"#] {
            let invalid = try AgentEncodedPreferenceAccess.read(address: address, configuration: configuration, syntax: syntax, inherited: .integer(17))
            #expect(invalid.effectiveValue == .integer(17))
            #expect(invalid.origin == "invalid" && invalid.hasOverride)
        }
        let system = try AgentEncodedPreferenceAccess.read(address: syntaxAddress("autocorrection"), configuration: "{}", syntax: syntax)
        #expect(system.effectiveValue == .null && system.origin == "system" && !system.hasOverride)
        #expect(throws: AgentErrorCode.unavailable) {
            try AgentEncodedPreferenceAccess.read(address: address, configuration: "{}", syntax: syntax)
        }
        let markdown = AgentJSONValue.object(["id": .string("markdown.github.tables")])
        let defaultValue = try AgentEncodedPreferenceAccess.read(address: markdown, configuration: "{}")
        #expect(defaultValue.effectiveValue == .bool(true) && defaultValue.origin == "default")
        let command = AgentJSONValue.object(["id": .string("commands.shortcut"), "command": .string("New Draft")])
        let imported = try AgentEncodedPreferenceAccess.read(address: command,
            configuration: #"{"New Draft":{"key":"Z","modifiers":["command"],"future":"preserved"}}"#)
        guard case .object(let value) = imported.effectiveValue else { Issue.record("Missing command value"); return }
        #expect(value["key"] == .string("z"))
        #expect(value["future"] == nil)
    }

    @Test func declaredFeatureRequiresExactInstalledIdentityAndKeepsOtherFeatures() throws {
        let id = UUID()
        let source = try ScriptSyntax.definition("Markdown").source
        var payload = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any])
        payload["name"] = "QA 語法"
        payload["featureKeys"] = [["id": "qa", "name": "QA", "description": "Neutral", "defaultValue": true]]
        let definition = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: payload), id: id)
        let address = AgentJSONValue.object(["id": .string("syntax.feature"), "feature": .string("qa"),
            "syntax": .object(["type": .string("installed"), "id": .string(id.uuidString)])])
        let initial = try AgentEncodedPreferenceAccess.read(address: address, configuration: "{}", syntax: definition)
        #expect(initial.effectiveValue == .bool(true) && initial.origin == "default")
        let original = #"{"QA 語法":{"other":true},"future":{"v":7}}"#
        let changed = try AgentEncodedPreferenceAccess.prepare(address: address, value: .bool(false), configuration: original, syntax: definition)
        #expect(SyntaxFeaturePreferences.values(for: definition.name, encoded: changed.configuration)["qa"] == false)
        let reset = try AgentEncodedPreferenceAccess.prepare(address: address, value: nil, configuration: changed.configuration, syntax: definition)
        #expect(try object(reset.configuration) == object(original))
        var other = definition; other.id = UUID()
        #expect(throws: AgentErrorCode.notFound) {
            try AgentEncodedPreferenceAccess.read(address: address, configuration: "{}", syntax: other)
        }
        #expect(throws: AgentErrorCode.notFound) {
            try AgentEncodedPreferenceAccess.prepare(address: address, value: .bool(false), configuration: "{}", syntax: other)
        }
    }

    @Test func shortcutResetChecksConflictsAndDoesNotChangeTheOriginal() throws {
        let address = AgentJSONValue.object(["id": .string("commands.shortcut"), "command": .string("New Draft")])
        let original = #"{"New Draft":{"key":"","modifiers":[]},"New Window":{"key":"n","modifiers":["command"]}}"#
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentEncodedPreferenceAccess.prepare(address: address, value: nil, configuration: original)
        }
        #expect(CommandShortcuts.binding("New Draft", configuration: original).key.isEmpty)
        let global = AgentJSONValue.object(["id": .string("commands.shortcut"), "command": .string("Quick Capture")])
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentEncodedPreferenceAccess.prepare(address: global,
                value: .object(["key": .string("q"), "modifiers": .array([.string("shift")])]), configuration: "{}")
        }
    }

}
