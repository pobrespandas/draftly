import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action step value policies")
struct ActionStepValuePolicyTests {
    @Test(arguments: [String?.none, "", "false", "true", "0", "1", "show", "hide", "TRUE", "False", " true", "future"])
    func booleanOptionsRetainTheirDistinctImportedValuePolicies(raw: String?) throws {
        var promptStep = ActionStep("prompt")
        promptStep.values["includeTextField"] = raw
        promptStep.values["includeCancelButton"] = raw
        let original = promptStep
        let prompt = try ActionPromptStep(promptStep) { $0 }
        let fields = try #require(prompt.values["fields"] as? [[String: Any]])
        #expect(fields.count == (raw == "true" || raw == "1" ? 1 : 0))
        #expect(prompt.values["isCancellable"] as? Bool == (raw != "false"))
        #expect(promptStep == original)

        var creationStep = ActionStep("createDraft")
        creationStep.values["openInEditor"] = raw
        let creation = try ActionCreateDraftStep(creationStep, text: "café 🐼", validateSyntax: { _ in }, render: { $0 })
        #expect(creation.opensInEditor == (raw != "false"))
        #expect((creation.note.accessedAt != nil) == (raw != "false"))

        var requiredStep = ActionStep("configurationKey", ["key": "neutral"])
        requiredStep.values["requiresInitialConfiguration"] = raw
        let action = DraftAction(name: "Neutral", steps: [requiredStep])
        let configuration = try ActionInitialConfiguration(action: action, steps: action.steps)
        #expect(configuration.needsPrompt == (raw == "true" || raw == "1"))
    }

    @Test(arguments: ["future", "", "String", " text"])
    func unknownConfigurationTypesKeepReadFallbackButFailInitialConfiguration(type: String) throws {
        let step = ActionStep("configurationKey", ["key": "neutral", "dataType": type,
            "defaultStringValue": "café 🐼", "requiresInitialConfiguration": "false"])
        let field = ActionConfigurationField(step)
        #expect(field.dataType == type)
        #expect(field.textValue(configuredValues: [:]) == "café 🐼")
        #expect(field.textValue(configuredValues: ["neutral": ""]) == "")
        let action = DraftAction(name: "Neutral", steps: [step])
        #expect(throws: (any Error).self) {
            try ActionInitialConfiguration(action: action, steps: action.steps)
        }
    }

    @Test func promptMissingValuesAndExplicitEmptyValuesStayDistinct() throws {
        let missing = try ActionPromptStep(ActionStep("prompt")) { $0 }
        #expect(missing.key == "prompt" && missing.titles == ["OK"])
        #expect(missing.values["title"] as? String == "Prompt")
        let empty = try ActionPromptStep(ActionStep("prompt", ["title": "", "message": "",
            "includeTextField": "true", "textFieldDefault": ""])) { $0 }
        #expect(empty.values["title"] as? String == "")
        #expect(empty.values["message"] as? String == "")
        let fields = try #require(empty.values["fields"] as? [[String: Any]])
        #expect(fields.first?["value"] as? String == "")
    }
}
