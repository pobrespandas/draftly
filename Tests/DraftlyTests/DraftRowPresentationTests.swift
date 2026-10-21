import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Draft row presentation") @MainActor
struct DraftRowPresentationTests {
    @Test func tableCallbacksUseTheDisplayedSnapshotUntilTheNextUpdate() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        let note = Note(content: "Displayed title\nDisplayed preview", tags: ["snapshot"])
        try library.saveNote(note)
        let view = NativeDraftTable(model: model, library: library, selection: .constant([]),
                                   showPreview: true, previewLines: 2, showTags: true, showDate: true)
        let coordinator = view.makeCoordinator()
        coordinator.notes = [note]
        model.query = "No matching rows"
        #expect(model.visibleNotes.isEmpty)
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        #expect(coordinator.numberOfRows(in: table) == 1)
        let expected = DraftRowPresentation.height(note: note, width: 256, showPreview: true,
            previewLines: 2, showTags: true, showDate: true, lastAction: false)
        #expect(coordinator.tableView(table, heightOfRow: 0) == expected)
        #expect(coordinator.tableView(table, heightOfRow: -1) == 56)
        #expect(coordinator.tableView(table, heightOfRow: 1) == 56)
        #expect(coordinator.tableView(table, viewFor: nil, row: 1) == nil)
        #expect(coordinator.tableView(table, rowActionsForRow: 0, edge: .trailing).count > 0)
        coordinator.notes = []
        #expect(coordinator.numberOfRows(in: table) == 0)
        #expect(coordinator.tableView(table, rowActionsForRow: 0, edge: .trailing).isEmpty)
    }

    @Test func paragraphsUseSeparatorsWithoutChangingTheDraft() {
        let note = Note(content: "Title\n\n First paragraph 🐼\n\nSecond café\n")
        #expect(DraftRowPresentation.preview(note) == "First paragraph 🐼 • Second café")
        #expect(note.content == "Title\n\n First paragraph 🐼\n\nSecond café\n")
        #expect(DraftRowPresentation.preview(Note(content: "Title\n\n")).isEmpty)
    }
    @Test func rowHeightUsesTheRenderedSearchSnippetAndCapsPreviewLines() {
        let content = "Title\n" + String(repeating: "Long paragraph ", count: 200) + "\nNeedle"
        let note = Note(content: content)
        let regular = DraftRowPresentation.height(note: note, width: 236, showPreview: true, previewLines: 2, showTags: false, showDate: true, lastAction: false)
        let snippet = DraftRowPresentation.height(note: note, width: 236, showPreview: true, previewLines: 2, showTags: false, showDate: true, lastAction: false, query: "Needle")
        #expect(snippet <= regular)
        #expect(DraftRowPresentation.preview(note, query: "Needle").hasSuffix("Needle"))
        let short = DraftRowPresentation.height(note: note, width: 236, showPreview: true, previewLines: 1, showTags: false, showDate: false, lastAction: false)
        #expect(short < regular)
        let hidden = DraftRowPresentation.height(note: note, width: 236, showPreview: false, previewLines: 2, showTags: false, showDate: false, lastAction: false)
        #expect(hidden < short)
    }
    @Test func searchPreviewUsesMatchingLinesAndOriginalLineNumbers() {
        let note = Note(content: "Title\n\nCafé 🐼\nOther text\ncafe again")
        #expect(DraftRowPresentation.preview(note, query: "cafe") == "3: Café 🐼\n5: cafe again")
        #expect(DraftRowPresentation.preview(note, query: "Title") == "1: Title")
        #expect(DraftRowPresentation.preview(note, query: "missing") == DraftRowPresentation.preview(note))
    }
    @Test func twoLineRowsMatchTheMeasuredReferencePitch() {
        let note = Note(content: "Title\n" + String(repeating: "Preview text ", count: 50))
        #expect(DraftRowPresentation.height(note: note, width: 236, showPreview: true, previewLines: 2,
                                           showTags: false, showDate: true, lastAction: false) == 81)
    }

    @Test func titleUsesTheMeasuredSemiboldReferenceFont() throws {
        let font = DraftRowPresentation.titleFont
        #expect(font.pointSize == 15)
        let traits = try #require(font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])
        let weight = try #require(traits[.weight] as? NSNumber)
        #expect(abs(weight.doubleValue - Double(NSFont.Weight.semibold.rawValue)) < 0.001)
    }

    @Test func optionalRowsUseTheSameVerticalMetricsAsTheView() {
        let note = Note(content: "Title", tags: ["work"])
        func height(tags: Bool = false, date: Bool = false) -> CGFloat {
            DraftRowPresentation.height(note: note, width: 236, showPreview: false, previewLines: 2,
                                        showTags: tags, showDate: date, lastAction: false)
        }
        #expect(height() == DraftRowPresentation.titleHeight + DraftRowPresentation.verticalInset + DraftRowPresentation.bottomInset)
        #expect(height(date: true) - height() == 17)
        #expect(height(tags: true) - height() == 21)
        #expect(height(tags: true, date: true) == height(tags: true) + 17)
    }

    @Test func dateUsesRelativeLabelsAndRegionalFormatting() {
        let today = DraftRowPresentation.modifiedDate(Date(), locale: Locale(identifier: "en_GB"))
        #expect(today.contains("Today"))
        let old = Date(timeIntervalSince1970: 1_577_880_000)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatted = DraftRowPresentation.modifiedDate(old, locale: Locale(identifier: "en_GB"), calendar: calendar)
        #expect(formatted == "01/01/2020, 12:00")
    }
}
