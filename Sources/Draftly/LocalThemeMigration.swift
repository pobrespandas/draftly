import Foundation
import DraftlyCore

@MainActor enum LocalThemeMigration {
    static let key = "editor.themes"
    static let migrationID = "editor.themes.v1"

    static func run(in library: LibraryStore, defaults: UserDefaults = .standard) throws {
        let deviceKey = "editor.themeMigrationDeviceID"
        let deviceID = defaults.string(forKey: deviceKey) ?? UUID().uuidString
        defaults.set(deviceID, forKey: deviceKey)
        let identifier = migrationID + ":" + deviceID
        if try library.hasThemeMigration(identifier) {
            defaults.removeObject(forKey: key)
            return
        }
        let text = defaults.string(forKey: key) ?? "[]"
        let themes = try JSONDecoder().decode([EditorThemeDefinition].self, from: Data(text.utf8))
        try library.migrateThemes(themes, migrationID: identifier)
        defaults.removeObject(forKey: key)
    }
}
