import AppKit
import Carbon
import DraftlyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?
    private var item: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private weak var clipboardCaptureItem: NSMenuItem?
    private weak var clipboardDraftItem: NSMenuItem?
    private weak var recentDraftsMenu: NSMenu?
    private weak var statusMenu: NSMenu?
    lazy var captureService = CaptureService(save: { text in
        try AppController.shared.captureController.captureDirectly(text)
    }, showOptions: { text in
        let app = AppController.shared
        guard app.library != nil else {
            app.captureController.buffer.receive(text)
            app.captureController.buffer.error = "The library is unavailable."
            throw DraftlyError.message("The library is unavailable.")
        }
        app.capture(content: text)
    })
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = ApplicationAppearance.resolved(
            UserDefaults.standard.string(forKey: ApplicationAppearance.preferenceKey) ?? "System"
        ).nativeAppearance
        Self.current = self
        NSApp.setActivationPolicy(.regular)
        NSApp.servicesProvider = self
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
        let id = EventHotKeyID(signature: 0x44524654, id: 1)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if registered != noErr { AppController.shared.captureShortcutStatus = "Shortcut unavailable (\(registered)). Use the menu bar." }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in AppController.shared.capture() }; return noErr
        }, 1, &type, nil, nil)
        if AppController.shared.library?.cloudIdentifier != nil { NSApp.registerForRemoteNotifications() }
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
    @objc func captureDraft() { AppController.shared.capture() }
    @objc func captureClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        AppController.shared.capture(content: text)
    }
    @objc func newDraft() { AppController.shared.newDraft() }
    @objc func newDraftWithClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        AppController.shared.newDraft(content: text)
    }
    @objc func showDraftly() { AppController.shared.show() }
    @objc func quickSearch() { AppController.shared.showQuickSearch() }
    @objc func findInDraftList() { AppController.shared.findInDraftList() }
    @objc func captureSelectionDirectly(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        receiveServiceSelection(pasteboard, mode: .direct, error: error)
    }
    @objc func captureSelectionWithOptions(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        receiveServiceSelection(pasteboard, mode: .options, error: error)
    }
    @objc func captureSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        captureSelectionWithOptions(pasteboard, userData: userData, error: error)
    }
    private func receiveServiceSelection(_ pasteboard: NSPasteboard, mode: CaptureService.Mode,
                                         error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        do { try captureService.handle(pasteboard, mode: mode) }
        catch let serviceError { error.pointee = serviceError.localizedDescription as NSString }
    }
    @objc func commandPalette() { AppController.shared.showCommandPalette() }
    @objc private func openRecentDraft(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        AppController.shared.show(id)
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
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for window in AppController.shared.windows.allObjects where !window.flush() { return .terminateCancel }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu {
            let available = AppController.shared.library != nil
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
        let notes = AppController.shared.library.map { AppController.shared.recentDrafts.notes(in: $0) } ?? []
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
