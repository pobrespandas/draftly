import SwiftUI
import AppKit
import Carbon
import DraftlyCore

extension Notification.Name {
    static let draftlyOpenNote = Notification.Name("DraftlyOpenNote")
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
    case findInDraftList
    case commandPalette
    case newDraft(String)
}

@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()
    @Published var library: LibraryStore?
    @Published var startupError: String?
    @Published var captureShortcutStatus = "⌃⌥⌘N"
    @Published var commandWindow: WindowModel?
    let recentDrafts = RecentDraftStore()
    var pendingNoteID: UUID?
    lazy var captureController = CaptureController()
    let quickSearchController = QuickSearchController()
    var openLibrary: (() -> Void)?
    let windows = NSHashTable<WindowModel>.weakObjects()
    private var pendingMenuAction: PendingMenuAction?
    init() { start() }
    func start() {
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing") || Bundle.main.object(forInfoDictionaryKey: "DraftlyUITesting") as? Bool == true
            let cloudTesting = Bundle.main.object(forInfoDictionaryKey: "DraftlyCloudTesting") as? Bool == true
            let disabled = ProcessInfo.processInfo.arguments.contains("--local-only") || testing
            let identifier = Bundle.main.object(forInfoDictionaryKey: "DraftlyCloudKitContainer") as? String
            let cloud = disabled || identifier?.isEmpty != false || identifier?.hasPrefix("$(") == true ? nil : identifier
            let testLibraryID = (Bundle.main.object(forInfoDictionaryKey: "DraftlyUITestingLibraryID") as? String)
                .flatMap(UUID.init(uuidString:)) ?? UUID()
            if cloudTesting && cloud == nil { throw DraftlyError.message("The iCloud test build has no CloudKit container.") }
            let directory = testing || cloudTesting ? FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-UITesting").appendingPathComponent(testLibraryID.uuidString) : nil
            library = try LibraryStore(cloudIdentifier: cloud, directory: directory, seed: !cloudTesting)
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
    func capture(content: String = "") {
        guard library != nil else { return }
        captureController.show(content: content)
    }
    func show(_ id: UUID? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let libraryWindows = NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("library") == true && $0.isVisible }
        if let window = libraryWindows.first(where: \.isKeyWindow) ?? libraryWindows.first {
            window.makeKeyAndOrderFront(nil)
            if let id { NotificationCenter.default.post(name: .draftlyOpenNote, object: id) }
        } else { pendingNoteID = id; openLibrary?() }
    }
    @discardableResult func openSearchResult(_ id: UUID) -> Bool {
        guard library?.notes.contains(where: { $0.id == id && $0.trashedAt == nil }) == true else { return false }
        let target = commandWindow.flatMap { $0.window?.isVisible == true ? $0 : nil }
            ?? windows.allObjects.first(where: { $0.window?.isVisible == true })
        if let target {
            guard target.flush() else { return false }
            target.select(id)
            target.window?.makeKeyAndOrderFront(nil)
            return target.editor.noteID == id
        }
        show(id); return true
    }
    func recordRecentDraft(_ id: UUID) {
        guard library?.notes.contains(where: { $0.id == id && $0.trashedAt == nil }) == true else { return }
        recentDrafts.record(id)
    }
    func newDraft(content: String = "") { openMenuAction(.newDraft(content)) }
    func showQuickSearch() {
        if let model = commandWindow, !model.flush() { return }
        quickSearchController.show()
    }
    func findInDraftList() { openMenuAction(.findInDraftList) }
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
        case .findInDraftList:
            model.setDraftListVisible(true)
            model.showNoteSearch = true
            model.noteSearchFocus = UUID()
        case .commandPalette:
            model.showPalette = true
        case .newDraft(let content):
            _ = model.capture(content)
        }
    }
    func handle(_ url: URL) {
        guard url.scheme == "draftly" else { return }
        if ActionCallbackRouter.receive(url) { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func parameter(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let endpoint = url.host == "x-callback-url" ? String(url.path.dropFirst()) : url.host
        switch endpoint {
        case "workspace":
            do {
                let workspace = try WorkspaceInstallation.decode(url)
                try library?.saveWorkspace(workspace)
                show()
            } catch { library?.error = error.localizedDescription }
        case "action":
            do { for action in try ActionImporter.installationActions(url) { try library?.saveAction(action) }; show() }
            catch { library?.error = error.localizedDescription }
        case "syntax":
            do {
                if let data = parameter("data") {
                    var syntax = try SyntaxDefinition(data: Data(data.utf8))
                    if let existing = library?.syntaxes.first(where: { $0.name == syntax.name }) {
                        if existing.source != syntax.source {
                            let alert = NSAlert(); alert.messageText = "Replace syntax “\(syntax.name)”?"
                            alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                            guard alert.runModal() == .alertFirstButtonReturn else { return }
                        }
                        syntax.id = existing.id
                    }
                    try library?.saveSyntax(syntax); show()
                } else if let name = parameter("name"), ScriptSyntax.names.contains(name) { show() }
                else { throw DraftlyError.message("The syntax link is invalid.") }
            } catch { library?.error = error.localizedDescription }
        case "create": newDraft(content: parameter("text") ?? "")
        case "capture": capture(content: parameter("text") ?? "")
        case "open": if let id = parameter("uuid").flatMap(UUID.init(uuidString:)) { show(id) }
        case "run", "runAction":
            guard let library, let name = parameter("action"), let action = library.actions.first(where: { $0.name == name }),
                  let id = parameter("uuid").flatMap(UUID.init(uuidString:)), let note = library.notes.first(where: { $0.id == id }) else { return }
            let alert = NSAlert(); alert.messageText = "Run \(name)?"; alert.informativeText = "An external link requested this action on \(note.title)."
            alert.addButton(withTitle: "Run Action"); alert.addButton(withTitle: "Cancel")
            let callbackParameters = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
            guard alert.runModal() == .alertFirstButtonReturn else {
                if let callback = ActionExecutionResult.cancelled.callbackURL(parameters: callbackParameters) { NSWorkspace.shared.open(callback) }
                return
            }
            let host = NativeActionHost(); let editor = EditorSession(); editor.load(note)
            let runner = ActionRunner(library: library, editor: editor, host: host)
            let result = runner.runResult(action)
            if case .failure(let message) = result { library.error = message }
            show(editor.noteID)
            if let callback = result.callbackURL(parameters: callbackParameters, successParameters: runner.successParameters) { NSWorkspace.shared.open(callback) }
        default: break
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?
    private var item: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private weak var clipboardCaptureItem: NSMenuItem?
    private weak var clipboardDraftItem: NSMenuItem?
    private weak var recentDraftsMenu: NSMenu?
    private weak var statusMenu: NSMenu?
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        let id = EventHotKeyID(signature: 0x44524654, id: 1)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if registered != noErr { AppController.shared.captureShortcutStatus = "Shortcut unavailable (\(registered)). Use the menu bar." }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in AppController.shared.capture() }; return noErr
        }, 1, &type, nil, nil)
        if AppController.shared.library?.cloudIdentifier != nil { NSApp.registerForRemoteNotifications() }
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
    @objc func captureSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text was provided."; return
        }
        AppController.shared.capture(content: text)
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
    @ObservedObject private var controller = AppController.shared
    @Environment(\.openWindow) private var openWindow
    private var model: WindowModel? {
        focusedModel ?? controller.commandWindow
    }
    var body: some Commands {
        if let model { WindowCommands(model: model) }
        else {
            CommandGroup(replacing: .newItem) {
                Button("New Draft") { AppController.shared.newDraft() }.commandShortcut("New Draft")
                Button("Quick Capture") { AppController.shared.capture() }.keyboardShortcut("n", modifiers: [.command, .control, .option])
                Button("New Window") { openWindow(id: "library") }.commandShortcut("New Window")
            }
        }
    }
}

