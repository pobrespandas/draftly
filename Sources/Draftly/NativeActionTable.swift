import AppKit
import SwiftUI
import DraftlyCore

struct NativeActionTable: NSViewRepresentable {
    let entries: [ActionCatalogPresentation.Entry]
    let selectionScope: String
    let canRun: Bool
    let run: (DraftAction) -> Void
    let edit: (DraftAction) -> Void
    let duplicate: (DraftAction) -> Void
    let delete: (DraftAction) -> Void
    let content: (ActionCatalogPresentation.Entry, Bool) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let table = ActionTableView()
        table.headerView = nil
        table.style = .inset
        table.rowSizeStyle = .custom
        table.rowHeight = 28
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.focusRingType = .none
        table.setAccessibilityLabel("Action List")
        let column = NSTableColumn(identifier: .init("action"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.runClicked(_:))
        table.runSelection = { [weak coordinator = context.coordinator] in coordinator?.runSelected() }
        table.menuProvider = { [weak coordinator = context.coordinator] row in coordinator?.menu(for: row) }
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeActionTable
        weak var table: ActionTableView?
        var entries: [ActionCatalogPresentation.Entry] = []
        init(_ parent: NativeActionTable) { self.parent = parent }

        func update(_ parent: NativeActionTable) {
            guard let table else { self.parent = parent; return }
            let sameScope = self.parent.selectionScope == parent.selectionScope
            let selectedID = sameScope && entries.indices.contains(table.selectedRow) ? entries[table.selectedRow].id : nil
            self.parent = parent
            entries = parent.entries
            table.reloadData()
            if let selectedID, let index = entries.firstIndex(where: { $0.id == selectedID }) {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            } else {
                table.deselectAll(nil)
            }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            let entry = entries[row]
            return (entry.kind == .separator ? 22 : 28) + (entry.sectionHeading == nil ? 0 : 28)
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard entries.indices.contains(row) else { return nil }
            let id = NSUserInterfaceItemIdentifier("ActionCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? ActionHostingCell) ?? ActionHostingCell(identifier: id)
            let entry = entries[row]
            cell.render = { [weak self] emphasized in self?.parent.content(entry, emphasized) ?? AnyView(EmptyView()) }
            cell.refresh()
            return cell
        }
        func runRow(_ row: Int) {
            guard parent.canRun, entries.indices.contains(row), let action = entries[row].runnableAction else { return }
            parent.run(action)
        }
        @objc func runClicked(_ sender: NSTableView) { runRow(sender.clickedRow) }
        func runSelected() { runRow(table?.selectedRow ?? -1) }
        func menu(for row: Int) -> NSMenu? {
            guard entries.indices.contains(row) else { return nil }
            let menu = NSMenu()
            for (title, selector) in [("Edit…", #selector(editAction(_:))), ("Duplicate", #selector(duplicateAction(_:))), ("Delete", #selector(deleteAction(_:)))] {
                if title == "Delete" { menu.addItem(.separator()) }
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                item.target = self
                item.representedObject = entries[row].id
                menu.addItem(item)
            }
            return menu
        }
        private func action(_ sender: NSMenuItem) -> DraftAction? {
            guard let id = sender.representedObject as? UUID else { return nil }
            return entries.first { $0.id == id }?.source
        }
        @objc func editAction(_ sender: NSMenuItem) { if let action = action(sender) { parent.edit(action) } }
        @objc func duplicateAction(_ sender: NSMenuItem) { if let action = action(sender) { parent.duplicate(action) } }
        @objc func deleteAction(_ sender: NSMenuItem) { if let action = action(sender) { parent.delete(action) } }
    }
}

final class ActionTableView: NSTableView {
    var runSelection: (() -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            runSelection?()
        } else {
            super.keyDown(with: event)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return nil }
        return menuProvider?(index)
    }
}

private final class ActionHostingCell: NSTableCellView {
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    var render: ((Bool) -> AnyView)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var backgroundStyle: NSView.BackgroundStyle { didSet { refresh() } }
    func refresh() { if let render { host.rootView = render(backgroundStyle == .emphasized) } }
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
