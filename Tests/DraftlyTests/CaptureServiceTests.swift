import AppKit
import Testing
@testable import Draftly

@Suite("macOS capture services") @MainActor
struct CaptureServiceTests {
    private func withPasteboard(types: [NSPasteboard.PasteboardType] = [.string],
                                _ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes(types, owner: nil)
        try body(pasteboard)
    }

    private func richText(_ text: String, type: NSAttributedString.DocumentType) throws -> Data {
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 16)])
        return try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                   documentAttributes: [.documentType: type])
    }

    @Test func directCaptureSavesExactSelectedTextOnlyOnce() throws {
        try withPasteboard { pasteboard in
            let text = "  Idea ñ 🐼\nSecond line\n"
            #expect(pasteboard.setString(text, forType: .string))
            let changeCount = pasteboard.changeCount
            var saved: [String] = [], shown: [String] = []
            let service = CaptureService(save: { saved.append($0) }, showOptions: { shown.append($0) })

            try service.handle(pasteboard, mode: .direct)

            #expect(saved == [text])
            #expect(shown.isEmpty)
            #expect(pasteboard.string(forType: .string) == text)
            #expect(pasteboard.changeCount == changeCount)
        }
    }

    @Test func captureWithOptionsShowsExactSelectionWithoutSaving() throws {
        try withPasteboard { pasteboard in
            let text = "Selected options\n🧪"
            #expect(pasteboard.setString(text, forType: .string))
            var saved: [String] = [], shown: [String] = []
            let service = CaptureService(save: { saved.append($0) }, showOptions: { shown.append($0) })

            try service.handle(pasteboard, mode: .options)

            #expect(saved.isEmpty)
            #expect(shown == [text])
            #expect(pasteboard.string(forType: .string) == text)
        }
    }

    @Test func saveFailurePropagatesAndPreservesSelectionForRetry() throws {
        withPasteboard { pasteboard in
            let text = "Keep this selection"
            #expect(pasteboard.setString(text, forType: .string))
            let changeCount = pasteboard.changeCount
            var attempts = 0, shown = false
            let service = CaptureService(save: { _ in
                attempts += 1
                throw ServiceTestError.storage
            }, showOptions: { _ in shown = true })

            #expect(throws: ServiceTestError.storage) { try service.handle(pasteboard, mode: .direct) }

            #expect(attempts == 1)
            #expect(!shown)
            #expect(pasteboard.string(forType: .string) == text)
            #expect(pasteboard.changeCount == changeCount)
        }
    }

    @Test func optionsFailurePropagatesWithoutSavingOrChangingSelection() throws {
        withPasteboard { pasteboard in
            #expect(pasteboard.setString("Retain options input", forType: .string))
            let changeCount = pasteboard.changeCount
            var saved = false
            let service = CaptureService(save: { _ in saved = true }, showOptions: { _ in throw ServiceTestError.options })

            #expect(throws: ServiceTestError.options) { try service.handle(pasteboard, mode: .options) }

            #expect(!saved)
            #expect(pasteboard.string(forType: .string) == "Retain options input")
            #expect(pasteboard.changeCount == changeCount)
        }
    }

    @Test func plainTextTakesPriorityOverRichTextAndURL() throws {
        try withPasteboard(types: [.string, .rtf, .URL]) { pasteboard in
            let data = try richText("Rich text", type: .rtf)
            #expect(pasteboard.setData(data, forType: .rtf))
            #expect(pasteboard.setString("https://example.com/", forType: .URL))
            #expect(pasteboard.setString("Plain text", forType: .string))
            let selected = try CaptureService.selectedText(from: pasteboard)
            #expect(selected == "Plain text")
        }
    }

    @Test func rtfBecomesPlainTextWithUnicodeAndLineBreaks() throws {
        try withPasteboard(types: [.rtf]) { pasteboard in
            let text = "Título ñ 🐼\nSecond line"
            let data = try richText(text, type: .rtf)
            #expect(pasteboard.setData(data, forType: .rtf))
            let selected = try CaptureService.selectedText(from: pasteboard)
            #expect(selected == text)
        }
    }

    @Test func rtfdBecomesPlainTextWithUnicodeAndLineBreaks() throws {
        try withPasteboard(types: [.rtfd]) { pasteboard in
            let text = "RTFD ñ 🐼\nSecond line"
            let data = try richText(text, type: .rtfd)
            #expect(pasteboard.setData(data, forType: .rtfd))
            let selected = try CaptureService.selectedText(from: pasteboard)
            #expect(selected == text)
        }
    }

    @Test func rtfTakesPriorityOverRtfdAndURL() throws {
        let source = SelectionFixture(
            types: [.URL, .rtfd, .rtf],
            strings: [.URL: "https://example.com/"],
            data: [.rtfd: try richText("RTFD", type: .rtfd), .rtf: try richText("RTF", type: .rtf)]
        )
        let selected = try CaptureService.selectedText(from: source)
        #expect(selected == "RTF")
    }

    @Test func rtfdTakesPriorityOverURL() throws {
        let source = SelectionFixture(
            types: [.URL, .rtfd], strings: [.URL: "https://example.com/"],
            data: [.rtfd: try richText("RTFD", type: .rtfd)]
        )
        let selected = try CaptureService.selectedText(from: source)
        #expect(selected == "RTFD")
    }

    @Test func urlSelectionReturnsItsAbsoluteString() throws {
        try withPasteboard(types: [.URL]) { pasteboard in
            #expect(pasteboard.setString("https://example.com/path?q=%F0%9F%90%BC#section", forType: .URL))
            let selected = try CaptureService.selectedText(from: pasteboard)
            #expect(selected == "https://example.com/path?q=%F0%9F%90%BC#section")
        }
    }

    @Test func fileURLSelectionReturnsItsAbsoluteString() throws {
        let source = SelectionFixture(types: [.fileURL], strings: [.fileURL: "file:///tmp/Neutral%20Document.txt"])
        let selected = try CaptureService.selectedText(from: source)
        #expect(selected == "file:///tmp/Neutral%20Document.txt")
    }

    @Test func legacyStringPasteboardTypeReadsExactText() throws {
        let legacy = NSPasteboard.PasteboardType("NSStringPboardType")
        try withPasteboard(types: [legacy]) { pasteboard in
            let text = "Legacy ñ 🐼\nSelection"
            #expect(pasteboard.setString(text, forType: legacy))
            let selected = try CaptureService.selectedText(from: pasteboard)
            #expect(selected == text)
        }
    }

    @Test func legacyRichTextPasteboardTypesDecodePlainText() throws {
        let formats: [(String, NSAttributedString.DocumentType)] = [("NSRTFPboardType", .rtf), ("NSRTFDPboardType", .rtfd)]
        for (name, format) in formats {
            let legacy = NSPasteboard.PasteboardType(name)
            let text = "Legacy rich ñ 🐼\nSelection"
            let data = try richText(text, type: format)
            try withPasteboard(types: [legacy]) { pasteboard in
                #expect(pasteboard.setData(data, forType: legacy))
                let selected = try CaptureService.selectedText(from: pasteboard)
                #expect(selected == text)
            }
        }
    }

    @Test func legacyURLPasteboardTypeReadsAbsoluteString() throws {
        let legacy = NSPasteboard.PasteboardType("NSURLPboardType")
        try withPasteboard(types: [legacy]) { pasteboard in
            let text = "https://example.com/neutral?item=1"
            #expect(pasteboard.setString(text, forType: legacy))
            let selected = try CaptureService.selectedText(from: pasteboard)
            #expect(selected == text)
        }
    }

    @Test func absentSelectionReportsUnavailable() {
        let selections: [[NSPasteboard.PasteboardType]?] = [nil, []]
        for types in selections {
            #expect(throws: CaptureServiceError.unavailableSelection) {
                try CaptureService.selectedText(from: SelectionFixture(types: types))
            }
        }
    }

    @Test func unsupportedSelectionReportsItsFormatFailure() {
        let source = SelectionFixture(types: [.png], data: [.png: Data([0, 1, 2])])
        #expect(throws: CaptureServiceError.unsupportedSelection) { try CaptureService.selectedText(from: source) }
    }

    @Test func emptySelectionDoesNotCallEitherDestination() {
        withPasteboard { pasteboard in
            #expect(pasteboard.setString("", forType: .string))
            var called = false
            let service = CaptureService(save: { _ in called = true }, showOptions: { _ in called = true })
            for mode in [CaptureService.Mode.direct, .options] {
                #expect(throws: CaptureServiceError.emptySelection) { try service.handle(pasteboard, mode: mode) }
            }
            #expect(!called)
            #expect(pasteboard.string(forType: .string) == "")
        }
    }

    @Test func whitespaceOnlySelectionIsPreservedAndDelivered() throws {
        for text in [" \t\n\r", "\u{2003}\u{2028}"] {
            try withPasteboard { pasteboard in
                #expect(pasteboard.setString(text, forType: .string))
                var saved: [String] = [], shown: [String] = []
                let service = CaptureService(save: { saved.append($0) }, showOptions: { shown.append($0) })
                try service.handle(pasteboard, mode: .direct)
                try service.handle(pasteboard, mode: .options)
                #expect(saved == [text])
                #expect(shown == [text])
                #expect(pasteboard.string(forType: .string) == text)
            }
        }
    }

    @Test func unreadablePreferredTextDoesNotSilentlyCaptureAnotherFormat() {
        let source = SelectionFixture(types: [.string, .URL], strings: [.URL: "https://example.com/"])
        #expect(throws: CaptureServiceError.unreadableSelection("text")) { try CaptureService.selectedText(from: source) }
    }

    @Test func missingRichTextDataReportsReadFailure() {
        for (type, name) in [(NSPasteboard.PasteboardType.rtf, "RTF"), (.rtfd, "RTFD")] {
            #expect(throws: CaptureServiceError.unreadableSelection(name)) {
                try CaptureService.selectedText(from: SelectionFixture(types: [type]))
            }
        }
    }

    @Test func malformedRichTextReportsReadFailure() {
        for (type, name) in [(NSPasteboard.PasteboardType.rtf, "RTF"), (.rtfd, "RTFD")] {
            let source = SelectionFixture(types: [type], data: [type: Data("not a rich text document".utf8)])
            #expect(throws: CaptureServiceError.unreadableSelection(name)) { try CaptureService.selectedText(from: source) }
        }
    }

    @Test func emptyRichTextReportsEmptySelection() throws {
        for (type, format) in [(NSPasteboard.PasteboardType.rtf, NSAttributedString.DocumentType.rtf), (.rtfd, .rtfd)] {
            let source = SelectionFixture(types: [type], data: [type: try richText("", type: format)])
            #expect(throws: CaptureServiceError.emptySelection) { try CaptureService.selectedText(from: source) }
        }
    }

    @Test func unreadableAndRelativeURLsReportReadFailure() {
        for value in [nil, "relative/path", " \n"] as [String?] {
            let source = SelectionFixture(types: [.URL], strings: value.map { [.URL: $0] } ?? [:])
            #expect(throws: CaptureServiceError.unreadableSelection("URL")) { try CaptureService.selectedText(from: source) }
        }
    }

    @Test func emptyURLReportsEmptySelection() {
        let source = SelectionFixture(types: [.URL], strings: [.URL: ""])
        #expect(throws: CaptureServiceError.emptySelection) { try CaptureService.selectedText(from: source) }
    }
}

private enum ServiceTestError: Error, Equatable { case storage, options }

@MainActor
private struct SelectionFixture: CaptureSelectionReading {
    let types: [NSPasteboard.PasteboardType]?
    var strings: [NSPasteboard.PasteboardType: String] = [:]
    var data: [NSPasteboard.PasteboardType: Data] = [:]

    func string(forType type: NSPasteboard.PasteboardType) -> String? { strings[type] }
    func data(forType type: NSPasteboard.PasteboardType) -> Data? { data[type] }
}
