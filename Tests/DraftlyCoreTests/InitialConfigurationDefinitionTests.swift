import Foundation
import Testing
@testable import DraftlyCore

@Suite("Initial configuration definition")
struct InitialConfigurationDefinitionTests {
    private func field(_ key: String = "label", type: String = "string", required: String = "true") -> ActionStep {
        ActionStep("configurationKey", ["key": key, "dataType": type, "requiresInitialConfiguration": required,
            "name": "Neutral label", "description": "Neutral description", "exampleValue": "Example", "defaultStringValue": "Default"])
    }
    private func action(_ steps: [ActionStep]) -> DraftAction { DraftAction(name: "Neutral", steps: steps) }

    @Test func importedDefaultsDoNotConfirmFirstUse() throws {
        let step = field(); var action = action([step]); action.configuredValues = ["label": "Default"]
        let definition = try ActionInitialConfiguration(action: action, steps: action.steps)
        #expect(definition.needsPrompt)
        #expect(definition.prompt["isCancellable"] as? Bool == true)
        #expect((definition.prompt["buttons"] as? [[String: Any]])?.count == 1)
        let fields = try #require(definition.prompt["fields"] as? [[String: Any]])
        #expect(fields.count == 2 && fields[0]["kind"] as? String == "label")
        #expect(fields[1]["value"] as? String == "Default" && fields[1]["placeholder"] as? String == "Example")
    }

    @Test func acceptancePreservesUnknownValuesAndMarksOnlyRequiredSchema() throws {
        let step = field(); var original = action([step])
        original.configuredValues = ["unknown": "Keep"]
        original.scriptMetadata = ["unknown": "Keep"]
        original.rawPayload = "{\"unknown\":true}"
        let definition = try ActionInitialConfiguration(action: original, steps: original.steps)
        let configured = try definition.configured(["index": 0, "fields": ["label": ""]])
        #expect(configured.configuredValues == ["unknown": "Keep", "label": ""])
        #expect(configured.scriptMetadata?["unknown"] == "Keep" && configured.rawPayload == original.rawPayload)
        #expect(try !ActionInitialConfiguration(action: configured, steps: configured.steps).needsPrompt)
        #expect(original.scriptMetadata?[ActionInitialConfiguration.confirmationKey] == nil)
        var defaultsChanged = step; defaultsChanged.values["defaultStringValue"] = "Other"
        #expect(try !ActionInitialConfiguration(action: configured, steps: [defaultsChanged]).needsPrompt)
        #expect(try ActionInitialConfiguration(action: configured, steps: [step, field("new")]).needsPrompt)
    }

    @Test func disabledAndOptionalFieldsDoNotRequireFirstUse() throws {
        var disabled = field(); disabled.isEnabled = false
        let steps = [disabled, field("optional", required: "false")]
        #expect(try !ActionInitialConfiguration(action: action(steps), steps: steps).needsPrompt)
        let one = field(required: "1")
        #expect(try ActionInitialConfiguration(action: action([one]), steps: [one]).needsPrompt)
    }

    @Test func fieldKindsAndTypedFalseZeroValuesArePreserved() throws {
        let steps = [field("bool", type: "boolean"), field("number", type: "number"), field("body", type: "text")]
        let definition = try ActionInitialConfiguration(action: action(steps), steps: steps)
        let controls = try #require(definition.prompt["fields"] as? [[String: Any]])
        #expect(controls.compactMap { $0["kind"] as? String }.filter { $0 != "label" } == ["switch", "number", "textView"])
        let copy = try definition.configured(["index": 0, "fields": ["bool": false, "number": 0, "body": "café 🐼\nText"]])
        #expect(copy.configuredValues == ["bool": "false", "number": "0", "body": "café 🐼\nText"])
    }

    @Test func cancellationDoesNotProduceAConfiguredCopy() throws {
        let steps = [field()]; let definition = try ActionInitialConfiguration(action: action(steps), steps: steps)
        for response in [nil, ["index": 1], ["index": -1]] as [Any?] {
            #expect(throws: ActionExecutionInterruption.cancelled) { try definition.configured(response) }
        }
    }

    @Test func confirmationUnionKeepsRootAndIncludedFieldsConfirmed() throws {
        let root = field("root"), child = field("child")
        var action = action([root])
        action = try ActionInitialConfiguration(action: action, steps: [root]).configured(["index": 0, "fields": ["root": "Root"]])
        let included = try ActionInitialConfiguration(action: action, steps: [root, child])
        let controls = try #require(included.prompt["fields"] as? [[String: Any]])
        #expect(controls.compactMap { $0["key"] as? String } == ["child"])
        let configured = try included.configured(["index": 0, "fields": ["child": "Child"]])
        #expect(try !ActionInitialConfiguration(action: configured, steps: [root]).needsPrompt)
        #expect(try !ActionInitialConfiguration(action: configured, steps: [root, child]).needsPrompt)
        #expect(configured.configuredValues == ["root": "Root", "child": "Child"])
    }

    @Test func malformedDefinitionsAndResponsesFailExplicitly() throws {
        for step in [field(" "), field(type: "unknown")] {
            #expect(throws: (any Error).self) { try ActionInitialConfiguration(action: action([step]), steps: [step]) }
        }
        for (type, invalid) in [("boolean", 1), ("number", true), ("number", Double.infinity), ("string", 3)] as [(String, Any)] {
            let steps = [field(type: type)]
            let definition = try ActionInitialConfiguration(action: action(steps), steps: steps)
            #expect(throws: (any Error).self) { try definition.configured(["index": 0, "fields": ["label": invalid]]) }
            #expect(throws: (any Error).self) { try definition.configured(["index": 0, "fields": [String: Any]()]) }
        }
    }
}
