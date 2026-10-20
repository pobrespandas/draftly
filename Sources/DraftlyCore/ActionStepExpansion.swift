import Foundation

enum ActionStepExpansion {
    static func expand(_ action: DraftAction, actions: [DraftAction], path: Set<UUID> = []) throws -> [ActionStep] {
        guard !path.contains(action.id) else { throw DraftlyError.message("An included action refers to itself.") }
        guard path.count < 50 else { throw DraftlyError.message("The included action depth exceeded 50.") }
        guard action.unsupportedSteps.isEmpty else { throw DraftlyError.message("Unsupported steps: \(action.unsupportedSteps.joined(separator: ", ")). No steps were run.") }
        var result: [ActionStep] = []
        for step in action.steps where step.isEnabled != false {
            if step.type == "includeAction" {
                guard let included = actions.first(where: { $0.name == step.values["name"] }) else { throw DraftlyError.message("The included action was not found.") }
                result += try expand(included, actions: actions, path: path.union([action.id]))
            } else { result.append(step) }
        }
        return result
    }
}
