import AppKit
import Carbon
import DraftlyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?
    private var hotKey: EventHotKeyRef?
    private var statusController: StatusMenuController?
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
        statusController = StatusMenuController(controller: AppController.shared)
        let id = EventHotKeyID(signature: 0x44524654, id: 1)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if registered != noErr { AppController.shared.captureShortcutStatus = "Shortcut unavailable (\(registered)). Use the menu bar." }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in AppController.shared.capture() }; return noErr
        }, 1, &type, nil, nil)
        if AppController.shared.library?.cloudIdentifier != nil { NSApp.registerForRemoteNotifications() }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.routeExternalURLs(urls, receiveCallback: ActionCallbackRouter.receive) {
            AppController.shared.handle($0)
        }
    }

    static func routeExternalURLs(_ urls: [URL], receiveCallback: (URL) -> Bool, handle: (URL) -> Void) {
        for url in urls where !receiveCallback(url) { handle(url) }
    }

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
        for window in AppController.shared.windows.allObjects where !window.flush() { return .terminateCancel }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
