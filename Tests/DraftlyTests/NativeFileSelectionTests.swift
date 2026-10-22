import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous file selection and export")
@MainActor
struct NativeFileSelectionTests {
    @Test func saveSelectionUsesSanitizedNameAndWritesUnicode() async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        let target = fixture.root.appendingPathComponent("saved.md")
        let result = try await fixture.adapter.saveFileAsync(["name": "a/b.md", "text": "café 🐼\nsecond line"], select: { selection in
            #expect(selection == .save(name: "a-b.md"))
            return target
        })
        #expect(result)
        #expect(try String(contentsOf: target, encoding: .utf8) == "café 🐼\nsecond line")
    }

    @Test func userCancelIsDistinctFromAStorageError() async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        do { _ = try await fixture.adapter.saveFileAsync([:], select: { _ in nil }); Issue.record("User cancellation succeeded.") }
        catch { #expect((error as? ActionExecutionInterruption) == .cancelled) }
        do { _ = try await fixture.adapter.saveFileAsync([:], select: { _ in fixture.root }); Issue.record("Writing into a directory succeeded.") }
        catch { #expect(!(error is ActionExecutionInterruption) && !(error is CancellationError)) }
    }

    @Test func bookmarkSelectionPersistsAndThenReusesTheExistingFolder() async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        let name = "Neutral café 🐼"
        let root = try await fixture.adapter.bookmarkRootAsync(name, select: { selection in
            #expect(selection == .folder(name: name))
            return fixture.root
        })
        #expect(root == fixture.root)
        #expect(fixture.defaults.data(forKey: "bookmark." + name) != nil)
        let reused = try await fixture.adapter.bookmarkRootAsync(name, select: { _ in
            Issue.record("A valid saved bookmark must not show a panel.")
            return nil
        })
        #expect(reused.resolvingSymlinksInPath() == fixture.root.resolvingSymlinksInPath())
    }

    @Test func invalidBookmarkIsReplacedOnlyAfterAnAcceptedSelection() async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        let invalid = Data([1, 2, 3])
        fixture.defaults.set(invalid, forKey: "bookmark.QA")
        do { _ = try await fixture.adapter.bookmarkRootAsync("QA", select: { _ in nil }); Issue.record("Folder cancellation succeeded.") }
        catch { #expect((error as? ActionExecutionInterruption) == .cancelled) }
        #expect(fixture.defaults.data(forKey: "bookmark.QA") == invalid)
        _ = try await fixture.adapter.bookmarkRootAsync("QA", select: { _ in fixture.root })
        #expect(fixture.defaults.data(forKey: "bookmark.QA") != invalid)
    }

    @Test func bookmarkedExportPreservesAllWriteModesAndCreateProtection() async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        let adapter = fixture.adapter
        let base: [String: Any] = ["bookmark": "QA", "folder": "nested", "name": "note.md"]
        for (mode, text, expected) in [("create", "A🐼", "A🐼"), ("append", "B", "A🐼B"), ("prepend", "C", "CA🐼B"), ("replace", "D", "D")] {
            let values = base.merging(["mode": mode, "text": text], uniquingKeysWith: { _, new in new })
            #expect(try await adapter.saveFileAsync(values, select: { _ in fixture.root }))
            #expect(try String(contentsOf: fixture.root.appendingPathComponent("nested/note.md"), encoding: .utf8) == expected)
        }
        do { _ = try await adapter.saveFileAsync(base.merging(["text": "replacement"], uniquingKeysWith: { _, new in new }), select: { _ in nil }); Issue.record("Create overwrote an existing file.") }
        catch { #expect(error.localizedDescription == "A file with this name already exists. Choose another draft title.") }
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("nested/note.md"), encoding: .utf8) == "D")
    }

    @Test func lostDirectoryWritePermissionPreservesFileAndBookmarkThenRecovers() async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        let manager = FileManager.default
        let permissions = try #require(manager.attributesOfItem(atPath: fixture.root.path)[.posixPermissions] as? NSNumber)
        defer { try? manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: fixture.root.path) }
        let target = fixture.root.appendingPathComponent("neutral.txt")
        try "Original café 🐼".write(to: target, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.root.path)
        let values: [String: Any] = ["bookmark": "QA", "name": "neutral.txt", "mode": "replace", "text": "Recovered café 🐼"]
        do {
            _ = try await fixture.adapter.saveFileAsync(values, select: { _ in fixture.root })
            Issue.record("The export replaced a file without directory write permission.")
        } catch {
            let native = error as NSError
            #expect(native.domain == NSCocoaErrorDomain && native.code == CocoaError.Code.fileWriteNoPermission.rawValue)
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "Original café 🐼")
        #expect(fixture.defaults.data(forKey: "bookmark.QA") != nil)
        try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: fixture.root.path)
        #expect(try await fixture.adapter.saveFileAsync(values, select: { _ in
            Issue.record("The retained bookmark must not request another selection."); return nil
        }))
        #expect(try String(contentsOf: target, encoding: .utf8) == "Recovered café 🐼")
    }

    @Test func unsupportedModeFailsBeforeSelectionAndPreservesExistingData() async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        let file = fixture.root.appendingPathComponent("existing")
        try "Original".write(to: file, atomically: true, encoding: .utf8)
        var selections = 0
        for bookmark in ["", "QA"] {
            do {
                _ = try await fixture.adapter.saveFileAsync(["mode": "unsupported", "text": "New", "bookmark": bookmark, "name": "existing"], select: { _ in
                    selections += 1
                    return bookmark.isEmpty ? file : fixture.root
                })
                Issue.record("The unsupported mode succeeded.")
            } catch { #expect(error.localizedDescription == "Unsupported file write type: unsupported") }
        }
        #expect(selections == 0)
        #expect(fixture.defaults.data(forKey: "bookmark.QA") == nil)
        #expect(try String(contentsOf: file, encoding: .utf8) == "Original")
    }

    @Test func bookmarkedExportRejectsTraversalAndSymbolicLinkEscapes() async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        let outside = fixture.root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let externalFile = outside.appendingPathComponent("keep.txt")
        try "Keep".write(to: externalFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("escape"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("alias.txt"), withDestinationURL: externalFile)
        for (folder, name) in [("../outside", "note.md"), ("escape", "note.md"), ("", "alias.txt")] {
            do {
                _ = try await fixture.adapter.saveFileAsync(["bookmark": "QA", "folder": folder, "name": name, "mode": "replace", "text": "Blocked"], select: { _ in fixture.root })
                Issue.record("The bookmarked export escaped its selected folder.")
            } catch { #expect(error.localizedDescription == "The destination must stay inside the selected folder.") }
        }
        #expect(try String(contentsOf: externalFile, encoding: .utf8) == "Keep")
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("note.md").path))
    }

    @Test func fileAPIUsesTheSelectedBookmarkWithoutASecondPanel() async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        var selections = 0
        let select: NativeFileSelector = { _ in selections += 1; return fixture.root }
        let base: [String: Any] = ["storage": "bookmark", "bookmark": "QA", "path": "nested/data.txt"]
        let written = try await fixture.adapter.fileAPIAsync(base.merging(["operation": "writeString", "text": "Neutral café 🐼"], uniquingKeysWith: { _, new in new }), select: select)
        #expect(written as? Bool == true)
        let text = try await fixture.adapter.fileAPIAsync(base.merging(["operation": "readString"], uniquingKeysWith: { _, new in new }), select: select)
        #expect(text as? String == "Neutral café 🐼")
        #expect(selections == 1)
    }

    @Test func emptyBookmarkNameDoesNotPresentAPanel() async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        do {
            _ = try await fixture.adapter.bookmarkRootAsync("", select: { _ in Issue.record("An empty bookmark name showed a panel."); return nil })
            Issue.record("The empty bookmark name succeeded.")
        } catch { #expect(error.localizedDescription == "The bookmark name is empty.") }
    }

    @Test(arguments: [false, true])
    func cancelledLateSelectionCannotWriteOrPersistABookmark(bookmarked: Bool) async throws {
        let fixture = try FileAdapterFixture()
        defer { fixture.close() }
        let gate = FileSelectorGate()
        let file = fixture.root.appendingPathComponent("late.txt")
        let task = Task { try await fixture.adapter.saveFileAsync(["bookmark": bookmarked ? "QA" : "", "text": "Must not write"], select: { _ in await gate.choose() }) }
        var started = gate.started.stream.makeAsyncIterator()
        try #require(await started.next() == true)
        task.cancel()
        gate.accept(bookmarked ? fixture.root : file)
        do { _ = try await task.value; Issue.record("The cancelled late selection succeeded.") }
        catch { #expect(error is CancellationError) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Draft.md").path))
        #expect(fixture.defaults.data(forKey: "bookmark.QA") == nil)
    }

    @Test func synchronousPanelResponseAndDuplicateCompletionCloseExactlyOnce() async throws {
        let selected = URL(fileURLWithPath: "/neutral-selection")
        var closes = 0
        let result = try await NativeFileSelectionRequest.select(.save(name: "note.md"), begin: { _, completion in
            completion(selected)
            completion(nil)
            return { closes += 1 }
        })
        #expect(result == selected)
        #expect(closes == 1)
    }

    @Test func taskCancellationClosesThePanelAndIgnoresLateCompletion() async throws {
        let started = AsyncStream.makeStream(of: Bool.self)
        var completion: (@MainActor @Sendable (URL?) -> Void)?
        var closes = 0
        let task = Task { try await NativeFileSelectionRequest.select(.folder(name: "QA"), begin: { _, callback in
            completion = callback
            started.continuation.yield(true); started.continuation.finish()
            return { closes += 1 }
        }) }
        var events = started.stream.makeAsyncIterator()
        try #require(await events.next() == true)
        task.cancel()
        do { _ = try await task.value; Issue.record("The cancelled panel returned a selection.") }
        catch { #expect(error is CancellationError) }
        completion?(URL(fileURLWithPath: "/late-selection"))
        #expect(closes == 1)
    }

    @Test func cancelledSelectionRejectsAResponseBeforeQueuedCleanup() async throws {
        let started = AsyncStream.makeStream(of: Bool.self)
        var completion: (@MainActor @Sendable (URL?) -> Void)?
        var closes = 0
        let task = Task { try await NativeFileSelectionRequest.select(.save(name: "neutral.md"), begin: { _, callback in
            completion = callback
            started.continuation.yield(true)
            return { closes += 1 }
        }) }
        var events = started.stream.makeAsyncIterator()
        try #require(await events.next() == true)
        task.cancel()
        completion?(URL(fileURLWithPath: "/neutral-late-selection"))
        do { _ = try await task.value; Issue.record("Cancellation returned a selected file.") }
        catch { #expect(error is CancellationError) }
        completion?(nil)
        #expect(closes == 1)
    }

    @Test func callbackAfterTheAbsoluteDeadlineCannotBeatTheTimeoutTask() async {
        var now = Date(timeIntervalSince1970: 100)
        var closes = 0
        do {
            _ = try await NativeFileSelectionRequest.select(.save(name: "note.md"), timeout: 10, now: { now }, begin: { _, completion in
                now = now.addingTimeInterval(11)
                completion(URL(fileURLWithPath: "/late-selection"))
                return { closes += 1 }
            })
            Issue.record("A selection after the deadline succeeded.")
        } catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(closes == 1)
    }

    @Test func selectionTimeoutClosesThePanel() async {
        var closes = 0
        do {
            _ = try await NativeFileSelectionRequest.select(.save(name: "note.md"), timeout: 0.02, begin: { _, _ in { closes += 1 } })
            Issue.record("The file panel did not time out.")
        } catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(closes == 1)
    }
}

@MainActor
private struct FileAdapterFixture {
    let root: URL
    let defaults: UserDefaults
    let suite: String
    var adapter: NativeFileAdapter { NativeFileAdapter(defaults: defaults, testFileRoot: root) }

    init() throws {
        suite = "Draftly-FilePanelTests-" + UUID().uuidString
        defaults = try #require(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func close() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class FileSelectorGate {
    let started = AsyncStream.makeStream(of: Bool.self)
    private var continuation: CheckedContinuation<URL?, Never>?
    func choose() async -> URL? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.continuation.yield(true); started.continuation.finish()
        }
    }
    func accept(_ url: URL?) { continuation?.resume(returning: url); continuation = nil }
}
