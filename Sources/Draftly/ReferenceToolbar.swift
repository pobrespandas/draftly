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
    private(set) var floatingButton: NSButton?
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    // Anchor draft commands to their panels. Let trailing space absorb window width.
    static let defaultItemIdentifiers: [NSToolbarItem.Identifier] = (
        ["filters", NSToolbarItem.Identifier.sidebarTrackingSeparator.rawValue, "drafts"]
        + [NSToolbarItem.Identifier.flexibleSpace.rawValue]
        + ["last", "NSToolbarSpaceItem", "navigate", "draftEditorTrackingSeparator", "capture", "flag", "tags", "NSToolbarSpaceItem", "inbox", "archive", "trash", "NSToolbarSpaceItem", "share", "NSToolbarFlexibleSpaceItem", "palette", "quickSearch", "NSToolbarSpaceItem", "actions"]
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
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        let button = NSButton(image: Self.floatToggleImage(isFloating: model.isFloating)!,
                              target: self, action: #selector(floatPressed(_:)))
        button.isBordered = false
        button.toolTip = "Float on Top"
        button.setAccessibilityLabel("Float on Top")
        button.translatesAutoresizingMaskIntoConstraints = false
        accessory.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
            button.centerXAnchor.constraint(equalTo: accessory.view.leadingAnchor, constant: 11),
            button.centerYAnchor.constraint(equalTo: accessory.view.centerYAnchor)
        ])
        floatingButton = button
        window.addTitlebarAccessoryViewController(accessory)
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
        case "draftEditorTrackingSeparator":
            guard let splitView else { return nil }
            item = NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitView, dividerIndex: 1)
        case "navigate": item = group(identifier, symbols: ["chevron.up", "chevron.down"], labels: ["Previous Draft", "Next Draft"])
        case "capture": item = group(identifier, symbols: ["plus", "mic"], labels: ["New Draft", "Dictate Text"])
        case "flag": item = group(identifier, symbols: ["flag", "chevron.down"], labels: ["Flag", "Flag Color"])
        default:
            let description: (String, String)
            switch identifier.rawValue {
            case "filters": description = ("sidebar.leading", "Toggle Filters")
            case "drafts": description = ("sidebar.left", "Toggle Draft List")
            case "last": description = ("chevron.left", "Last Draft")
            case "tags": description = ("tag.fill", "Toggle Tags")
            case "share": description = ("square.and.arrow.up", "Share")
            case "inbox": description = ("tray.and.arrow.down", "Move to Inbox")
            case "archive": description = ("archivebox", "Archive")
            case "trash": description = ("trash", "Trash")
            case "palette": description = ("sparkle.magnifyingglass", "Command Palette")
            case "quickSearch": description = ("magnifyingglass", "Quick Search")
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
            if identifier.rawValue == "actions" {
                item.image = Self.actionsToggleImage(isVisible: model?.showActions ?? false)
            }
            item.isBordered = identifier.rawValue != "float"
            item.target = self
            item.action = #selector(pressed(_:))
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
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { _ in
            (isVisible ? NSColor.labelColor : NSColor.secondaryLabelColor).setStroke()
            drawPanelOutline(dividerX: 12)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Toggle Actions"
        return image
    }
    private static func panelToggleImage(filters: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            drawPanelOutline(dividerX: 6)
            if filters {
                let divider = NSBezierPath()
                divider.move(to: NSPoint(x: 3.3, y: 3)); divider.line(to: NSPoint(x: 3.3, y: 11))
                divider.lineWidth = 1.1; divider.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
    private static func drawPanelOutline(dividerX: CGFloat) {
        let outline = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 0.75, width: 16.5, height: 12.5), xRadius: 1.5, yRadius: 1.5)
        outline.lineWidth = 1.3; outline.stroke()
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: dividerX, y: 1)); divider.line(to: NSPoint(x: dividerX, y: 13))
        divider.lineWidth = 1.1; divider.stroke()
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
        if floating != model.isFloating {
            floatingButton?.image = Self.floatToggleImage(isFloating: model.isFloating)
            floating = model.isFloating
        }
        let title = model.currentNote?.title ?? "Draftly"
        if model.window?.title != title { model.window?.title = title }
        setEnabled(model.lastNoteID != nil, for: items[NSToolbarItem.Identifier("last")])
        if let group = items[NSToolbarItem.Identifier("navigate")] as? NSToolbarItemGroup {
            for item in group.subitems { setEnabled(!model.visibleNotes.isEmpty, for: item) }
        }
        let note = model.currentNote
        let saved = model.library.notes.contains { $0.id == note?.id }
        setEnabled(saved && (note?.isArchived == true || note?.trashedAt != nil), for: items[.init("inbox")])
        setEnabled(saved && note?.isArchived == false, for: items[.init("archive")])
        setEnabled(saved && note?.trashedAt == nil, for: items[.init("trash")])
    }
    @objc private func floatPressed(_ sender: NSButton) { model?.toggleFloat() }
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
        case "palette": model.openCommandPalette()
        case "quickSearch": model.openQuickSearch("")
        case "inbox", "archive", "trash":
            guard let note = model.currentNote else { return }
            model.change([note.id]) { note in
                if sender.itemIdentifier.rawValue == "inbox" { note.isArchived = false; note.trashedAt = nil }
                else if sender.itemIdentifier.rawValue == "archive" { note.isArchived = true }
                else { note.trashedAt = Date() }
            }
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
