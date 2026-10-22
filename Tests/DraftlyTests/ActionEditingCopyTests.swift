import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Action editing copy")
struct ActionEditingCopyTests {
    @Test(arguments: [Bool?.none, .some(true), .some(false)])
    func openingPreservesImportedValuesAndDoesNotApplyNewStepDefaults(isEnabled: Bool?) throws {
        var step = ActionStep("script", ["script": "Original café 🐼"])
        step.isEnabled = isEnabled
        step.unknownFields = ["platforms": .number(3), "future": .object(["nested": .null])]
        var original = DraftAction(name: "Imported action", steps: [step])
        original.rawPayload = "{\"future\":true}"
        original.unknownFields = ["futureOption": .array([.bool(false), .string("Neutral")])]
        original.scriptMetadata = ["future": "Keep"]
        original.configuredValues = ["name": "Existing"]
        original.sourceURL = "https://example.com/neutral"

        var copy = ActionEditingCopy(action: original)
        #expect(copy.action == original)
        #expect(copy.selectedStep == nil)
        copy.selectFirstStep()
        #expect(copy.selectedStep == step.id)
        #expect(copy.action == original)
        copy.action.steps[0].values["script"] = "Changed"
        #expect(original.steps[0].values == ["script": "Original café 🐼"])
        #expect(copy.action.steps[0].values["allowAsync"] == nil)
        #expect(copy.action.id == original.id)
        #expect(copy.action.steps[0].id == step.id)
        #expect(copy.action.steps[0].isEnabled == isEnabled)
        #expect(copy.action.steps[0].unknownFields == step.unknownFields)
        #expect(copy.action.rawPayload == original.rawPayload)
        #expect(copy.action.unknownFields == original.unknownFields)
        #expect(copy.action.scriptMetadata == original.scriptMetadata)
        #expect(copy.action.configuredValues == original.configuredValues)
        #expect(copy.action.sourceURL == original.sourceURL)
        let exported = try JSONDecoder().decode(DraftAction.self, from: JSONEncoder().encode(copy.action))
        #expect(exported == copy.action)
    }

    @Test(arguments: DraftAction.supportedSteps.sorted() + ["futureStep"])
    func addedStepsKeepInspectorDefaultsAndSelectOnlyTheNewIdentity(type: String) {
        let expected: [String: [String: String]] = [
            "script": ["script": "// Write JavaScript here.\n", "allowAsync": "false"],
            "runAppleScript": ["source": "return \"Hello\""],
            "url": ["url": "https://example.com"],
            "callbackUrl": ["url": "https://example.com"],
            "runShortcut": ["name": "", "template": "[[draft]]"],
            "includeAction": ["name": "", "template": "[[draft]]"],
            "file": ["name": "[[safe_title]].md", "template": "[[draft]]"],
            "createDraft": ["template": "[[draft]]", "openInEditor": "true"],
            "configurationKey": ["key": "", "dataType": "string", "defaultStringValue": "",
                                 "description": "", "exampleValue": "", "requiresInitialConfiguration": "true"]
        ]
        let original = DraftAction(name: "Neutral", steps: [ActionStep("futureOriginal", ["keep": "café 🐼"])])
        var copy = ActionEditingCopy(action: original)
        copy.selectFirstStep()
        copy.addStep(type)
        #expect(copy.action.id == original.id)
        #expect(copy.action.steps.count == 2)
        #expect(copy.action.steps.first == original.steps.first)
        let added = copy.action.steps[1]
        #expect(added.type == type)
        #expect(added.values == expected[type, default: ["template": "[[draft]]"]])
        #expect(added.id != original.steps[0].id)
        #expect(added.isEnabled == nil)
        #expect(added.unknownFields.isEmpty)
        #expect(copy.selectedStep == added.id)
        copy.addStep(type)
        #expect(copy.action.steps[2].id != added.id)
        #expect(copy.selectedStep == copy.action.steps[2].id)
    }

    @Test func appearingAgainResetsSelectionToTheFirstStepAndEmptyActionsSelectNothing() {
        let first = ActionStep("clipboard"), second = ActionStep("share")
        var copy = ActionEditingCopy(action: DraftAction(name: "Neutral", steps: [first, second]))
        copy.selectedStep = second.id
        copy.selectFirstStep()
        #expect(copy.selectedStep == first.id)
        copy.action.steps = []
        copy.selectFirstStep()
        #expect(copy.selectedStep == nil)
    }

    @Test func removalSelectsTheFirstRemainingStepAndRemovesAllMatchingIdentities() {
        let first = ActionStep("clipboard"), second = ActionStep("share"), third = ActionStep("file")
        var copy = ActionEditingCopy(action: DraftAction(name: "Neutral", steps: [first, second, second, third]))
        copy.selectedStep = second.id
        copy.removeSelectedStep()
        #expect(copy.action.steps == [first, third])
        #expect(copy.selectedStep == first.id)
        copy.removeSelectedStep()
        #expect(copy.action.steps == [third])
        #expect(copy.selectedStep == third.id)
        copy.removeSelectedStep()
        #expect(copy.action.steps.isEmpty)
        #expect(copy.selectedStep == nil)
    }

