import Foundation
import DraftlyCore

struct WindowThemePresentation {
    let reference: [String: Any]?
    let theme: EditorTheme?
    let dark: Bool?
}

@MainActor extension WindowModel {
    var themePreferences: EditorThemePreferences {
        EditorThemePreferences(defaults: dependencies.preferences.defaults)
    }

    func configuredThemeReference(dark: Bool) -> [String: Any] {
        themePreferences.reference(dark: dark, themes: library.themes)
    }

    func setConfiguredThemeReference(_ reference: [String: Any], dark: Bool) throws {
        try themePreferences.set(reference: reference, dark: dark, themes: library.themes)
    }

    func editorThemePresentation(systemIsDark: Bool) -> WindowThemePresentation {
        let dark = darkTheme ?? systemIsDark
        let key = dark ? "preferredDarkTheme" : "preferredLightTheme"
        let workspace = (workspaceSnapshot(name: "Current").apiOptions[key] as? [String: Any])
            .flatMap { try? ThemeReferenceResolver.resolve($0, themes: library.themes) }
        let reference = workspace ?? (themePreferences.hasConfiguredPair ? configuredThemeReference(dark: dark) : nil)
        let theme: EditorTheme?
        if let reference {
            theme = reference["type"] as? String == "custom"
                ? (reference["uuid"] as? String).flatMap(UUID.init(uuidString:))
                    .flatMap { id in library.themes.first { $0.id == id } }
                : nil
        } else {
            let legacy = dependencies.preferences.defaults.string(forKey: "editor.theme")
            theme = library.themes.first { $0.name == legacy }
        }
        let scheme: Bool?
        if let name = reference?["name"] as? String, reference?["type"] as? String == "builtIn", ["Dark", "Light"].contains(name) {
            scheme = name == "Dark"
        } else { scheme = darkTheme ?? theme?.isDark }
        return WindowThemePresentation(reference: reference, theme: theme, dark: scheme)
    }
}
