import SwiftUI
import AppKit
import Carbon
import DraftlyCore

extension Notification.Name {
    static let draftlyOpenNote = Notification.Name("DraftlyOpenNote")
    static let draftlyCapture = Notification.Name("DraftlyCapture")
}

@MainActor
final class RecentDraftStore {
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int
    private(set) var ids: [UUID]

    init(defaults: UserDefaults = .standard, key: String = "draftly.menu.recentDraftIDs", limit: Int = 10) {
        self.defaults = defaults
        self.key = key
        self.limit = max(1, limit)
        var seen = Set<UUID>()
        ids = (defaults.stringArray(forKey: key) ?? [])
            .compactMap { UUID(uuidString: $0) }
            .filter { seen.insert($0).inserted }
            .prefix(self.limit)
            .map { $0 }
    }

    func record(_ id: UUID) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        ids = Array(ids.prefix(limit))
        persist()
    }

    func notes(in library: LibraryStore) -> [Note] {
        let available = Dictionary(library.notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let notes = ids.compactMap { available[$0] }.filter { $0.trashedAt == nil }
        let validIDs = Array(notes.prefix(limit).map(\.id))
        if ids != validIDs {
            ids = validIDs
            persist()
        }
        return notes
    }

    private func persist() {
        defaults.set(ids.map(\.uuidString), forKey: key)
    }
}

private enum PendingMenuAction {
    case quickSearch
    case commandPalette
}

