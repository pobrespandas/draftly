import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous native sharing")
@MainActor
struct NativeSharingRequestTests {
    @Test(arguments: [true, false])
    func cancellationDuringServiceDiscoveryNeverShowsPicker(available: Bool) async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        driver.available = available
        var task: Task<Bool, Error>?
        driver.beforeCanShare = { task?.cancel() }
        driver.whenShown = { driver.onEvent?(.cancelled) }
        task = Task { try await NativeSharingRequest.run("shareFile", [:], driver: driver, temporaryDirectory: root.url) }
        let pending = try #require(task)
        do { _ = try await pending.value; Issue.record("Cancelled discovery returned a result.") }
        catch { #expect(error is CancellationError) }
        #expect(driver.shows == 0 && driver.detaches == 1)
        #expect(try root.contents().isEmpty)
    }

    @Test(arguments: [9.0, 10.0, 11.0])
    func serviceDiscoveryUsesTheOriginalRequestDeadline(elapsed: Double) async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        var now = Date(timeIntervalSince1970: 100)
        driver.beforeCanShare = { now = now.addingTimeInterval(elapsed) }
        driver.whenShown = { driver.onEvent?(.cancelled) }
        do {
            let result = try await NativeSharingRequest.run("shareFile", [:], driver: driver, timeout: 10,
                                                          temporaryDirectory: root.url, now: { now })
            #expect(elapsed < 10 && !result)
        } catch { #expect(elapsed >= 10 && error as? ActionExecutionInterruption == .timeout) }
        #expect(driver.shows == (elapsed < 10 ? 1 : 0))
        #expect(driver.detaches == 1)
        #expect(try root.contents().isEmpty)
    }

    @Test func expiredPreparationDoesNotDiscoverOrShowServices() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        var discoveries = 0
        var clockReads = 0
        driver.beforeCanShare = { discoveries += 1 }
        do {
            _ = try await NativeSharingRequest.run("shareFile", [:], driver: driver, timeout: 10,
                                                   temporaryDirectory: root.url, now: {
                defer { clockReads += 1 }
                return Date(timeIntervalSince1970: clockReads == 0 ? 100 : 110)
            })
            Issue.record("Expired preparation returned a result.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        #expect(discoveries == 0 && driver.shows == 0 && driver.detaches == 1)
        #expect(try root.contents().isEmpty)
    }

    @Test func textSharingWaitsForTheActualServiceCompletion() async throws {
        let driver = SharingDriverFixture()
        let task = Task { try await NativeSharingRequest.run("share", ["text": "café 🐼"], driver: driver) }
        try await driver.waitUntilShown()
        #expect(driver.item == .text("café 🐼"))
        driver.onEvent?(.selected)
        #expect(driver.detaches == 0)
        driver.onEvent?(.completed)
        #expect(try await task.value)
        #expect(driver.detaches == 1)
    }

    @Test func sharedFileRemainsReadableUntilServiceCompletionThenIsRemoved() async throws {
        let root = try SharingFolderFixture()
        let driver = SharingDriverFixture()
        defer { driver.onEvent?(.completed); root.close() }
        let task = Task { try await NativeSharingRequest.run("shareFile", ["name": "note.txt", "text": "café 🐼\nsecond line"], driver: driver, temporaryDirectory: root.url) }
        try await driver.waitUntilShown()
        let file = try #require(driver.file)
        driver.onEvent?(.selected)
        #expect(try String(contentsOf: file, encoding: .utf8) == "café 🐼\nsecond line")
        driver.onEvent?(.completed)
        #expect(try await task.value)
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
    }

    @Test func URLSharingPreservesTheURLItem() async throws {
        let driver = SharingDriverFixture()
        driver.whenShown = { driver.onEvent?(.selected); driver.onEvent?(.completed) }
        let url = "https://example.invalid/neutral?q=caf%C3%A9"
        #expect(try await NativeSharingRequest.run("shareURL", ["url": url], driver: driver))
        let expectedURL = try #require(URL(string: url))
        #expect(driver.item == .url(expectedURL))
    }

    @Test func dismissingThePickerReturnsFalseAndRemovesTheTemporaryFile() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        driver.whenShown = { driver.onEvent?(.cancelled) }
        #expect(try await NativeSharingRequest.run("shareFile", [:], driver: driver, temporaryDirectory: root.url) == false)
        #expect(try root.contents().isEmpty)
        #expect(driver.detaches == 1)
    }

