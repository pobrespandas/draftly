import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Draft selection presentation") @MainActor
struct DraftSelectionPresentationTests {
    private func item(_ title: String, body: String, id: UUID = UUID()) -> [String: Any] {
        ["id": id.uuidString, "title": title, "lastAction": "Neutral action",
         "draft": ["uuid": id.uuidString, "content": title + "\n" + body, "tags": ["neutral"], "flagType": 2,
                   "createdAt": "2025-01-01T12:00:00.000Z", "modifiedAt": "2025-01-02T12:00:00.000Z"]]
    }

    @Test func preparedSelectionPreservesWorkspaceOptionsAndSharedRowMeasurements() throws {
        let values: [String: Any] = ["showPreview": true, "previewLines": 3, "showTags": false,
            "showDate": false, "showLastAction": true, "highlightFlagged": true,
            "searchTitlesOnly": true, "caseSensitiveSearch": true, "previewSearchMatches": true]
        let rowItem = item("Title café 🐼", body: "First line\nSecond line\nThird line")
        let options = DraftSelectionRow.options(values)
        #expect(options.previewLines == 3 && options.highlightFlagged)
        #expect(options.searchTitlesOnly && options.caseSensitiveSearch && options.previewSearchMatches)
        #expect(!options.showDate && !options.showTags && options.showLastAction)
        let presentation = try #require(DraftSelectionRow(item: rowItem, options: options))
        #expect(presentation.lastAction == "Neutral action")
        let expectedHeight = DraftRowPresentation.height(note: presentation.note, width: 388,
            showPreview: true, previewLines: 3, showTags: false, showDate: false, lastAction: true)
        #expect(presentation.height(width: 400) == expectedHeight)
        let prepared = try #require(NativePromptAdapter().prepareSelection([
            "items": [rowItem], "draftListOptions": values]))
        #expect(prepared.choices.selectedIndex == 0)
        #expect(prepared.choices.tableView(prepared.choices.table, heightOfRow: 0) ==
                presentation.height(width: prepared.choices.table.bounds.width))
        let rendered = presentation.view(width: 400, emphasized: true)
        #expect(abs(rendered.fittingSize.height - expectedHeight) <= 1)
    }

    @Test func hiddenPreviewsStillSearchContentAndReturnTheOriginalItemIndex() throws {
        let items = [item("First", body: "Other"), item("Second", body: "Needle café 🐼"), item("Third", body: "Needle too")]
        let prepared = try #require(NativePromptAdapter().prepareSelection([
            "items": items, "draftListOptions": ["showPreview": false, "showDate": false, "showTags": false]]))
        let choices = prepared.choices
        choices.search.stringValue = "Needle"; choices.filter("Needle")
        #expect(choices.visibleIndices == [1, 2] && choices.selectedIndex == 1)
        #expect(choices.emphasizedRow == 0)
        choices.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(choices.selectedIndex == 2 && choices.emphasizedRow == 1)
        choices.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        #expect(choices.selectedIndex == 1 && choices.emphasizedRow == 0)
        choices.filter("no match")
        #expect(choices.selectedIndex == nil && choices.emphasizedRow == nil)
        let row = try #require(DraftSelectionRow(item: items[1], options: DraftSelectionRow.options(["showPreview": false])))
        #expect(row.matches("Needle") && row.matches("needle"))
        let caseSensitive = try #require(DraftSelectionRow(item: items[1], options: DraftSelectionRow.options(["caseSensitiveSearch": true])))
        #expect(caseSensitive.matches("Needle") && !caseSensitive.matches("needle"))
        let titlesOnly = try #require(DraftSelectionRow(item: items[1], options: DraftSelectionRow.options(["searchTitlesOnly": true])))
        #expect(!titlesOnly.matches("Needle") && titlesOnly.matches("Second"))
    }

    @Test func draftSearchKeysNavigateWithoutWrappingAndRouteEscapeToCancel() throws {
        let items = [item("Excluded", body: "Other"), item("Alpha", body: "Needle"), item("Zulu", body: "Needle")]
        let choices = try #require(NativePromptAdapter().prepareSelection([
            "items": items, "draftListOptions": ["showPreview": false]])).choices
        choices.search.stringValue = "Needle"; choices.filter("Needle")
        let editor = NSTextView(frame: .zero)
        func send(_ selector: Selector) -> Bool {
            choices.control(choices.search, textView: editor, doCommandBy: selector)
        }
        #expect(send(#selector(NSResponder.moveUp(_:))))
        #expect(choices.selectedIndex == 1 && choices.emphasizedRow == 0)
        #expect(send(#selector(NSResponder.moveDown(_:))))
        #expect(choices.selectedIndex == 2 && choices.emphasizedRow == 1)
        #expect(send(#selector(NSResponder.moveDown(_:))))
        #expect(choices.selectedIndex == 2 && choices.emphasizedRow == 1)
        #expect(send(#selector(NSResponder.moveUp(_:))))
        #expect(choices.selectedIndex == 1 && choices.emphasizedRow == 0)
        #expect(choices.visibleIndices == [1, 2] && choices.search.stringValue == "Needle")
        #expect(!send(#selector(NSResponder.insertNewline(_:))))
        var cancelled = 0
        choices.cancelSelection = { cancelled += 1 }
        #expect(send(#selector(NSResponder.cancelOperation(_:))) && cancelled == 1)
        #expect(choices.visibleIndices == [1, 2] && choices.selectedIndex == 1 && choices.emphasizedRow == 0)
        #expect(choices.search.stringValue == "Needle")
        choices.filter("no match")
        #expect(send(#selector(NSResponder.moveDown(_:))) && send(#selector(NSResponder.moveUp(_:))))
        #expect(choices.selectedIndex == nil && choices.emphasizedRow == nil)
        let ordinary = SearchablePromptChoices(items: [["id": "one", "title": "First"]])
        #expect(!ordinary.control(ordinary.search, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        ordinary.cancelSelection = { Issue.record("Ordinary SelectPrompt intercepted Escape.") }
        #expect(!ordinary.control(ordinary.search, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(!choices.control(NSSearchField(), textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
    }

    @Test func workspaceQueryStartsVisibleAndCanBeReplacedWithoutLosingSourceRows() throws {
        let items = [item("First", body: "Other"), item("Second", body: "Needle"), item("Third", body: "Tail")]
        let prepared = try #require(NativePromptAdapter().prepareSelection([
            "items": items, "draftListOptions": ["showPreview": false], "draftSelectionQuery": "Second"]))
        let choices = prepared.choices
        #expect(choices.search.stringValue == "Second")
        #expect(choices.visibleIndices == [1] && choices.selectedIndex == 1 && choices.emphasizedRow == 0)
        choices.search.stringValue = "Third"
        choices.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: choices.search))
        #expect(choices.visibleIndices == [2] && choices.selectedIndex == 2)
        choices.search.stringValue = ""
        choices.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: choices.search))
        #expect(choices.visibleIndices == [0, 1, 2] && choices.selectedIndex == 2 && choices.emphasizedRow == 2)
        let unmatched = try #require(NativePromptAdapter().prepareSelection([
            "items": items, "draftListOptions": ["showPreview": false], "draftSelectionQuery": "Absent content"])).choices
        #expect(unmatched.search.stringValue == "Absent content" && unmatched.visibleIndices.isEmpty)
        #expect(unmatched.selectedIndex == nil && unmatched.emphasizedRow == nil)
        let ordinary = SearchablePromptChoices(items: [["id": "one", "title": "First"]], initialQuery: "Ignored")
        #expect(ordinary.search.stringValue.isEmpty && ordinary.visibleIndices == [0])
    }

    @Test func preparedEscapeUsesTheCancelButtonsCurrentAction() throws {
        let prepared = try #require(NativePromptAdapter().prepareSelection([
            "items": [item("First", body: "Neutral")], "draftListOptions": ["showPreview": false],
            "draftSelectionQuery": "First"]))
        let target = DraftSelectionCancelTarget()
        let cancel = prepared.alert.buttons[1]
        cancel.target = target; cancel.action = #selector(DraftSelectionCancelTarget.cancel(_:))
        #expect(prepared.choices.control(prepared.choices.search, textView: NSTextView(frame: .zero),
            doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(target.count == 1)
        #expect(prepared.choices.search.stringValue == "First" && prepared.choices.selectedIndex == 0)
    }

    @Test func ordinarySelectPromptKeepsItsOriginalFixedRowsAndTitleSearch() throws {
        let choices = SearchablePromptChoices(items: [["id": "one", "title": "First", "subtitle": "Find me"],
                                                     ["id": "two", "title": "Second"]])
        choices.filter("Find me")
        #expect(choices.visibleIndices == [0] && choices.selectedIndex == 0)
        #expect(choices.tableView(choices.table, heightOfRow: 0) == 48)
        #expect(choices.emphasizedRow == nil)
    }
}

@MainActor private final class DraftSelectionCancelTarget: NSObject {
    private(set) var count = 0
    @objc func cancel(_ sender: NSButton) { count += 1 }
}
