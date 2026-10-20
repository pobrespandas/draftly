import SwiftUI
import AppKit
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
    lazy var captureController = CaptureController(libraryProvider: { [weak self] in self?.library },
        windowProvider: { [weak self] in self?.windows.allObjects ?? [] })
    lazy var quickSearchController = QuickSearchController(libraryProvider: { [weak self] in self?.library },
        openResult: { [weak self] in self?.openSearchResult($0) ?? false })
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
    func makeActionHost() -> NativeActionHost {
        let host = NativeActionHost()
        host.onError = { [weak self] in self?.library?.error = $0 }
        return host
    }

    func makeWindowModel(library: LibraryStore) -> WindowModel {
        var dependencies = WindowDependencies()
        dependencies.windowModels = { [weak self] in self?.windows.allObjects ?? [] }
        dependencies.makeActionHost = { [weak self] in self?.makeActionHost() ?? NativeActionHost() }
        dependencies.recoverDictation = { [weak self] in self?.capture(content: $0) }
        dependencies.openQuickSearch = { [weak self] in self?.showQuickSearch() }
        dependencies.openDraftWindow = { [weak self] id, tab, window in
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            self?.pendingNoteID = id
            self?.openLibrary?()
            if tab, let window {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if let created = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) && $0.identifier?.rawValue.hasPrefix("library") == true }) { window.addTabbedWindow(created, ordered: .above) }
                }
            }
        }
        return WindowModel(library: library, dependencies: dependencies,
            onAccessDraft: { [weak self] in self?.recordRecentDraft($0) })
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
    func handle(_ url: URL) { ApplicationURLRouter(controller: self).handle(url) }
}
