import SwiftUI
import AppKit
import DraftlyCore

@main
struct DraftlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var controller = AppController.shared
    var body: some Scene {
        WindowGroup(id: "library") {
            Group {
                if let library = controller.library { LibraryView(library: library, controller: controller) }
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
        .commands { DraftlyCommands(controller: controller) }
        Settings { SettingsView(controller: controller) }
            .commands {
                if let library = controller.library {
                    LibraryApplicationCommands(library: library, models: { controller.windows.allObjects })
                }
            }
    }
}
