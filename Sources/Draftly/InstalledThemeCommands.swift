import Foundation
import DraftlyCore

@MainActor
struct InstalledThemeCommands {
    let library: LibraryStore
    let defaults: UserDefaults

    init(library: LibraryStore, defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults
    }

    func saveEditorTheme(_ theme: EditorTheme, dark: Bool? = nil) throws {
        try library.saveTheme(DraftsThemeImport.applyingEditorChanges(theme))
        try select(reference: ["type": "custom", "uuid": theme.id.uuidString, "name": theme.name],
                   dark: dark ?? theme.isDark)
    }

    func select(reference: [String: Any], dark: Bool) throws {
        try EditorThemePreferences(defaults: defaults).set(reference: reference, dark: dark, themes: library.themes)
    }

    func install(_ prepared: ThemeFileAccess.Prepared, dark: Bool? = nil) throws {
        try ThemeFileAccess.install(prepared, in: library, defaults: defaults)
        try select(reference: ["type": "file", "uuid": prepared.definition.id.uuidString],
                   dark: dark ?? prepared.definition.isDark)
    }

    func delete(_ theme: EditorTheme) throws {
        try library.deleteTheme(theme.id)
        if theme.type == "file" {
            defaults.removeObject(forKey: ThemeFileAccess.bookmarkKey(for: theme.id))
        }
    }
}
