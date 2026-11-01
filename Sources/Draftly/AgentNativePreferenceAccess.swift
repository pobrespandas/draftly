import Foundation
import AgentContracts

// Application coordination only. The command service must authorize before apply.
@MainActor enum AgentNativePreferenceAccess {
    enum Change {
        case loginItem(enabled: Bool)
        case spotlight(enabled: Bool, reset: Bool)

        var requiresHumanApproval: Bool { true }
        var requiresLibraryScope: Bool {
            if case .spotlight = self { return true }
            return false
        }
    }

    static func prepare(address: AgentJSONValue, value: AgentJSONValue?) throws -> Change {
        let registry = try AgentPreferenceCatalog.make()
        let target = try registry.address(address)
        let field = try registry.field(target.id)
        guard target.id == "application.launchAtLogin" || target.id == SpotlightPreferences.enabledKey else {
            throw AgentErrorCode.unavailable
        }
        if let value { try field.value.validate(value) }
        let override: Bool?
        switch value { case .bool(let flag): override = flag; case nil: override = nil
        default: throw AgentErrorCode.invalidInput }
        if target.id == "application.launchAtLogin" { return .loginItem(enabled: override ?? false) }
        return .spotlight(enabled: override ?? SpotlightPreferences.defaultEnabled, reset: value == nil)
    }

    static func readLoginItem(_ model: LoginItemPreferences) throws -> AgentPreferenceReading {
        guard !model.isChanging else { throw AgentErrorCode.busy }
        model.refresh()
        switch model.status {
        case .unavailable: throw AgentErrorCode.unavailable
        case .requiresApproval: throw AgentErrorCode.interactionRequired
        case .disabled, .enabled:
            return .init(effectiveValue: .bool(model.isRegistered), origin: "system", hasOverride: false)
        }
    }

    static func readSpotlight(_ model: SpotlightPreferences, hasStoredOverride: Bool) throws -> AgentPreferenceReading {
        guard model.isAvailable else { throw AgentErrorCode.unavailable }
        guard !model.isChanging else { throw AgentErrorCode.busy }
        guard model.error == nil else { throw AgentErrorCode.executionError }
        return .init(effectiveValue: .bool(model.isEnabled), origin: hasStoredOverride ? "stored" : "default",
            hasOverride: hasStoredOverride)
    }

    struct EffectCompletion {
        let reading: AgentPreferenceReading
        let removeSpotlightOverride: Bool
    }

    static func applyNativeEffect(_ change: Change, loginItem: LoginItemPreferences,
                                  spotlight: SpotlightPreferences,
                                  spotlightHasStoredOverride: () -> Bool) async throws -> EffectCompletion {
        guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
        switch change {
        case .loginItem(let enabled):
            guard !loginItem.isChanging else { throw AgentErrorCode.busy }
            loginItem.refresh()
            guard loginItem.status != .unavailable else { throw AgentErrorCode.unavailable }
            if enabled, loginItem.status == .requiresApproval { throw AgentErrorCode.interactionRequired }
            if loginItem.isRegistered != enabled {
                await loginItem.setEnabled(enabled)
                guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
                guard loginItem.error == nil else { throw AgentErrorCode.executionError }
            }
            let result = try readLoginItem(loginItem)
            guard result.effectiveValue == .bool(enabled) else { throw AgentErrorCode.executionError }
            return EffectCompletion(reading: result, removeSpotlightOverride: false)
        case .spotlight(let enabled, let reset):
            guard !reset || enabled == SpotlightPreferences.defaultEnabled else { throw AgentErrorCode.invalidInput }
            guard spotlight.isAvailable else { throw AgentErrorCode.unavailable }
            guard !spotlight.isChanging else { throw AgentErrorCode.busy }
            if spotlight.isEnabled != enabled { spotlight.setEnabled(enabled) }
            else if reset { spotlight.retry() }
            await spotlight.waitForUpdates()
            guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
            guard spotlight.error == nil, spotlight.isEnabled == enabled else { throw AgentErrorCode.executionError }
            // The service must verify the local reset and finish its operation record.
            let result = try readSpotlight(spotlight, hasStoredOverride: spotlightHasStoredOverride())
            return EffectCompletion(reading: result, removeSpotlightOverride: reset)
        }
    }
}
