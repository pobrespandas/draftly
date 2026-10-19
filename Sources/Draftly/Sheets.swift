import SwiftUI
import DraftlyCore

struct ActionEditor: View {
    @State var action: DraftAction
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var selectedStep: UUID?
    private var shortcutConflict: String? { ActionShortcut.conflict(for: action, in: library.actions) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Action: " + action.name).font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(action.name.trimmingCharacters(in: .whitespaces).isEmpty || shortcutConflict != nil)
            }.padding(16)
            Divider()
            HSplitView {
                Form {
                    Section("Action") {
                        TextField("Name", text: $action.name)
                        TextField("Group", text: $action.group)
                        TextField("Description", text: $action.presentation.description, axis: .vertical).lineLimit(2...4)
                        TextField("SF Symbol", text: $action.symbol)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                            ForEach(["bolt", "doc.on.doc", "square.and.arrow.up", "folder", "checklist", "calendar", "envelope", "message", "terminal", "globe", "wand.and.stars", "pencil"], id: \.self) { symbol in
                                Button { action.symbol = symbol } label: { Image(systemName: symbol).frame(width: 24, height: 24).foregroundStyle(action.symbol == symbol ? Color.accentColor : .secondary) }.buttonStyle(.plain).help(symbol)
                            }
                        }
                        TextField("Section", text: $action.presentation.section)
                        Stepper("Order: \(action.presentation.order)", value: $action.presentation.order)
                    }
                    Section("Visibility") {
                        Toggle("Action List", isOn: $action.presentation.showInList)
                        Toggle("Editing Bar", isOn: $action.presentation.showInBar)
                        Toggle("Command Palette", isOn: $action.presentation.showInSearch)
                    }
                    Section("Execution") {
                        Toggle("Confirm Before Run", isOn: $action.presentation.confirmBeforeRun)
                        Toggle("Notify on Success", isOn: $action.presentation.notifyOnSuccess)
                        Toggle("Notify on Error", isOn: $action.presentation.notifyOnError)
                    }
                    Section("Keyboard Shortcut") {
                        TextField("Key", text: $action.shortcut)
                        ForEach(["command", "option", "control", "shift"], id: \.self) { modifier in
                            Toggle(modifier.capitalized, isOn: Binding(get: { (action.shortcutModifiers ?? ["command", "option"]).contains(modifier) }, set: { enabled in
                                var values = action.shortcutModifiers ?? ["command", "option"]
                                values.removeAll { $0 == modifier }; if enabled { values.append(modifier) }; action.shortcutModifiers = values
                            }))
                        }
                    }
                    if let shortcutConflict { Text(shortcutConflict).foregroundStyle(.red).font(.caption) }
                    Section("After Success") {
                        Picker("Move", selection: $action.afterSuccess) {
                            Text("Keep Draft").tag("none"); Text("Archive").tag("archive"); Text("Trash").tag("trash")
                        }
                    }
                    Section("After-success Tags and Flag") {
                        TextField("Add tags", text: Binding(get: { action.presentation.addTags.joined(separator: ", ") }, set: { action.presentation.addTags = TagRules.normalize($0.components(separatedBy: ",")) }))
                        TextField("Remove tags", text: Binding(get: { action.presentation.removeTags.joined(separator: ", ") }, set: { action.presentation.removeTags = TagRules.normalize($0.components(separatedBy: ",")) }))
                        Picker("Flag", selection: $action.presentation.flagAfterSuccess) {
                            Text("Keep Current").tag(Int?.none)
                            Text("Clear Flag").tag(Optional(0))
                            ForEach(1...7, id: \.self) { value in Text(flagName(value)).tag(Optional(value)) }
                        }
                    }
                    if !action.configuredValues.isEmpty {
                        Section("Configuration") {
                            ForEach(action.configuredValues.keys.sorted(), id: \.self) { key in
                                TextField(key, text: Binding(get: { action.configuredValues[key] ?? "" }, set: { action.configuredValues[key] = $0 }))
                            }
                        }
                    }
                }.formStyle(.grouped).frame(minWidth: 240, idealWidth: 270, maxWidth: 300)
                VStack(spacing: 0) {
                    HStack { Text("Steps").font(.headline); Spacer() }.padding(14)
                    Divider()
                    List(action.steps, selection: $selectedStep) { step in
                        HStack {
                            Image(systemName: DraftAction.supportedSteps.contains(step.type) ? "square.stack.3d.up" : "exclamationmark.triangle").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.type).font(.system(size: 12, weight: .medium))
                                if let template = step.values["template"] { Text(template).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                            }
                        }.padding(.vertical, 5).tag(step.id)
                    }.listStyle(.sidebar)
                    Divider()
                    HStack {
                        Menu {
                            ForEach(DraftAction.supportedSteps.sorted().filter { $0 != "configurationKey" }, id: \.self) { type in
                                Button(type) { let step = ActionStep(type, defaults(type)); action.steps.append(step); selectedStep = step.id }
                            }
                        } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).frame(width: 24)
                        Spacer()
                        Button { if let id = selectedStep { move(id, offset: -1) } } label: { Image(systemName: "arrow.up") }
                        Button { if let id = selectedStep { move(id, offset: 1) } } label: { Image(systemName: "arrow.down") }
                        Button {
                            if let id = selectedStep { action.steps.removeAll { $0.id == id }; selectedStep = action.steps.first?.id }
                        } label: { Image(systemName: "trash") }.disabled(selectedStep == nil)
                    }.buttonStyle(.borderless).padding(12)
                }.frame(minWidth: 180, idealWidth: 210, maxWidth: 260)
                if let index = action.steps.firstIndex(where: { $0.id == selectedStep }) {
                    ActionStepInspector(step: $action.steps[index]).frame(minWidth: 320, maxWidth: .infinity)
                } else {
                    ContentUnavailableView("Select a step", systemImage: "square.stack.3d.up").frame(minWidth: 320, maxWidth: .infinity)
                }
            }
            Divider()
            HStack {
                Button("Export Action…") { export() }
                Spacer()
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                else { Text("Unknown steps stay in the exported action.").font(.caption).foregroundStyle(.secondary) }
            }.padding(14)
        }.frame(width: 1000, height: 700).onAppear { selectedStep = action.steps.first?.id }
    }
    private func defaults(_ type: String) -> [String: String] {
        switch type {
        case "script": ["script": "// Write JavaScript here.\n", "allowAsync": "false"]
        case "runAppleScript": ["source": "return \"Hello\""]
        case "url", "callbackUrl": ["url": "https://example.com"]
        case "runShortcut", "includeAction": ["name": "", "template": "[[draft]]"]
        case "file": ["name": "[[safe_title]].md", "template": "[[draft]]"]
        default: ["template": "[[draft]]"]
        }
    }
    private func move(_ id: UUID, offset: Int) {
        guard let index = action.steps.firstIndex(where: { $0.id == id }), action.steps.indices.contains(index + offset) else { return }
        action.steps.swapAt(index, index + offset)
    }
    private func save() { guard shortcutConflict == nil else { return }; do { try library.saveAction(action); dismiss() } catch { self.error = error.localizedDescription } }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = action.name + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(action).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
}

