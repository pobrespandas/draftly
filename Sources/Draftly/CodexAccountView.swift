import SwiftUI

struct CodexAccountView: View {
    @ObservedObject var model: CodexAccountModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ChatGPT Account").font(.title2)
            Text("Connect your ChatGPT account through Codex.").foregroundStyle(.secondary)
            HStack {
                Text(model.executable?.lastPathComponent ?? "Codex was not found")
                Spacer()
                Button("Choose Codex…") { chooseExecutable() }.disabled(model.isBusy || model.isAwaitingLogin)
            }
            if model.isSignedIn {
                Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Sign Out") { Task { await model.signOut() } }.disabled(model.isBusy)
            } else if model.isAwaitingLogin {
                Text("Complete sign-in in your browser.")
                Button("Cancel Sign-In") { Task { await model.cancelSignIn() } }
            } else {
                Button("Sign in with ChatGPT") { Task { await model.signIn() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.executable == nil)
            }
            if model.isBusy { ProgressView().controlSize(.small) }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button("Refresh") { Task { await model.refresh() } }
                    .disabled(model.isBusy || model.isAwaitingLogin)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 420)
        .task { await model.refresh() }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose Codex"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              FileManager.default.isExecutableFile(atPath: url.path) else { return }
        model.disconnect(); model.executable = url
        Task { await model.refresh() }
    }
}
