import SwiftUI

struct ChatGPTAccountView: View {
    @ObservedObject var model: ChatGPTAccountModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ChatGPT Account").font(.title2)
            if !model.accounts.isEmpty {
                Picker("Account", selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                    Text("New account").tag(Optional<UUID>.none)
                    ForEach(model.accounts, id: \.id) { account in
                        Text(label(account)).tag(Optional(account.id))
                    }
                }.disabled(model.isBusy)
            }
            if model.isSignedIn {
                Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if model.selectedAccount?.tokens?.allowsInference == false {
                    Text("This connection does not have permission to use your ChatGPT plan.").foregroundStyle(.secondary)
                }
                Button("Sign Out") { Task { await model.signOut() } }.disabled(model.isBusy)
                Button("Add Account…") { model.addAccount() }.disabled(model.isBusy)
            } else if model.isAwaitingLogin {
                Text("Complete sign-in in your browser.")
                Button("Cancel Sign-In") { model.cancelSignIn() }
            } else {
                Button("Continue with ChatGPT") { model.signIn() }
                    .buttonStyle(.borderedProminent).disabled(model.isBusy)
            }
            if model.isBusy { ProgressView().controlSize(.small) }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Refresh") { model.refresh(); Task { await model.loadModels() } }.disabled(model.isBusy || model.isLoadingModels)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 440)
        .task { model.refresh(); await model.loadModels() }
        .onDisappear { model.cancelSignIn() }
    }

    private func label(_ account: ChatGPTAccountRecord) -> String {
        let name = account.identity.email ?? account.identity.name ?? "ChatGPT"
        return name + " · " + String(account.id.uuidString.prefix(6))
    }
}
