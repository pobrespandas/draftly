import Foundation

@MainActor
public enum ThemeCatalog {
    nonisolated public static let builtInNames = ["Default", "Dark", "Light"]

    public static func values(in library: LibraryStore) -> [[String: String]] {
        builtInNames.map { ["name": $0, "type": "builtIn"] }
            + library.themes.map { ["name": $0.name, "type": "custom", "uuid": $0.id.uuidString] }
    }
}
