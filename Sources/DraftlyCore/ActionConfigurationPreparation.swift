import Foundation

@MainActor extension ActionRunner {
    func prepareInitialConfiguration(_ action: DraftAction, steps: [ActionStep]) throws -> DraftAction {
        let definition = try ActionInitialConfiguration(action: action, steps: steps)
        guard definition.needsPrompt else { return action }
        let stored = library.actions.first { $0.id == action.id }
        let response = try platform("prompt", definition.prompt)
        try checkCancellation()
        return try saveInitialConfiguration(definition.configured(response), replacing: stored)
    }

    func prepareInitialConfigurationAsync(_ action: DraftAction, steps: [ActionStep]) async throws -> DraftAction {
        let definition = try ActionInitialConfiguration(action: action, steps: steps)
        guard definition.needsPrompt else { return action }
        let stored = library.actions.first { $0.id == action.id }
        let response = try await nativeValue("prompt", definition.prompt)
        try Task.checkCancellation()
        try checkCancellation()
        return try saveInitialConfiguration(definition.configured(response), replacing: stored)
    }

    private func saveInitialConfiguration(_ configured: DraftAction, replacing stored: DraftAction?) throws -> DraftAction {
        guard let stored else { return configured }
        guard library.actions.first(where: { $0.id == stored.id }) == stored else {
            throw DraftlyError.message("The action changed while configuration was open. No configuration was saved.")
        }
        try library.saveActions([configured])
        return configured
    }
}