@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()
    @Published var library: LibraryStore?
    @Published var startupError: String?
    @Published var captureShortcutStatus = "⌃⌥⌘N"
    let recentDrafts = RecentDraftStore()
    var pendingNoteID: UUID?
    var pendingCaptureText: String?
    var openLibrary: (() -> Void)?
    let windows = NSHashTable<WindowModel>.weakObjects()
    private var pendingMenuAction: PendingMenuAction?
    init() { start() }
    func start() {
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            let disabled = ProcessInfo.processInfo.arguments.contains("--local-only") || testing
            let identifier = Bundle.main.object(forInfoDictionaryKey: "DraftlyCloudKitContainer") as? String
            let cloud = disabled || identifier?.isEmpty != false || identifier?.hasPrefix("$(") == true ? nil : identifier
            let directory = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-UITesting") : nil
            library = try LibraryStore(cloudIdentifier: cloud, directory: directory)
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
    func capture(content: String = "") {
        guard library != nil else { return }
        pendingCaptureText = content
        show()
        NotificationCenter.default.post(name: .draftlyCapture, object: content)
    }
    func show(_ id: UUID? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let libraryWindows = NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("library") == true && $0.isVisible }
        if let window = libraryWindows.first(where: \.isKeyWindow) ?? libraryWindows.first {
            window.makeKeyAndOrderFront(nil)
            if let id { NotificationCenter.default.post(name: .draftlyOpenNote, object: id) }
        } else { pendingNoteID = id; openLibrary?() }
    }
    func recordRecentDraft(_ id: UUID) {
        guard library?.notes.contains(where: { $0.id == id && $0.trashedAt == nil }) == true else { return }
        recentDrafts.record(id)
    }
    func showQuickSearch() { openMenuAction(.quickSearch) }
    func showCommandPalette() { openMenuAction(.commandPalette) }
    func consumePendingMenuAction(for model: WindowModel) {
        guard let action = pendingMenuAction else { return }
        pendingMenuAction = nil
        apply(action, to: model)
    }
    private func openMenuAction(_ action: PendingMenuAction) {
        pendingMenuAction = action
        show()
        let windows = NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("library") == true && $0.isVisible }
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first,
              let model = self.windows.allObjects.first(where: { $0.window === window }) else { return }
        pendingMenuAction = nil
        apply(action, to: model)
    }
    private func apply(_ action: PendingMenuAction, to model: WindowModel) {
        switch action {
        case .quickSearch:
            model.setDraftListVisible(true)
            model.showNoteSearch = true
            model.noteSearchFocus = UUID()
        case .commandPalette:
            model.showPalette = true
        }
    }
    func handle(_ url: URL) {
        guard url.scheme == "draftly" else { return }
        if ActionCallbackRouter.receive(url) { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func parameter(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "action":
            do { for action in try ActionImporter.installationActions(url) { try library?.saveAction(action) }; show() }
            catch { library?.error = error.localizedDescription }
        case "create": capture(content: parameter("text") ?? "")
        case "open": if let id = parameter("uuid").flatMap(UUID.init(uuidString:)) { show(id) }
        case "run":
            guard let library, let name = parameter("action"), let action = library.actions.first(where: { $0.name == name }),
                  let id = parameter("uuid").flatMap(UUID.init(uuidString:)), let note = library.notes.first(where: { $0.id == id }) else { return }
            let alert = NSAlert(); alert.messageText = "Run \(name)?"; alert.informativeText = "An external link requested this action on \(note.title)."
            alert.addButton(withTitle: "Run Action"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let host = NativeActionHost(); let editor = EditorSession(); editor.load(note)
            let runner = ActionRunner(library: library, editor: editor, host: host); _ = runner.run(action); show(editor.noteID)
        default: break
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private weak var clipboardCaptureItem: NSMenuItem?
    private weak var recentDraftsMenu: NSMenu?
    private weak var statusMenu: NSMenu?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Draftly")
        let menu = NSMenu()
        menu.addItem(makeItem("Capture…", symbol: "square.and.pencil", action: #selector(captureDraft)))
        let clipboardCapture = makeItem("Capture Clipboard", symbol: "doc.on.clipboard", action: #selector(captureClipboard))
        menu.addItem(clipboardCapture); clipboardCaptureItem = clipboardCapture
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(makeItem("Quick Search…", symbol: "magnifyingglass", action: #selector(quickSearch), key: "f", modifiers: [.command, .shift]))
        menu.addItem(makeItem("Command Palette…", symbol: "sparkle.magnifyingglass", action: #selector(commandPalette), key: "p", modifiers: [.command, .shift]))
        let recentItem = NSMenuItem(title: "Recent Drafts", action: nil, keyEquivalent: "")
        recentItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Recent Drafts")
        let recentMenu = NSMenu(title: "Recent Drafts")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        recentDraftsMenu = recentMenu
        menu.addItem(recentItem)
        menu.addItem(.separator())
        menu.addItem(makeItem("Show Draftly", symbol: "macwindow", action: #selector(showDraftly)))
        menu.addItem(.separator())
        let quitItem = makeItem("Quit Draftly", action: #selector(NSApplication.terminate(_:)), key: "q", modifiers: [.command])
        quitItem.target = NSApp
        menu.addItem(quitItem)
        statusMenu = menu
        status.menu = menu; item = status
        let id = EventHotKeyID(signature: 0x44524654, id: 1)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if registered != noErr { AppController.shared.captureShortcutStatus = "Shortcut unavailable (\(registered)). Use the menu bar." }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in AppController.shared.capture() }; return noErr
        }, 1, &type, nil, nil)
        let container = Bundle.main.object(forInfoDictionaryKey: "DraftlyCloudKitContainer") as? String ?? ""
        if !container.isEmpty { NSApp.registerForRemoteNotifications() }
    }
    @objc func captureDraft() { AppController.shared.capture() }
    @objc func captureClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        AppController.shared.capture(content: text)
    }
    @objc func showDraftly() { AppController.shared.show() }
    @objc func quickSearch() { AppController.shared.showQuickSearch() }
    @objc func commandPalette() { AppController.shared.showCommandPalette() }
    @objc private func openRecentDraft(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        AppController.shared.show(id)
    }
    private func makeItem(_ title: String, symbol: String? = nil, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            item.image = image.withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? image
        }
        return item
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
            clipboardCaptureItem?.isEnabled = !(NSPasteboard.general.string(forType: .string)?.isEmpty ?? true)
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
            item.representedObject = note.id.uuidString
            menu.addItem(item)
        }
    }
}

@main
struct DraftlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var controller = AppController.shared
    var body: some Scene {
        WindowGroup(id: "library") {
            Group {
                if let library = controller.library { LibraryView(library: library) }
                else {
                    VStack(spacing: 18) {
                        Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                        Text("Draftly could not open the library").font(.title2)
                        Text(controller.startupError ?? "Unknown error").textSelection(.enabled)
                        Button("Try Again") { controller.start() }
                    }.padding(40).frame(minWidth: 600, minHeight: 400)
                }
            }.onOpenURL { controller.handle($0) }
        }
        .defaultSize(width: 1033, height: 734)
        .commands { DraftlyCommands() }
        Settings { SettingsView() }
    }
}

struct DraftlyCommands: Commands {
    @FocusedValue(\.windowModel) private var focusedModel
    private var model: WindowModel? {
        focusedModel ?? AppController.shared.windows.allObjects.first {
            $0.window === (NSApp.keyWindow ?? NSApp.mainWindow)
        }
    }
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Draft") { model?.create() }.keyboardShortcut("n")
            Button("Quick Capture") { AppController.shared.capture() }.keyboardShortcut("n", modifiers: [.command, .control, .option])
            Button("New Window") { openWindow(id: "library") }.keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Import…") { model?.importFile() }.keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Export Draft…") { model?.exportNote() }.disabled(model?.currentNote == nil)
            Button("Export Full Backup…") { model?.exportBackup() }
        }
        CommandGroup(after: .toolbar) {
            Button(model?.showFilters == true ? "Hide Filters" : "Show Filters") { model?.toggleFilters() }.keyboardShortcut("1", modifiers: [.command, .option])
            Button(model?.showDraftList == true ? "Hide Draft List" : "Show Draft List") { model?.toggleDraftList() }.keyboardShortcut("2", modifiers: [.command, .option])
            Button("Toggle Actions") { model?.showActions.toggle() }.keyboardShortcut("a", modifiers: [.command, .option])
            Button("Command Palette…") { AppController.shared.showCommandPalette() }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Quick Search…") { AppController.shared.showQuickSearch() }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Markdown Preview") { model?.preview() }.keyboardShortcut("p", modifiers: [.command, .option])
            Button("Revision History…") { model?.showHistory = true }
        }
        CommandMenu("Actions") {
            Button("New Action…") { model?.editingAction = DraftAction(name: "New Action", steps: [ActionStep("script", ["script": ""])]) }
            Button("Import from Directory…") { model?.showActionImporter = true }
            Button("Execution History…") { model?.showRunLog = true }
            Divider()
            if let model {
                ForEach(model.library.actions) { action in
                    if action.shortcut.count == 1, let key = action.shortcut.first,
                       !("12".contains(key) && modifiers(action) == [.command, .option]) {
                        Button(action.name) { model.run(action) }.keyboardShortcut(KeyEquivalent(key), modifiers: modifiers(action))
                    } else { Button(action.name) { model.run(action) } }
                }
            }
        }
    }
    private func modifiers(_ action: DraftAction) -> SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        for name in action.shortcutModifiers ?? ["command", "option"] {
            switch name { case "command": result.insert(.command); case "option": result.insert(.option); case "control": result.insert(.control); case "shift": result.insert(.shift); default: break }
        }
        return result
    }
}

