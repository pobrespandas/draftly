import Foundation
import AppKit
import PDFKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous printing requests") @MainActor
struct NativePrintRequestTests {
    @Test func completedPDFKeepsPaginationOnTheMainActorWithoutShowingPanels() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("neutral.pdf")
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
        let text = "Print QA heading\nUnicode café 🐼\nSecond line"
        let operation = try NativePrintLayout.makeOperation(NativePrintConfiguration(["text": text]), printInfo: info)
        // Stop before rendering if AppKit could call the actor-isolated view on another thread.
        try #require(!operation.canSpawnSeparateThread)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        #expect(operation.run())
        let document = try #require(PDFDocument(url: output))
        #expect(document.pageCount == 1)
        let contents = try #require(document.string)
        // PDFKit can extract the emoji font run after the other text runs.
        for part in ["Print QA heading", "Unicode café", "🐼", "Second line"] {
            #expect(contents.contains(part), "Missing PDF text: \(part)")
        }
    }

    @MainActor private final class Driver: NativePrintDriver {
        var onFinish: ((Result<Bool, Error>) -> Void)?
        var late: ((Result<Bool, Error>) -> Void)?
        var result: Result<Bool, Error>? = .success(true)
        var started = false
        var detached = 0
        var cancelled = 0
        var beforeFinish: (() -> Void)?
        func start() { started = true; late = onFinish; beforeFinish?(); if let result { onFinish?(result) } }
        func cancelOwnedPresentation() { cancelled += 1 }
        func detach() { detached += 1; onFinish = nil }
    }
    @Test func defaultFormatAndMarginsAreExplicit() throws {
        let configuration = try NativePrintConfiguration(["text": "Neutral café 🐼"])
        #expect(configuration.text == "Neutral café 🐼" && configuration.format == .text)
        #expect(configuration.topMargin == 72 && configuration.bottomMargin == 72 && configuration.leftMargin == 72 && configuration.rightMargin == 72)
    }
    @Test func shortTextUsesOnlyItsLaidOutHeightWithinThePrintablePage() throws {
        let configuration = try NativePrintConfiguration(["text": "Short café 🐼"])
        let view = try NativePrintLayout.makeView(configuration, paperSize: NSSize(width: 612, height: 792))
        #expect(view.frame.width == 468)
        #expect(view.frame.height > 0 && view.frame.height < 648)
        #expect(view.string == "Short café 🐼")
        #expect(view.textContainerInset == .zero)
    }

    @Test func longUnicodeTextWrapsAndKeepsTheFinalGlyphWithinTheView() throws {
        let text = String(repeating: "Neutral café 🐼 wraps across printable lines.\n", count: 500) + "Last 🐼"
        let view = try NativePrintLayout.makeView(NativePrintConfiguration(["text": text]), paperSize: NSSize(width: 612, height: 792))
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        #expect(view.frame.width == 468 && view.frame.height > 648)
        #expect(view.string == text)
        #expect(manager.glyphRange(for: container).length == manager.numberOfGlyphs)
        let end = (text as NSString).range(of: "Last 🐼", options: .backwards)
        let glyphs = manager.glyphRange(forCharacterRange: end, actualCharacterRange: nil)
        #expect(manager.boundingRect(forGlyphRange: glyphs, in: container).maxY <= view.frame.height)
    }

    @Test func changingPaperOrScaleReflowsInsteadOfAddingHorizontalPages() throws {
        let text = String(repeating: "Neutral wrapping words café 🐼 ", count: 40)
        let view = try NativePrintLayout.makeView(NativePrintConfiguration(["text": text]), paperSize: NSSize(width: 612, height: 792))
        let wideHeight = view.frame.height
        view.apply(try NativePrintPageGeometry(paperSize: NSSize(width: 420, height: 595), top: 72, bottom: 72, left: 72, right: 72))
        #expect(view.frame.width == 276 && view.frame.height > wideHeight)
        view.apply(try NativePrintPageGeometry(paperSize: NSSize(width: 612, height: 792), top: 72, bottom: 72, left: 72, right: 72, scale: 2))
        #expect(view.frame.width == 234 && view.string == text)
    }

    @Test func emptyAndTrailingNewlineDocumentsKeepTheirActualTextLayout() throws {
        let empty = try NativePrintLayout.makeView(NativePrintConfiguration([:]), paperSize: NSSize(width: 612, height: 792))
        let single = try NativePrintLayout.makeView(NativePrintConfiguration(["text": "Line"]), paperSize: NSSize(width: 612, height: 792))
        let trailing = try NativePrintLayout.makeView(NativePrintConfiguration(["text": "Line\n"]), paperSize: NSSize(width: 612, height: 792))
        #expect(empty.frame.height >= 1 && empty.frame.height < 648)
        #expect(trailing.frame.height > single.frame.height)
    }

    @Test func htmlStylesRemainInThePrintedTextStorage() throws {
        let configuration = try NativePrintConfiguration(["printFormat": "HTML", "text": "<p style='font-size:20pt'>Neutral café 🐼</p>"])
        let view = try NativePrintLayout.makeView(configuration, paperSize: NSSize(width: 612, height: 792))
        #expect(view.string.contains("Neutral café 🐼"))
        let font = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize >= 19)
        #expect(view.frame.height < 648)
    }

    @Test func marginsThatRemoveThePrintableAreaFailBeforeLayout() throws {
        let invalid: [[String: Any]] = [["leftMargin": 306, "rightMargin": 306], ["topMargin": 500, "bottomMargin": 400]]
        for values in invalid {
            let configuration = try NativePrintConfiguration(values)
            #expect(throws: (any Error).self) { try NativePrintLayout.makeView(configuration, paperSize: NSSize(width: 612, height: 792)) }
        }
        #expect(throws: (any Error).self) { try NativePrintPageGeometry(paperSize: .zero, top: 0, bottom: 0, left: 0, right: 0) }
        #expect(throws: (any Error).self) { try NativePrintPageGeometry(paperSize: NSSize(width: 612, height: 792), top: 0, bottom: 0, left: 0, right: 0, scale: 0) }
    }

    @Test func firstPartyStringsAndNumericMarginsKeepTheirValues() async throws {
        let driver = Driver()
        let result = try await NativePrintRequest.run(["printFormat": "HTML", "text": "<p>Neutral</p>", "topMargin": "12.5", "bottomMargin": 20, "leftMargin": "0", "rightMargin": 35.25], makeDriver: { configuration in
            #expect(configuration.format == .html && configuration.text == "<p>Neutral</p>")
            #expect(configuration.topMargin == 12.5 && configuration.bottomMargin == 20 && configuration.leftMargin == 0 && configuration.rightMargin == 35.25)
            return driver
        })
        #expect(result && driver.started && driver.detached == 1 && driver.cancelled == 0)
    }
    @Test func invalidOptionsFailBeforeCreatingAnyNativePrintOperation() async {
        let invalid: [[String: Any]] = [["printFormat": "PDF"], ["topMargin": "bad"], ["topMargin": -1], ["rightMargin": Double.infinity], ["leftMargin": true]]
        for values in invalid {
            do {
                _ = try await NativePrintRequest.run(values, makeDriver: { _ in Issue.record("Invalid options created a print operation."); return Driver() })
                Issue.record("Invalid print options succeeded.")
            } catch { }
        }
    }
    @Test func nativeFalseRemainsUnsuccessfulWithoutClaimingAReasonAppKitDoesNotProvide() async throws {
        let driver = Driver(); driver.result = .success(false)
        let result = try await NativePrintRequest.run([:], makeDriver: { _ in driver })
        #expect(!result && driver.detached == 1 && driver.cancelled == 0)
    }
    @Test func driverErrorsAndUnavailableWindowsRemainErrors() async {
        enum Failure: Error { case unavailable }
        do { _ = try await NativePrintRequest.run([:], makeDriver: { _ in throw Failure.unavailable }); Issue.record("Unavailable printing succeeded.") }
        catch { #expect(error is Failure) }
        let driver = Driver(); driver.result = .failure(NSError(domain: "NeutralPrintFailure", code: 7))
        do { _ = try await NativePrintRequest.run([:], makeDriver: { _ in driver }); Issue.record("Failed printing succeeded.") }
        catch { #expect((error as NSError).domain == "NeutralPrintFailure") }
        #expect(driver.detached == 1)
    }
    @Test func aLateCallbackCannotBeatTheDeadlineWhenTheTimerHasNotRun() async {
        let driver = Driver()
        var clock = Date(timeIntervalSince1970: 10)
        driver.beforeFinish = { clock = clock.addingTimeInterval(61) }
        do {
            _ = try await NativePrintRequest.run([:], timeout: 60, now: { clock }, makeDriver: { _ in driver })
            Issue.record("A late print callback succeeded.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        #expect(driver.detached == 1 && driver.cancelled == 1)
    }

    @Test func timeoutCancelsOnlyOwnedPresentationAndRejectsLateCallbacks() async {
        let driver = Driver(); driver.result = nil
        do { _ = try await NativePrintRequest.run([:], timeout: 0.02, makeDriver: { _ in driver }); Issue.record("Timed out printing succeeded.") }
        catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        driver.late?(.success(true))
        #expect(driver.detached == 1 && driver.cancelled == 1)
    }
    @Test func taskCancellationCancelsOnlyOwnedPresentationAndCompletesOnce() async {
        let driver = Driver(); driver.result = nil
        let task = Task { @MainActor in
            do { _ = try await NativePrintRequest.run([:], makeDriver: { _ in driver }); return false }
            catch { return error is CancellationError }
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while !driver.started, ContinuousClock.now < deadline { await Task.yield() }
        task.cancel()
        #expect(await task.value)
        driver.late?(.success(false))
        #expect(driver.detached == 1 && driver.cancelled == 1)
    }
}
