import SwiftUI
import AppKit
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
                        Picker("Color", selection: Binding(get: { action.presentation.tintColor ?? "" },
                            set: { action.presentation.tintColor = $0.isEmpty ? nil : $0 })) {
                            Text("Default").tag("")
                            ForEach(ActionTint.names, id: \.self) { Text($0.capitalized).tag($0) }
                            if let name = action.presentation.tintColor, !ActionTint.names.contains(name) {
                                Text(name).tag(name)
                            }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                            ForEach(["bolt", "doc.on.doc", "square.and.arrow.up", "folder", "checklist", "calendar", "envelope", "message", "terminal", "globe", "wand.and.stars", "pencil"], id: \.self) { symbol in
                                Button { action.symbol = symbol } label: { Image(systemName: symbol).frame(width: 24, height: 24).foregroundStyle(action.symbol == symbol ? Color.accentColor : .secondary) }.buttonStyle(.plain).help(symbol)
                            }
                        }
                        TextField("Section", text: $action.presentation.section)
                        Stepper("Order: \(action.presentation.order)", value: $action.presentation.order)
                    }
                    Section("Editing Bar") {
                        TextField("Label", text: Binding(get: { action.presentation.barLabel ?? "" },
                            set: { action.presentation.barLabel = $0 }))
                        Toggle("Show Icon", isOn: Binding(get: { action.presentation.barUsesIcon ?? true },
                            set: { action.presentation.barUsesIcon = $0 }))
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
                        Picker("Log Level", selection: Binding(get: { action.presentation.logLevel ?? 2 },
                            set: { action.presentation.logLevel = $0 })) {
                            Text("None").tag(0)
                            Text("Errors").tag(1)
                            Text("All").tag(2)
                            if let level = action.presentation.logLevel, !(0...2).contains(level) {
                                Text("Unknown (\(level))").tag(level)
                            }
                        }
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
                                if step.isEnabled == false { Text("Disabled").font(.caption2).foregroundStyle(.secondary) }
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
                    Toggle("Enabled", isOn: Binding(
                        get: { step.isEnabled != false },
                        set: { step.isEnabled = $0 }
                    ))
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
