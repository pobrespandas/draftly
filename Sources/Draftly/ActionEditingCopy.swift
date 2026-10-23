import Foundation
import DraftlyCore

struct ActionEditingCopy {
    var action: DraftAction
    var selectedStep: UUID?
    private let originalShortcut: String
    private let originalModifiers: [String]?

    init(action: DraftAction) {
        self.action = action
        originalShortcut = action.shortcut
        originalModifiers = action.shortcutModifiers
    }

    func blockingShortcutConflict(in actions: [DraftAction]) -> String? {
        if actions.contains(where: { $0.id == action.id }),
           action.shortcut == originalShortcut, action.shortcutModifiers == originalModifiers { return nil }
        return ActionShortcut.conflict(for: action, in: actions)
    }

    @MainActor func save(to library: LibraryStore) throws {
        try library.saveActions([action])
    }

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