private struct WindowCommands: Commands {
    @ObservedObject var model: WindowModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Draft") { model.create() }.commandShortcut("New Draft")
            Button("Quick Capture") { AppController.shared.capture() }.keyboardShortcut("n", modifiers: [.command, .control, .option])
            Button("New Window") { openWindow(id: "library") }.commandShortcut("New Window")
            Divider()
            Button("Import…") { model.importFile() }.commandShortcut("Import")
            Button("Export Draft…") { model.exportNote() }.disabled(model.currentNote == nil)
            Button("Export Full Backup…") { model.exportBackup() }
        }
        CommandGroup(after: .toolbar) {
            Button(model.showFilters ? "Hide Filters" : "Show Filters") { model.toggleFilters() }.commandShortcut("Filters")
            Button(model.showDraftList ? "Hide Draft List" : "Show Draft List") { model.toggleDraftList() }.commandShortcut("Draft List")
            Button("Toggle Actions") { model.showActions.toggle() }.commandShortcut("Actions")
            Button("Command Palette…") { AppController.shared.showCommandPalette() }.commandShortcut("Command Palette")
            Button("Quick Search…") { AppController.shared.showQuickSearch() }.commandShortcut("Quick Search")
            Button("Markdown Preview") { model.preview() }.commandShortcut("Markdown Preview")
            Button("Revision History…") { model.showHistory = true }
        }
        if Bundle.main.object(forInfoDictionaryKey: "DraftlyUITesting") as? Bool == true {
            CommandMenu("Visual QA") {
                ForEach(["1033 × 734", "1200 × 800", "850 × 600"], id: \.self) { size in
                    Button(size) {
                        let values = size.components(separatedBy: " × ").compactMap(Double.init)
                        guard values.count == 2, let window = model.window else { return }
                        var frame = window.frame
                        frame.size = NSSize(width: values[0], height: values[1])
                        window.setFrame(frame, display: true)
                    }
                }
                Divider()
                Button("Light") { model.darkTheme = false }
                Button("Dark") { model.darkTheme = true }
                Button("Open Status Menu") { AppDelegate.current?.openStatusMenuForTesting() }
            }
        }
        CommandMenu("Actions") {
            Button("New Action…") { model.editingAction = DraftAction(name: "New Action", steps: [ActionStep("script", ["script": ""])]) }
            Button("Import from Directory…") { model.showActionImporter = true }
            Button("Execution History…") { model.showRunLog = true }
            Button("Manage Actions and Workspaces…") { model.showLibraryManagement = true }
            Divider()
            ForEach(model.library.orderedActions()) { action in
                if ActionShortcut.conflict(for: action, in: model.library.actions) == nil,
                   let key = ActionShortcut(action).key.first {
                    Button(action.name) { model.run(action) }.keyboardShortcut(KeyEquivalent(key), modifiers: modifiers(action))
                } else { Button(action.name) { model.run(action) } }
            }
        }
    }
    private func modifiers(_ action: DraftAction) -> SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        for name in ActionShortcut(action).modifiers {
            switch name { case "command": result.insert(.command); case "option": result.insert(.option); case "control": result.insert(.control); case "shift": result.insert(.shift); default: break }
        }
        return result
    }
}

struct SettingsView: View {
    @AppStorage("editor.fontName") private var fontName = "System"
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
                    Text("System").tag("System")
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
            EditorLayoutPreferences()
            ShortcutPreferences()
            Section("Capture") {
                LabeledContent("Global shortcut", value: AppController.shared.captureShortcutStatus)
                Picker("New Draft After", selection: $newDraftAfter) {
                    Text("Never").tag(0.0); Text("30 seconds").tag(30.0); Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0); Text("15 minutes").tag(900.0); Text("1 hour").tag(3600.0)
                }
            }
            Section("Data") {
                if let library = AppController.shared.library { LibrarySyncStatusView(library: library) }
                else { Text("Library unavailable").font(.caption) }
                Button("Show Library Folder") {
                    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draftly")
                    NSWorkspace.shared.open(folder)
                }
                Text("Use File → Export Full Backup to save drafts, revisions, workspaces, and actions.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 500, height: 440)
    }
}

struct LibrarySyncStatusView: View {
    @ObservedObject var library: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(library.syncStatus).font(.caption).textSelection(.enabled)
            if library.cloudIdentifier != nil {
                Button("Check iCloud Account") { Task { await library.refreshCloudAccount() } }
                Text("Local saves do not confirm that other Macs received your changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
