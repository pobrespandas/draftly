import SwiftUI
import AppKit
import DraftlyCore

@main enum DraftlyLauncher {
    @MainActor static func main() {
        if let status = NativeAppleScriptProcess.runHelperIfRequested() { exit(status) }
        while true {
            do {
                try ApplicationIdentityMigration.prepare()
                break
            } catch {
                _ = NSApplication.shared
                let alert = NSAlert(error: error)
                alert.messageText = "Draftly could not migrate local preferences"
                alert.addButton(withTitle: "Try Again")
                alert.addButton(withTitle: "Quit")
                if alert.runModal() != .alertFirstButtonReturn { exit(EXIT_FAILURE) }
            }
        }
        DraftlyApp.main()
    }
}

struct DraftlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(GeneralPreferences.showMainWindowAtLaunchKey) private var showMainWindowAtLaunch = true
    @StateObject private var controller = AppController.shared
    var body: some Scene {
        WindowGroup(id: "library", for: UUID.self) { requestID in
            Group {
                if let library = controller.library { LibraryView(library: library, controller: controller, requestID: requestID.wrappedValue) }
                else {
                    VStack(spacing: 18) {
                        Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                        Text("Draftly could not open the library").font(.title2)
                        Text(controller.startupError ?? "Unknown error").textSelection(.enabled)
                        Button("Try Again") { controller.start() }
                    }.padding(40).frame(minWidth: 600, minHeight: 400)
                }
            }
        }
        .handlesExternalEvents(matching: [])
        .defaultLaunchBehavior(showMainWindowAtLaunch ? .automatic : .suppressed)
        .restorationBehavior(showMainWindowAtLaunch ? .automatic : .disabled)
        .onChange(of: scenePhase, initial: true) {
            controller.openLibrary = { openWindow(id: "library") }
            controller.openDraftLibrary = { openWindow(id: "library", value: $0) }
        }
        .defaultSize(width: 1033, height: 734)
        .commands { DraftlyCommands(controller: controller) }
        Settings { SettingsView(controller: controller) }
            .handlesExternalEvents(matching: [])
            .commands {
                if let library = controller.library {
                    LibraryApplicationCommands(library: library, models: { controller.windows.allObjects })
                }
            }
    }
}
