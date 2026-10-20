import AppKit
import DraftlyCore

@MainActor
final class StatusMenuController: NSObject {
    private unowned let controller: AppController
    private var item: NSStatusItem?
    private weak var clipboardCaptureItem: NSMenuItem?
    private weak var clipboardDraftItem: NSMenuItem?
    private weak var recentDraftsMenu: NSMenu?
    private weak var statusMenu: NSMenu?

    init(controller: AppController) {
        self.controller = controller
        super.init()
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Draftly")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(makeItem("Capture…", symbol: "arrow.right.square", action: #selector(captureDraft)))
        let clipboardCapture = makeItem("Capture Clipboard", symbol: "list.clipboard", action: #selector(captureClipboard))
        menu.addItem(clipboardCapture); clipboardCaptureItem = clipboardCapture
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(makeItem("New Draft", symbol: "plus", action: #selector(newDraft)))
        let clipboardDraft = makeItem("New Draft with Clipboard", symbol: "clipboard", action: #selector(newDraftWithClipboard))
        menu.addItem(clipboardDraft); clipboardDraftItem = clipboardDraft
        menu.addItem(.separator())
        let recentItem = NSMenuItem(title: "Recent Drafts", action: nil, keyEquivalent: "")
        if #available(macOS 27.0, *) { recentItem.preferredImageVisibility = .visible }
        recentItem.image = statusMenuImage("clock.arrow.circlepath", description: "Recent Drafts")
        let recentMenu = NSMenu(title: "Recent Drafts")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        recentDraftsMenu = recentMenu
        menu.addItem(recentItem)
        menu.addItem(.separator())
        menu.addItem(makeItem("Quick Search", symbol: "magnifyingglass", action: #selector(quickSearch)))
        menu.addItem(makeItem("Command Palette", symbol: "plus.magnifyingglass", action: #selector(commandPalette)))
        menu.addItem(makeItem("Find in Draft List", symbol: "doc.text.magnifyingglass", action: #selector(findInDraftList)))
        menu.addItem(makeItem("Open Draftly", symbol: "arrow.up.right.square", action: #selector(showDraftly)))
        menu.addItem(.separator())
        let quitItem = makeItem("Quit Draftly", symbol: "arrow.down.left.square", action: #selector(NSApplication.terminate(_:)))
        quitItem.target = NSApp
        menu.addItem(quitItem)
        statusMenu = menu
        status.menu = menu; item = status
        setStatusItemVisible(GeneralPreferences.showInMenuBar(defaults: .standard))
    }
    func setStatusItemVisible(_ visible: Bool) {
        item?.isVisible = visible
    }
    func openStatusMenuForTesting() {
        guard Bundle.main.object(forInfoDictionaryKey: "DraftlyUITesting") as? Bool == true else { return }
        guard let view = NSApp.keyWindow?.contentView else { return }
        let point = NSPoint(x: 24, y: view.isFlipped ? 24 : view.bounds.height - 24)
        statusMenu?.popUp(positioning: nil, at: point, in: view)
    }
    @objc func captureDraft() { controller.capture() }
    @objc func captureClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        controller.capture(content: text)
    }
    @objc func newDraft() { controller.newDraft() }
    @objc func newDraftWithClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        controller.newDraft(content: text)
    }
    @objc func showDraftly() { controller.show() }
    @objc func quickSearch() { controller.showQuickSearch() }
    @objc func findInDraftList() { controller.findInDraftList() }
    @objc func commandPalette() { controller.showCommandPalette() }
    @objc private func openRecentDraft(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        controller.show(id)
    }
    private func makeItem(_ title: String, symbol: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        item.image = statusMenuImage(symbol, description: title)
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
        return item
    }
    private func statusMenuImage(_ symbol: String, description: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) else { return nil }
        let configured = image.withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? image
        configured.size = NSSize(width: 16, height: 16)
        configured.isTemplate = true
        return configured
    }
}

extension StatusMenuController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu {
            let available = controller.library != nil
            for item in menu.items where !item.isSeparatorItem && item.title != "Quit Draftly" && item.title != "Open Draftly" {
                item.isEnabled = available
            }
            let hasClipboardText = available && !(NSPasteboard.general.string(forType: .string)?.isEmpty ?? true)
            clipboardCaptureItem?.isEnabled = hasClipboardText
            clipboardDraftItem?.isEnabled = hasClipboardText
        } else if menu === recentDraftsMenu {
            populateRecentDraftsMenu(menu)
        }
    }
    private func populateRecentDraftsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let notes = controller.library.map { controller.recentDrafts.notes(in: $0) } ?? []
        guard !notes.isEmpty else {
            let empty = NSMenuItem(title: "No Recent Drafts", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for note in notes {
            let item = NSMenuItem(title: note.title, action: #selector(openRecentDraft(_:)), keyEquivalent: "")
            item.target = self
            item.image = statusMenuImage("doc.text", description: note.title)
            if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            item.representedObject = note.id.uuidString
            menu.addItem(item)
        }
    }
}
