import SwiftUI
import AppKit
import CoreGraphics
import DraftlyCore
import AgentContracts
import AgentLocalSecurity

extension Notification.Name {
    static let draftlyOpenNote = Notification.Name("DraftlyOpenNote")
}

// Public session properties establish console membership, not graphical lock state.
@MainActor enum AgentApplicationSession {
    static func permitsAccess(onConsole: Bool?, loginDone: Bool?, protectedDataAvailable: Bool) -> Bool {
        onConsole == true && loginDone == true && protectedDataAvailable
    }

    #if DRAFTLY_AGENT_QA
    static var qaAdmissionDiagnostics: String {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        func value(_ key: String) -> String {
            (session?[key] as? Bool).map { String($0) } ?? "unknown"
        }
        return "QA admission: console=" + value(kCGSessionOnConsoleKey)
            + ", login=" + value(kCGSessionLoginDoneKey)
            + ", protectedData=" + String(NSApplication.shared.isProtectedDataAvailable)
    }
    #endif

    static var isUnavailable: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return !permitsAccess(onConsole: session?[kCGSessionOnConsoleKey as String] as? Bool,
            loginDone: session?[kCGSessionLoginDoneKey as String] as? Bool,
            protectedDataAvailable: NSApplication.shared.isProtectedDataAvailable)
    }
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
    case workspace(Workspace)
}

@MainActor private final class DraftSceneRequest {
    let noteID: UUID?
    let tab: Bool
    weak var origin: NSWindow?
    weak var model: WindowModel?
    var completed = false
    let authorize: (() throws -> Void)?
    let focusEditor: Bool
    var onModel: ((WindowModel) -> Void)?
    init(noteID: UUID?, tab: Bool, origin: NSWindow?, authorize: (() throws -> Void)? = nil,
         focusEditor: Bool = true, onModel: ((WindowModel) -> Void)? = nil) {
        self.noteID = noteID; self.tab = tab; self.origin = origin
        self.authorize = authorize; self.focusEditor = focusEditor; self.onModel = onModel
    }
    var canCloseWithoutSaving: Bool {
        guard authorize != nil, let model else { return true }
        return Self.canClose(model, noteID: noteID)
    }
    static func canClose(_ model: WindowModel, noteID: UUID?) -> Bool {
        guard !model.hasUnsavedChanges, !model.editor.hasUnpersistedText,
              !model.actionPending, !model.runner.isRunning, model.actionPreview == nil,
              model.previewHTML == nil, !model.arrangementSession.isActive,
              model.editor.canApplyExternalEdit?() != false else { return false }
        if model.editor.noteID == nil { return model.editor.content.isEmpty }
        guard model.editor.noteID == noteID,
              let stored = model.library.notes.first(where: { $0.id == noteID }) else { return false }
        return DraftOperations.sameText(model.editor.content, stored.content)
    }
}

