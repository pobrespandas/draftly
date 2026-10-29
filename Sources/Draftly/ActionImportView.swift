import SwiftUI
import AppKit
@_spi(DraftlyInternal) import DraftlyCore

struct ActionImportView: View {
    @ObservedObject var library: LibraryStore
    var onImport: (([DraftAction]) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var imported: [DraftAction] = []
    @State private var installationData: Data?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Import Actions").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Paste a Drafts Directory URL or an installation link. Review the steps before saving.").foregroundStyle(.secondary)
            HStack { TextField("https://actions.getdrafts.com/a/…", text: $link).textFieldStyle(.roundedBorder); Button("Load") { load() }.disabled(loading || link.isEmpty) }
            if loading { ProgressView() }
            if imported.isEmpty && installationData == nil {
                Text("Compatibility reference actions").font(.headline)
                ForEach([("New Draft with Template", "1VL"), ("Add to List", "1Ga"), ("Text Modifier…", "1Bg"), ("Copy as Rich Text", "1DM"), ("Save in Obsidian Vault", "1qn")], id: \.1) { name, id in
                    Button(name) { link = "https://actions.getdrafts.com/a/" + id; load() }.buttonStyle(.link)
                }
            } else {
                if let installationData, let backup = try? JSONDecoder().decode(Backup.self, from: installationData) {
                    ForEach(backup.actionGroups ?? []) { group in Text("Group: " + group.name).font(.headline) }
                }
                List(imported) { action in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(action.name).font(.headline)
                        Text("\(action.steps.count) steps · \(action.steps.map(\.type).joined(separator: ", "))").font(.caption)
                        if !action.unsupportedSteps.isEmpty { Text("Unsupported: " + action.unsupportedSteps.joined(separator: ", ")).foregroundStyle(.orange).font(.caption) }
                    }.padding(.vertical, 6)
                }.frame(height: 180)
                Button("Save Actions") {
                    do {
                        if let installationData {
                            var link = URLComponents(); link.scheme = "draftly"; link.host = "action"
                            link.queryItems = [URLQueryItem(name: "data", value: installationData.base64EncodedString())]
                            guard let url = link.url else { throw DraftlyError.message("The action installation data is invalid.") }
                            let installed = try ApplicationURLRouter.installActions(url, library: library) { actions, groups in
                                let alert = NSAlert()
                                alert.messageText = "Replace installed actions or groups?"
                                alert.informativeText = (actions.map { "Action: \($0.name)" } + groups.map { "Group: \($0.name)" }).joined(separator: "\n")
                                alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                                alert.buttons.last?.keyEquivalent = "\u{1b}"
                                return alert.runModal() == .alertFirstButtonReturn
                            }
                            guard installed else { return }
                        } else { try library.saveActions(imported) }
                        onImport?(imported); dismiss()
                    }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Spacer(minLength: 0)
        }.padding(24).frame(width: 580, height: 470)
    }
    private func load() {
        guard let url = URL(string: link) else { error = "Enter a valid URL."; return }
        loading = true; error = nil; installationData = nil; imported = []
        Task {
            do {
                if ["draftly", "drafts", "drafts5"].contains(url.scheme?.lowercased() ?? ""), ["action", "actiongroup"].contains(url.host?.lowercased() ?? "") {
                    let data = try ActionImporter.installationData(url)
                    imported = try ActionImporter.decode(data); installationData = data
                } else {
                    let data = try await ActionImporter.directoryInstallationData(url)
                    imported = try ActionImporter.decode(data); installationData = data
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
