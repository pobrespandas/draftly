import SwiftUI
import AgentContracts

struct AgentConnectionsSettingsView: View {
    @ObservedObject var model: AgentConnectionsSettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Allow local agent access", isOn: Binding(get: { model.accessEnabled }, set: { enabled in
                    try? model.setEnabled(enabled)
                })).disabled(!model.readable)
                Text("Each connection needs your approval. Permissions stay on this Mac and are not included in backups.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.pending.isEmpty {
                Section("Connection requests") {
                    ForEach(model.pending) { challenge in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(challenge.clientName).font(.headline)
                            Text("This name comes from the client. Compare the code before approving.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(challenge.code).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            HStack {
                                Text("Expires " + challenge.expiresAt.formatted(date: .omitted, time: .standard)).font(.caption)
                                Spacer()
                                Button("Deny", role: .destructive) { try? model.denyPairing(challenge.id) }
                                Button("Review…") { try? model.beginPairing(challenge.id) }
                            }
                        }
                    }
                }
            }
            Section("Connections for this library") {
                if model.connections.isEmpty { Text("No approved connections.").foregroundStyle(.secondary) }
                ForEach(model.connections) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(record.name).font(.headline)
                            Spacer()
                            Text(model.status(record).userTitle).foregroundStyle(.secondary)
                        }
                        Text(record.scopeKind == .library ? "Entire library" : "Selected resources: \(record.resources.count)")
                        Text("Expires " + record.expiresAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        HStack {
                            Button("Edit permissions…") { try? model.beginEditing(record.id) }.disabled(record.revoked || !model.readable)
                            Button(record.revoked ? "Retry credential cleanup" : "Revoke access", role: .destructive) { try? model.revoke(record.id) }
                                .disabled(!model.readable)
                        }
                    }
                }
            }
            if model.cleanupPending {
                Text("Access is revoked. Credential cleanup is still pending.").foregroundStyle(.secondary)
            }
            if let error = model.lastError {
                HStack {
                    Text(error.connectionMessage).foregroundStyle(.red)
                    Button("Dismiss") { model.clearError() }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(get: { model.draft != nil }, set: { if !$0 { model.cancelEditing() } })) {
            AgentConnectionGrantEditor(model: model)
        }
        .task {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct AgentConnectionGrantEditor: View {
    @ObservedObject var model: AgentConnectionsSettingsModel
    @State private var search = ""
    @State private var codesMatch = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.isPairing ? "Review connection" : "Edit connection permissions").font(.headline)
                Spacer()
                Button("Cancel") { model.cancelEditing() }.keyboardShortcut(.cancelAction)
                if model.isPairing {
                    if model.review != nil {
                        Button("Approve") { _ = try? model.approvePairing(codesMatch: codesMatch) }
                            .keyboardShortcut(.defaultAction).disabled(!codesMatch || !model.canReviewPairing)
                    } else {
                        Button("Review") { try? model.preparePairingReview() }
                            .keyboardShortcut(.defaultAction).disabled(!model.canReviewPairing)
                    }
                } else {
                    Button("Save") { try? model.saveExisting() }.keyboardShortcut(.defaultAction).disabled(!model.readable)
                }
            }.padding(16)
            Divider()
            if let review = model.review { reviewSummary(review) }
            else if let draft = model.draft { editingForm(draft) }
            if let error = model.lastError {
                Text(error.connectionMessage).foregroundStyle(.red).padding(12)
            }
        }
        .frame(width: 650, height: 630)
        .onChange(of: model.review?.id) { _, _ in codesMatch = false }
        .onDisappear { model.cancelEditing() }
    }

    private func editingForm(_ draft: AgentGrantEditingCopy) -> some View {
        Form {
            Section("Connection") {
                TextField("Name", text: field(\.name, fallback: draft.name)).disabled(!model.isPairing)
                DatePicker("Access expires", selection: field(\.expiresAt, fallback: draft.expiresAt))
                Toggle("Allow explicit renewal", isOn: field(\.renewable, fallback: draft.renewable))
                Text("Renewal does not extend access by itself. Expiry and revocation apply to every request.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                ForEach(AgentCapability.allCases, id: \.rawValue) { capability in
                    Toggle(capability.userTitle, isOn: Binding(get: { model.draft?.capabilities.contains(capability) == true }, set: { enabled in
                        guard var copy = model.draft else { return }
                        if enabled { copy.capabilities.insert(capability) } else { copy.capabilities.remove(capability) }
                        model.draft = copy
                    }))
                }
                Text("Permissions do not approve individual destructive operations or native effects.")
                    .font(.caption).foregroundStyle(.secondary)
                if draft.capabilities.contains(.scriptsUnrestricted) {
                    Text("Unrestricted scripts can affect files, other apps and external systems. Each use still needs your approval.")
                        .foregroundStyle(.orange)
                }
            }
            Section("Resources") {
                Toggle("Entire library, including future resources", isOn: field(\.wholeLibrary, fallback: draft.wholeLibrary))
                if !draft.wholeLibrary {
                    TextField("Filter resources", text: $search)
                    ForEach(model.resourceChoices().filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.reference.id.uuidString.localizedCaseInsensitiveContains(search) }) { choice in
                        Toggle(isOn: Binding(get: { model.draft?.targets.contains(choice.reference) == true }, set: { enabled in
                            guard var copy = model.draft else { return }
                            if enabled { copy.targets.insert(choice.reference) } else { copy.targets.remove(choice.reference) }
                            model.draft = copy
                        })) {
                            VStack(alignment: .leading) {
                                Text(choice.title)
                                Text(choice.reference.kind.userTitle + " · " + choice.reference.id.uuidString)
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }.accessibilityLabel(choice.accessibilityTitle)
                    }
                    Text("A Workspace is a saved query, not an access boundary. Future matches are not added to selected resources.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }

    private func reviewSummary(_ review: AgentPairingCoordinator.Review) -> some View {
        let titles = Dictionary(model.resourceChoices().map { ($0.reference, $0.title) }, uniquingKeysWith: { first, _ in first })
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(review.name).font(.title2)
                Text("Compare this code with the code shown by your client:")
                Text(review.challenge.code).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Toggle("The codes match", isOn: $codesMatch)
                Text("Access expires " + review.grantExpiresAt.formatted(date: .abbreviated, time: .shortened))
                Text(review.renewable ? "Explicit renewal is allowed." : "Renewal is not allowed.")
                Text("Permissions").font(.headline)
                ForEach(review.capabilities.sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { Text($0.userTitle) }
                Text("Resources").font(.headline)
                switch review.scope {
                case .library: Text("All resources in this library, including future resources.").foregroundStyle(.orange)
                case .resources(let targets):
                    if targets.isEmpty { Text("No resource IDs selected.") }
                    ForEach(targets.sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }, id: \.self) { target in
                        VStack(alignment: .leading) {
                            Text(titles[target] ?? "Unavailable resource")
                            Text(target.kind.userTitle + " · " + target.id.uuidString).font(.caption).textSelection(.enabled)
                        }
                    }
                }
                Button("Change choices") { model.changeReviewChoices() }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
    }

    private func field<Value>(_ keyPath: WritableKeyPath<AgentGrantEditingCopy, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { model.draft?[keyPath: keyPath] ?? fallback }, set: { value in
            guard var copy = model.draft else { return }
            copy[keyPath: keyPath] = value; model.draft = copy
        })
    }
}
