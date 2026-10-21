import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Bookmark reopen and recovery") @MainActor
struct BookmarkReopenContractTests {
    @Test func reopenedBookmarkReportsMissingFileAndRecoversOnlyAfterAcceptedFolder() async throws {
        let preferences = try TestPreferences(prefix: "Draftly-BookmarkReopen-")
        defer { preferences.close() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let replacement = root.appendingPathComponent("Replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("keep.txt")
        try "Original café 🐼".write(to: original, atomically: true, encoding: .utf8)
        let first = NativeFileAdapter(defaults: preferences.defaults, testFileRoot: root)
        _ = try await first.bookmarkRootAsync("Neutral", select: { _ in root })
        let saved = try #require(preferences.defaults.data(forKey: "bookmark.Neutral"))

        let reopenedDefaults = try #require(UserDefaults(suiteName: preferences.name))
        let reopened = NativeFileAdapter(defaults: reopenedDefaults, testFileRoot: root)
        let read = try await reopened.fileAPIAsync([
            "storage": "bookmark", "bookmark": "Neutral", "operation": "readString", "path": "keep.txt"
        ], select: { _ in Issue.record("A reopened valid bookmark showed a selector."); return nil })
        #expect(read as? String == "Original café 🐼")
        do {
            _ = try await reopened.fileAPIAsync([
                "storage": "bookmark", "bookmark": "Neutral", "operation": "readString", "path": "missing.txt"
            ], select: { _ in Issue.record("A missing file requested a new bookmark."); return nil })
            Issue.record("The missing bookmark file read succeeded.")
        } catch {
            let error = error as NSError
            #expect(error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileReadNoSuchFile.rawValue)
        }
        #expect(reopenedDefaults.data(forKey: "bookmark.Neutral") == saved)

        let invalid = Data([0, 1, 2])
        reopenedDefaults.set(invalid, forKey: "bookmark.Neutral")
        do {
            _ = try await reopened.bookmarkRootAsync("Neutral", select: { _ in nil })
            Issue.record("Cancelling bookmark recovery succeeded.")
        } catch { #expect((error as? ActionExecutionInterruption) == .cancelled) }
        #expect(reopenedDefaults.data(forKey: "bookmark.Neutral") == invalid)
        _ = try await reopened.bookmarkRootAsync("Neutral", select: { request in
            #expect(request == .folder(name: "Neutral"))
            return replacement
        })
        #expect(reopenedDefaults.data(forKey: "bookmark.Neutral") != invalid)
        let finalDefaults = try #require(UserDefaults(suiteName: preferences.name))
        let final = NativeFileAdapter(defaults: finalDefaults, testFileRoot: root)
        let written = try await final.fileAPIAsync([
            "storage": "bookmark", "bookmark": "Neutral", "operation": "writeString", "path": "recovered.txt", "text": "Recovered 🐼"
        ], select: { _ in Issue.record("The recovered bookmark showed a selector."); return nil })
        #expect(written as? Bool == true)
        #expect(try String(contentsOf: replacement.appendingPathComponent("recovered.txt"), encoding: .utf8) == "Recovered 🐼")
        #expect(try String(contentsOf: original, encoding: .utf8) == "Original café 🐼")
        BookmarkPreferences.forget("Neutral", defaults: finalDefaults)
        #expect(!BookmarkPreferences.names(defaults: finalDefaults).contains("Neutral"))
        #expect(FileManager.default.fileExists(atPath: replacement.appendingPathComponent("recovered.txt").path))
    }
}
