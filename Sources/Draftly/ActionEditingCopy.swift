import Foundation
import DraftlyCore

struct ActionEditingCopy {
    var action: DraftAction
    var selectedStep: UUID?

    init(action: DraftAction) { self.action = action }

    mutating func selectFirstStep() { selectedStep = action.steps.first?.id }

    mutating func addStep(_ type: String) {
        let step = ActionStep(type, Self.defaults(type))
        action.steps.append(step)
        selectedStep = step.id
    }

    mutating func removeSelectedStep() {
        guard let id = selectedStep else { return }
        action.steps.removeAll { $0.id == id }
        selectFirstStep()
    }

    mutating func moveSelectedStep(offset: Int) {
        guard let id = selectedStep,
              let index = action.steps.firstIndex(where: { $0.id == id }),
              action.steps.indices.contains(index + offset) else { return }
        action.steps.swapAt(index, index + offset)
    }

    private static func defaults(_ type: String) -> [String: String] {
        switch type {
        case "script": ["script": "// Write JavaScript here.\n", "allowAsync": "false"]
        case "runAppleScript": ["source": "return \"Hello\""]
        case "url", "callbackUrl": ["url": "https://example.com"]
        case "runShortcut", "includeAction": ["name": "", "template": "[[draft]]"]
        case "file": ["name": "[[safe_title]].md", "template": "[[draft]]"]
        case "createDraft": ["template": "[[draft]]", "openInEditor": "true"]
        case "prompt": ActionStepInspectorFields.promptDefaults
        case "configurationKey": ["key": "", "dataType": "string", "defaultStringValue": "",
                                  "description": "", "exampleValue": "", "requiresInitialConfiguration": "true"]
        default: ["template": "[[draft]]"]
        }
    }
}
