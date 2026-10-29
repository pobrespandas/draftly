import AppKit
import Carbon
import DraftlyCore
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?
    private var globalHotKeys: GlobalHotKeys?
    private var statusController: StatusMenuController?
    private let termination = ActionTerminationCoordinator()
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
        AppUpdates.shared.start()
        NSApp.appearance = ApplicationAppearance.resolved(
            UserDefaults.standard.string(forKey: ApplicationAppearance.preferenceKey) ?? "System"
        ).nativeAppearance
        Self.current = self
        AppController.shared.startSpotlightIndexing()
        NSApp.setActivationPolicy(.regular)
        NSApp.servicesProvider = self
        statusController = StatusMenuController(controller: AppController.shared)
        globalHotKeys = GlobalHotKeys(perform: { name in
            let controller = AppController.shared
            switch name {
            case "Main Window": controller.show()
            case "Quick Capture": controller.capture()
            case "Capture Clipboard":
                guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
                controller.capture(content: text)
            default: break
            }
        }, changed: { AppController.shared.globalShortcutErrors = $0 })
        reloadGlobalShortcuts()
        if AppController.shared.library?.cloudIdentifier != nil { NSApp.registerForRemoteNotifications() }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.routeExternalURLs(urls, receiveCallback: ActionCallbackRouter.receive) {
            AppController.shared.handle($0)
        }
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard let id = SpotlightPreferences.draftID(activityType: userActivity.activityType,
                                                   userInfo: userActivity.userInfo) else { return false }
        return AppController.shared.openSearchResult(id)
    }

    static func routeExternalURLs(_ urls: [URL], receiveCallback: (URL) -> Bool, handle: (URL) -> Void) {
        for url in urls where !receiveCallback(url) { handle(url) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppController.shared.refreshThemeDevelopmentFolder()
    }

    func reloadGlobalShortcuts() {
        globalHotKeys?.reload(configuration: UserDefaults.standard.string(forKey: CommandShortcuts.storageKey) ?? "{}",
                             actions: AppController.shared.library?.actions ?? [])
    }
    func suspendGlobalShortcuts() { globalHotKeys?.suspend() }
    func dispatchGlobalShortcut(_ id: UInt32) { globalHotKeys?.dispatch(id) }
    func applicationWillTerminate(_ notification: Notification) { globalHotKeys?.stop() }
    func setStatusItemVisible(_ visible: Bool) { statusController?.setStatusItemVisible(visible) }
    func openStatusMenuForTesting() { statusController?.openStatusMenuForTesting() }
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
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let controller = AppController.shared
        let flush = { controller.windows.allObjects.allSatisfy { $0.flush() } }
        guard let library = controller.library else { return flush() ? .terminateNow : .terminateCancel }
        return termination.request(busy: { ActionRunner.isExecuting(in: library) },
            changes: ActionRunner.executionBusyPublisher(in: library), flush: flush,
            reply: { sender.reply(toApplicationShouldTerminate: $0) })
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        AppController.shared.show()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor
final class ActionTerminationCoordinator {
    private var observation: AnyCancellable?
    private var waiting = false

    func request(busy: @escaping () -> Bool, changes: AnyPublisher<Bool, Never>, flush: @escaping () -> Bool,
                 reply: @escaping (Bool) -> Void) -> NSApplication.TerminateReply {
        if waiting { return .terminateLater }
        guard busy() else { return flush() ? .terminateNow : .terminateCancel }
        waiting = true
        observation = changes.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self, self.waiting, !busy() else { return }
            self.waiting = false
            self.observation = nil
            reply(flush())
        }
        return .terminateLater
    }
}
