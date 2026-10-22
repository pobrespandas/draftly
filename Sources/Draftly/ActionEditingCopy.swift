import Foundation
import DraftlyCore

struct ActionEditingCopy {
    var action: DraftAction
    var selectedStep: UUID?

    init(action: DraftAction) { self.action = action }

    mutating func selectFirstStep() { selectedStep = action.steps.first?.id }

    mutating func addStep(_ type: String) {
        let step = ActionStep(type, ActionStepCreationDefaults.values(for: type))
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
}