struct SettingsView: View {
    @AppStorage("editor.fontName") private var fontName = "SFMono-Regular"
    @AppStorage("editor.fontSize") private var fontSize = 17.0
    @AppStorage("editor.lineSpacing") private var lineSpacing = 2.0
    @AppStorage("capture.newDraftAfter") private var newDraftAfter = 300.0
    private var nerdFontOptions: [(family: String, postScriptName: String)] {
        NSFontManager.shared.availableFontFamilies
            .filter { $0.localizedCaseInsensitiveContains("Nerd Font") }
            .sorted()
            .compactMap { family in
                guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                      let regular = members.first(where: { ($0[1] as? String) == "Regular" }),
                      let postScriptName = regular[0] as? String else { return nil }
                return (family, postScriptName)
            }
    }
    var body: some View {
        Form {
            Section("Editor") {
                Picker("Font", selection: $fontName) {
                    Text("SF Mono").tag("SFMono-Regular")
                    Text("Menlo").tag("Menlo-Regular")
                    Text("Helvetica Neue").tag("HelveticaNeue")
                    if !nerdFontOptions.isEmpty {
                        Divider()
                        ForEach(nerdFontOptions, id: \.postScriptName) { option in
                            Text(option.family).tag(option.postScriptName)
                        }
                    }
                }
                HStack { Text("Size"); Slider(value: $fontSize, in: 11...28, step: 1); Text("\(Int(fontSize)) pt").monospacedDigit() }
                HStack { Text("Line spacing"); Slider(value: $lineSpacing, in: 0...16, step: 1); Text("\(Int(lineSpacing)) pt").monospacedDigit() }
            }
            Section("Capture") {
                LabeledContent("Global shortcut", value: AppController.shared.captureShortcutStatus)
                Picker("New Draft After", selection: $newDraftAfter) {
                    Text("Never").tag(0.0); Text("30 seconds").tag(30.0); Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0); Text("15 minutes").tag(900.0); Text("1 hour").tag(3600.0)
                }
            }
            Section("Data") {
                Text(AppController.shared.library?.syncStatus ?? "Library unavailable").font(.caption)
                Button("Show Library Folder") {
                    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draftly")
                    NSWorkspace.shared.open(folder)
                }
                Text("Use File → Export Full Backup to save notes, revisions, workspaces, and actions.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 500, height: 440)
    }
}
