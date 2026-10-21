import Foundation
import DraftlyCore

struct WindowThemePresentation {
    struct Key: Equatable {
        let systemIsDark: Bool
        let override: Bool?
        let references: Data?
        let revision: Int
        let legacy: String?
        let themes: [EditorTheme]
        let workspace: [String: String]?
    }
    let reference: [String: Any]?
    let theme: EditorTheme?
    let dark: Bool?
    let error: String?
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

    func validateWorkspaceThemeFiles(_ workspace: Workspace) throws {
        for key in ["preferredDarkTheme", "preferredLightTheme"] {
            guard let reference = workspace.apiOptions[key] as? [String: Any],
                  reference["type"] as? String == "file",
                  let id = (reference["uuid"] as? String).flatMap(UUID.init(uuidString:)),
                  let theme = library.themes.first(where: { $0.id == id }) else { continue }
            _ = try ThemeFileAccess.read(theme, defaults: dependencies.preferences.defaults)
        }
    }

    func editorThemePresentation(systemIsDark: Bool) -> WindowThemePresentation {
        let defaults = dependencies.preferences.defaults
        let cacheKey = WindowThemePresentation.Key(systemIsDark: systemIsDark, override: darkTheme,
            references: defaults.data(forKey: EditorThemePreferences.key),
            revision: defaults.integer(forKey: EditorThemePreferences.revisionKey),
            legacy: defaults.string(forKey: "editor.theme"), themes: library.themes, workspace: workspaceScriptMetadata)
        if let cached = cachedThemePresentation, cached.key == cacheKey { return cached.value }
        let dark = darkTheme ?? systemIsDark
        let key = dark ? "preferredDarkTheme" : "preferredLightTheme"
        let workspace = (workspaceSnapshot(name: "Current").apiOptions[key] as? [String: Any])
            .flatMap { try? ThemeReferenceResolver.resolve($0, themes: library.themes) }
        let reference = workspace ?? (themePreferences.hasConfiguredPair ? configuredThemeReference(dark: dark) : nil)
        var theme: EditorTheme?
        var readError: String?
        if let reference {
            theme = ["custom", "file"].contains(reference["type"] as? String ?? "")
                ? (reference["uuid"] as? String).flatMap(UUID.init(uuidString:))
                    .flatMap { id in library.themes.first { $0.id == id } }
                : nil
        } else {
            let legacy = dependencies.preferences.defaults.string(forKey: "editor.theme")
            theme = library.themes.first { $0.name == legacy && $0.type == "custom" }
        }
        if let selected = theme {
            do { theme = try ThemeFileAccess.read(selected, defaults: dependencies.preferences.defaults) }
            catch { theme = nil; readError = error.localizedDescription }
        }
        let scheme: Bool?
        if let name = reference?["name"] as? String, reference?["type"] as? String == "builtIn", ["Dark", "Light"].contains(name) {
            scheme = name == "Dark"
        } else { scheme = darkTheme ?? theme?.isDark }
        let presentation = WindowThemePresentation(reference: reference, theme: theme, dark: scheme, error: readError)
        cachedThemePresentation = (cacheKey, presentation)
        return presentation
    }
}
