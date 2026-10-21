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

@MainActor private final class DraftSceneRequest {
    let noteID: UUID?
    let tab: Bool
    weak var origin: NSWindow?
    weak var model: WindowModel?
    var completed = false
    init(noteID: UUID?, tab: Bool, origin: NSWindow?) {
        self.noteID = noteID; self.tab = tab; self.origin = origin
    }
}

@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()
    @Published var library: LibraryStore?
    @Published var startupError: String?
    @Published var globalShortcutErrors: [String: String] = [:]
    @Published var commandWindow: WindowModel?
    let recentDrafts: RecentDraftStore
    var pendingNoteID: UUID? { didSet { pendingTargetWindow = nil; pendingTargetModel = nil; pendingExcludedModels = nil } }
    private var pendingExcludedModels: Set<ObjectIdentifier>?
    private weak var pendingTargetWindow: NSWindow?
    private weak var pendingTargetModel: WindowModel?
    lazy var captureController = CaptureController(libraryProvider: { [weak self] in self?.library },
        windowProvider: { [weak self] in self?.windows.allObjects ?? [] })
    lazy var quickSearchController = QuickSearchController(libraryProvider: { [weak self] in self?.library },
        openResult: { [weak self] in self?.openSearchResult($0) ?? false })
    private var libraryWindowRequested = false
    var openDraftLibrary: ((UUID) -> Void)?
    private let windowOpenRequests = WindowOpenRequestRegistry()
    private var draftSceneRequests: [UUID: DraftSceneRequest] = [:]
    private var retiredDraftSceneRequests: Set<UUID> = []
    var openLibrary: (() -> Void)? {
        didSet {
            guard libraryWindowRequested, let openLibrary else { return }
            libraryWindowRequested = false
            openLibrary()
        }
    }
    func requestLibraryWindow() {
        if let openLibrary { openLibrary() }
        else { libraryWindowRequested = true }
    }
    let windows = NSHashTable<WindowModel>.weakObjects()
    private var pendingMenuAction: PendingMenuAction?
    init() { recentDrafts = RecentDraftStore(); start() }
    init(library: LibraryStore, recentDrafts: RecentDraftStore) {
        self.library = library; self.recentDrafts = recentDrafts
    }
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
            let store = try LibraryStore(cloudIdentifier: cloud, directory: directory, seed: !cloudTesting)
            do { try LocalThemeMigration.run(in: store) }
            catch { store.error = "Theme migration failed: " + error.localizedDescription }
            library = store
            refreshThemeDevelopmentFolder()
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
    func refreshThemeDevelopmentFolder(defaults: UserDefaults = .standard) {
        guard let library else { return }
        do { _ = try ThemeDevelopmentFolder.refresh(in: library, defaults: defaults) }
        catch { library.error = error.localizedDescription }
    }

    func makeActionHost() -> NativeActionHost {
        let host = NativeActionHost()
        host.onError = { [weak self] in self?.library?.error = $0 }
        host.onMessage = { [weak self] message, severity in
            guard let model = self?.commandWindow else {
                throw DraftlyError.message("Message banners require an open Draftly window.")
            }
            try model.showMessageBanner(message, severity: severity)
        }
        return host
    }

    func makeWindowModel(library: LibraryStore) -> WindowModel {
        var dependencies = WindowDependencies()
        dependencies.windowModels = { [weak self] in self?.windows.allObjects ?? [] }
        dependencies.makeActionHost = { [weak self] in self?.makeActionHost() ?? NativeActionHost() }
        dependencies.recoverDictation = { [weak self] in self?.capture(content: $0) }
        dependencies.openQuickSearch = { [weak self] query in self?.showQuickSearch(initialQuery: query) }
        dependencies.openDraftWindow = { [weak self] id, tab, window in
            guard let self else { return false }
            var result: Bool?
            let task = Task { @MainActor in
                do { result = try await self.openDraftWindow(id, tab: tab, origin: window) }
                catch { result = false }
            }
            defer { task.cancel() }
            // The legacy synchronous runner needs to service scene events.
            while result == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            return result == true
        }
        dependencies.openDraftWindowAsync = { [weak self] id, tab, window, timeout in
            guard let self else { return false }
            return try await self.openDraftWindow(id, tab: tab, origin: window, timeout: timeout)
        }
        return WindowModel(library: library, dependencies: dependencies,
            onAccessDraft: { [weak self] in self?.recordRecentDraft($0) })
    }

    func capture(content: String = "") {
        guard captureController.receive(content) else { return }
        captureController.show()
    }
    func openDraftWindow(_ id: UUID?, tab: Bool, origin: NSWindow?, timeout: TimeInterval = 120) async throws -> Bool {
        guard let library, let openDraftLibrary else { return false }
        if let id, !library.notes.contains(where: { $0.id == id }) { return false }
        if tab, origin == nil || !windows.allObjects.contains(where: { $0.window === origin }) { return false }
        return try await windowOpenRequests.request(timeout: timeout, start: { requestID in
            draftSceneRequests[requestID] = DraftSceneRequest(noteID: id, tab: tab, origin: origin)
            openDraftLibrary(requestID)
        }, onEnd: { [weak self] requestID in
            guard let self, let request = self.draftSceneRequests[requestID], !request.completed else { return }
            self.draftSceneRequests.removeValue(forKey: requestID)
            self.retiredDraftSceneRequests.insert(requestID)
            request.model?.window?.close()
        })
    }

    func registerWindow(_ model: WindowModel, window: NSWindow? = nil, requestID: UUID? = nil) {
        if let window { model.window = window }
        if let requestID {
            registerRequestedWindow(model, requestID: requestID)
            return
        }
        windows.add(model)
        if model.window?.isKeyWindow == true { commandWindow = model }
        _ = consumePendingDraft(for: model)
    }

    private func registerRequestedWindow(_ model: WindowModel, requestID: UUID) {
        if draftSceneRequests[requestID] == nil, !retiredDraftSceneRequests.contains(requestID) {
            // A restored scene has no pending request in this process.
            registerWindow(model, window: model.window)
            return
        }
        guard let request = draftSceneRequests[requestID],
              request.model == nil || request.model === model else {
            model.window?.close()
            return
        }
        request.model = model
        windows.add(model)
        if model.window?.isKeyWindow == true { commandWindow = model }
        guard !request.completed, let window = model.window else { return }
        guard windowOpenRequests.contains(requestID), model.library === library else {
            _ = windowOpenRequests.complete(requestID, false)
            return
        }
        guard model.flush() else { _ = windowOpenRequests.complete(requestID, false); return }
        if let id = request.noteID {
            guard model.library.notes.contains(where: { $0.id == id }) else {
                _ = windowOpenRequests.complete(requestID, false); return
            }
            model.folder = .inbox; model.clearFilters(); model.select(id)
            guard model.editor.noteID == id else { _ = windowOpenRequests.complete(requestID, false); return }
        } else { model.create() }
        if request.tab {
            guard let origin = request.origin, origin !== window,
                  windows.allObjects.contains(where: { $0.window === origin }) else {
                _ = windowOpenRequests.complete(requestID, false); return
            }
            origin.addTabbedWindow(window, ordered: .above)
            guard origin.tabbedWindows?.contains(where: { $0 === window }) == true else {
                _ = windowOpenRequests.complete(requestID, false); return
            }
        }
        request.completed = true
        if !windowOpenRequests.complete(requestID, true) {
            draftSceneRequests.removeValue(forKey: requestID)
            retiredDraftSceneRequests.insert(requestID)
            window.close()
        }
    }

    func hasDraftSceneRequest(_ requestID: UUID?) -> Bool {
        guard let requestID else { return false }
        return draftSceneRequests[requestID] != nil || retiredDraftSceneRequests.contains(requestID)
    }
    func queueDraftSelection(_ id: UUID?) { if let id { pendingNoteID = id } }
    func queueNewWindowDraftSelection(_ id: UUID?) {
        pendingNoteID = id
        if id != nil { pendingExcludedModels = Set(windows.allObjects.map(ObjectIdentifier.init)) }
    }
    func unregisterWindow(_ model: WindowModel) {
        for (id, request) in Array(draftSceneRequests) {
            if request.model === model {
                if request.completed { draftSceneRequests.removeValue(forKey: id); retiredDraftSceneRequests.insert(id) }
                else { windowOpenRequests.cancel(id) }
            } else if !request.completed, let origin = request.origin, origin === model.window {
                windowOpenRequests.cancel(id)
            }
        }
        if pendingTargetModel === model || (model.window != nil && pendingTargetWindow === model.window)
            || (pendingExcludedModels != nil && pendingExcludedModels?.contains(ObjectIdentifier(model)) == false) { pendingNoteID = nil }
        windows.remove(model)
        if commandWindow === model { commandWindow = nil }
    }
    @discardableResult func consumePendingDraft(for model: WindowModel) -> Bool {
        guard let id = pendingNoteID, let library, model.library === library,
              pendingExcludedModels?.contains(ObjectIdentifier(model)) != true,
              pendingTargetModel == nil || pendingTargetModel === model,
              pendingTargetWindow == nil || model.window === pendingTargetWindow else { return false }
        guard library.notes.contains(where: { $0.id == id }) else {
            library.error = "The requested draft was not found."
            if pendingNoteID == id { pendingNoteID = nil }
            return false
        }
        pendingTargetModel = model
        guard model.flush() else { return false }
        model.folder = .inbox; model.clearFilters(); model.select(id)
        guard model.editor.noteID == id else { return false }
        pendingNoteID = nil
        return true
    }
    func draftSelectionDidChange(_ id: UUID?, for model: WindowModel) {
        guard let id, model.editor.noteID == id, let pending = pendingNoteID, pending != id,
              pendingExcludedModels?.contains(ObjectIdentifier(model)) != true,
              pendingTargetModel == nil || pendingTargetModel === model,
              pendingTargetWindow == nil || model.window === pendingTargetWindow else { return }
        pendingNoteID = nil
    }
    func show(_ id: UUID? = nil) {
        queueDraftSelection(id)
        NSApp.activate(ignoringOtherApps: true)
        let libraryWindows = NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("library") == true && $0.isVisible }
        let pendingWindow = pendingTargetModel?.window.flatMap { $0.isVisible ? $0 : nil }
        if let window = pendingWindow ?? libraryWindows.first(where: \.isKeyWindow) ?? libraryWindows.first {
            if pendingNoteID != nil, pendingExcludedModels == nil, pendingTargetModel == nil { pendingTargetWindow = window }
            window.makeKeyAndOrderFront(nil)
            if let model = windows.allObjects.first(where: { $0.window === window }) { _ = consumePendingDraft(for: model) }
        } else { requestLibraryWindow() }
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
    func newDraft(content: String = "") { pendingNoteID = nil; openMenuAction(.newDraft(content)) }
    func showQuickSearch(initialQuery: String = "") {
        if let model = commandWindow, !model.flush() { return }
        quickSearchController.show(initialQuery: initialQuery)
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
            model.openCommandPalette()
        case .newDraft(let content):
            _ = model.capture(content)
        }
    }
    func handle(_ url: URL) { ApplicationURLRouter(controller: self).handle(url) }
}
