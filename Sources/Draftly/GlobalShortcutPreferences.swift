import AppKit
import SwiftUI
import DraftlyCore

struct GlobalShortcutPreferences: View {
    @ObservedObject var app: AppController
    @AppStorage(CommandShortcuts.storageKey) private var configuration = "{}"
    @State private var errors: [String: String] = [:]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(GlobalShortcuts.names, id: \.self) { name in
                GridRow {
                    Text(label(name)).gridColumnAlignment(.trailing)
                    HStack {
                        ShortcutCaptureButton(binding: CommandShortcuts.binding(name, configuration: configuration)) { binding in
                            save(name, binding)
                        }.frame(width: 180, height: 26)
                        Button("Clear") { save(name, CommandBinding(key: "", modifiers: [])) }
                            .help("Disable this global shortcut")
                    }
                }
                if let error = errors[name] ?? app.globalShortcutErrors[name] {
                    GridRow {
                        Text("")
                        Text(error).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 330, alignment: .leading)
                    }
                }
            }
        }
        .onChange(of: configuration) { _, _ in AppDelegate.current?.reloadGlobalShortcuts() }
    }

    private func label(_ name: String) -> String {
        switch name {
        case "Main Window": "Main window shortcut:"
        case "Quick Capture": "Quick capture shortcut:"
        default: "Capture clipboard shortcut:"
        }
    }

    private func save(_ name: String, _ binding: CommandBinding) {
        if let error = GlobalShortcuts.conflict(name: name, binding: binding, configuration: configuration,
                                               actions: app.library?.actions ?? []) {
            errors[name] = error
            return
        }
        var values = (try? JSONDecoder().decode([String: CommandBinding].self, from: Data(configuration.utf8))) ?? [:]
        values[name] = binding
        do {
            let data = try JSONEncoder().encode(values)
            configuration = String(decoding: data, as: UTF8.self)
            errors[name] = nil
        } catch { errors[name] = error.localizedDescription }
    }
}

private struct ShortcutCaptureButton: NSViewRepresentable {
    var binding: CommandBinding
    var record: (CommandBinding) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.begin))
        button.bezelStyle = .rounded
        context.coordinator.button = button
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.record = record
        context.coordinator.binding = binding
        if context.coordinator.monitor == nil { button.title = Self.title(binding) }
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) { coordinator.stop() }

    static func title(_ binding: CommandBinding) -> String {
        guard !binding.key.isEmpty else { return "Record Shortcut" }
        let flags = Set(binding.modifiers)
        return (flags.contains("control") ? "⌃" : "") + (flags.contains("option") ? "⌥" : "")
            + (flags.contains("shift") ? "⇧" : "") + (flags.contains("command") ? "⌘" : "") + binding.key.uppercased()
    }

    @MainActor final class Coordinator: NSObject {
        private static weak var active: Coordinator?
        private var resignObserver: NSObjectProtocol?
        weak var button: NSButton?
        var monitor: Any?
        var record: ((CommandBinding) -> Void)?
        var binding = CommandBinding(key: "", modifiers: [])

        @objc func begin() {
            if monitor != nil { stop(); return }
            Self.active?.stop()
            Self.active = self
            AppDelegate.current?.suspendGlobalShortcuts()
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: button?.window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stop() }
                }
            button?.title = "Type shortcut…"
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, event.window === self.button?.window else { return false }
                    if event.keyCode == 53 { self.stop(); return true }
                    if event.keyCode == 51 || event.keyCode == 117 {
                        self.stop(); self.record?(CommandBinding(key: "", modifiers: [])); return true
                    }
                    guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1,
                          key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return true }
                    var modifiers: [String] = []
                    for (flag, name): (NSEvent.ModifierFlags, String) in [(.command, "command"), (.control, "control"), (.option, "option"), (.shift, "shift")] {
                        if event.modifierFlags.contains(flag) { modifiers.append(name) }
                    }
                    self.stop()
                    self.record?(CommandBinding(key: key, modifiers: modifiers, keyCode: UInt32(event.keyCode)))
                    return true
                }
                return handled ? nil : event
            }
        }
        func stop() {
            let wasRecording = monitor != nil
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            resignObserver = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            button?.title = ShortcutCaptureButton.title(binding)
            if Self.active === self { Self.active = nil }
            if wasRecording { AppDelegate.current?.reloadGlobalShortcuts() }
        }
    }
}
