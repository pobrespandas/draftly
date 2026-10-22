import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Action step inspector fields")
struct ActionStepInspectorFieldsTests {
    @Test func mixedFieldsKeepOrderAndExcludeStoredMetadataKeys() {
        let keys = ["url", "template", "script", "source", "name", "data", "parameters", "values", "uuid", "isEnabled", "platforms"]
        let step = ActionStep("script", Dictionary(uniqueKeysWithValues: keys.map { ($0, "value") }))
        let fields = ActionStepInspectorFields.fields(for: step)
        #expect(fields.map(\.key) == ["name", "script", "source", "template", "url"])
        #expect(fields.map(\.id) == fields.map(\.key))
        #expect(fields.filter(\.isMultiline).map(\.key) == ["script", "source", "template"])
        #expect(fields.filter(\.allowsTagInsertion).map(\.key) == ["script", "source", "template"])
        #expect(fields.map(\.minHeight) == [nil, 360, 360, 180, nil])
    }

    @Test func emptyStepsHaveNoFields() {
        #expect(ActionStepInspectorFields.fields(for: ActionStep("script")).isEmpty)
    }

    @Test func unknownFieldsUseSingleLineEditorsAndKeepExactKeys() {
        let step = ActionStep("futureStep", ["futureOption": "café 🐼", "Script": "mixed case", "script ": "trailing space"])
        let fields = ActionStepInspectorFields.fields(for: step)
        #expect(fields.map(\.key) == ["Script", "futureOption", "script "])
        #expect(fields.allSatisfy { !$0.isMultiline && !$0.allowsTagInsertion && $0.minHeight == nil })
    }

    @Test(arguments: [Bool?.none, .some(true), .some(false)])
    func descriptorCalculationPreservesStepAndMetadata(isEnabled: Bool?) {
        var step = ActionStep("futureStep", ["template": "[[draft]]", "platforms": "3", "futureOption": "café 🐼"])
        step.isEnabled = isEnabled
        step.unknownFields = ["platforms": .number(3), "future": .object(["nested": .array([.null, .bool(false)])])]
        let original = step
        _ = ActionStepInspectorFields.fields(for: step)
        #expect(step == original)
        #expect(step.id == original.id)
        #expect(step.values == original.values)
        #expect(step.unknownFields == original.unknownFields)
        #expect(step.isEnabled == original.isEnabled)
    }
    @Test func configurationUsesTypedControlsWithoutDuplicatingKnownOrDiscardingUnknownFields() {
        let keys = ["key", "name", "description", "dataType", "exampleValue",
            "requiresInitialConfiguration", "defaultValue", "defaultStringValue",
            "defaultTextValue", "defaultNumberValue", "defaultBoolValue", "futureOption"]
        let step = ActionStep("configurationKey", Dictionary(uniqueKeysWithValues: keys.map { ($0, "Keep café 🐼") }))
        let original = step
        #expect(ActionStepInspectorFields.fields(for: step).map(\.key) == ["futureOption"])
        #expect(step == original)
        #expect(ActionStepInspectorFields.configurationTypes.compactMap(ActionStepInspectorFields.configurationDefaultKey)
            == ["defaultStringValue", "defaultTextValue", "defaultBoolValue", "defaultNumberValue"])
        #expect(ActionStepInspectorFields.configurationDefaultKey(for: "future") == nil)
    }

}
