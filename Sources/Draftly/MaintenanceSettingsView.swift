import SwiftUI
import DraftlyCore

struct MaintenanceSettingsView: View {
    @ObservedObject var library: LibraryStore
    @State private var confirmsInstallation = false
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        Form {
            Section("Actions") {
                Text("Replace the default Basic, Editing, Markdown, Processing, and Tools actions with the current catalog, including icons and colors. This overwrites edited defaults and restores deleted defaults. Other actions remain.")
                    .foregroundStyle(.secondary)
                Button("Replace Default Actions…") { confirmsInstallation = true }
                if let result { Text(result).foregroundStyle(.secondary).textSelection(.enabled) }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Replace Default Actions?", isPresented: $confirmsInstallation) {
            Button("Replace Defaults", role: .destructive) { install() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Draftly will install \(DefaultActionCatalog.actions.count) default actions. Changes to default actions will be overwritten, and deleted defaults will return. Other actions remain.")
        }
    }

    private func install() {
        do {
            let installation = try library.replaceDefaultActions()
            result = "Installed \(installation.actionCount) actions in " + installation.groupNames.joined(separator: ", ") + "."
            error = nil
        } catch {
            self.error = error.localizedDescription
            result = nil
        }
    }
}
