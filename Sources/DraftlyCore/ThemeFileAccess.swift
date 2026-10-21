import Foundation

@MainActor
public enum ThemeFileAccess {
    public struct Prepared: Sendable {
        public let definition: EditorThemeDefinition
        public let bookmark: Data
    }

    public static func bookmarkKey(for id: UUID) -> String { "theme.file." + id.uuidString }

    public static func prepare(_ url: URL, id: UUID = UUID()) throws -> Prepared {
        let active = url.startAccessingSecurityScopedResource()
        defer { if active { url.stopAccessingSecurityScopedResource() } }
        let definition = try definition(at: url, id: id)
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        return Prepared(definition: definition, bookmark: bookmark)
    }

    public static func install(_ prepared: Prepared, in library: LibraryStore, defaults: UserDefaults = .standard) throws {
        try install([prepared], in: library, defaults: defaults)
    }

    public static func install(_ prepared: [Prepared], in library: LibraryStore, defaults: UserDefaults = .standard) throws {
        for file in prepared {
            guard file.definition.type == "file" else { throw DraftlyError.message("The file theme has an invalid type.") }
            if let existing = library.themes.first(where: { $0.id == file.definition.id }), existing.type != "file" {
                throw DraftlyError.message("The theme identity belongs to a different theme type.")
            }
        }
        let definitions = prepared.map(\.definition)
        guard Set(definitions.map(\.id)).count == definitions.count,
              Set(definitions.map(\.name)).count == definitions.count else {
            throw DraftlyError.message("The file themes contain duplicate names or identities.")
        }
        let changed = definitions.filter { definition in !library.themes.contains(definition) }
        if !changed.isEmpty { try library.saveThemes(changed) }
        for file in prepared { defaults.set(file.bookmark, forKey: bookmarkKey(for: file.definition.id)) }
    }

    public static func registeredURL(for id: UUID, defaults: UserDefaults = .standard) throws -> URL? {
        guard let bookmark = defaults.data(forKey: bookmarkKey(for: id)) else { return nil }
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    public static func read(_ definition: EditorThemeDefinition, defaults: UserDefaults = .standard) throws -> EditorThemeDefinition {
        try definition.validate()
        guard definition.type == "file" else { return definition }
        guard let bookmark = defaults.data(forKey: bookmarkKey(for: definition.id)) else {
            throw DraftlyError.message("Reselect the file for theme \(definition.name).")
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        let active = url.startAccessingSecurityScopedResource()
        defer { if active { url.stopAccessingSecurityScopedResource() } }
        let current = try self.definition(at: url, id: definition.id)
        guard current.name == definition.name else {
            throw DraftlyError.message("The file theme name changed. Reselect or import it again.")
        }
        if stale {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: bookmarkKey(for: definition.id))
        }
        return current
    }

    private static func definition(at url: URL, id: UUID) throws -> EditorThemeDefinition {
        guard url.isFileURL else { throw DraftlyError.message("Choose a local theme file.") }
        let data = try Data(contentsOf: url)
        guard String(data: data, encoding: .utf8) != nil else { throw DraftlyError.message("The theme file must contain UTF-8 JSON.") }
        var definition: EditorThemeDefinition
        if let native = try? JSONDecoder().decode(EditorThemeDefinition.self, from: data) {
            try native.validate()
            definition = native
        } else { definition = try DraftsThemeImport.decode(data: data, id: id) }
        definition.id = id
        definition.type = "file"
        try definition.validate()
        return definition
    }
}
