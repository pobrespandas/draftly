import AppKit
import Combine
import DraftlyCore

@MainActor
final class ReferenceToolbar: NSObject, NSToolbarDelegate {
    private weak var model: WindowModel?
    private weak var splitView: NSSplitView?
    private var subscriptions: Set<AnyCancellable> = []
    private var refreshPending = false
    private var actionsVisible: Bool?
    private var floating: Bool?
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    // Keep Share with draft commands. Let trailing space absorb window width.
    static let defaultItemIdentifiers: [NSToolbarItem.Identifier] = (
        ["filters", NSToolbarItem.Identifier.sidebarTrackingSeparator.rawValue, "drafts"]
        + [NSToolbarItem.Identifier.flexibleSpace.rawValue, NSToolbarItem.Identifier.flexibleSpace.rawValue]
        + ["last", "NSToolbarSpaceItem", "navigate", "NSToolbarSpaceItem", "capture", "flag", "tags", "folders", "NSToolbarSpaceItem", "share", "NSToolbarFlexibleSpaceItem", "search", "actions", "float"]
    ).map { NSToolbarItem.Identifier($0) }
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
        if window.tabGroup?.isTabBarVisible != true { window.toggleTabBar(nil) }
        for publisher in [model.objectWillChange, model.editor.objectWillChange, model.library.objectWillChange] {
            publisher.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &subscriptions)
        }
        refresh()
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.defaultItemIdentifiers }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.defaultItemIdentifiers }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item: NSToolbarItem
        switch identifier.rawValue {
        case NSToolbarItem.Identifier.sidebarTrackingSeparator.rawValue:
            guard let splitView else { return nil }
            item = NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitView, dividerIndex: 0)
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
            if identifier.rawValue == "filters" || identifier.rawValue == "drafts" {
                item.image = Self.panelToggleImage(filters: identifier.rawValue == "filters")
            }
            if identifier.rawValue == "float" {
                item.image = Self.floatToggleImage(isFloating: model?.isFloating ?? false)
                item.image?.size = NSSize(width: 12, height: 12)
            }
            if identifier.rawValue == "actions" {
                item.image = Self.actionsToggleImage(isVisible: model?.showActions ?? false)
            }
            item.isBordered = identifier.rawValue != "float"
            item.target = self; item.action = #selector(pressed(_:))
        }
        item.autovalidates = false
        items[identifier] = item
        return item
    }
    static func floatToggleImage(isFloating: Bool) -> NSImage? {
        let image = NSImage(systemSymbolName: isFloating ? "square.fill.on.square.fill" : "square.on.square",
                            accessibilityDescription: "Float on Top")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        image?.size = NSSize(width: 12, height: 12)
        return image
    }
    static func actionsToggleImage(isVisible: Bool) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil) else { return nil }
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            (isVisible ? NSColor.labelColor : NSColor.secondaryLabelColor).setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Toggle Actions"
        return image
    }
    private static func panelToggleImage(filters: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let outline = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 0.75, width: 16.5, height: 12.5), xRadius: 1.5, yRadius: 1.5)
            outline.lineWidth = 1.3; outline.stroke()
            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: 6, y: 1)); divider.line(to: NSPoint(x: 6, y: 13))
            if filters {
                divider.move(to: NSPoint(x: 3.3, y: 3)); divider.line(to: NSPoint(x: 3.3, y: 11))
            }
            divider.lineWidth = 1.1; divider.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
    private func group(_ identifier: NSToolbarItem.Identifier, symbols: [String], labels: [String]) -> NSToolbarItemGroup {
        let images = symbols.map { NSImage(systemSymbolName: $0, accessibilityDescription: nil)! }
        let group = NSToolbarItemGroup(itemIdentifier: identifier, images: images, selectionMode: .momentary, labels: labels, target: self, action: #selector(groupPressed(_:)))
        group.label = labels.joined(separator: " / ")
        group.controlRepresentation = .expanded
        for (index, item) in group.subitems.enumerated() { item.toolTip = labels[index]; item.autovalidates = false }
        return group
    }
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshPending = false
            self?.refresh()
        }
    }
    private func setEnabled(_ enabled: Bool, for item: NSToolbarItem?) {
        if let item, item.isEnabled != enabled { item.isEnabled = enabled }
    }
    private func refresh() {
        guard let model else { return }
        if actionsVisible != model.showActions, let item = items[NSToolbarItem.Identifier("actions")] {
            item.image = Self.actionsToggleImage(isVisible: model.showActions)
            actionsVisible = model.showActions
        }
        if floating != model.isFloating, let item = items[NSToolbarItem.Identifier("float")] {
            item.image = Self.floatToggleImage(isFloating: model.isFloating)
            floating = model.isFloating
        }
        let title = model.currentNote?.title ?? "Draftly"
        if model.window?.title != title { model.window?.title = title }
        setEnabled(model.lastNoteID != nil, for: items[NSToolbarItem.Identifier("last")])
        if let group = items[NSToolbarItem.Identifier("navigate")] as? NSToolbarItemGroup {
            for item in group.subitems { setEnabled(!model.visibleNotes.isEmpty, for: item) }
        }
        if let group = items[NSToolbarItem.Identifier("folders")] as? NSToolbarItemGroup {
            let note = model.currentNote
            let saved = model.library.notes.contains { $0.id == note?.id }
            setEnabled(saved && (note?.isArchived == true || note?.trashedAt != nil), for: group.subitems[0])
            setEnabled(saved && note?.isArchived == false, for: group.subitems[1])
            setEnabled(saved && note?.trashedAt == nil, for: group.subitems[2])
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
            else { model.perform { _ = try model.actionUIOperation(["operation": "showDictate"]) } }
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
            else { model.openQuickSearch() }
        default: break
        }
    }
    private func showFlagMenu() {
        let menu = NSMenu()
        for number in 0...7 {
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
