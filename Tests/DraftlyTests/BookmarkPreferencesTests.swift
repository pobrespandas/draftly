import Foundation
import CryptoKit
import Testing
@testable import Draftly

@Suite("Bookmark preferences")
struct BookmarkPreferencesTests {
    @Test func agentIdentitiesSurviveReloadAndChangeWithPermissionOrRecreation() throws {
        let prefs = try TestPreferences(prefix: "Draftly-Bookmark-Identity-"); defer { prefs.close() }
        let name = "Folder café 🐼"
        BookmarkPreferences.store(Data([1, 2, 3]), named: name, defaults: prefs.defaults)
        let first = try #require(BookmarkPreferences.agentRecords(defaults: prefs.defaults).first)
        let reopened = try #require(UserDefaults(suiteName: prefs.name))
        #expect(try BookmarkPreferences.agentRecords(defaults: reopened).first?.id == first.id)
        BookmarkPreferences.store(Data([1, 2, 3]), named: name, defaults: prefs.defaults)
        #expect(try BookmarkPreferences.agentRecords(defaults: prefs.defaults).first?.id == first.id)
        BookmarkPreferences.store(Data([4, 5, 6]), named: name, defaults: prefs.defaults)
        let replaced = try #require(BookmarkPreferences.agentRecords(defaults: prefs.defaults).first)
        #expect(replaced.id != first.id)
        BookmarkPreferences.forget(name, defaults: prefs.defaults)
        BookmarkPreferences.store(replaced.data, named: name, defaults: prefs.defaults)
        #expect(try BookmarkPreferences.agentRecords(defaults: prefs.defaults).first?.id != replaced.id)
    }

    @Test func legacyAndCorruptMetadataCannotRetargetAnExistingIdentity() throws {
        let prefs = try TestPreferences(prefix: "Draftly-Bookmark-Migration-"); defer { prefs.close() }
        let name = "Existing folder"
        prefs.defaults.set(Data([1]), forKey: "bookmark." + name)
        let first = try #require(BookmarkPreferences.agentRecords(defaults: prefs.defaults).first)
        let key = "agent.bookmark.identities.v1"
        var metadata = try #require(prefs.defaults.dictionary(forKey: key) as? [String: [String: String]])
        let index = Data(name.utf8).base64EncodedString(), changed = Data([2])
        metadata[index]?["digest"] = SHA256.hash(data: changed).map { String(format: "%02x", $0) }.joined()
        prefs.defaults.set(changed, forKey: "bookmark." + name)
        prefs.defaults.set(metadata, forKey: key)
        let retargeted = try #require(BookmarkPreferences.agentRecords(defaults: prefs.defaults).first)
        #expect(retargeted.id != first.id)
        prefs.defaults.set("corrupt", forKey: key)
        let recovered = try #require(BookmarkPreferences.agentRecords(defaults: prefs.defaults).first)
        #expect(recovered.id != first.id && recovered.id != retargeted.id)
        #expect(recovered.data == changed)
    }

    @Test func failedIdentityPersistenceDoesNotPublishOrRetainANewIdentity() throws {
        let prefs = try TestPreferences(prefix: "Draftly-Bookmark-Storage-"); defer { prefs.close() }
        prefs.defaults.set(Data([1]), forKey: "bookmark.Folder")
        #expect(throws: (any Error).self) {
            try BookmarkPreferences.agentRecords(defaults: prefs.defaults, synchronize: { false })
        }
        #expect(prefs.defaults.object(forKey: "agent.bookmark.identities.v1") == nil)
        let first = try #require(BookmarkPreferences.agentRecords(defaults: prefs.defaults).first)
        #expect(try BookmarkPreferences.agentRecords(defaults: prefs.defaults).first?.id == first.id)
        #expect(prefs.defaults.data(forKey: "bookmark.Folder") == Data([1]))
    }

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