@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()
    @Published var library: LibraryStore? {
        willSet {
            guard library !== newValue else { return }
            closeAgentContext()
        }
    }
    private var cachedAgentEditors: AgentEditorRegistry?
    private var agentHost: AgentLocalHost?
    private var agentLifecycleObservers: [NSObjectProtocol] = []
    private var agentProtectedDataObserver: NSObjectProtocol?
    @Published var startupError: String?
    @Published var agentSettings: AgentConnectionsSettingsModel?
    @Published var globalShortcutErrors: [String: String] = [:]
    @Published var commandWindow: WindowModel?
    let recentDrafts: RecentDraftStore
    private(set) var spotlight: SpotlightPreferences?
    private var spotlightRequested = false
    private lazy var agentLoginItemPreferences = LoginItemPreferences()
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
    private var retiredAuthorizedDraftSceneRequests: [UUID: UUID] = [:]
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
    init(library: LibraryStore, recentDrafts: RecentDraftStore, agentSettings: AgentConnectionsSettingsModel? = nil) {
        self.library = library; self.recentDrafts = recentDrafts; self.agentSettings = agentSettings
    }
    isolated deinit { closeAgentContext() }

    func adoptAgentHost(_ host: AgentLocalHost) throws {
        guard let library, let editors = cachedAgentEditors,
              host.isBound(to: library, editors: editors) else { throw AgentErrorCode.invalidInput }
        guard agentHost !== host else { return }
        let settings = try host.makeLibrarySettingsModel()
        if let previous = agentHost { previous.close(); agentSettings = nil }
        agentHost = host
        agentSettings = settings
        observeAgentSessionSuspension()
    }

    private func observeAgentSessionSuspension() {
        guard agentLifecycleObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            agentLifecycleObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspendAgentSession() }
            })
        }
        agentProtectedDataObserver = NotificationCenter.default.addObserver(
            forName: .NSApplicationProtectedDataWillBecomeUnavailable, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspendAgentSession() }
        }
    }

    func suspendAgentSession() {
        agentHost?.suspend()
        agentSettings?.refresh()
    }

    func configureAgentHost(isLocked: @escaping () -> Bool = { AgentApplicationSession.isUnavailable },
                            enableReviewedActions: Bool = false,
                            enableReviewedMutations: Bool = false,
                            preferenceStorage: AgentPreferenceStorage? = nil,
                            preferenceDefaults: UserDefaults = .standard,
                            protectedDataAvailable: @escaping () -> Bool = { NSApplication.shared.isProtectedDataAvailable },
                            credentials: AgentConnectionRegistry.CredentialAccess? = nil,
                            validateApplication: @escaping () throws -> Void = { try AgentCredentialIdentity.validateCurrentProcess(.application) },
                            validateHelper: @escaping @Sendable (Data) throws -> Void = { try AgentPeerIdentity.validate($0, role: .helper) }) throws {
        guard let library else { throw AgentErrorCode.unavailable }
        guard agentHost == nil else { return }
        let editors = try agentEditorRegistry(for: library)
        let resources = AgentLibraryResourceChoices(library: library, editors: editors, bookmarkDefaults: preferenceDefaults)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let host = try AgentLocalHost(library: library, appVersion: version, editors: editors,
            enableReviewedActions: enableReviewedActions,
            nativeHost: { [weak self] in self?.makeActionHost() ?? NativeActionHost() },
            enableReviewedMutations: enableReviewedMutations,
            nativePreferenceRead: { [weak self] id in
                guard let self else { throw AgentErrorCode.cancelled }
                if id == "application.launchAtLogin" {
                    return try AgentNativePreferenceAccess.readLoginItem(self.agentLoginItemPreferences)
                }
                guard id == SpotlightPreferences.enabledKey, let spotlight = self.spotlight else {
                    throw AgentErrorCode.unavailable
                }
                return try AgentNativePreferenceAccess.readSpotlight(spotlight,
                    hasStoredOverride: UserDefaults.standard.object(forKey: SpotlightPreferences.enabledKey) != nil)
            }, preferenceDefaults: preferenceDefaults, preferenceStorage: preferenceStorage,
            isLocked: { isLocked() || !protectedDataAvailable() },
            pendingEditorGeneration: { _ in "" }, resolveTargets: { resources.resolve($0) },
            credentials: credentials, validateApplication: validateApplication, validateHelper: validateHelper)
        do { try adoptAgentHost(host) } catch { host.close(); throw error }
    }

    func requestChatToolsFromUserInterface(for model: WindowModel) throws -> AgentChatToolSession {
        guard let host = agentHost, let library, model.library === library,
              let editors = cachedAgentEditors, host.isBound(to: library, editors: editors),
              let draftID = model.editor.noteID else { throw AgentErrorCode.unavailable }
        guard model.chatConsole.canConnectTools else { throw AgentErrorCode.permissionDenied }
        let selectedModel = model.chatConsole.selectedModel
        let accountEpoch = selectedModel.hasPrefix("chatgpt:") ? model.chatConsole.chatGPTAccount?.sessionEpoch : nil
        let providerName = model.chatConsole.toolProviderName
        guard let window = try editors.windowSnapshots().first(where: { snapshot in
            snapshot.draftID == draftID && (try? editors.executionModels(draftID: draftID, windowID: snapshot.id)
                .contains(where: { $0 === model })) == true
        }) else { throw AgentErrorCode.notFound }
        let alert = NSAlert()
        let title = String((model.currentNote?.title ?? "this draft").prefix(80))
        alert.messageText = "Allow \(providerName) to use “\(title)”?"
        alert.informativeText = "The selected draft and its editor content can be " + model.chatConsole.toolDataDestination + ". "
            + "Access applies only to this draft and editor and expires in 15 minutes. "
            + "Editing permits changes to this draft's text, tags, flags, syntax, folder and versions. "
            + "You can disconnect from this chat or revoke access in Settings."
        alert.addButton(withTitle: "Allow Reading")
        alert.addButton(withTitle: "Allow Editing")
        alert.addButton(withTitle: "Cancel")
        let decision = alert.runModal()
        guard decision != .alertThirdButtonReturn else { throw AgentErrorCode.cancelled }
        guard decision == .alertFirstButtonReturn || decision == .alertSecondButtonReturn else { throw AgentErrorCode.cancelled }
        guard model.editor.noteID == draftID,
              selectedModel.hasPrefix("chatgpt:") ? model.chatConsole.selectedModel.hasPrefix("chatgpt:") : model.chatConsole.selectedModel == selectedModel,
              !selectedModel.hasPrefix("chatgpt:") || model.chatConsole.chatGPTAccount?.sessionEpoch == accountEpoch,
              try editors.executionModels(draftID: draftID, windowID: window.id).contains(where: { $0 === model }) else {
            throw AgentErrorCode.versionConflict
        }
        var capabilities: Set<AgentCapability> = [.draftsRead, .editorRead]
        if decision == .alertSecondButtonReturn { capabilities.formUnion([.draftsWrite, .editorWrite]) }
        return try host.makeChatToolsFromUserInterface(capabilities: capabilities,
            targets: [.init(kind: .draft, id: draftID), .init(kind: .window, id: window.id)], providerName: providerName,
            onRevocationError: { [weak model] error in model?.chatConsole.reportToolError(error) },
            validateContext: { [weak model] in
                guard let model, model.editor.noteID == draftID,
                      selectedModel.hasPrefix("chatgpt:") ? model.chatConsole.selectedModel.hasPrefix("chatgpt:") : model.chatConsole.selectedModel == selectedModel,
                      !selectedModel.hasPrefix("chatgpt:") || model.chatConsole.chatGPTAccount?.sessionEpoch == accountEpoch else {
                    throw AgentErrorCode.permissionDenied
                }
            })
    }

    func closeAgentContext() {
        let center = NSWorkspace.shared.notificationCenter
        agentLifecycleObservers.forEach { center.removeObserver($0) }
        agentLifecycleObservers.removeAll()
        if let observer = agentProtectedDataObserver { NotificationCenter.default.removeObserver(observer) }
        agentProtectedDataObserver = nil
        if let host = agentHost {
            agentHost = nil; host.close(); agentSettings = nil
        }
        cachedAgentEditors?.invalidate(); cachedAgentEditors = nil
    }

    func prepareForTermination() -> Bool {
        guard windows.allObjects.allSatisfy({ $0.flush() }) else { return false }
        closeAgentContext()
        return true
    }

    func agentEditorRegistry(for library: LibraryStore) throws -> AgentEditorRegistry {
        guard self.library === library else { throw AgentErrorCode.invalidInput }
        if let registry = cachedAgentEditors, registry.isBound(to: library) { return registry }
        let registry = AgentEditorRegistry(library: library, models: { [weak self, weak library] in
            guard let self, let library, self.library === library else { return [] }
            return self.windows.allObjects
        }, openWindow: { [weak self, weak library] id, focus, authorize in
            guard let self, let library, self.library === library else { throw AgentErrorCode.cancelled }
            return try await self.openAuthorizedDraftWindow(id, focusEditor: focus, authorize: authorize)
        })
        registry.refreshMembership()
        cachedAgentEditors = registry
        return registry
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
            #if DRAFTLY_AGENT_QA
            if AgentQAConfiguration.isActive, let directory {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            }
            #endif
            let store = try LibraryStore(cloudIdentifier: cloud, directory: directory, seed: !cloudTesting)
            #if DRAFTLY_AGENT_QA
            if AgentQAConfiguration.isActive &&
                ProcessInfo.processInfo.arguments.contains("--agent-workspace-fixtures") {
                guard store.workspaces.isEmpty && store.notes.isEmpty else { throw DraftlyError.message("QA workspace fixtures require an empty test library.") }
                var visible = Workspace(name: "QA Visible"); visible.query = "QA query"
                try store.saveWorkspaces([visible, Workspace(name: "QA Hidden")])
                _ = try store.createNote(content: "QA query visible")
                _ = try store.createNote(content: "QA query hidden")
                _ = try store.createNote(content: "QA unrelated")
            }
            #endif
            let catalogQATesting = testing && ProcessInfo.processInfo.arguments.contains("--catalog-installation-testing")
            let catalogCloudQATesting = cloudTesting && ProcessInfo.processInfo.arguments.contains("--catalog-cloud-installation-testing")
            if (!testing && !cloudTesting) || catalogQATesting || catalogCloudQATesting {
                let bundle = Bundle.main
                let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
                let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
                let attributes = try FileManager.default.attributesOfItem(atPath: bundle.bundleURL.path)
                let created = (attributes[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
                let fileID = (attributes[.systemFileNumber] as? NSNumber)?.stringValue ?? "unknown"
                try store.requestActionCatalogReplacement(installation: "temporary-defaults/\(version)/\(build)/\(created)/\(fileID)")
            }
            do { try LocalThemeMigration.run(in: store) }
            catch { store.error = "Theme migration failed: " + error.localizedDescription }
            library = store
            #if DRAFTLY_AGENT_QA
            if AgentQAConfiguration.isActive {
                do {
                    do { try AgentCredentialIdentity.validateCurrentProcess(.application) }
                    catch { FileHandle.standardError.write(Data("Agent QA identity check failed\n".utf8)); throw error }
                    do { _ = try AgentLibraryLocation(library: store) }
                    catch { FileHandle.standardError.write(Data("Agent QA library check failed\n".utf8)); throw error }
                }
                catch {
                    FileHandle.standardError.write(Data("Agent QA host failed: \(error)\n".utf8))
                    throw error
                }
            }
            #endif
            if (!testing && !cloudTesting) || AgentQAConfiguration.isActive {
                let helper = Bundle.main.bundleURL.appendingPathComponent(
                    "Contents/Helpers/DraftlyAgent.app/Contents/MacOS/draftly-agent")
                if FileManager.default.isExecutableFile(atPath: helper.path) {
                    do {
                        let defaults = AgentQAConfiguration.chatDefaults ?? .standard
                        let domain = AgentQAConfiguration.chatNamespace ?? ApplicationIdentityMigration.identifier
                        try configureAgentHost(enableReviewedActions: true, enableReviewedMutations: true,
                            preferenceStorage: AgentPreferenceStorage(defaults: defaults, domain: domain),
                            preferenceDefaults: defaults)
                    } catch {
                        // Agent startup must not prevent access to the writing library.
                        FileHandle.standardError.write(Data("Local agent host unavailable at startup\n".utf8))
                    }
                }
            }
            if spotlightRequested { startSpotlightIndexing() }
            refreshThemeDevelopmentFolder()
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
    func startSpotlightIndexing() {
        spotlightRequested = true
        guard let library else { return }
        if spotlight == nil { spotlight = SpotlightPreferences() }
        spotlight?.attach(to: library)
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

    func openAuthorizedDraftWindow(_ id: UUID, focusEditor: Bool, timeout: TimeInterval = 120,
                                   authorize: @escaping () throws -> Void) async throws -> WindowModel {
        try authorize(); try Task.checkCancellation()
        guard let library, let openDraftLibrary,
              library.notes.contains(where: { $0.id == id }) else { throw AgentErrorCode.unavailable }
        var selected: WindowModel?
        let result = try await windowOpenRequests.request(timeout: timeout, start: { requestID in
            draftSceneRequests[requestID] = DraftSceneRequest(noteID: id, tab: false, origin: nil,
                authorize: authorize, focusEditor: focusEditor, onModel: { selected = $0 })
            openDraftLibrary(requestID)
        }, onEnd: { [weak self] requestID in
            guard let self, let request = self.draftSceneRequests[requestID], !request.completed else { return }
            self.draftSceneRequests.removeValue(forKey: requestID)
            self.retiredDraftSceneRequests.insert(requestID)
            self.retiredAuthorizedDraftSceneRequests[requestID] = id
            if request.canCloseWithoutSaving { request.model?.window?.close() }
        })
        try Task.checkCancellation(); try authorize()
        guard result, self.library === library, let selected,
              windows.allObjects.contains(where: { $0 === selected }), selected.editor.noteID == id,
              selected.window != nil else { throw AgentErrorCode.outcomeUnknown }
        return selected
    }

    func registerWindow(_ model: WindowModel, window: NSWindow? = nil, requestID: UUID? = nil) {
        if let window { model.window = window }
        if let window = model.window { model.installCloseProtection(on: window) }
        if let requestID {
            registerRequestedWindow(model, requestID: requestID)
            return
        }
        windows.add(model)
        cachedAgentEditors?.refreshMembership()
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
            let target = retiredAuthorizedDraftSceneRequests[requestID] ?? draftSceneRequests[requestID]?.noteID
            let protected = retiredAuthorizedDraftSceneRequests[requestID] != nil || draftSceneRequests[requestID]?.authorize != nil
            if !protected || DraftSceneRequest.canClose(model, noteID: target) { model.window?.close() }
            return
        }
        request.model = model
        if !request.completed {
            do { try request.authorize?() }
            catch { _ = windowOpenRequests.complete(requestID, false); return }
        }
        windows.add(model)
        cachedAgentEditors?.refreshMembership()
        if model.window?.isKeyWindow == true { commandWindow = model }
        guard !request.completed, let window = model.window else { return }
        guard windowOpenRequests.contains(requestID), model.library === library else {
            _ = windowOpenRequests.complete(requestID, false)
            return
        }
        if request.authorize != nil {
            guard model.editor.noteID == nil, model.editor.content.isEmpty,
                  !model.hasUnsavedChanges, !model.editor.hasUnpersistedText,
                  model.editor.canApplyExternalEdit?() != false else {
                _ = windowOpenRequests.complete(requestID, false); return
            }
        }
        let validateRequest = {
            try request.authorize?()
            if request.authorize != nil, !request.canCloseWithoutSaving { throw AgentErrorCode.interactionRequired }
        }
        do { try validateRequest() }
        catch { _ = windowOpenRequests.complete(requestID, false); return }
        guard model.flush() else { _ = windowOpenRequests.complete(requestID, false); return }
        if let id = request.noteID {
            guard model.library.notes.contains(where: { $0.id == id }) else {
                _ = windowOpenRequests.complete(requestID, false); return
            }
            model.folder = .inbox; model.clearFilters()
            do {
                guard try model.selectAuthorized(id, focusEditor: request.focusEditor,
                    authorize: validateRequest) else {
                    _ = windowOpenRequests.complete(requestID, false); return
                }
            } catch { _ = windowOpenRequests.complete(requestID, false); return }
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
        do { try validateRequest() }
        catch { _ = windowOpenRequests.complete(requestID, false); return }
        request.onModel?(model)
        request.onModel = nil
        request.completed = true
        if !windowOpenRequests.complete(requestID, true) {
            draftSceneRequests.removeValue(forKey: requestID)
            retiredDraftSceneRequests.insert(requestID)
            if request.authorize != nil, let id = request.noteID { retiredAuthorizedDraftSceneRequests[requestID] = id }
            if request.canCloseWithoutSaving { window.close() }
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
                if request.completed {
                    draftSceneRequests.removeValue(forKey: id); retiredDraftSceneRequests.insert(id)
                    if request.authorize != nil, let target = request.noteID { retiredAuthorizedDraftSceneRequests[id] = target }
                }
                else { windowOpenRequests.cancel(id) }
            } else if !request.completed, let origin = request.origin, origin === model.window {
                windowOpenRequests.cancel(id)
            }
        }
        if pendingTargetModel === model || (model.window != nil && pendingTargetWindow === model.window)
            || (pendingExcludedModels != nil && pendingExcludedModels?.contains(ObjectIdentifier(model)) == false) { pendingNoteID = nil }
        windows.remove(model)
        cachedAgentEditors?.refreshMembership()
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
    func openWorkspace(_ workspace: Workspace) { openMenuAction(.workspace(workspace)) }
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
        case .workspace(let workspace):
            guard model.flush() else { return }
            model.apply(workspace)
        case .newDraft(let content):
            _ = model.capture(content)
        }
    }
    func handle(_ url: URL) { ApplicationURLRouter(controller: self).handle(url) }
}
