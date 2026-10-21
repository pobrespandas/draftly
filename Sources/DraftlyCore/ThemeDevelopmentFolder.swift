import Foundation

@MainActor
public enum ThemeDevelopmentFolder {
    public static let enabledKey = "theme.developmentFolder.enabled"
    public static let bookmarkKey = "theme.developmentFolder.bookmark"

    @discardableResult
    public static func select(_ directory: URL, in library: LibraryStore,
                              defaults: UserDefaults = .standard) throws -> Int {
        guard directory.isFileURL else { throw DraftlyError.message("Choose a local theme development folder.") }
        let active = directory.startAccessingSecurityScopedResource()
        defer { if active { directory.stopAccessingSecurityScopedResource() } }
        guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw DraftlyError.message("Choose a theme development folder.")
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey, .isAliasFileKey]
        let children = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]).sorted {
                $0.lastPathComponent < $1.lastPathComponent
            }
        var existing: [(id: UUID, url: URL)] = []
        for theme in library.themes where theme.type == "file" {
            do {
                if let url = try ThemeFileAccess.registeredURL(for: theme.id, defaults: defaults) {
                    existing.append((theme.id, url))
                }
            } catch let error as CocoaError where [.fileNoSuchFile, .fileReadNoSuchFile].contains(error.code) {
                continue
            }
        }
        var sourceURLs: [URL] = []
        var prepared: [ThemeFileAccess.Prepared] = []
        for url in children where ["json", "draftstheme"].contains(url.pathExtension.lowercased()) {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  values.isHidden != true, values.isAliasFile != true else { continue }
            guard !sourceURLs.contains(where: { sameSource($0, url) }) else {
                throw DraftlyError.message("The theme folder contains the same source file more than once.")
            }
            let matches = existing.filter { sameSource($0.url, url) }
            guard matches.count <= 1 else {
                throw DraftlyError.message("The theme file has more than one registered identity.")
            }
            do {
                prepared.append(try ThemeFileAccess.prepare(url, id: matches.first?.id ?? UUID()))
            } catch {
                throw DraftlyError.message("Could not load theme file “\(url.lastPathComponent)”: \(error.localizedDescription)")
            }
            sourceURLs.append(url)
        }
        let bookmark = try directory.bookmarkData(options: [.withSecurityScope],
            includingResourceValuesForKeys: nil, relativeTo: nil)
        try ThemeFileAccess.install(prepared, in: library, defaults: defaults)
        defaults.set(bookmark, forKey: bookmarkKey)
        defaults.set(true, forKey: enabledKey)
        ThemeCatalog.advanceLocalRevision(defaults: defaults)
        return prepared.count
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool, in library: LibraryStore,
                                  defaults: UserDefaults = .standard) throws -> Int {
        guard enabled else {
            defaults.set(false, forKey: enabledKey)
            return 0
        }
        guard let directory = try registeredDirectory(defaults: defaults) else {
            throw DraftlyError.message("Choose the theme development folder again.")
        }
        return try select(directory, in: library, defaults: defaults)
    }

    @discardableResult
    public static func refresh(in library: LibraryStore, defaults: UserDefaults = .standard) throws -> Int {
        guard defaults.bool(forKey: enabledKey) else { return 0 }
        guard let directory = try registeredDirectory(defaults: defaults) else {
            throw DraftlyError.message("Choose the theme development folder again.")
        }
        return try select(directory, in: library, defaults: defaults)
    }

    public static func folderName(defaults: UserDefaults = .standard) throws -> String? {
        try registeredDirectory(defaults: defaults)?.lastPathComponent
    }

    private static func registeredDirectory(defaults: UserDefaults) throws -> URL? {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                       relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private static func sameSource(_ first: URL, _ second: URL) -> Bool {
        if first.standardizedFileURL == second.standardizedFileURL { return true }
        let firstActive = first.startAccessingSecurityScopedResource()
        let secondActive = second.startAccessingSecurityScopedResource()
        defer {
            if firstActive { first.stopAccessingSecurityScopedResource() }
            if secondActive { second.stopAccessingSecurityScopedResource() }
        }
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let left = (try? first.resourceValues(forKeys: keys))?.fileResourceIdentifier as? NSObject,
              let right = (try? second.resourceValues(forKeys: keys))?.fileResourceIdentifier as? NSObject else { return false }
        return left.isEqual(right)
    }
}
