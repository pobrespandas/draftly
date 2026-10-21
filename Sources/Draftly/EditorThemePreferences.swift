import Foundation
import DraftlyCore

struct EditorThemePreferences {
    static let key = "editor.themeReferences"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var stored: [String: [String: Any]] {
        guard let data = defaults.data(forKey: Self.key),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [:] }
        return values
    }
    var hasConfiguredPair: Bool { stored["dark"] != nil || stored["light"] != nil }

    private func legacyReference(dark: Bool, themes: [EditorTheme]) -> [String: Any]? {
        guard let name = defaults.string(forKey: "editor.theme"),
              let theme = themes.first(where: { $0.name == name && $0.isDark == dark }) else { return nil }
        return ["type": "custom", "uuid": theme.id.uuidString, "name": theme.name]
    }

    func reference(dark: Bool, themes: [EditorTheme]) -> [String: Any] {
        let key = dark ? "dark" : "light"
        if let raw = stored[key] {
            return (try? ThemeReferenceResolver.resolve(raw, themes: themes)) ??
                ["type": "builtIn", "name": dark ? "Dark" : "Light"]
        }
        return legacyReference(dark: dark, themes: themes) ?? ["type": "builtIn", "name": dark ? "Dark" : "Light"]
    }

    func set(reference: [String: Any], dark: Bool, themes: [EditorTheme]) throws {
        let resolved = try ThemeReferenceResolver.resolve(reference, themes: themes)
        var values = stored
        for legacyDark in [false, true] {
            let key = legacyDark ? "dark" : "light"
            if values[key] == nil { values[key] = legacyReference(dark: legacyDark, themes: themes) }
        }
        values[dark ? "dark" : "light"] = resolved
        guard JSONSerialization.isValidJSONObject(values) else {
            throw DraftlyError.message("The theme reference contains unsupported values.")
        }
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        defaults.set(data, forKey: Self.key)
    }
}
