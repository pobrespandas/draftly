import AppKit

enum BookmarkPreferences {
    static func data(for url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: .withSecurityScope)
    }

    static func names(defaults: UserDefaults = .standard) -> [String] {
        defaults.dictionaryRepresentation().compactMap { key, value in
            guard key.hasPrefix("bookmark."), value is Data else { return nil }
            let name = String(key.dropFirst("bookmark.".count))
            return name.isEmpty ? nil : name
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func forget(_ name: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "bookmark." + name)
    }
}
