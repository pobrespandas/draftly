import SwiftUI
import AppKit
@_spi(ActionEditing) import DraftlyCore

struct ActionEditor: View {
    @State private var editingCopy: ActionEditingCopy
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    init(action: DraftAction, library: LibraryStore) {
        _editingCopy = State(initialValue: ActionEditingCopy(action: action))
        self.library = library
    }

    private var shortcutConflict: String? { ActionShortcut.conflict(for: editingCopy.action, in: library.actions) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Action: " + editingCopy.action.name).font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(editingCopy.action.name.trimmingCharacters(in: .whitespaces).isEmpty || shortcutConflict != nil)
            }.padding(16)
            Divider()
            HSplitView {
                Form {
                    Section("Action") {
                        TextField("Name", text: $editingCopy.action.name)
                        TextField("Group", text: $editingCopy.action.group)
                        TextField("Description", text: $editingCopy.action.presentation.description, axis: .vertical).lineLimit(2...4)
                        ActionSymbolPicker(symbol: $editingCopy.action.symbol)
                        Picker("Color", selection: Binding(get: { editingCopy.action.presentation.tintColor ?? "" },
                            set: { editingCopy.action.presentation.tintColor = $0.isEmpty ? nil : $0 })) {
                            Text("Default").tag("")
                            ForEach(ActionTint.names, id: \.self) { Text($0.capitalized).tag($0) }
                            if let name = editingCopy.action.presentation.tintColor, !ActionTint.names.contains(name) {
                                Text(name).tag(name)
                            }
                        }
                        TextField("Section", text: $editingCopy.action.presentation.section)
                        Stepper("Order: \(editingCopy.action.presentation.order)", value: $editingCopy.action.presentation.order)
                    }
                    Section("Editing Bar") {
                        TextField("Label", text: Binding(get: { editingCopy.action.presentation.barLabel ?? "" },
                            set: { editingCopy.action.presentation.barLabel = $0 }))
                        Toggle("Show Icon", isOn: Binding(get: { editingCopy.action.presentation.barUsesIcon ?? true },
                            set: { editingCopy.action.presentation.barUsesIcon = $0 }))
                    }
                    Section("Visibility") {
                        Toggle("Action List", isOn: $editingCopy.action.presentation.showInList)
                        Toggle("Editing Bar", isOn: $editingCopy.action.presentation.showInBar)
                        Toggle("Command Palette", isOn: $editingCopy.action.presentation.showInSearch)
                    }
                    Section("Execution") {
                        Toggle("Confirm Before Run", isOn: $editingCopy.action.presentation.confirmBeforeRun)
                        Toggle("Notify on Success", isOn: $editingCopy.action.presentation.notifyOnSuccess)
                        Toggle("Notify on Error", isOn: $editingCopy.action.presentation.notifyOnError)
                        Picker("Log Level", selection: Binding(get: { editingCopy.action.presentation.logLevel ?? 2 },
                            set: { editingCopy.action.presentation.logLevel = $0 })) {
                            Text("None").tag(0)
                            Text("Errors").tag(1)
                            Text("All").tag(2)
                            if let level = editingCopy.action.presentation.logLevel, !(0...2).contains(level) {
                                Text("Unknown (\(level))").tag(level)
                            }
                        }
                    }
                    Section("Keyboard Shortcut") {
                        TextField("Key", text: $editingCopy.action.shortcut)
                        ForEach(["command", "option", "control", "shift"], id: \.self) { modifier in
                            Toggle(modifier.capitalized, isOn: Binding(get: { (editingCopy.action.shortcutModifiers ?? ["command", "option"]).contains(modifier) }, set: { enabled in
                                var values = editingCopy.action.shortcutModifiers ?? ["command", "option"]
                                values.removeAll { $0 == modifier }; if enabled { values.append(modifier) }; editingCopy.action.shortcutModifiers = values
                            }))
                        }
                    }
                    if let shortcutConflict { Text(shortcutConflict).foregroundStyle(.red).font(.caption) }
                    Section("After Success") {
                        Picker("Move", selection: $editingCopy.action.afterSuccess) {
                            Text("Keep Draft").tag("none"); Text("Archive").tag("archive"); Text("Trash").tag("trash")
                        }
                    }
                    Section("After-success Tags and Flag") {
                        TextField("Add tags", text: Binding(get: { editingCopy.action.presentation.addTags.joined(separator: ", ") }, set: { editingCopy.action.presentation.addTags = TagRules.normalize($0.components(separatedBy: ",")) }))
                        TextField("Remove tags", text: Binding(get: { editingCopy.action.presentation.removeTags.joined(separator: ", ") }, set: { editingCopy.action.presentation.removeTags = TagRules.normalize($0.components(separatedBy: ",")) }))
                        Picker("Flag", selection: $editingCopy.action.presentation.flagAfterSuccess) {
                            Text("Keep Current").tag(Int?.none)
                            Text("Clear Flag").tag(Optional(0))
                            ForEach(1...7, id: \.self) { value in Text(flagName(value)).tag(Optional(value)) }
                        }
                    }
                    if !editingCopy.action.configuredValues.isEmpty {
                        Section("Configuration") {
                            ForEach(editingCopy.action.configuredValues.keys.sorted(), id: \.self) { key in
                                TextField(key, text: Binding(get: { editingCopy.action.configuredValues[key] ?? "" }, set: { editingCopy.action.configuredValues[key] = $0 }))
                            }
                        }
                    }
                }.formStyle(.grouped).frame(minWidth: 240, idealWidth: 270, maxWidth: 300)
                VStack(spacing: 0) {
                    HStack { Text("Steps").font(.headline); Spacer() }.padding(14)
                    Divider()
                    List(editingCopy.action.steps, selection: $editingCopy.selectedStep) { step in
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
                            ForEach(DraftAction.supportedSteps.sorted(), id: \.self) { type in
                                Button(type) { editingCopy.addStep(type) }
                            }
                        } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).frame(width: 24)
                        Spacer()
                        Button { editingCopy.moveSelectedStep(offset: -1) } label: { Image(systemName: "arrow.up") }
                        Button { editingCopy.moveSelectedStep(offset: 1) } label: { Image(systemName: "arrow.down") }
                        Button {
                            editingCopy.removeSelectedStep()
                        } label: { Image(systemName: "trash") }.disabled(editingCopy.selectedStep == nil)
                    }.buttonStyle(.borderless).padding(12)
                }.frame(minWidth: 180, idealWidth: 210, maxWidth: 260)
                if let index = editingCopy.action.steps.firstIndex(where: { $0.id == editingCopy.selectedStep }) {
                    ActionStepInspector(step: $editingCopy.action.steps[index]).frame(minWidth: 320, maxWidth: .infinity)
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
        }.frame(width: 1000, height: 700).onAppear { editingCopy.selectFirstStep() }
    }
    private func save() { guard shortcutConflict == nil else { return }; do { try library.saveAction(editingCopy.action); dismiss() } catch { self.error = error.localizedDescription } }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = editingCopy.action.name + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(editingCopy.action).write(to: url, options: .atomic) }
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
                    if let limitation = ActionStepInspectorFields.limitation(for: step) {
                        Text(limitation).font(.caption).foregroundStyle(.secondary)
                    }
                    if step.type == "configurationKey" {
                        ActionConfigurationStepEditor(step: $step)
                    }
                    if step.type == "configureWindow" {
                        ActionWindowConfigurationEditor(step: $step)
                    }
                    if step.type == "prompt" {
                        Toggle("Include Text Field", isOn: Binding(
                            get: { ActionStepValueRules.promptIncludesTextField(step.values) },
                            set: { step.values["includeTextField"] = $0 ? "true" : "false" }
                        ))
                        Toggle("Include Cancel Button", isOn: Binding(
                            get: { ActionStepValueRules.promptIncludesCancelButton(step.values) },
                            set: { step.values["includeCancelButton"] = $0 ? "true" : "false" }
                        ))
                    }
                    if step.type == "createDraft" {
                        Toggle("Open in Editor", isOn: Binding(
                            get: { ActionStepValueRules.createdDraftOpensInEditor(step.values) },
                            set: { step.values["openInEditor"] = $0 ? "true" : "false" }
                        ))
                    }
                    ForEach(ActionStepInspectorFields.fields(for: step)) { field in
                        let key = field.key
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(ActionStepInspectorFields.title(for: key, in: step)).font(.system(size: 12, weight: .medium))
                                Spacer()
                                if field.allowsTagInsertion {
                                    Menu("Insert Tag") {
                                        ForEach(["draft", "title", "body", "selection", "date", "tags", "uuid"], id: \.self) { tag in
                                            Button("[[" + tag + "]]") { ActionStepInspectorFields.appendTag(tag, for: key, in: &step) }
                                        }
                                    }.font(.caption).fixedSize()
                                }
                            }
                            if step.type == "includeAction" && key == "uuid" {
                                Text("An Action UUID takes precedence over the name. Leave it empty to use the name template.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if case .toggle = field.control {
                                Toggle(ActionStepInspectorFields.title(for: key, in: step), isOn: Binding(
                                    get: { ActionStepInspectorFields.toggleValue(for: field, in: step) },
                                    set: { step.values[key] = $0 ? "true" : "false" }
                                ))
                            } else if case .choice(let options) = field.control {
                                Picker(ActionStepInspectorFields.title(for: key, in: step), selection: Binding(
                                    get: { ActionStepInspectorFields.textValue(for: key, in: step) },
                                    set: { step.values[key] = $0 }
                                )) {
                                    ForEach(options, id: \.self) { option in
                                        Text(option.isEmpty ? "Use Flagged Option" : option).tag(option)
                                    }
                                    let current = ActionStepInspectorFields.textValue(for: key, in: step)
                                    if !options.contains(current) { Text(current).tag(current) }
                                }
                            } else if field.isMultiline {
                                TextEditor(text: Binding(get: { ActionStepInspectorFields.textValue(for: key, in: step) }, set: { step.values[key] = $0 }))
                                    .font(.system(size: 12, design: .monospaced)).frame(minHeight: field.minHeight).border(.quaternary)
                            } else {
                                TextField(key, text: Binding(get: { ActionStepInspectorFields.textValue(for: key, in: step) }, set: { step.values[key] = $0 })).textFieldStyle(.roundedBorder)
                                if field.control == .number {
                                    Stepper("Adjust points", onIncrement: { adjustNumber(key, by: 1) }, onDecrement: { adjustNumber(key, by: -1) })
                                    if let value = Double(ActionStepInspectorFields.textValue(for: key, in: step)), value.isFinite, value >= 0 {
                                        Text("Points").font(.caption).foregroundStyle(.secondary)
                                    } else { Text("Enter a finite nonnegative number.").font(.caption).foregroundStyle(.red) }
                                }
                            }
                        }
                    }
                }.padding(16)
            }
        }
    }
    private func adjustNumber(_ key: String, by amount: Double) {
        guard let value = Double(ActionStepInspectorFields.textValue(for: key, in: step)), value.isFinite else { return }
        step.values[key] = String(max(0, value + amount))
    }
}

