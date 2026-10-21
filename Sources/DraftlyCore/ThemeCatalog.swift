import Foundation

@MainActor
public enum ThemeCatalog {
    nonisolated public static let revisionKey = "editor.themeRevision"

    public static func advanceLocalRevision(defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: revisionKey) &+ 1, forKey: revisionKey)
    }

    nonisolated public static let builtInNames = ["Default", "Dark", "Light"]

    public static func values(in library: LibraryStore) -> [[String: String]] {
        builtInNames.map { ["name": $0, "type": "builtIn"] }
            + library.themes.map { ["name": $0.name, "type": $0.type, "uuid": $0.id.uuidString] }
    }
}
