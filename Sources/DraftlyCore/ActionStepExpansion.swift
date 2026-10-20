import Foundation

enum ActionStepExpansion {
    static func resolve(_ step: ActionStep, actions: [DraftAction], render: (String) throws -> String) throws -> DraftAction {
        if let value = step.values["uuid"], !value.isEmpty {
            guard let id = UUID(uuidString: value), let action = actions.first(where: { $0.id == id }) else {
                throw DraftlyError.message("The included action UUID was not found.")
            }
            return action
        }
        let name = try render(step.values["name"] ?? "")
        guard !name.isEmpty, let action = actions.first(where: { $0.name == name }) else {
            throw DraftlyError.message("The included action was not found.")
        }
        return action
    }

    static func expand(_ action: DraftAction, actions: [DraftAction], path: Set<UUID> = []) throws -> [ActionStep] {
        guard !path.contains(action.id) else { throw DraftlyError.message("An included action refers to itself.") }
        guard path.count < 50 else { throw DraftlyError.message("The included action depth exceeded 50.") }
        guard action.unsupportedSteps.isEmpty else { throw DraftlyError.message("Unsupported steps: \(action.unsupportedSteps.joined(separator: ", ")). No steps were run.") }
        var result: [ActionStep] = []
        for step in action.steps where step.isEnabled != false {
            if step.type == "includeAction" {
                if (step.values["uuid"] ?? "").isEmpty,
                   (step.values["name"] ?? "").range(of: #"\[\[[\s\S]*?\]\]"#, options: .regularExpression) != nil {
                    result.append(step)
                    continue
                }
                let included = try resolve(step, actions: actions, render: { $0 })
                result += try expand(included, actions: actions, path: path.union([action.id]))
            } else { result.append(step) }
        }
        return result
    }
}
