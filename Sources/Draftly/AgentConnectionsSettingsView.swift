import SwiftUI
import AppKit
import AgentContracts

struct AgentConnectionsSettingsView: View {
    @ObservedObject var model: AgentConnectionsSettingsModel
    @State private var confirmClearActivity = false
    @State private var operationReview: AgentApprovalStore.Review?

    var body: some View {
        Form {
            Section {
                Toggle("Allow local agent access", isOn: Binding(get: { model.accessEnabled }, set: { enabled in
                    try? model.setEnabled(enabled)
                })).disabled(!model.readable)
                Button("Stop work") { try? model.stopWork() }
                    .disabled(!model.readable || !model.accessEnabled)
                Text("Stops local connections and pending connection requests. You can enable access again later.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Each connection needs your approval. Permissions stay on this Mac and are not included in backups.")
                    .font(.caption).foregroundStyle(.secondary)
                #if DRAFTLY_AGENT_QA
                if AgentQAConfiguration.isActive {
                    Text(AgentApplicationSession.qaAdmissionDiagnostics)
                        .font(.caption).textSelection(.enabled)
                }
                #endif
                if let command = model.pairingCommand {
                    Button("Copy connection command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }.disabled(!model.accessEnabled)
                    Text("Run the command in Terminal, then compare the code shown here before approving.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
            if !model.pendingOperationReviews.isEmpty {
                Section("Operation requests") {
                    ForEach(model.pendingOperationReviews) { review in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(review.operation)
                                Text(model.connections.first(where: { $0.id == review.connectionID })?.name ?? "Local connection")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Review…") { operationReview = review }
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
                            if let configuration = model.mcpConfiguration(for: record.id) {
                                Button("Copy MCP configuration") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(configuration, forType: .string)
                                }
                            }
                            Button("Edit permissions…") { try? model.beginEditing(record.id) }.disabled(record.revoked || !model.readable)
                            Button(record.revoked ? "Clean up credential" : "Revoke access", role: .destructive) { try? model.revoke(record.id) }
                                .disabled(!model.readable)
                        }
                    }
                }
            }
            Section("Recent activity") {
                if let error = model.activityError {
                    Text("Some activity may be missing. " + error.connectionMessage).foregroundStyle(.red)
                }
                if model.activity.isEmpty && model.activityError == nil { Text("No recorded activity.").foregroundStyle(.secondary) }
                ForEach(model.activity.prefix(20)) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.operation + " · " + entry.result)
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened) + " · " +
                             (model.connections.first(where: { $0.id == entry.connectionID })?.name ?? "Connection " + entry.connectionID.uuidString))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Results describe responses. A failed response can require checking whether a change took effect.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear activity…", role: .destructive) { confirmClearActivity = true }
                    .disabled(model.activity.isEmpty && model.activityError == nil)
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
        .confirmationDialog("Clear activity for this library?", isPresented: $confirmClearActivity) {
            Button("Clear activity", role: .destructive) { try? model.clearActivity() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the local activity history for this library.") }
        .background(AgentGrantSheetPresenter(model: model))
        .sheet(item: $operationReview) { review in
            AgentOperationReviewSheet(model: model, review: review, dismiss: { operationReview = nil })
        }
        .task {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct AgentOperationReviewSheet: View {
    @ObservedObject var model: AgentConnectionsSettingsModel
    let review: AgentApprovalStore.Review
    let dismiss: () -> Void
    @State private var showTechnicalDetails = false

    private var destructiveButtonTitle: String? {
        switch review.operation {
        case "syntaxes.delete": "Delete Syntax"
        case "bookmarks.forget": "Forget Bookmark"
        case "themes.delete": "Delete Theme"
        case "workspaces.delete": "Delete Workspace"
        case "actions.delete": "Delete Action"
        case "actionGroups.delete": "Remove Group"
        default: nil
        }
    }

    private var nativeTitle: String? {
        if review.effects.snapshot["sourceImport"] == .bool(true) {
            return ["themes.install": "Download and Install Theme", "themes.replace": "Download and Replace Theme",
                "backups.validate": "Download Backup for Validation", "backups.previewRestore": "Download Backup for Preview"][review.operation] ?? "Download Input"
        }
        if review.operation == "actionGroups.delete" { return "Remove Action Group" }
        if review.operation == "bookmarks.requestAdd" { return "Add Folder Bookmark" }
        if review.operation == "imports.commit" { return "Import into Library" }
        if let destructiveButtonTitle { return destructiveButtonTitle }
        guard case .string(let operation) = review.effects.snapshot["nativeOperation"] else { return nil }
        switch operation {
        case "http": return "Make an HTTP request"
        case "clipboard": return "Copy text to the clipboard"
        case "getClipboard": return "Read the current clipboard"
        case "htmlToMarkdown": return "Convert HTML to Markdown"
        case "speak": return "Read text aloud"
        case "dictate": return "Record dictation"
        case "transcribe": return "Transcribe a selected audio file"
        case "location": return "Read the current location"
        case "shellScript": return "Run a Shell script"
        case "appleScript": return "Run AppleScript"
        case "shortcut": return "Run a Shortcut"
        case "htmlToClipboard": return "Copy formatted text to the clipboard"
        case "share": return "Share text"
        case "shareFile": return "Share a text file"
        case "print": return "Print text"
        case "openURL": return "Open a link"
        default: return nil
        }
    }

    private var nativeFields: [(String, String)] {
        if review.operation == "imports.commit", case .object(let changes) = review.effects.snapshot["changes"] {
            let labels = ["drafts": "Drafts", "versions": "Versions", "actions": "Actions", "actionGroups": "Action Groups",
                "workspaces": "Workspaces", "themes": "Themes", "syntaxes": "Syntaxes", "runs": "Action Runs"]
            return AgentBackupSchemas.collectionNames.compactMap { key in
                guard let title = labels[key], case .object(let counts) = changes[key],
                      case .integer(let added) = counts["created"], case .integer(let updated) = counts["updated"],
                      added > 0 || updated > 0 else { return nil }
                return (title, "\(added) added, \(updated) updated")
            }
        }
        if case .string(let name) = review.effects.snapshot["bookmarkName"] {
            if review.operation == "bookmarks.requestAdd" {
                return [("Bookmark", name), ("Effect", "Open a folder picker. Save access only if you select a folder.")]
            }
            if review.operation == "bookmarks.forget" {
                return [("Bookmark", name), ("Effect", "Remove the saved folder permission. Keep the folder and its files.")]
            }
        }
        if review.operation == "syntaxes.delete", case .string(let name) = review.effects.snapshot["syntaxName"] {
            return [("Syntax", name), ("Effect", "Delete the installed syntax and its saved file permission. Keep drafts and the source file.")]
        }
        if review.operation == "themes.delete", case .string(let name) = review.effects.snapshot["themeName"] {
            return [("Theme", name), ("Effect", "Delete the installed theme and its saved file permission. Keep drafts and the source file.")]
        }
        if review.operation == "workspaces.delete",
           case .string(let name) = review.effects.snapshot["workspaceName"] {
            return [("Workspace", name), ("Effect", "Delete the saved Workspace. Keep all drafts.")]
        }
        if review.operation == "actionGroups.delete", case .string(let name) = review.effects.snapshot["groupName"],
           case .string(let destination) = review.effects.snapshot["destination"],
           case .array(let actions) = review.effects.snapshot["actions"] {
            let names = actions.compactMap { item -> String? in
                guard case .object(let fields) = item, case .string(let name) = fields["name"] else { return nil }
                return name
            }
            return [("Group", name), ("Move actions to", destination), ("Actions", names.isEmpty ? "None" : names.joined(separator: "\n")),
                ("Effect", "Remove this group. Keep its actions, all drafts and action history.")]
        }
        if review.operation == "actions.delete", case .string(let name) = review.effects.snapshot["actionName"] {
            return [("Action", name), ("Effect", "Permanently delete this action. Keep all drafts and action history.")]
        }
        if review.operation == "drafts.purge", case .array(let drafts) = review.effects.snapshot["drafts"] {
            let names = drafts.compactMap { value -> String? in
                guard case .object(let fields) = value, case .string(let title) = fields["title"] else { return nil }
                return title
            }
            return [("Drafts", names.joined(separator: "\n")),
                ("Effect", "Permanently delete these trashed drafts and their versions. Keep action history. This cannot be undone.")]
        }
        guard case .object(let fields) = review.effects.snapshot["nativeParameters"] else { return [] }
        let rows = fields.keys.sorted().map { key in
            let value = fields[key]!
            let label = (key == "name" && review.effects.snapshot["nativeOperation"] == .string("shortcut")) ? "Shortcut" : ["text": "Text", "html": "HTML content", "name": "File name", "format": "Format", "template": "Template", "url": "URL", "source": "Source", "locale": "Language", "arguments": "Arguments", "argumentsJSON": "Arguments", "subroutine": "Subroutine", "waitForResponse": "Track completion", "method": "Method", "headersJSON": "Headers", "bodyText": "Body", "bodyBase64": "Body (Base64)", "timeout": "Timeout (seconds)", "followRedirects": "Follow redirects on this origin", "maximumBytes": "Maximum download bytes", "purpose": "Purpose"][key] ?? key
            if case .string(let text) = value { return (label, text) }
            let data = try? JSONEncoder().encode(value)
            return (label, data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unavailable")
        }
        if case .string(let operation) = review.effects.snapshot["nativeOperation"],
           ["shellScript", "shell", "appleScript", "shortcut"].contains(operation) {
            return [("Access", "Uses your macOS permissions and full library access.")] + rows
        }
        return rows
    }

    private var details: String? {
        func references(_ values: [AgentResourceReference]) -> AgentJSONValue {
            .array(values.sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }
                .map { .object(["kind": .string($0.kind.rawValue), "id": .string($0.id.uuidString)]) })
        }
        let value: AgentJSONValue = .object([
            "parameters": .object(review.parameters),
            "targets": references(review.targets),
            "expectedVersion": review.expectedVersion.map(AgentJSONValue.string) ?? .null,
            "effectTargets": references(Array(review.effects.targets)),
            "effectCapabilities": .array(review.effects.capabilities.map(\.rawValue).sorted().map(AgentJSONValue.string)),
            "requiresEntireLibrary": .bool(review.effects.requiresLibraryScope),
            "effectDetails": .object(review.effects.snapshot)
        ])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review operation").font(.headline)
            Text(nativeTitle ?? review.operation).font(.title3)
            Text((model.connections.first(where: { $0.id == review.connectionID })?.name ?? "Connection")
                 + " · " + review.connectionID.uuidString).textSelection(.enabled)
            Text("Expires " + review.expiresAt.formatted(date: .omitted, time: .standard))
                .foregroundStyle(.secondary)
            Text("Check the request and its effects before allowing it once.")
            if let details {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if nativeTitle != nil {
                            if review.effects.snapshot["nativeOperation"] == .string("getClipboard") {
                                Text("This Action will read the current clipboard before preparing its next step.")
                            }
                            ForEach(Array(nativeFields.enumerated()), id: \.offset) { _, field in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(field.0).font(.headline)
                                    Text(field.1).textSelection(.enabled)
                                }
                            }
                            DisclosureGroup("Technical details", isExpanded: $showTechnicalDetails) {
                                Text(details).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        } else {
                            Text(details).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("The request details cannot be displayed.").foregroundStyle(.red)
            }
            if let error = model.lastError { Text(error.connectionMessage).foregroundStyle(.red) }
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Stop work", role: .destructive) {
                    if (try? model.stopWork()) != nil { dismiss() }
                }.disabled(!model.readable || !model.accessEnabled)
                Spacer()
                Button("Deny", role: .destructive) {
                    if (try? model.decideOperation(review, approved: false)) != nil { dismiss() }
                }
                Group {
                    if let destructiveButtonTitle {
                        Button(destructiveButtonTitle, role: .destructive) {
                            if (try? model.decideOperation(review, approved: true)) != nil { dismiss() }
                        }
                    } else {
                        Button("Allow once") {
                            if (try? model.decideOperation(review, approved: true)) != nil { dismiss() }
                        }.keyboardShortcut(.defaultAction)
                    }
                }.disabled(details == nil || !model.pendingOperationReviews.contains { $0.id == review.id && $0.fingerprint == review.fingerprint })
            }
        }
        .padding(20).frame(minWidth: 520, minHeight: 400)
    }
}

private struct AgentGrantSheetPresenter: NSViewRepresentable {
    @ObservedObject var model: AgentConnectionsSettingsModel

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak view, weak model] in
            guard let model else { return }
            coordinator.update(parent: view?.window, model: model)
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.invalidate() }

    @MainActor final class Coordinator {
        private var panel: NSPanel?
        private var invalidated = false
        func update(parent: NSWindow?, model: AgentConnectionsSettingsModel) {
            guard !invalidated else { return }
            guard model.draft != nil else { close(); return }
            guard panel == nil, let parent else { return }
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620),
                                styleMask: [.titled], backing: .buffered, defer: false)
            panel.title = "Agent Permissions"
            panel.contentViewController = NSHostingController(rootView: AgentConnectionGrantEditor(model: model))
            self.panel = panel
            parent.beginSheet(panel)
        }
        func invalidate() { invalidated = true; close() }
        func close() {
            guard let panel else { return }
            self.panel = nil
            if let parent = panel.sheetParent { parent.endSheet(panel) }
            else { panel.orderOut(nil) }
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
                    Toggle(capability.userTitle + (model.availableCapabilities.contains(capability) ? "" : " (unavailable)"), isOn: Binding(get: { model.draft?.capabilities.contains(capability) == true }, set: { enabled in
                        guard var copy = model.draft else { return }
                        if enabled { copy.capabilities.insert(capability) } else { copy.capabilities.remove(capability) }
                        model.draft = copy
                    })).disabled(!model.availableCapabilities.contains(capability) && !draft.capabilities.contains(capability))
                }
                Text("Permissions do not approve individual destructive operations or native effects.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Some available permissions cover only part of their operation category.")
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
                if case .library = review.scope {
                    Label("Entire library, including future resources", systemImage: "exclamationmark.shield")
                        .foregroundStyle(.orange)
                }
                Text("Permissions").font(.headline)
                ForEach(review.capabilities.sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { Text($0.userTitle) }
                Text("Resources").font(.headline)
                switch review.scope {
                case .library: Text("Entire library, including future resources.")
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
