import AppKit
import DraftlyCore

@MainActor
struct WindowPreferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var prefersAdvancedFind: Bool { defaults.bool(forKey: GeneralPreferences.advancedFindKey) }
    var listOptions: DraftListOptions { DraftListDefaults.load(defaults: defaults) }
}
