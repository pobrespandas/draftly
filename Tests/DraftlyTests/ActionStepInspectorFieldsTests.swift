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
        #expect(fields.map(\.key) == ["allowAsync", "name", "script", "source", "template", "url"])
        #expect(fields.map(\.id) == fields.map(\.key))
        #expect(fields.filter(\.isMultiline).map(\.key) == ["script", "source", "template"])
        #expect(fields.filter(\.allowsTagInsertion).map(\.key) == ["script", "source", "template"])
        #expect(fields.map(\.minHeight) == [nil, nil, 360, 360, 180, nil])
    }

    @Test func emptyStepsHaveNoFields() {
        #expect(ActionStepInspectorFields.fields(for: ActionStep("script")).map(\.key) == ["allowAsync", "script"])
        #expect(ActionStepInspectorFields.fields(for: ActionStep("futureStep")).isEmpty)
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

    @Test func includedActionTargetUUIDIsEditableAndDistinctFromStepIdentity() {
        let target = UUID()
        var imported = ActionStep("includeAction", ["uuid": target.uuidString, "name": "Old helper", "futureOption": "Keep"])
        imported.unknownFields = ["future": .bool(true)]
        let original = imported
        #expect(ActionStepInspectorFields.fields(for: imported).map(\.key) == ["futureOption", "name", "uuid"])
        #expect(imported == original && imported.id != target)
        #expect(ActionStepInspectorFields.fields(for: ActionStep("includeAction")).map(\.key) == ["name", "uuid"])
        #expect(!ActionStepInspectorFields.fields(for: ActionStep("script", ["uuid": target.uuidString])).contains { $0.key == "uuid" })
    }

    @Test(arguments: [String?.none, "false", "true", "futureValue"])
    func createDraftOpenOptionHasOneDedicatedControlWithoutRewritingImports(openInEditor: String?) {
        var step = ActionStep("createDraft", ["template": "Neutral café 🐼", "futureOption": "Keep"])
        step.values["openInEditor"] = openInEditor
        let original = step
        #expect(ActionStepInspectorFields.fields(for: step).map(\.key) == ["flagType", "flagged", "folder", "futureOption", "syntax", "tags", "template"])
        #expect(step == original)
    }

    @Test func windowConfigurationExposesAbsentReferencesWithoutChangingImportedToggleValues() {
        var step = ActionStep("configureWindow", ["showActionBar": "hide", "showTagEntry": "future", "futureOption": "Keep café 🐼"])
        step.unknownFields = ["future": .array([.bool(true)])]
        let original = step
        #expect(ActionStepInspectorFields.fields(for: step).map(\.key) == ["futureOption", "loadActionBarGroup", "loadActionGroup", "loadWorkspace"])
        #expect(step == original)
        #expect(WindowConfigurationOptions.selectionValue(step.values["showActionBar"]) == "false")
        #expect(WindowConfigurationOptions.selectionValue(step.values["showTagEntry"]) == "future")
        #expect(WindowConfigurationOptions.selectionValue(nil) == "unchanged")
        #expect(WindowConfigurationOptions.selectionValue("show") == "true")
        #expect(WindowConfigurationOptions.selectionValue("1") == "true")
        #expect(WindowConfigurationOptions.selectionValue("0") == "false")
        #expect(WindowConfigurationOptions.selectionValue("") == "")
        #expect(ActionStepInspectorFields.fields(for: ActionStep("configureWindow")).map(\.key)
            == ["loadActionBarGroup", "loadActionGroup", "loadWorkspace"])
    }

    @Test func promptShowsMissingDocumentedFieldsWithoutInsertingDefaultsIntoImports() {
        let empty = ActionStep("prompt")
        #expect(ActionStepInspectorFields.fields(for: empty).map(\.key) == ["buttons", "key", "message", "textFieldDefault", "title"])
        #expect(ActionStepInspectorFields.textValue(for: "buttons", in: empty) == "OK")
        #expect(ActionStepInspectorFields.textValue(for: "key", in: empty) == "prompt")
        #expect(ActionStepInspectorFields.textValue(for: "title", in: empty) == "Prompt")
        var imported = ActionStep("prompt", ["key": "", "title": "Café 🐼", "includeTextField": "1", "futureOption": "Keep"])
        imported.unknownFields = ["future": .bool(false)]
        let original = imported
        let fields = ActionStepInspectorFields.fields(for: imported)
        #expect(fields.map(\.key) == ["buttons", "futureOption", "key", "message", "textFieldDefault", "title"])
        #expect(fields.first { $0.key == "message" }?.isMultiline == true)
        #expect(fields.first { $0.key == "message" }?.minHeight == 100)
        #expect(ActionStepInspectorFields.textValue(for: "key", in: imported).isEmpty)
        #expect(ActionStepInspectorFields.textValue(for: "title", in: imported) == "Café 🐼")
        #expect(imported == original)
        #expect(ActionStepInspectorFields.textValue(for: "title", in: ActionStep("futureStep")).isEmpty)
    }

}
