import Foundation
import Testing
@testable import DraftlyCore

@Suite("Included action resolution")
struct ActionIncludeResolutionTests {
    @Test func selectedUUIDSurvivesRenamingAndTakesPrecedenceOverName() throws {
        let selected = DraftAction(name: "Renamed helper", steps: [])
        let other = DraftAction(name: "Old helper", steps: [])
        let step = ActionStep("includeAction", ["uuid": selected.id.uuidString.lowercased(), "name": other.name])
        let resolved = try ActionStepExpansion.resolve(step, actions: [other, selected]) { _ in
            Issue.record("A selected UUID must not render the name.")
            return other.name
        }
        #expect(resolved.id == selected.id)
    }

    @Test func importedStepUUIDIsSeparateFromTheSelectedActionUUID() throws {
        let selected = DraftAction(name: "Helper", steps: [])
        let stepID = UUID()
        let raw = """
        {"name":"Parent","steps":[{"uuid":"\(stepID.uuidString)","type":"includeAction","data":{"uuid":"\(selected.id.uuidString)","name":"Old helper"}}]}
        """
        let imported = try ActionImporter.decode(Data(raw.utf8))
        let step = try #require(imported.first?.steps.first)
        #expect(step.id == stepID)
        #expect(try ActionStepExpansion.resolve(step, actions: [selected], render: { $0 }).id == selected.id)
    }

    @Test func importedStepIdentityDoesNotBecomeAnActionReference() throws {
        let selected = DraftAction(name: "Helper", steps: [])
        let raw = """
        {"name":"Parent","steps":[{"uuid":"\(UUID().uuidString)","type":"includeAction","data":{"name":"Helper"}}]}
        """
        let imported = try ActionImporter.decode(Data(raw.utf8))
        let step = try #require(imported.first?.steps.first)
        #expect(step.values["uuid"] == nil)
        #expect(try ActionStepExpansion.resolve(step, actions: [selected], render: { $0 }).id == selected.id)
        let retained = try #require(imported.first?.rawPayload)
        let original = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? NSDictionary)
        let preserved = try #require(JSONSerialization.jsonObject(with: Data(retained.utf8)) as? NSDictionary)
        #expect(original == preserved)
    }

    @Test func emptyUUIDUsesRenderedNameAndPropagatesTemplateErrors() throws {
        let helper = DraftAction(name: "Neutral helper 🐼", steps: [])
        let step = ActionStep("includeAction", ["uuid": "", "name": "[[helper]]"])
        let resolved = try ActionStepExpansion.resolve(step, actions: [helper]) { source in
            #expect(source == "[[helper]]")
            return helper.name
        }
        #expect(resolved.id == helper.id)
        #expect(throws: DraftlyError.self) {
            try ActionStepExpansion.resolve(step, actions: [helper]) { _ in
                throw DraftlyError.message("Template failure")
            }
        }
    }

    @Test func invalidOrMissingUUIDNeverFallsBackToMatchingName() {
        let helper = DraftAction(name: "Helper", steps: [])
        for value in ["invalid", UUID().uuidString] {
            #expect(throws: DraftlyError.self) {
                try ActionStepExpansion.resolve(ActionStep("includeAction", ["uuid": value, "name": helper.name]), actions: [helper], render: { $0 })
            }
        }
    }

    @Test func missingAndEmptyNamesFailExplicitly() {
        let unnamed = DraftAction(name: "", steps: [])
        for values in [[:], ["name": ""], ["name": "Missing"]] as [[String: String]] {
            #expect(throws: DraftlyError.self) {
                try ActionStepExpansion.resolve(ActionStep("includeAction", values), actions: [unnamed], render: { $0 })
            }
        }
    }

    @Test func staticNamesAndUUIDsExpandInOrderWhileDynamicNamesRemainSteps() throws {
        let clipboard = ActionStep("clipboard", ["text": "Neutral"])
        let helper = DraftAction(name: "Helper", steps: [clipboard])
        let dynamic = ActionStep("includeAction", ["name": "[[helper]]"])
        let parent = DraftAction(name: "Parent", steps: [
            ActionStep("includeAction", ["name": helper.name]), dynamic,
            ActionStep("includeAction", ["uuid": helper.id.uuidString, "name": "[[ignored]]"])
        ])
        #expect(try ActionStepExpansion.expand(parent, actions: [helper]) == [clipboard, dynamic, clipboard])
    }

    @Test func UUIDCyclesAndDepthLimitRemainRejected() {
        var first = DraftAction(name: "First", steps: [])
        var second = DraftAction(name: "Second", steps: [])
        first.steps = [ActionStep("includeAction", ["uuid": second.id.uuidString])]
        second.steps = [ActionStep("includeAction", ["uuid": first.id.uuidString])]
        #expect(throws: DraftlyError.self) {
            try ActionStepExpansion.expand(first, actions: [first, second])
        }
        #expect(throws: DraftlyError.self) {
            try ActionStepExpansion.expand(first, actions: [first, second], path: Set((0..<50).map { _ in UUID() }))
        }
    }

    @Test func disabledIncludesDoNotResolveAndUnknownEnabledStepsStillFail() throws {
        var disabled = ActionStep("includeAction", ["uuid": "invalid"])
        disabled.isEnabled = false
        let parent = DraftAction(name: "Parent", steps: [disabled])
        #expect(try ActionStepExpansion.expand(parent, actions: []) == [])
        let unsupported = DraftAction(name: "Unsupported helper", steps: [ActionStep("futureUnknown")])
        let including = DraftAction(name: "Parent", steps: [ActionStep("includeAction", ["uuid": unsupported.id.uuidString])])
        #expect(throws: DraftlyError.self) {
            try ActionStepExpansion.expand(including, actions: [unsupported])
        }
    }
}
