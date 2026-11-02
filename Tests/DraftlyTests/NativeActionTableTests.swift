import AppKit
import SwiftUI
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Native action table") @MainActor
struct NativeActionTableTests {
    @Test func selectionDoesNotRunAndReturnRunsOnlyExecutableRows() throws {
        _ = NSApplication.shared
        let action = DraftAction(name: "Neutral action", steps: [])
        let entry = ActionCatalogPresentation.Entry(source: action, kind: .action, sectionHeading: nil)
        let separator = ActionCatalogPresentation.Entry(source: DraftAction(name: "Section", steps: []), kind: .separator, sectionHeading: nil)
        var runs: [UUID] = []
        var parent = NativeActionTable(entries: [entry, separator], selectionScope: "Basic", canRun: true,
            run: { runs.append($0.id) }, edit: { _ in }, duplicate: { _ in }, delete: { _ in },
            content: { _, _ in AnyView(EmptyView()) })
        let coordinator = parent.makeCoordinator()
        let table = ActionTableView()
        table.addTableColumn(NSTableColumn(identifier: .init("action")))
        table.dataSource = coordinator; table.delegate = coordinator
        coordinator.table = table
        table.runSelection = { coordinator.runSelected() }
        coordinator.update(parent)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        #expect(runs.isEmpty)
        let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        table.keyDown(with: enter)
        #expect(runs == [action.id])
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        table.keyDown(with: enter)
        coordinator.runRow(-1)
        coordinator.runRow(2)
        #expect(runs == [action.id])
        parent = NativeActionTable(entries: [entry], selectionScope: "Basic", canRun: false,
            run: { runs.append($0.id) }, edit: { _ in }, duplicate: { _ in }, delete: { _ in },
            content: { _, _ in AnyView(EmptyView()) })
        coordinator.update(parent)
        coordinator.runRow(0)
        #expect(runs == [action.id])
    }

    @Test func reorderPreservesIdentityAndGroupChangeClearsSelection() {
        _ = NSApplication.shared
        let actions = ["First", "Second"].map { DraftAction(name: $0, steps: []) }
        let entries = actions.map { ActionCatalogPresentation.Entry(source: $0, kind: .action, sectionHeading: nil) }
        var edited: UUID?
        func parent(_ rows: [ActionCatalogPresentation.Entry], _ scope: String) -> NativeActionTable {
            NativeActionTable(entries: rows, selectionScope: scope, canRun: true, run: { _ in },
                edit: { edited = $0.id }, duplicate: { _ in }, delete: { _ in },
                content: { _, _ in AnyView(EmptyView()) })
        }
        let coordinator = parent(entries, "Basic").makeCoordinator()
        let table = ActionTableView()
        table.addTableColumn(NSTableColumn(identifier: .init("action")))
        table.dataSource = coordinator; table.delegate = coordinator; coordinator.table = table
        coordinator.update(parent(entries, "Basic"))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let item = coordinator.menu(for: 1)!.items[0]
        coordinator.update(parent(entries.reversed(), "Basic"))
        #expect(table.selectedRow == 1)
        coordinator.editAction(item)
        #expect(edited == actions[1].id)
        coordinator.update(parent(entries, "Processing"))
        #expect(table.selectedRow == -1)
    }
}
