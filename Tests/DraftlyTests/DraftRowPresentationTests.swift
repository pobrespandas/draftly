import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Draft row presentation") @MainActor
struct DraftRowPresentationTests {
    @Test func nativeSelectionLoadsTheClickedDraftAndKeepsMultipleSelectionSeparate() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "First QA")
        let target = try library.createNote(content: "Target café 🐼")
        let preferences = try TestPreferences(prefix: "Draftly-TableSelection-")
        defer { preferences.close() }
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.select(first.id, focusEditor: false)
        let selection = Binding<Set<UUID>>(get: { model.selectedDraftIDs },
                                           set: { model.selectedDraftIDs = $0 })
        let view = NativeDraftTable(model: model, library: library, selection: selection,
                                   showPreview: true, previewLines: 2, showTags: true, showDate: true)
        let coordinator = view.makeCoordinator()
        coordinator.notes = [first, target]
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        table.addTableColumn(NSTableColumn(identifier: .init("draft")))
        table.allowsMultipleSelection = true
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.table = table
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(model.selectedDraftIDs == [target.id])
        #expect(model.editor.noteID == target.id)
        #expect(model.editor.content == target.content)
        table.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
        #expect(model.selectedDraftIDs == [first.id, target.id])
        #expect(model.editor.noteID == target.id)
        coordinator.synchronizingSelection = true
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        coordinator.synchronizingSelection = false
        #expect(model.selectedDraftIDs == [first.id, target.id])
        #expect(model.editor.noteID == target.id)
    }

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

    @Test func hostedRowSizeComesFromTheTableInsteadOfItsContent() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        let view = NativeDraftTable(model: model, library: library, selection: .constant([]),
                                   showPreview: true, previewLines: 2, showTags: true, showDate: true)
        let coordinator = view.makeCoordinator()
        coordinator.notes = [Note(content: "Title\n" + String(repeating: "Preview ", count: 100))]
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let cell = try #require(coordinator.tableView(table, viewFor: nil, row: 0))
        let host = try #require(cell.subviews.first)
        #expect(host.intrinsicContentSize.width == NSView.noIntrinsicMetric)
        #expect(host.intrinsicContentSize.height == NSView.noIntrinsicMetric)
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
        var note = Note(content: "Title\n" + String(repeating: "Preview text ", count: 50))
        #expect(DraftRowPresentation.height(note: note, width: 236, showPreview: true, previewLines: 2,
                                           showTags: false, showDate: true, lastAction: false) == 84)
        note.tags = ["visual-qa-20261021"]
        #expect(DraftRowPresentation.height(note: note, width: 236, showPreview: true, previewLines: 2,
                                           showTags: true, showDate: true, lastAction: false) == 105)
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
        #expect(height(date: true) - height() == 20)
        #expect(height(tags: true) - height() == 21)
        #expect(height(tags: true, date: true) == height(tags: true) + 20)
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
