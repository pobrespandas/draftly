import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Agent native preference coordination") @MainActor
struct AgentNativePreferenceAccessTests {
    @MainActor private final class Fixture {
        let preferences: TestPreferences
        var system = LoginItemPreferences.Status.disabled
        var approvalRequired = false
        var registerFails = false
        var clearFails = false
        var replaceFails = false
        var registrations = 0
        var removals = 0
        var replacements = 0
        var clears = 0
        var clearCompletion: CheckedContinuation<Void, Never>?
        var suspendClear = false
        lazy var login = LoginItemPreferences(readStatus: { [unowned self] in self.system }, register: { [unowned self] in
            self.registrations += 1
            if self.registerFails { throw AgentErrorCode.executionError }
            self.system = self.approvalRequired ? .requiresApproval : .enabled
        }, unregister: { [unowned self] in self.removals += 1; self.system = .disabled })
        lazy var spotlight = SpotlightPreferences(defaults: preferences.defaults, isAvailable: true, replace: { @MainActor [unowned self] _ in
            self.replacements += 1
            if self.replaceFails { throw AgentErrorCode.executionError }
        }, clear: { @MainActor [unowned self] in
            self.clears += 1
            if self.suspendClear { await withCheckedContinuation { self.clearCompletion = $0 } }
            if self.clearFails { throw AgentErrorCode.executionError }
        })
        init() throws { preferences = try TestPreferences(prefix: "Agent-Native-Preferences-") }
        var hasOverride: Bool { preferences.defaults.persistentDomain(forName: preferences.name)?[SpotlightPreferences.enabledKey] != nil }
        func apply(_ change: AgentNativePreferenceAccess.Change) async throws -> AgentNativePreferenceAccess.EffectCompletion {
            try await AgentNativePreferenceAccess.applyNativeEffect(change, loginItem: login, spotlight: spotlight,
                spotlightHasStoredOverride: { self.hasOverride })
        }
    }

    @Test func preparationAndReadsDoNotRegisterOrIndex() throws {
        let fixture = try Fixture(); defer { fixture.preferences.close() }
        for id in ["application.launchAtLogin", SpotlightPreferences.enabledKey] {
            let change = try AgentNativePreferenceAccess.prepare(address: .object(["id": .string(id)]), value: .bool(true))
            #expect(change.requiresHumanApproval)
            #expect(change.requiresLibraryScope == (id == SpotlightPreferences.enabledKey))
        }
        let loginReset = try AgentNativePreferenceAccess.prepare(address: .object(["id": .string("application.launchAtLogin")]), value: nil)
        if case .loginItem(let enabled) = loginReset { #expect(!enabled) }
        else { Issue.record("Reset must remove the login registration") }
        let spotlightReset = try AgentNativePreferenceAccess.prepare(address: .object(["id": .string(SpotlightPreferences.enabledKey)]), value: nil)
        if case .spotlight(let enabled, let reset) = spotlightReset {
            #expect(enabled == SpotlightPreferences.defaultEnabled && reset)
        } else { Issue.record("Reset must select the Spotlight default") }
        #expect(try AgentNativePreferenceAccess.readLoginItem(fixture.login).effectiveValue == .bool(false))
        #expect(try AgentNativePreferenceAccess.readSpotlight(fixture.spotlight, hasStoredOverride: fixture.hasOverride).origin == "default")
        #expect(fixture.registrations == 0 && fixture.clears == 0 && fixture.replacements == 0)
        #expect((fixture.preferences.defaults.persistentDomain(forName: fixture.preferences.name) ?? [:]).isEmpty)
    }

    @Test func pendingLoginApprovalIsNotSuccessAndCanStillBeRemoved() async throws {
        let fixture = try Fixture(); defer { fixture.preferences.close() }
        fixture.approvalRequired = true
        await #expect(throws: AgentErrorCode.interactionRequired) { try await fixture.apply(.loginItem(enabled: true)) }
        #expect(fixture.registrations == 1 && fixture.system == .requiresApproval)
        let removal = try await fixture.apply(.loginItem(enabled: false))
        #expect(removal.reading.effectiveValue == .bool(false) && fixture.removals == 1)
        #expect(!removal.removeSpotlightOverride)
        fixture.system = .unavailable
        await #expect(throws: AgentErrorCode.unavailable) { try await fixture.apply(.loginItem(enabled: true)) }
        #expect(fixture.registrations == 1)
    }

    @Test func loginFailureAndUnchangedNativeStateNeverInventSuccess() async throws {
        let fixture = try Fixture(); defer { fixture.preferences.close() }
        fixture.registerFails = true
        await #expect(throws: AgentErrorCode.executionError) { try await fixture.apply(.loginItem(enabled: true)) }
        #expect(fixture.system == .disabled && fixture.registrations == 1)
        let unchanged = try await fixture.apply(.loginItem(enabled: false))
        #expect(unchanged.reading.effectiveValue == .bool(false))
        #expect(fixture.removals == 0)
    }

    @Test func spotlightResetReportsNativeCompletionBeforeStorageFinalization() async throws {
        let fixture = try Fixture(); defer { fixture.preferences.close() }
        fixture.preferences.defaults.set("保持", forKey: "future.option")
        let enabled = try await fixture.apply(.spotlight(enabled: true, reset: false))
        #expect(enabled.reading.effectiveValue == .bool(true) && !enabled.removeSpotlightOverride)
        let disabled = try await fixture.apply(.spotlight(enabled: false, reset: true))
        #expect(disabled.reading.effectiveValue == .bool(false) && disabled.removeSpotlightOverride)
        #expect(fixture.replacements == 1 && fixture.clears == 1)
        // A later verified local write, not this coordinator, removes the override.
        #expect(fixture.hasOverride)
        #expect(fixture.preferences.defaults.string(forKey: "future.option") == "保持")
    }

    @Test func failedIndexAndCleanupKeepCompletedEffectsAndErrorState() async throws {
        let fixture = try Fixture(); defer { fixture.preferences.close() }
        fixture.replaceFails = true
        await #expect(throws: AgentErrorCode.executionError) { try await fixture.apply(.spotlight(enabled: true, reset: false)) }
        #expect(fixture.spotlight.isEnabled && fixture.hasOverride)
        #expect(throws: AgentErrorCode.executionError) {
            try AgentNativePreferenceAccess.readSpotlight(fixture.spotlight, hasStoredOverride: fixture.hasOverride)
        }
        fixture.clearFails = true
        await #expect(throws: AgentErrorCode.executionError) { try await fixture.apply(.spotlight(enabled: false, reset: true)) }
        #expect(!fixture.spotlight.isEnabled && fixture.hasOverride)
        fixture.clearFails = false
        let retry = try await fixture.apply(.spotlight(enabled: false, reset: true))
        #expect(retry.removeSpotlightOverride && fixture.clears == 2)
    }