    @Test func removalWithoutSelectionDoesNothingAndAnUnknownSelectionResetsToFirst() {
        let original = DraftAction(name: "Neutral", steps: [ActionStep("clipboard")])
        var copy = ActionEditingCopy(action: original)
        copy.removeSelectedStep()
        #expect(copy.action == original)
        #expect(copy.selectedStep == nil)
        copy.selectedStep = UUID()
        copy.removeSelectedStep()
        #expect(copy.action == original)
        #expect(copy.selectedStep == original.steps.first?.id)
    }

    @Test func movingSwapsStepsWithoutChangingSelectionAndIgnoresInvalidTargets() {
        let first = ActionStep("clipboard"), second = ActionStep("share"), third = ActionStep("file")
        let original = DraftAction(name: "Neutral", steps: [first, second, third])
        var copy = ActionEditingCopy(action: original)
        copy.moveSelectedStep(offset: 1)
        #expect(copy.action == original)
        copy.selectedStep = UUID()
        copy.moveSelectedStep(offset: -1)
        #expect(copy.action == original)
        copy.selectedStep = second.id
        copy.moveSelectedStep(offset: -1)
        #expect(copy.action.steps == [second, first, third])
        #expect(copy.selectedStep == second.id)
        copy.moveSelectedStep(offset: -1)
        #expect(copy.action.steps == [second, first, third])
        copy.moveSelectedStep(offset: 1)
        copy.moveSelectedStep(offset: 1)
        #expect(copy.action.steps == [first, third, second])
        copy.moveSelectedStep(offset: 1)
        #expect(copy.action.steps == [first, third, second])
        #expect(copy.selectedStep == second.id)
        #expect(copy.action.id == original.id)
    }

    @MainActor @Test func editsAndDiscardDoNotWriteTheLibraryAndSaveUsesTheSameActionIdentity() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = DraftAction(name: "Neutral original", steps: [ActionStep("clipboard")])
        try library.saveAction(original)
        var copy = ActionEditingCopy(action: original)
        copy.action.name = "Neutral changed"
        copy.addStep("script")
        copy.action.steps[0].isEnabled = false
        #expect(library.actions == [original])
        let reopened = ActionEditingCopy(action: try #require(library.actions.first))
        #expect(reopened.action == original)
        #expect(reopened.selectedStep == nil)
        try library.saveAction(copy.action)
        #expect(library.actions == [copy.action])
        #expect(library.actions.first?.id == original.id)
        #expect(library.actions.first?.steps.first?.id == original.steps.first?.id)
    }

    @MainActor @Test func newConfigurationStaysTemporaryUntilSaveAndLeavesImportedConfigurationUntouched() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var imported = ActionStep("configurationKey", ["key": "legacy", "defaultValue": "Keep café 🐼"])
        imported.isEnabled = false
        imported.unknownFields = ["future": .object(["nested": .bool(true)])]
        var original = DraftAction(name: "Neutral configuration", steps: [imported])
        original.rawPayload = "{\"future\":true}"
        original.unknownFields = ["futureAction": .string("Keep")]
        original.configuredValues = ["legacy": "Confirmed value"]
        try library.saveAction(original)

        var copy = ActionEditingCopy(action: original)
        copy.addStep("configurationKey")
        let createdID = try #require(copy.selectedStep)
        #expect(createdID != imported.id)
        #expect(copy.action.steps[0] == imported)
        #expect(copy.action.steps[0].values["dataType"] == nil)
        #expect(copy.action.steps[0].values["requiresInitialConfiguration"] == nil)
        #expect(copy.action.steps[1].values["template"] == nil)
        copy.action.steps[1].values["key"] = "destination"
        copy.action.steps[1].values["name"] = "Neutral destination"
        copy.action.steps[1].values["defaultStringValue"] = "café 🐼"
        #expect(library.actions == [original])
        let discarded = ActionEditingCopy(action: try #require(library.actions.first))
        #expect(discarded.action == original)
        #expect(discarded.action.steps.count == 1)

        try library.saveAction(copy.action)
        try library.reload()
        let saved = try #require(library.actions.first)
        #expect(saved == copy.action)
        #expect(saved.id == original.id)
        #expect(saved.steps[0] == imported)
        #expect(saved.steps[1].id == createdID)
        #expect(saved.steps[1].values["key"] == "destination")
        #expect(saved.steps[1].values["requiresInitialConfiguration"] == "true")
        #expect(saved.configuredValues == original.configuredValues)
        #expect(saved.rawPayload == original.rawPayload)
        #expect(saved.unknownFields == original.unknownFields)
    }
}