private struct ActionStepInspector: View {
    @Binding var step: ActionStep
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit: " + step.type).font(.headline).padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !DraftAction.supportedSteps.contains(step.type) {
                        Label("Unsupported step · preserved on export", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(step.values.keys.filter { !["data", "parameters", "values", "uuid", "isEnabled", "platforms"].contains($0) }.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(key).font(.system(size: 12, weight: .medium))
                                Spacer()
                                if ["template", "script", "source"].contains(key) {
                                    Menu("Insert Tag") {
                                        ForEach(["draft", "title", "body", "selection", "date", "tags", "uuid"], id: \.self) { tag in
                                            Button("[[" + tag + "]]") { step.values[key, default: ""] += "[[" + tag + "]]" }
                                        }
                                    }.font(.caption).fixedSize()
                                }
                            }
                            if ["template", "script", "source"].contains(key) {
                                TextEditor(text: Binding(get: { step.values[key] ?? "" }, set: { step.values[key] = $0 }))
                                    .font(.system(size: 12, design: .monospaced)).frame(minHeight: key == "script" || key == "source" ? 360 : 180).border(.quaternary)
                            } else {
                                TextField(key, text: Binding(get: { step.values[key] ?? "" }, set: { step.values[key] = $0 })).textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }.padding(16)
            }
        }
    }
}

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

