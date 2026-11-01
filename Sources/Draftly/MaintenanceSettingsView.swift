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
                Text("Reinstall the current versions of the Basic, Editing, Markdown, Processing, and Tools action groups. Draftly installs new groups and does not replace existing groups.")
                    .foregroundStyle(.secondary)
                Button("Reinstall Default Actions…") { confirmsInstallation = true }
                if let result { Text(result).foregroundStyle(.secondary).textSelection(.enabled) }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reinstall Default Actions?", isPresented: $confirmsInstallation) {
            Button("Install New Copies") { install() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Draftly will add five new groups and \(DefaultActionCatalog.actions.count) actions. Existing groups and actions will not change.")
        }
    }

    private func install() {
        do {
            let installation = try library.reinstallDefaultActions()
            result = "Installed \(installation.actionCount) actions in " + installation.groupNames.joined(separator: ", ") + "."
            error = nil
        } catch {
            self.error = error.localizedDescription
            result = nil
        }
    }
}
