import SwiftUI
import DraftlyCore

private struct CommandKeyModifier: ViewModifier {
    let name: String
    @AppStorage("commands.bindings") private var configuration = "{}"
    func body(content: Content) -> some View {
        let binding = CommandShortcuts.binding(name, configuration: configuration)
        if let key = binding.key.first {
            content.keyboardShortcut(KeyEquivalent(key), modifiers: shortcutModifiers(binding.modifiers))
        } else { content }
    }
}

extension View {
    func commandShortcut(_ name: String) -> some View { modifier(CommandKeyModifier(name: name)) }
}

private func shortcutModifiers(_ values: [String]) -> EventModifiers {
    var modifiers: EventModifiers = []
    for value in values {
        switch value { case "command": modifiers.insert(.command); case "option": modifiers.insert(.option); case "control": modifiers.insert(.control); case "shift": modifiers.insert(.shift); default: break }
    }
    return modifiers
}

struct ShortcutPreferences: View {
    @AppStorage("commands.bindings") private var configuration = "{}"
    @ObservedObject var app: AppController
    @State private var selected = "New Draft"
    @State private var key = "n"
    @State private var modifiers = ["command"]
    @State private var storedBinding: CommandBinding?
    @State private var editError: String?
    private var conflict: String? {
        if key.isEmpty { return nil }
        var action = DraftAction(name: "Command", steps: []); action.shortcut = key; action.shortcutModifiers = modifiers
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter one key." }
        return ActionShortcut.conflict(for: action, in: app.library?.actions ?? [], commands: CommandShortcuts.bindings(configuration: configuration).filter { $0.0 != selected })
    }
    var body: some View {
        let recordingCommand = selected
        Section("Keyboard Shortcuts") {
            Picker("Command", selection: $selected) { ForEach(CommandShortcuts.editable.filter { !GlobalShortcuts.names.contains($0) }, id: \.self) { Text($0).tag($0) } }
                .onChange(of: selected) { _, _ in load() }
            ShortcutCaptureButton(binding: CommandBinding(key: key, modifiers: modifiers)) { binding in
                guard selected == recordingCommand else { return }
                key = binding.key
                modifiers = binding.modifiers
                storedBinding = binding
            }
            .id(recordingCommand)
            .frame(width: 180, height: 26)
            TextField("Key", text: $key)
            HStack {
                ForEach(["command", "option", "control", "shift"], id: \.self) { name in
                    Toggle(name.capitalized, isOn: Binding(get: { modifiers.contains(name) }, set: { enabled in modifiers.removeAll { $0 == name }; if enabled { modifiers.append(name) } }))
                }
            }
            if let conflict { Text(conflict).foregroundStyle(.red).font(.caption) }
            if let editError { Text(editError).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Save Shortcut") {
                    let physicalKey = storedBinding?.key.lowercased() == key.lowercased()
                        && Set(storedBinding?.modifiers ?? []) == Set(modifiers) ? storedBinding?.keyCode : nil
                    save(CommandBinding(key: key.lowercased(), modifiers: modifiers, keyCode: physicalKey))
                }.disabled(conflict != nil)
                Button("Clear Shortcut") { save(CommandBinding(key: "", modifiers: [])) }
                Button("Reset Command") { save(nil) }
            }
            Text("Configure global shortcuts in General. Standard macOS editing shortcuts remain fixed.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { load() }
    }
    private func save(_ binding: CommandBinding?) {
        do {
            configuration = try SettingsOptionEditing.command(selected, binding: binding, configuration: configuration)
            editError = nil
            load()
        } catch { editError = "The shortcut could not be saved: " + error.localizedDescription }
    }
    private func load() {
        let value = CommandShortcuts.binding(selected, configuration: configuration)
        key = value.key; modifiers = value.modifiers; storedBinding = value
    }
}
