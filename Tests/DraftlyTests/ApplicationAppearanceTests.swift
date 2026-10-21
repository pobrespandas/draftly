import AppKit
import Testing
@testable import Draftly

@Suite("Application appearance")
struct ApplicationAppearanceTests {
    @Test func systemReleasesTheApplicationOverride() {
        #expect(ApplicationAppearance.system.nativeAppearance == nil)
        #expect(ApplicationAppearance.resolved("unknown") == .system)
        #expect(ApplicationAppearance.resolved("") == .system)
    }

    @Test func explicitChoicesUseTheNativeAppearances() {
        #expect(ApplicationAppearance.light.nativeAppearance?.name == .aqua)
        #expect(ApplicationAppearance.dark.nativeAppearance?.name == .darkAqua)
        #expect(ApplicationAppearance.resolved("Dark") == .dark)
        #expect(ApplicationAppearance.resolved("Light") == .light)
    }
}

@Suite("General preferences")
struct GeneralPreferencesTests {
    @Test func launchWindowDefaultAndStoredChoiceAreLocal() throws {
        let preferences = try TestPreferences(prefix: "Draftly-LaunchPreferences-")
        defer { preferences.close() }
        let defaults = preferences.defaults
        #expect(GeneralPreferences.showMainWindowAtLaunch(defaults: defaults))
        defaults.set(false, forKey: GeneralPreferences.showMainWindowAtLaunchKey)
        #expect(!GeneralPreferences.showMainWindowAtLaunch(defaults: defaults))
        let reopened = try #require(UserDefaults(suiteName: preferences.name))
        #expect(!GeneralPreferences.showMainWindowAtLaunch(defaults: reopened))
        defaults.set(true, forKey: GeneralPreferences.showMainWindowAtLaunchKey)
        #expect(GeneralPreferences.showMainWindowAtLaunch(defaults: defaults))
    }

    @Test func menuBarVisibilityKeepsTheExistingDefaultAndStoredChoice() throws {
        let preferences = try TestPreferences(prefix: "Draftly-GeneralPreferences-")
        defer { preferences.close() }
        let defaults = preferences.defaults
        #expect(GeneralPreferences.showInMenuBar(defaults: defaults))
        defaults.set(false, forKey: GeneralPreferences.showInMenuBarKey)
        #expect(!GeneralPreferences.showInMenuBar(defaults: defaults))
        defaults.set(true, forKey: GeneralPreferences.showInMenuBarKey)
        #expect(GeneralPreferences.showInMenuBar(defaults: defaults))
    }
}
