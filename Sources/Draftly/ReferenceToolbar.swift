import AppKit
import Combine
import DraftlyCore

@MainActor
final class ReferenceToolbar: NSObject, NSToolbarDelegate {
    private weak var model: WindowModel?
    private weak var splitView: NSSplitView?
    private var subscriptions: Set<AnyCancellable> = []
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private let order: [NSToolbarItem.Identifier] = ["filters", "filtersDivider", "drafts", "draftsDivider", "last", "NSToolbarSpaceItem", "navigate", "NSToolbarSpaceItem", "capture", "flag", "tags", "folders", "NSToolbarFlexibleSpaceItem", "share", "NSToolbarSpaceItem", "search", "actions", "float"].map { NSToolbarItem.Identifier($0) }
    init(model: WindowModel, window: NSWindow, splitView: NSSplitView) {
        self.model = model
        self.splitView = splitView
        super.init()
        let toolbar = NSToolbar(identifier: "Draftly.ReferenceToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = false
        window.titleVisibility = .hidden; window.toolbarStyle = .unified
        window.toolbar = toolbar
        for publisher in [model.objectWillChange, model.editor.objectWillChange, model.library.objectWillChange] {
            publisher.sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }.store(in: &subscriptions)
        }
        refresh()
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { order }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { order }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item: NSToolbarItem
        switch identifier.rawValue {
        case "filtersDivider", "draftsDivider":
            guard let splitView else { return nil }
            item = NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitView, dividerIndex: identifier.rawValue == "filtersDivider" ? 0 : 1)
        case "navigate": item = group(identifier, symbols: ["chevron.up", "chevron.down"], labels: ["Previous Draft", "Next Draft"])
        case "capture": item = group(identifier, symbols: ["plus", "mic"], labels: ["New Draft", "Dictate Text"])
        case "flag": item = group(identifier, symbols: ["flag", "chevron.down"], labels: ["Flag", "Flag Color"])
        case "folders": item = group(identifier, symbols: ["tray.and.arrow.down", "archivebox", "trash"], labels: ["Move to Inbox", "Archive", "Trash"])
        case "search": item = group(identifier, symbols: ["sparkle.magnifyingglass", "magnifyingglass"], labels: ["Command Palette", "Quick Search"])
        default:
            let description: (String, String)
            switch identifier.rawValue {
            case "filters": description = ("sidebar.leading", "Toggle Filters")
            case "drafts": description = ("sidebar.left", "Toggle Draft List")
            case "last": description = ("chevron.left", "Last Draft")
            case "tags": description = ("tag.fill", "Toggle Tags")
            case "share": description = ("square.and.arrow.up", "Share")
            case "actions": description = ("sidebar.right", "Toggle Actions")
            case "float": description = ("square.on.square", "Float on Top")
            default: return nil
            }
            item = NSToolbarItem(itemIdentifier: identifier)
            item.label = description.1; item.paletteLabel = description.1; item.toolTip = description.1
            item.image = NSImage(systemSymbolName: description.0, accessibilityDescription: description.1)
            item.isBordered = identifier.rawValue != "float"
            item.target = self; item.action = #selector(pressed(_:))
        }
        item.autovalidates = false
        items[identifier] = item
        return item
    }
    private func group(_ identifier: NSToolbarItem.Identifier, symbols: [String], labels: [String]) -> NSToolbarItemGroup {
        let images = symbols.map { NSImage(systemSymbolName: $0, accessibilityDescription: nil)! }
        let group = NSToolbarItemGroup(itemIdentifier: identifier, images: images, selectionMode: .momentary, labels: labels, target: self, action: #selector(groupPressed(_:)))
        group.label = labels.joined(separator: " / ")
        group.controlRepresentation = .expanded
        for (index, item) in group.subitems.enumerated() { item.toolTip = labels[index]; item.autovalidates = false }
        return group
    }
    private func refresh() {
        guard let model else { return }
        model.window?.title = model.currentNote?.title ?? "Draftly"
        model.window?.titleVisibility = .hidden
        items[NSToolbarItem.Identifier("last")]?.isEnabled = model.lastNoteID != nil
        if let group = items[NSToolbarItem.Identifier("navigate")] as? NSToolbarItemGroup {
            for item in group.subitems { item.isEnabled = !model.visibleNotes.isEmpty }
        }
        if let group = items[NSToolbarItem.Identifier("folders")] as? NSToolbarItemGroup {
            let note = model.currentNote
            let saved = model.library.notes.contains { $0.id == note?.id }
            group.subitems[0].isEnabled = saved && (note?.isArchived == true || note?.trashedAt != nil)
            group.subitems[1].isEnabled = saved && note?.isArchived == false
            group.subitems[2].isEnabled = saved && note?.trashedAt == nil
        }
    }
    @objc private func pressed(_ sender: NSToolbarItem) {
        guard let model else { return }
        switch sender.itemIdentifier.rawValue {
        case "filters": model.toggleFilters()
        case "drafts": model.toggleDraftList()
        case "last": if let id = model.lastNoteID { model.select(id) }
        case "tags": model.showTags.toggle()
        case "share": model.perform { _ = try model.host.perform("share", values: ["text": model.editor.content]) }
        case "actions": model.showActions.toggle()
        case "float": model.toggleFloat()
        default: break
        }
    }
    @objc private func groupPressed(_ sender: NSToolbarItemGroup) {
        guard let model else { return }
        let index = sender.selectedIndex
        switch sender.itemIdentifier.rawValue {
        case "navigate": model.navigate(index == 0 ? -1 : 1)
        case "capture":
            if index == 0 { model.create() }
            else { model.editor.focusToken = UUID(); DispatchQueue.main.async { NSApp.sendAction(NSSelectorFromString("startDictation:"), to: nil, from: nil) } }
        case "flag":
            if index == 0, let note = model.currentNote { model.change([note.id]) { $0.flag = $0.flag == 0 ? 1 : 0 } }
            else { showFlagMenu() }
        case "folders":
            guard let note = model.currentNote else { return }
            model.change([note.id]) { note in
                if index == 0 { note.isArchived = false; note.trashedAt = nil }
                else if index == 1 { note.isArchived = true }
                else { note.trashedAt = Date() }
            }
        case "search":
            if index == 0 { model.showPalette = true }
            else { model.setDraftListVisible(true); model.showNoteSearch = true; model.noteSearchFocus = UUID() }
        default: break
        }
    }
    private func showFlagMenu() {
        let menu = NSMenu()
        for number in 0...6 {
            let item = NSMenuItem(title: number == 0 ? "No Flag" : flagName(number), action: #selector(setFlag(_:)), keyEquivalent: "")
            item.tag = number; item.target = self; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    @objc private func setFlag(_ sender: NSMenuItem) {
        guard let model, let note = model.currentNote else { return }
        model.change([note.id]) { $0.flag = sender.tag }
    }
}
