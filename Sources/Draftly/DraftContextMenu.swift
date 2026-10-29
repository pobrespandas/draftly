import AppKit
import DraftlyCore

@MainActor
private final class DraftMenuCallback: NSObject {
    let callback: () -> Void
    init(_ callback: @escaping () -> Void) { self.callback = callback }
    @objc func invoke(_ sender: NSMenuItem) { callback() }
}

@MainActor
extension WindowModel {
    func draftContextMenu(ids: [UUID]) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        let notes = ids.compactMap { id in library.notes.first { $0.id == id } }
        let single = notes.count == 1 && ids.count == 1
        func add(_ title: String, to parent: NSMenu, enabled: Bool = true, checked: Bool = false, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(DraftMenuCallback.invoke(_:)), keyEquivalent: "")
            let callback = DraftMenuCallback(action)
            item.target = callback; item.representedObject = callback
            item.isEnabled = enabled; item.state = checked ? .on : .off
            parent.addItem(item)
        }
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(); child.autoenablesItems = false; item.submenu = child; menu.addItem(item); return child
        }
        add("Open in New Window", to: menu, enabled: single) { self.openDraft(ids[0], tab: false) }
        add("Open in New Tab", to: menu, enabled: single) { self.openDraft(ids[0], tab: true) }
        menu.addItem(.separator())
        add("Move to Inbox", to: menu) { self.moveDrafts(ids, to: .inbox) }
        add("Move to Archive", to: menu) { self.moveDrafts(ids, to: .archive) }
        add("Move to Trash", to: menu) { self.moveDrafts(ids, to: .trash) }
        if notes.contains(where: { $0.trashedAt != nil }) { add("Restore", to: menu) { self.moveDrafts(ids, to: .restore) } }
        menu.addItem(.separator())
        let flags = submenu("Flag")
        for value in [2, 1, 6, 5, 3, 4, 7] {
            add(flagName(value), to: flags, checked: !notes.isEmpty && notes.allSatisfy { $0.flag == value }) { self.flagDrafts(ids, value: value) }
        }
        flags.addItem(.separator())
        add("Clear Flag", to: flags, checked: !notes.isEmpty && notes.allSatisfy { $0.flag == 0 }) { self.flagDrafts(ids, value: 0) }
        let tags = submenu("Tags")
        add("Add…", to: tags) { self.promptTags(ids, remove: false) }
        add("Remove…", to: tags) { self.promptTags(ids, remove: true) }
        let syntax = submenu("Change Syntax")
        for name in ["Plain Text", "Markdown"] {
            add(name, to: syntax, checked: !notes.isEmpty && notes.allSatisfy { $0.syntax == name }) { self.modifyDrafts(ids) { $0.syntax = name } }
        }
        menu.addItem(.separator())
        add("Run Action…", to: menu, enabled: !runner.isRunning && !ActionCatalogPresentation.actions(library.orderedActions(on: .search), on: .search).isEmpty) { self.promptAction(ids) }
        add("Merge…", to: menu, enabled: ids.count >= 2) { self.mergeDrafts(ids) }
        add("Duplicate", to: menu) { self.duplicateDrafts(ids) }
        menu.addItem(.separator())
        add("Get Info…", to: menu, enabled: single) { self.inspectDraft(ids[0], versions: false) }
        add("Versions…", to: menu, enabled: single) { self.inspectDraft(ids[0], versions: true) }
        menu.addItem(.separator())
        let copy = submenu("Copy")
        for (title, field) in [("Contents", DraftCopyField.contents), ("Title", .title), ("Link", .link), ("UUID", .uuid)] {
            add(title, to: copy) { self.copyDrafts(ids, field: field) }
        }
        let share = submenu("Share")
        let services = NSSharingService.sharingServices(forItems: [notes.map(\.content).joined(separator: "\n\n")])
        for service in services {
            add(service.title, to: share) {
                self.perform { service.perform(withItems: [try self.copyText(ids, field: .contents)]) }
            }
            share.items.last?.image = service.image
        }
        if services.isEmpty {
            let empty = NSMenuItem(title: "No sharing services available", action: nil, keyEquivalent: ""); empty.isEnabled = false; share.addItem(empty)
        }
        let export = submenu("Export")
        for (title, format) in [("As Text…", DraftExportFormat.txt), ("As CSV…", .csv), ("As JSON…", .json)] {
            add(title, to: export) { self.exportDrafts(ids, format: format) }
        }
        menu.addItem(.separator())
        add("Empty Trash…", to: menu, enabled: library.notes.contains { $0.trashedAt != nil }) { self.confirmEmptyTrash() }
        return menu
    }
}
