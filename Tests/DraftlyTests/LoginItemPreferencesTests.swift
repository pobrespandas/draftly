import Foundation
import Testing
@testable import Draftly

@MainActor
struct LoginItemPreferencesTests {
    @Test func registrationUsesSystemStateAndRefreshesExternalChanges() async {
        var system = LoginItemPreferences.Status.disabled
        var registrations = 0
        var removals = 0
        let model = LoginItemPreferences(readStatus: { system }, register: {
            registrations += 1
            system = .requiresApproval
        }, unregister: {
            removals += 1
            system = .disabled
        })
        #expect(!model.isRegistered)
        await model.setEnabled(true)
        #expect(model.status == .requiresApproval)
        #expect(model.isRegistered)
        #expect(registrations == 1)
        await model.setEnabled(true)
        #expect(registrations == 1)
        system = .enabled
        model.refresh()
        #expect(model.status == .enabled)
        await model.setEnabled(false)
        #expect(removals == 1)
        #expect(model.status == .disabled)
        #expect(!model.isChanging)
        #expect(model.error == nil)
    }

    @Test func failuresDoNotInventARegisteredOrRemovedState() async {
        var system = LoginItemPreferences.Status.disabled
        let model = LoginItemPreferences(readStatus: { system }, register: {
            throw NSError(domain: "Login fixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Registration failed"])
        }, unregister: {
            throw NSError(domain: "Login fixture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Removal failed"])
        })
        await model.setEnabled(true)
        #expect(model.error == "Registration failed")
        #expect(!model.isRegistered)
        #expect(!model.isChanging)
        system = .enabled
        model.refresh()
        await model.setEnabled(false)
        #expect(model.error == "Removal failed")
        #expect(model.isRegistered)
        #expect(!model.isChanging)
    }

    @Test func overlappingChangesDoNotRegisterDuringRemoval() async {
        var system = LoginItemPreferences.Status.enabled
        var completion: CheckedContinuation<Void, Never>?
        var registrations = 0
        let model = LoginItemPreferences(readStatus: { system }, register: {
            registrations += 1
        }, unregister: {
            await withCheckedContinuation { completion = $0 }
            system = .disabled
        })
        let removal = Task { await model.setEnabled(false) }
        while completion == nil { await Task.yield() }
        #expect(model.isChanging)
        await model.setEnabled(true)
        #expect(registrations == 0)
        completion?.resume()
        await removal.value
        #expect(!model.isChanging)
        #expect(!model.isRegistered)
    }
}
