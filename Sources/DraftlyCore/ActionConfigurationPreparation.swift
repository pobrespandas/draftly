import Foundation

@MainActor extension ActionRunner {
    func prepareInitialConfiguration(_ action: DraftAction, steps: [ActionStep]) throws -> DraftAction {
        let definition = try ActionInitialConfiguration(action: action, steps: steps)
        guard definition.needsPrompt else { return action }
        try checkConfigurationAuthority(action)
        let stored = library.actions.first { $0.id == action.id }
        let response = try platform("prompt", definition.prompt)
        try checkCancellation()
        try checkConfigurationAuthority(action)
        return try saveInitialConfiguration(definition.configured(response), replacing: stored)
    }

    func prepareInitialConfigurationAsync(_ action: DraftAction, steps: [ActionStep]) async throws -> DraftAction {
        let definition = try ActionInitialConfiguration(action: action, steps: steps)
        guard definition.needsPrompt else { return action }
        try checkConfigurationAuthority(action)
        let stored = library.actions.first { $0.id == action.id }
        let response = try await nativeValue("prompt", definition.prompt)
        try Task.checkCancellation()
        try checkCancellation()
        try checkConfigurationAuthority(action)
        return try saveInitialConfiguration(definition.configured(response), replacing: stored)
    }

    private func checkConfigurationAuthority(_ action: DraftAction) throws {
        guard filterActionCatalog != nil else { return }
        _ = try permittedActionCatalog(for: action)
        guard let authorizeActionConfiguration, actionConfigurationCommitted != nil else {
            throw DraftlyError.message("Action configuration is unavailable.")
        }
        try authorizeActionConfiguration(action)
    }

    private func saveInitialConfiguration(_ configured: DraftAction, replacing stored: DraftAction?) throws -> DraftAction {
        guard let stored else { return configured }
        guard library.actions.first(where: { $0.id == stored.id }) == stored else {
            throw DraftlyError.message("The action changed while configuration was open. No configuration was saved.")
        }
        try library.saveActions([configured])
        if let actionConfigurationCommitted {
            do { try actionConfigurationCommitted(stored, configured) }
            catch { scriptOutcomeUnknown = true; cancel(); throw error }
        }
        return configured
    }
}
