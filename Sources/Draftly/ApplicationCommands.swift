import SwiftUI
import AppKit
import DraftlyCore

struct DraftlyCommands: Commands {
    @FocusedValue(\.windowModel) private var focusedModel
    @ObservedObject private var controller = AppController.shared
    @Environment(\.openWindow) private var openWindow
    private var model: WindowModel? {
        focusedModel ?? controller.commandWindow
    }
    var body: some Commands {
        if let model { WindowCommands(model: model) }
        else {
            CommandGroup(replacing: .newItem) {
                Button("New Draft") { AppController.shared.newDraft() }.commandShortcut("New Draft")
                Button("Quick Capture") { AppController.shared.capture() }.keyboardShortcut("n", modifiers: [.command, .control, .option])
                Button("New Window") { openWindow(id: "library") }.commandShortcut("New Window")
            }
        }
    }
}

private struct WindowCommands: Commands {
    @ObservedObject var model: WindowModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Draft") { model.create() }.commandShortcut("New Draft")
            Button("Quick Capture") { AppController.shared.capture() }.keyboardShortcut("n", modifiers: [.command, .control, .option])
            Button("New Window") { openWindow(id: "library") }.commandShortcut("New Window")
            Divider()
            Button("Import…") { model.importFile() }.commandShortcut("Import")
            Button("Export Draft…") { model.exportNote() }.disabled(model.currentNote == nil)
            Button("Export Full Backup…") { model.exportBackup() }
        }
        CommandGroup(after: .toolbar) {
            Button(model.showFilters ? "Hide Filters" : "Show Filters") { model.toggleFilters() }.commandShortcut("Filters")
            Button(model.showDraftList ? "Hide Draft List" : "Show Draft List") { model.toggleDraftList() }.commandShortcut("Draft List")
            Button("Toggle Actions") { model.showActions.toggle() }.commandShortcut("Actions")
            Button("Command Palette…") { AppController.shared.showCommandPalette() }.commandShortcut("Command Palette")
            Button("Quick Search…") { AppController.shared.showQuickSearch() }.commandShortcut("Quick Search")
            Button("Markdown Preview") { model.preview() }.commandShortcut("Markdown Preview")
            Button("Revision History…") { model.showHistory = true }
        }
        if Bundle.main.object(forInfoDictionaryKey: "DraftlyUITesting") as? Bool == true {
            CommandMenu("Visual QA") {
                ForEach(["1033 × 734", "1200 × 800", "850 × 600"], id: \.self) { size in
                    Button(size) {
                        let values = size.components(separatedBy: " × ").compactMap(Double.init)
                        guard values.count == 2, let window = model.window else { return }
                        var frame = window.frame
                        frame.size = NSSize(width: values[0], height: values[1])
                        window.setFrame(frame, display: true)
                    }
                }
                Divider()
                Button("Light") { model.darkTheme = false }
                Button("Dark") { model.darkTheme = true }
                Button("Open Status Menu") { AppDelegate.current?.openStatusMenuForTesting() }
            }
        }
        CommandMenu("Actions") {
            Button("New Action…") { model.editingAction = DraftAction(name: "New Action", steps: [ActionStep("script", ["script": ""])]) }
            Button("Import from Directory…") { model.showActionImporter = true }
            Button("Execution History…") { model.showRunLog = true }
            Button("Manage Actions and Workspaces…") { model.showLibraryManagement = true }
            Divider()
            ForEach(model.library.orderedActions()) { action in
                if ActionShortcut.conflict(for: action, in: model.library.actions) == nil,
                   let key = ActionShortcut(action).key.first {
                    Button(action.name) { model.run(action) }.keyboardShortcut(KeyEquivalent(key), modifiers: modifiers(action))
                } else { Button(action.name) { model.run(action) } }
            }
        }
    }
    private func modifiers(_ action: DraftAction) -> SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        for name in ActionShortcut(action).modifiers {
            switch name { case "command": result.insert(.command); case "option": result.insert(.option); case "control": result.insert(.control); case "shift": result.insert(.shift); default: break }
        }
        return result
    }
}