    @Test func cancelledBeforeStartDoesNotTouchEitherNativeService() async throws {
        let fixture = try Fixture(); defer { fixture.preferences.close() }
        let task = Task { try await fixture.apply(.spotlight(enabled: true, reset: false)) }
        task.cancel()
        await #expect(throws: AgentErrorCode.cancelled) { try await task.value }
        #expect(fixture.registrations == 0 && fixture.replacements == 0 && fixture.clears == 0)
    }

    @Test func busyAndLateCancellationDoNotClaimResetOrReverseCleanup() async throws {
        let fixture = try Fixture(); defer { fixture.preferences.close() }
        fixture.suspendClear = true
        let task = Task { try await fixture.apply(.spotlight(enabled: false, reset: true)) }
        while fixture.clearCompletion == nil { await Task.yield() }
        #expect(throws: AgentErrorCode.busy) { try AgentNativePreferenceAccess.readSpotlight(fixture.spotlight, hasStoredOverride: false) }
        await #expect(throws: AgentErrorCode.busy) { try await fixture.apply(.spotlight(enabled: true, reset: false)) }
        task.cancel()
        fixture.clearCompletion?.resume()
        await #expect(throws: AgentErrorCode.cancelled) { try await task.value }
        #expect(fixture.clears == 1 && fixture.replacements == 0 && !fixture.spotlight.isChanging)
    }
    @Test func loginSuccessUsesActualSystemStateAndIdempotentChanges() async throws {
        let fixture = try Fixture(); defer { fixture.preferences.close() }
        let result = try await fixture.apply(.loginItem(enabled: true))
        #expect(result.reading.effectiveValue == .bool(true) && result.reading.origin == "system")
        _ = try await fixture.apply(.loginItem(enabled: true))
        #expect(fixture.registrations == 1)
        fixture.system = .disabled
        #expect(try AgentNativePreferenceAccess.readLoginItem(fixture.login).effectiveValue == .bool(false))
        let unavailable = SpotlightPreferences(defaults: fixture.preferences.defaults, isAvailable: false,
            replace: { _ in Issue.record("Unavailable index must not be used") }, clear: { Issue.record("Unavailable index must not be cleared") })
        await #expect(throws: AgentErrorCode.unavailable) {
            try await AgentNativePreferenceAccess.applyNativeEffect(.spotlight(enabled: true, reset: false),
                loginItem: fixture.login, spotlight: unavailable, spotlightHasStoredOverride: { false })
        }
    }

}