private struct ActionConfigurationStepEditor: View {
    @Binding var step: ActionStep

    private func value(_ key: String, fallback: String = "") -> Binding<String> {
        Binding(get: { step.values[key] ?? fallback }, set: { step.values[key] = $0 })
    }
    private var type: String { step.values["dataType"] ?? "string" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Key", text: value("key"))
            TextField("Name", text: value("name"))
            TextField("Description", text: value("description"), axis: .vertical)
            Picker("Value Type", selection: value("dataType", fallback: "string")) {
                ForEach(ActionStepInspectorFields.configurationTypes, id: \.self) { type in
                    Text(type.capitalized).tag(type)
                }
                if !ActionStepInspectorFields.configurationTypes.contains(type) {
                    Text("Unknown (" + type + ")").tag(type)
                }
            }
            if let key = ActionStepInspectorFields.configurationDefaultKey(for: type) {
                if type == "boolean" {
                    Toggle("Default Value", isOn: Binding(
                        get: { ActionStepValueRules.configurationBooleanValue(step.values[key]) },
                        set: { step.values[key] = $0 ? "true" : "false" }
                    ))
                } else if type == "text" {
                    Text("Default Value")
                    TextEditor(text: value(key)).frame(minHeight: 120)
                } else {
                    TextField("Default Value", text: value(key))
                }
            }
            // Keep the imported fallback separate from the type-specific default.
            if step.values["defaultValue"] != nil {
                TextField("Imported Default Value", text: value("defaultValue"))
                Text("Imported Default Value overrides the type-specific default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Example Value", text: value("exampleValue"))
            Toggle("Requires Configuration", isOn: Binding(
                get: { ActionStepValueRules.requiresInitialConfiguration(step.values) },
                set: { step.values["requiresInitialConfiguration"] = $0 ? "true" : "false" }
            ))
        }.textFieldStyle(.roundedBorder)
    }
}

private struct ActionWindowConfigurationEditor: View {
    @Binding var step: ActionStep

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(WindowConfigurationOptions.toggleKeys, id: \.self) { key in
                let selected = WindowConfigurationOptions.selectionValue(step.values[key])
                Picker(WindowConfigurationOptions.title(for: key), selection: Binding(
                    get: { WindowConfigurationOptions.selectionValue(step.values[key]) },
                    set: { step.values[key] = $0 == "unchanged" ? nil : $0 }
                )) {
                    Text("Unchanged").tag("unchanged")
                    Text("On").tag("true")
                    Text("Off").tag("false")
                    if !["unchanged", "true", "false"].contains(selected) {
                        Text("Imported (" + selected + ")").tag(selected)
                    }
                }
            }
        }
    }
}
