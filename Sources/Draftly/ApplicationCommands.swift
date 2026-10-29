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
                Button("Capture") { controller.capture() }.commandShortcut("Quick Capture")
                Button("New Draft in New Window") { openWindow(id: "library") }.commandShortcut("New Window")
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
            if AppUpdates.shared.isAvailable {
                Button("Check for Updates…") { AppUpdates.shared.check() }
                Divider()
            }
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
        let fileCommands = FileDraftCommands(model: model)
        CommandGroup(replacing: .newItem) {
            creationItems(fileCommands)
            Divider()
            draftItems(fileCommands)
            Divider()
            Button("Merge…") { model.mergeDrafts(fileCommands.targetIDs) }
                .disabled(!fileCommands.canUseTargets || fileCommands.targetIDs.count < 2)
            Button("Duplicate") { model.duplicateDrafts(fileCommands.targetIDs) }.disabled(!fileCommands.canUseTargets)
            Button("Save Version") { fileCommands.saveVersion() }.commandShortcut("Save Version")
                .disabled(fileCommands.singleTarget == nil)
            Divider()
            Button("Get Info…") { if let id = fileCommands.singleTarget { model.inspectDraft(id, versions: false) } }
                .commandShortcut("Get Info").disabled(fileCommands.singleTarget == nil)
            Button("Versions…") { if let id = fileCommands.singleTarget { model.inspectDraft(id, versions: true) } }
                .disabled(fileCommands.singleTarget == nil)
            Divider()
            copyItems(fileCommands)
            sharingItems(fileCommands)
            Divider()
            Button { model.navigate(-1) } label: { Label("Previous Draft", systemImage: "chevron.up") }
                .commandShortcut("Previous Draft").disabled(model.visibleNotes.isEmpty)
            Button { model.navigate(1) } label: { Label("Next Draft", systemImage: "chevron.down") }
                .commandShortcut("Next Draft").disabled(model.visibleNotes.isEmpty)
        }
        CommandGroup(replacing: .printItem) {
            Button { model.preview() } label: { Label(model.showPreview ? "Hide Preview" : "Show Preview", systemImage: "doc.text.magnifyingglass") }
                .commandShortcut("Markdown Preview")
            Button { _ = NSPageLayout().runModal(with: .shared) } label: { Label("Page Setup…", systemImage: "doc.text") }
            Button { Task { await fileCommands.printDraft() } } label: { Label("Print…", systemImage: "printer") }
                .commandShortcut("Print").disabled(!fileCommands.canUseTargets)
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") {
                model.perform { _ = try model.actionUIOperation(["operation": "showFind", "args": [], "preserveQuery": true]) }
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
            Button("Cancel Running Action") { model.cancelActions() }.disabled(!model.canCancelActions)
            Divider()
            Button("New Action…") { model.editingAction = DraftAction(name: "New Action", steps: [ActionStep("script", ["script": ""])]) }
            Button("Import from Directory…") { model.showActionImporter = true }
            Button("Execution History…") { model.showRunLog = true }
            Button("Manage Actions and Workspaces…") { model.openLibraryManagement(section: .groups) }
            Divider()
            ForEach(ActionCatalogPresentation.entries(model.library.orderedActions())) { entry in
                if let heading = entry.sectionHeading { Text(heading) }
                if entry.kind == .separator {
                    Divider()
                } else if let action = entry.runnableAction {
                    if ActionShortcut.conflict(for: action, in: model.library.actions) == nil,
                       let key = ActionShortcut(action).key.first {
                        Button(action.name) { model.run(action) }.keyboardShortcut(KeyEquivalent(key), modifiers: modifiers(action)).disabled(!model.canRunActions)
                    } else { Button(action.name) { model.run(action) }.disabled(!model.canRunActions) }
                }
            }
        }
    }
    @ViewBuilder private func creationItems(_ fileCommands: FileDraftCommands) -> some View {
        Button("New Draft") { model.create() }.commandShortcut("New Draft")
        Button("New Draft in New Window") { Task { _ = await fileCommands.openNewWindow() } }.commandShortcut("New Window")
        Button("Capture") { controller.capture() }.commandShortcut("Quick Capture")
        Button("New with Clipboard") { _ = fileCommands.createWithClipboard(NSPasteboard.general.string(forType: .string)) }
            .commandShortcut("New with Clipboard").disabled(NSPasteboard.general.string(forType: .string)?.isEmpty != false)
        Button("New with Dictation…") { if model.create() { model.perform { try model.showDictation() } } }
            .commandShortcut("New with Dictation")
        Menu("New with Syntax") {
            ForEach(fileCommands.syntaxNames, id: \.self) { name in Button(name) { _ = fileCommands.create(syntax: name) } }
        }
        Menu("New in Workspace") {
            ForEach(model.library.workspaces) { workspace in Button(workspace.name) { _ = fileCommands.create(in: workspace) } }
        }.disabled(model.library.workspaces.isEmpty)
        Button("Import…") { model.importFile() }.commandShortcut("Import")
        Menu("Export") {
            Button("As Text…") { model.exportDrafts(fileCommands.targetIDs, format: .txt) }.disabled(!fileCommands.canUseTargets)
            Button("As CSV…") { model.exportDrafts(fileCommands.targetIDs, format: .csv) }.disabled(!fileCommands.canUseTargets)
            Button("As JSON…") { model.exportDrafts(fileCommands.targetIDs, format: .json) }.disabled(!fileCommands.canUseTargets)
            Divider()
            Button("Export Full Backup…") { model.exportBackup() }
        }
    }

    @ViewBuilder private func draftItems(_ fileCommands: FileDraftCommands) -> some View {
        Button("Move to Inbox") { model.moveDrafts(fileCommands.targetIDs, to: .inbox) }
            .commandShortcut("Move to Inbox").disabled(!fileCommands.canUseTargets)
        Button("Move to Archive") { model.moveDrafts(fileCommands.targetIDs, to: .archive) }
            .commandShortcut("Move to Archive").disabled(!fileCommands.canUseTargets)
        Button("Move to Trash") { model.moveDrafts(fileCommands.targetIDs, to: .trash) }
            .commandShortcut("Move to Trash").disabled(!fileCommands.canUseTargets)
        Menu {
            ForEach([2, 1, 6, 5, 3, 4, 7], id: \.self) { flag in
                Toggle(flagName(flag), isOn: Binding(get: { fileCommands.sharesFlag(flag) },
                    set: { _ in model.flagDrafts(fileCommands.targetIDs, value: flag) }))
            }
            Divider()
            Toggle("Clear Flag", isOn: Binding(get: { fileCommands.sharesFlag(0) },
                set: { _ in model.flagDrafts(fileCommands.targetIDs, value: 0) }))
        } label: { Label("Flag", systemImage: "flag") }.disabled(!fileCommands.canUseTargets)
        Menu {
            Button("Add…") { model.promptTags(fileCommands.targetIDs, remove: false) }
            Button("Remove…") { model.promptTags(fileCommands.targetIDs, remove: true) }
        } label: { Label("Tags", systemImage: "tag") }.disabled(!fileCommands.canUseTargets)
        Button("Change Syntax…") { fileCommands.promptSyntax() }.disabled(fileCommands.targetIDs.isEmpty)
    }

    private func copyItems(_ fileCommands: FileDraftCommands) -> some View {
        Menu {
            Button("Contents") { model.copyDrafts(fileCommands.targetIDs, field: .contents) }
            Button("Title") { model.copyDrafts(fileCommands.targetIDs, field: .title) }
            Button("Link") { model.copyDrafts(fileCommands.targetIDs, field: .link) }
            Button("UUID") { model.copyDrafts(fileCommands.targetIDs, field: .uuid) }
        } label: { Label("Copy", systemImage: "doc.on.doc") }.disabled(!fileCommands.canUseTargets)
    }

    private func sharingItems(_ fileCommands: FileDraftCommands) -> some View {
        let notes = fileCommands.targetIDs.compactMap { id in model.library.notes.first { $0.id == id } }
        let services = NSSharingService.sharingServices(forItems: [notes.map(\.content).joined(separator: "\n\n")])
        return Menu {
            ForEach(Array(services.enumerated()), id: \.offset) { _, service in
                Button {
                    model.perform { service.perform(withItems: [try model.copyText(fileCommands.targetIDs, field: .contents)]) }
                } label: { Label { Text(service.title) } icon: { Image(nsImage: service.image) } }
            }
            if services.isEmpty { Text("No sharing services available") }
        } label: { Label("Share", systemImage: "square.and.arrow.up") }.disabled(!fileCommands.canUseTargets || services.isEmpty)
    }

    private func modifiers(_ action: DraftAction) -> SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        for name in ActionShortcut(action).modifiers {
            switch name { case "command": result.insert(.command); case "option": result.insert(.option); case "control": result.insert(.control); case "shift": result.insert(.shift); default: break }
        }
        return result
    }
}