    @Test func serviceFailurePreservesTheErrorAndCleansTheTemporaryFile() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        driver.whenShown = {
            driver.onEvent?(.selected)
            driver.onEvent?(.failed(NSError(domain: "Draftly.SharingFixture", code: 42, userInfo: [NSLocalizedDescriptionKey: "Neutral sharing failure"])))
        }
        do { _ = try await NativeSharingRequest.run("shareFile", [:], driver: driver, temporaryDirectory: root.url); Issue.record("The failed share succeeded.") }
        catch { #expect(error.localizedDescription == "Neutral sharing failure") }
        #expect(try root.contents().isEmpty)
    }

    @Test func explicitServiceUserCancellationReturnsFalse() async throws {
        let driver = SharingDriverFixture()
        driver.whenShown = {
            driver.onEvent?(.selected)
            driver.onEvent?(.failed(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        }
        #expect(try await NativeSharingRequest.run("share", [:], driver: driver) == false)
        #expect(driver.detaches == 1)
    }

    @Test func unavailableServicesDoNotShowAPickerAndRemovePreparedFiles() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        driver.available = false
        do { _ = try await NativeSharingRequest.run("shareFile", [:], driver: driver, temporaryDirectory: root.url); Issue.record("An unavailable service succeeded.") }
        catch { #expect(error.localizedDescription == "No sharing service is available for these items.") }
        #expect(driver.shows == 0)
        #expect(try root.contents().isEmpty)
    }

    @Test func invalidFileNamesCannotEscapeOrCreateTemporaryFolders() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        for name in ["", ".", "..", "   ", "\0"] {
            do { _ = try await NativeSharingRequest.run("shareFile", ["name": name], driver: driver, temporaryDirectory: root.url); Issue.record("An invalid shared file name succeeded.") }
            catch { #expect(error.localizedDescription == "The shared file name is invalid.") }
        }
        #expect(driver.shows == 0)
        #expect(try root.contents().isEmpty)
    }

    @Test func slashInFileNameIsSanitizedWithoutChangingItsText() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        driver.whenShown = {
            #expect(driver.file?.lastPathComponent == "a-b.txt")
            driver.onEvent?(.cancelled)
        }
        #expect(try await NativeSharingRequest.run("shareFile", ["name": "a/b.txt"], driver: driver, temporaryDirectory: root.url) == false)
        #expect(try root.contents().isEmpty)
    }

    @Test func cancellationBeforeServiceSelectionClosesOnlyThePickerAndRemovesTheFile() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        let task = Task { try await NativeSharingRequest.run("shareFile", [:], driver: driver, temporaryDirectory: root.url) }
        try await driver.waitUntilShown()
        let lateEvent = driver.onEvent
        task.cancel()
        do { _ = try await task.value; Issue.record("The cancelled picker succeeded.") }
        catch { #expect(error is CancellationError) }
        lateEvent?(.selected); lateEvent?(.completed)
        #expect(driver.detaches == 1)
        #expect(try root.contents().isEmpty)
    }

    @Test func cancellationAfterHandoffKeepsTheFileUntilTheServiceActuallyFinishes() async throws {
        let root = try SharingFolderFixture()
        let driver = SharingDriverFixture()
        defer { driver.onEvent?(.completed); root.close() }
        let task = Task { try await NativeSharingRequest.run("shareFile", [:], driver: driver, temporaryDirectory: root.url) }
        try await driver.waitUntilShown()
        let file = try #require(driver.file)
        driver.onEvent?(.selected)
        task.cancel()
        do { _ = try await task.value; Issue.record("The cancelled share succeeded.") }
        catch { #expect(error is CancellationError) }
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(driver.detaches == 0)
        driver.onEvent?(.completed)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(driver.detaches == 1)
    }

    @Test func timeoutAfterHandoffRetainsTheFileUntilALateServiceCallback() async throws {
        let root = try SharingFolderFixture()
        let driver = SharingDriverFixture()
        defer { driver.onEvent?(.completed); root.close() }
        driver.whenShown = { driver.onEvent?(.selected) }
        do { _ = try await NativeSharingRequest.run("shareFile", [:], driver: driver, timeout: 0.02, temporaryDirectory: root.url); Issue.record("The service did not time out.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        let file = try #require(driver.file)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(driver.detaches == 0)
        driver.onEvent?(.failed(NSError(domain: "Draftly.SharingFixture", code: 7)))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func timeoutBeforeSelectionRemovesTheTemporaryFile() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        do { _ = try await NativeSharingRequest.run("shareFile", [:], driver: driver, timeout: 0.02, temporaryDirectory: root.url); Issue.record("The picker did not time out.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(driver.detaches == 1)
        #expect(try root.contents().isEmpty)
    }

    @Test func completionAfterTheAbsoluteDeadlineCannotReportSuccess() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        var now = Date(timeIntervalSince1970: 100)
        let driver = SharingDriverFixture()
        driver.whenShown = {
            driver.onEvent?(.selected)
            now = now.addingTimeInterval(11)
            driver.onEvent?(.completed)
        }
        do { _ = try await NativeSharingRequest.run("shareFile", [:], driver: driver, timeout: 10, temporaryDirectory: root.url, now: { now }); Issue.record("A late service completion reported success.") }
        catch { #expect((error as? ActionExecutionInterruption) == .timeout) }
        #expect(try root.contents().isEmpty)
    }

    @Test func completedServiceBeforeSelectionDoesNotResurrectTheLease() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        var cleanupErrors: [String] = []
        driver.whenShown = {
            let delayedEvent = driver.onEvent
            delayedEvent?(.completed)
            delayedEvent?(.selected)
            delayedEvent?(.completed)
        }
        #expect(try await NativeSharingRequest.run("shareFile", [:], driver: driver, temporaryDirectory: root.url,
                                                  reportCleanupError: { cleanupErrors.append($0) }))
        #expect(driver.detaches == 1)
        #expect(try root.contents().isEmpty)
        #expect(cleanupErrors.isEmpty)
    }

    @Test func presentationFailureDoesNotLeakAPreparedFile() async throws {
        let root = try SharingFolderFixture()
        defer { root.close() }
        let driver = SharingDriverFixture()
        driver.showError = DraftlyError.message("Open a Draftly window before sharing.")
        do { _ = try await NativeSharingRequest.run("shareFile", [:], driver: driver, temporaryDirectory: root.url); Issue.record("The failed picker presentation succeeded.") }
        catch { #expect(error.localizedDescription == "Open a Draftly window before sharing.") }
        #expect(try root.contents().isEmpty)
    }

    @Test func invalidURLAndTimeoutDoNotShowAPicker() async {
        let driver = SharingDriverFixture()
        do { _ = try await NativeSharingRequest.run("shareURL", ["url": "relative-path"], driver: driver); Issue.record("A relative sharing URL succeeded.") }
        catch { #expect(error.localizedDescription == "The sharing URL is invalid.") }
        do { _ = try await NativeSharingRequest.run("share", [:], driver: driver, timeout: 0); Issue.record("The invalid timeout succeeded.") }
        catch { #expect(error.localizedDescription == "The sharing timeout must be positive and finite.") }
        #expect(driver.shows == 0)
    }
}

@MainActor
private final class SharingDriverFixture: NativeSharingDriving {
    let shown = AsyncStream.makeStream(of: Bool.self)
    var onEvent: ((NativeSharingEvent) -> Void)?
    var whenShown: (() -> Void)?
    var beforeCanShare: (() -> Void)?
    var available = true
    var showError: Error?
    var item: NativeSharingItem?
    var shows = 0
    var detaches = 0
    var pickerVisible = false
    var file: URL? { if case .file(let url) = item { return url }; return nil }

    func waitUntilShown() async throws {
        var events = shown.stream.makeAsyncIterator()
        try #require(await events.next() == true)
    }
    func canShare(_ item: NativeSharingItem) -> Bool { beforeCanShare?(); return available }
    func show(_ item: NativeSharingItem) throws {
        self.item = item; shows += 1
        if let showError { throw showError }
        pickerVisible = true
        shown.continuation.yield(true); shown.continuation.finish()
        whenShown?()
    }
    func dismissPicker() { pickerVisible = false }
    func detach() { detaches += 1; dismissPicker(); onEvent = nil; whenShown = nil; beforeCanShare = nil; shown.continuation.finish() }
}

private struct SharingFolderFixture {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func contents() throws -> [URL] { try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) }
    func close() { try? FileManager.default.removeItem(at: url) }
}
