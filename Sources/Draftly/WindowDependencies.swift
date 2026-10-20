import AppKit
import DraftlyCore

@MainActor
struct WindowPreferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var prefersAdvancedFind: Bool { defaults.bool(forKey: GeneralPreferences.advancedFindKey) }
    var themes: [EditorTheme] {
        let data = defaults.string(forKey: "editor.themes") ?? "[]"
        return (try? JSONDecoder().decode([EditorTheme].self, from: Data(data.utf8))) ?? []
    }
    var listOptions: DraftListOptions { DraftListDefaults.load(defaults: defaults) }
}

@MainActor
struct WindowDependencies {
    var preferences = WindowPreferences()
    var recoverDictation: (String) -> Void = { _ in }
    var openQuickSearch: () -> Void = {}
    var openDraftWindow: (UUID?, Bool, NSWindow?) -> Void = { _, _, _ in }
}
