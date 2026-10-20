import SwiftUI
import AppKit
import DraftlyCore

struct ActionImportView: View {
    @ObservedObject var library: LibraryStore
    var onImport: (([DraftAction]) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var imported: [DraftAction] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Import Actions").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Paste a Drafts Directory URL or an installation link. Review the steps before saving.").foregroundStyle(.secondary)
            HStack { TextField("https://actions.getdrafts.com/a/…", text: $link).textFieldStyle(.roundedBorder); Button("Load") { load() }.disabled(loading || link.isEmpty) }
            if loading { ProgressView() }
            if imported.isEmpty {
                Text("Compatibility reference actions").font(.headline)
                ForEach([("New Draft with Template", "1VL"), ("Add to List", "1Ga"), ("Text Modifier…", "1Bg"), ("Copy as Rich Text", "1DM"), ("Save in Obsidian Vault", "1qn")], id: \.1) { name, id in
                    Button(name) { link = "https://actions.getdrafts.com/a/" + id; load() }.buttonStyle(.link)
                }
            } else {
                List(imported) { action in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(action.name).font(.headline)
                        Text("\(action.steps.count) steps · \(action.steps.map(\.type).joined(separator: ", "))").font(.caption)
                        if !action.unsupportedSteps.isEmpty { Text("Unsupported: " + action.unsupportedSteps.joined(separator: ", ")).foregroundStyle(.orange).font(.caption) }
                    }.padding(.vertical, 6)
                }.frame(height: 180)
                Button("Save Actions") {
                    do { for action in imported { try library.saveAction(action) }; onImport?(imported); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Spacer(minLength: 0)
        }.padding(24).frame(width: 580, height: 470)
    }
    private func load() {
        guard let url = URL(string: link) else { error = "Enter a valid URL."; return }
        loading = true; error = nil
        Task { do { imported = try await ActionImporter.download(url) } catch { self.error = error.localizedDescription }; loading = false }
    }
}
