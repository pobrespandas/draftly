import Foundation
import Testing
@testable import Draftly

@Suite("Bookmark preferences")
struct BookmarkPreferencesTests {
    @Test func inventoryUsesTheExistingActionKeysAndForgetKeepsOtherData() throws {
        let suite = "Draftly-BookmarkPreferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1]), forKey: "bookmark.Journal.2026")
        defaults.set(Data([2]), forKey: "bookmark.café 🐼")
        defaults.set("unrelated", forKey: "editor.theme")
        defaults.set("invalid", forKey: "bookmark.invalid")
        defaults.set(Data(), forKey: "bookmark.")
        #expect(Set(BookmarkPreferences.names(defaults: defaults)) == ["Journal.2026", "café 🐼"])
        BookmarkPreferences.forget("Journal.2026", defaults: defaults)
        #expect(BookmarkPreferences.names(defaults: defaults) == ["café 🐼"])
        #expect(defaults.data(forKey: "bookmark.café 🐼") == Data([2]))
        #expect(defaults.string(forKey: "editor.theme") == "unrelated")
    }
}

@Suite("Bookmark file access") @MainActor
struct BookmarkFileAccessTests {
    @Test(arguments: [false, true])
    func savedBookmarkWorksInTheNativeFileAPIAndForgetKeepsFiles(asynchronous: Bool) async throws {
        let name = "Bookmark-contract-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = "Neutral café 🐼\nSecond line"
        try text.write(to: folder.appendingPathComponent("input.txt"), atomically: true, encoding: .utf8)
        defaults.set(try BookmarkPreferences.data(for: folder), forKey: "bookmark." + name)
        defaults.set("Keep", forKey: "unrelated")
        let host = NativeActionHost()
        host.fileDefaults = defaults
        let libraryFolder = folder.appendingPathComponent("Library", isDirectory: true)
        host.testFileRoot = libraryFolder
        #expect(try host.libraryFolder() == libraryFolder)
        let bookmarkPath = try #require(try await perform("bookmark", values: ["name": name], host: host, asynchronous: asynchronous) as? String)
        #expect(URL(fileURLWithPath: bookmarkPath).resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
        #expect(try await perform("fileAPI", values: ["storage": "bookmark", "bookmark": name, "operation": "readString", "path": "input.txt"], host: host, asynchronous: asynchronous) as? String == text)
        #expect(try await perform("fileAPI", values: ["storage": "bookmark", "bookmark": name, "operation": "writeString", "path": "output.txt", "text": text], host: host, asynchronous: asynchronous) as? Bool == true)
        #expect(try await perform("saveFile", values: ["bookmark": name, "name": "export.txt", "text": text], host: host, asynchronous: asynchronous) as? Bool == true)
        #expect(try await perform("forgetBookmark", values: ["name": name], host: host, asynchronous: asynchronous) as? Bool == true)
        #expect(!BookmarkPreferences.names(defaults: defaults).contains(name))
        #expect(defaults.string(forKey: "unrelated") == "Keep")
        #expect(try String(contentsOf: folder.appendingPathComponent("input.txt"), encoding: .utf8) == text)
        #expect(try String(contentsOf: folder.appendingPathComponent("output.txt"), encoding: .utf8) == text)
        #expect(try String(contentsOf: folder.appendingPathComponent("export.txt"), encoding: .utf8) == text)
    }

    private func perform(_ operation: String, values: [String: Any], host: NativeActionHost, asynchronous: Bool) async throws -> Any? {
        if asynchronous {
            let payload = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
            let response = try await host.performAsync(operation, payload: payload)
            return (try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])?["value"]
        }
        return try host.perform(operation, values: values)
    }
}