struct WorkspaceEditor: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tags = ""
    @State private var excludedTags = ""
    @State private var matchAnyTag = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Save Workspace").font(.title2.weight(.semibold))
            Text("Save the current draft view, search, sort order, and tag filters.").foregroundStyle(.secondary)
            TextField("Workspace name", text: $name).textFieldStyle(.roundedBorder)
            TextField("Included tags, separated by commas", text: $tags).textFieldStyle(.roundedBorder)
            TextField("Excluded tags, separated by commas", text: $excludedTags).textFieldStyle(.roundedBorder)
            Toggle("Match any included tag", isOn: $matchAnyTag)
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") {
                var w = Workspace(name: name); w.folder = model.folder; w.query = model.query; w.sort = model.sort; w.ascending = model.ascending
                w.tagged = model.tagPresence; w.listOptions = model.listOptions
                w.tags = TagRules.normalize(tags.split(separator: ",").map(String.init))
                w.excludedTags = TagRules.normalize(excludedTags.split(separator: ",").map(String.init))
                w.matchAnyTag = matchAnyTag
                model.perform { try library.saveWorkspace(w); model.apply(w); dismiss() }
            }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(24).frame(width: 450).onAppear {
            tags = model.activeTagFilters.joined(separator: ", ")
            excludedTags = model.excludedTagFilters.joined(separator: ", ")
            matchAnyTag = model.matchAnyTag
        }
    }
}

struct HistoryView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var library: LibraryStore
    var noteID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    var revisions: [Revision] { library.revisions.filter { $0.noteID == noteID } }
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("Revision History").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            HSplitView {
                List(revisions, selection: $selected) { revision in
                    VStack(alignment: .leading) { Text(revision.date, format: .dateTime.month().day().hour().minute().second()); Text("\(revision.content.count) characters").font(.caption).foregroundStyle(.secondary) }.tag(revision.id)
                }.frame(width: 200)
                if let revision = revisions.first(where: { $0.id == selected }) {
                    ScrollView { Text(revision.content).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                } else { ContentUnavailableView("Select a revision", systemImage: "clock.arrow.circlepath") }
            }
            HStack {
                Text("Each saved content change keeps a revision.").font(.caption).foregroundStyle(.secondary); Spacer()
                Button("Restore Revision") {
                    guard let revision = revisions.first(where: { $0.id == selected }) else { return }
                    model.restoreRevision(revision)
                    if library.error == nil { dismiss() }
                }.disabled(selected == nil)
            }
        }.padding(20).frame(width: 780, height: 560).onAppear { model.flush(); selected = revisions.first?.id }
    }
}

struct RunLogView: View {
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            HStack { Text("Execution History").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding()
            List(library.runs) { run in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(run.actionName).bold(); Spacer(); Text(run.status).foregroundStyle(run.status == "Error" ? .red : .secondary); Text(run.date, style: .time).foregroundStyle(.secondary) }
                    if !run.message.isEmpty { Text(run.message).font(.caption).textSelection(.enabled) }
                }.padding(.vertical, 5)
            }
        }.frame(width: 680, height: 460)
    }
}

struct MergeDraftsView: View {
    @ObservedObject var model: WindowModel
    let request: WindowModel.MergeRequest
    var body: some View {
        MergeDialogContent(cancel: { model.mergeRequest = nil }, merge: { separator, blankLine, destination in
            model.confirmMerge(request, separator: separator, includeBlankLine: blankLine, destination: destination)
        }).frame(width: 400, height: 354)
    }
}

