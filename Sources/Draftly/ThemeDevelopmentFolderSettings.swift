import SwiftUI
import AppKit
import DraftlyCore

struct ThemeDevelopmentFolderSettings: View {
    @ObservedObject var library: LibraryStore
    @AppStorage(ThemeDevelopmentFolder.enabledKey) private var enabled = false
    @AppStorage(ThemeDevelopmentFolder.bookmarkKey) private var bookmark = Data()
    @State private var status: String?
    @State private var error: String?

    private var folderName: String? {
        _ = bookmark
        return try? ThemeDevelopmentFolder.folderName()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Refresh Development Folder", isOn: Binding(get: { enabled }, set: { value in
                perform {
                    let count = try ThemeDevelopmentFolder.setEnabled(value, in: library)
                    status = value ? "Loaded \(count) theme files" : "Folder refresh disabled"
                }
            }))
            HStack {
                Text(folderName ?? "No development folder selected").foregroundStyle(.secondary)
                Spacer()
                Button("Choose Folder…") { chooseFolder() }
                Button("Reload Folder") {
                    perform { status = "Loaded \(try ThemeDevelopmentFolder.refresh(in: library)) theme files" }
                }.disabled(!enabled)
            }
            Text("Reloads at launch and when Draftly becomes active. Turning refresh off keeps registered themes available.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            else if let status { Text(status).foregroundStyle(.secondary) }
        }
    }

    private func perform(_ body: () throws -> Void) {
        do { try body(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your theme development folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { status = "Loaded \(try ThemeDevelopmentFolder.select(url, in: library)) theme files" }
    }
}
