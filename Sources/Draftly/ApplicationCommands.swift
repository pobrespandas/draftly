import SwiftUI
import AppKit
import DraftlyCore

struct DraftlyCommands: Commands {
    @FocusedValue(\.windowModel) private var focusedModel
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow
    private var model: WindowModel? {
        focusedModel ?? controller.commandWindow
    }
    var body: some Commands {
        if let model { WindowCommands(controller: controller, model: model) }
        else {
            CommandGroup(replacing: .newItem) {
                Button("New Draft") { controller.newDraft() }.commandShortcut("New Draft")
                Button("Quick Capture") { controller.capture() }.keyboardShortcut("n", modifiers: [.command, .control, .option])
                Button("New Window") { openWindow(id: "library") }.commandShortcut("New Window")
            }
        }
    }
}

struct LibraryApplicationCommands: Commands {
    @ObservedObject var library: LibraryStore
    var models: () -> [WindowModel]
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button {
                openSettings()
            } label: { Label("Settings…", systemImage: "gearshape") }
            .keyboardShortcut(",", modifiers: .command)
            Button {
                UserDefaults.standard.set("editor", forKey: "settings.selectedTab")
                openSettings()
            } label: { Label("Editor Settings…", systemImage: "textformat") }
            .keyboardShortcut(",", modifiers: [.command, .option])
            Divider()
            Button("Library Summary") {
                let alert = NSAlert()
                alert.messageText = "Library Summary"
                alert.informativeText = LibrarySummary(library: library).text
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            Divider()
            Button {
                do { _ = try LibraryTrashCommand.run(library: library, models: models()) }
                catch { NSApp.presentError(error) }
            } label: { Label("Empty Trash", systemImage: "trash") }
            .disabled(!library.notes.contains { $0.trashedAt != nil })
        }
    }
}

@MainActor
struct LibrarySummary {
    let inbox: Int
    let archive: Int
    let trash: Int
    let revisions: Int
    let actions: Int
    let workspaces: Int

    init(library: LibraryStore) {
        inbox = library.notes.filter { $0.trashedAt == nil && !$0.isArchived }.count
        archive = library.notes.filter { $0.trashedAt == nil && $0.isArchived }.count
        trash = library.notes.filter { $0.trashedAt != nil }.count
        revisions = library.revisions.count
        actions = library.actions.count
        workspaces = library.workspaces.count
    }

    var text: String {
        "Inbox: \(inbox)\nArchive: \(archive)\nTrash: \(trash)\n\nVersions: \(revisions)\nActions: \(actions)\nWorkspaces: \(workspaces)"
    }
}

private struct WindowCommands: Commands {
    @ObservedObject var controller: AppController
    @ObservedObject var model: WindowModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Draft") { model.create() }.commandShortcut("New Draft")
            Button("Quick Capture") { controller.capture() }.keyboardShortcut("n", modifiers: [.command, .control, .option])
            Button("New Window") { openWindow(id: "library") }.commandShortcut("New Window")
            Divider()
            Button("Import…") { model.importFile() }.commandShortcut("Import")
            Button("Export Draft…") { model.exportNote() }.disabled(model.currentNote == nil)
            Button("Export Full Backup…") { model.exportBackup() }
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") {
                model.perform { _ = try model.actionUIOperation(["operation": "showFind", "args": []]) }
            }.keyboardShortcut("f", modifiers: .command)
        }
        CommandGroup(after: .toolbar) {
            Button(model.showFilters ? "Hide Filters" : "Show Filters") { model.toggleFilters() }.commandShortcut("Filters")
            Button(model.showDraftList ? "Hide Draft List" : "Show Draft List") { model.toggleDraftList() }.commandShortcut("Draft List")
            Button("Toggle Actions") { model.showActions.toggle() }.commandShortcut("Actions")
            Button("Command Palette…") { controller.showCommandPalette() }.commandShortcut("Command Palette")
            Button("Quick Search…") { controller.showQuickSearch() }.commandShortcut("Quick Search")
            Button("Markdown Preview") { model.preview() }.commandShortcut("Markdown Preview")
            Button("Revision History…") { model.showHistory = true }
        }
        if Bundle.main.object(forInfoDictionaryKey: "DraftlyUITesting") as? Bool == true {
            CommandMenu("Visual QA") {
                ForEach(["1033 × 734", "1200 × 800", "850 × 600", "1115 × 645"], id: \.self) { size in
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