private struct MergeDialogContent: NSViewRepresentable {
    let cancel: () -> Void
    let merge: (String, Bool, MergeDestination) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(cancel: cancel, merge: merge) }
    func makeNSView(context: Context) -> NSView {
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 354))
        let coordinator = context.coordinator
        func label(_ text: String, _ rect: NSRect, size: CGFloat = 13, color: NSColor = .labelColor) {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: size); label.textColor = color
            label.frame = rect; view.addSubview(label)
        }
        let icon = NSImageView(frame: NSRect(x: 22, y: 23, width: 24, height: 32))
        icon.image = NSImage(systemSymbolName: "arrow.triangle.merge", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 28, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        view.addSubview(icon)
        let title = NSTextField(labelWithString: "Merge Drafts")
        title.font = .boldSystemFont(ofSize: 16); title.frame = NSRect(x: 54, y: 31, width: 300, height: 22)
        view.addSubview(title)
        let divider = NSBox(frame: NSRect(x: 22, y: 61, width: 356, height: 1))
        divider.boxType = .separator; view.addSubview(divider)
        label("Selected drafts will be merged into one draft, in the order selected. Enter separator, or leave blank for new line.",
              NSRect(x: 20, y: 76, width: 360, height: 34))
        label("Separator", NSRect(x: 20, y: 131, width: 60, height: 16), size: 11, color: .secondaryLabelColor)
        let field = coordinator.field
        field.frame = NSRect(x: 82, y: 125, width: 294, height: 24)
        field.bezelStyle = .roundedBezel; field.font = .systemFont(ofSize: 13)
        field.setAccessibilityLabel("Separator"); field.delegate = coordinator
        view.addSubview(field)
        label("After merge move originals to:", NSRect(x: 20, y: 160, width: 360, height: 18), color: .secondaryLabelColor)
        let picker = coordinator.picker
        picker.frame = NSRect(x: 21, y: 183, width: 232, height: 24)
        picker.segmentCount = 3; picker.segmentStyle = .rounded
        picker.trackingMode = .selectOne; picker.font = .systemFont(ofSize: 12)
        for (index, destination) in MergeDestination.allCases.enumerated() {
            picker.setLabel(destination.rawValue, forSegment: index)
        }
        picker.setWidth(70, forSegment: 0); picker.setWidth(58, forSegment: 1); picker.setWidth(102, forSegment: 2)
        picker.selectedSegment = 0
        picker.setAccessibilityLabel("After merge move originals to")
        view.addSubview(picker)
        let checkbox = coordinator.checkbox
        checkbox.frame = NSRect(x: 22, y: 216, width: 250, height: 18)
        checkbox.font = .systemFont(ofSize: 11); checkbox.controlSize = .small
        checkbox.isEnabled = false; view.addSubview(checkbox)
        let cancel = NSButton(title: "Cancel", target: coordinator, action: #selector(Coordinator.cancelClicked))
        cancel.frame = NSRect(x: 230, y: 304, width: 70, height: 28)
        cancel.bezelStyle = .rounded; cancel.controlSize = .large; cancel.font = .systemFont(ofSize: 13)
        cancel.keyEquivalent = "\u{1b}"; view.addSubview(cancel)
        let merge = NSButton(title: "Merge", target: coordinator, action: #selector(Coordinator.mergeClicked))
        merge.frame = NSRect(x: 308, y: 304, width: 70, height: 28)
        merge.bezelStyle = .rounded; merge.controlSize = .large; merge.font = .systemFont(ofSize: 13)
        merge.keyEquivalent = "\r"; view.addSubview(merge)
        view.initialField = field
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class FlippedView: NSView {
        weak var initialField: NSTextField?
        override var isFlipped: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let initialField else { return }
            window.initialFirstResponder = initialField
            DispatchQueue.main.async { [weak self] in
                guard let self, let field = self.initialField else { return }
                self.window?.makeFirstResponder(field)
            }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        let field = NSTextField(string: "")
        let picker = NSSegmentedControl()
        let checkbox = NSButton(checkboxWithTitle: "Include blank line", target: nil, action: nil)
        let cancel: () -> Void
        let merge: (String, Bool, MergeDestination) -> Void
        init(cancel: @escaping () -> Void, merge: @escaping (String, Bool, MergeDestination) -> Void) {
            self.cancel = cancel; self.merge = merge
        }
        func controlTextDidChange(_ obj: Notification) { checkbox.isEnabled = !field.stringValue.isEmpty }
        @objc func cancelClicked() { cancel() }
        @objc func mergeClicked() {
            merge(field.stringValue, checkbox.state == .on, MergeDestination.allCases[max(0, picker.selectedSegment)])
        }
    }
}
