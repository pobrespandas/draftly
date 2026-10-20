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
    @Test func savedBookmarkWorksInTheNativeFileAPIAndForgetKeepsFiles() throws {
        let name = "Bookmark-contract-\(UUID().uuidString)"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            BookmarkPreferences.forget(name)
            try? FileManager.default.removeItem(at: folder)
        }
        let text = "Neutral café 🐼\nSecond line"
        try text.write(to: folder.appendingPathComponent("input.txt"), atomically: true, encoding: .utf8)
        UserDefaults.standard.set(try BookmarkPreferences.data(for: folder), forKey: "bookmark." + name)
        let host = NativeActionHost()
        #expect(try host.fileAPI(["storage": "bookmark", "bookmark": name, "operation": "readString", "path": "input.txt"]) as? String == text)
        #expect(try host.fileAPI(["storage": "bookmark", "bookmark": name, "operation": "writeString", "path": "output.txt", "text": text]) as? Bool == true)
        BookmarkPreferences.forget(name)
        #expect(!BookmarkPreferences.names().contains(name))
        #expect(try String(contentsOf: folder.appendingPathComponent("output.txt"), encoding: .utf8) == text)
    }
}
