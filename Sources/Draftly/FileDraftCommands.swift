import AppKit
import DraftlyCore

@MainActor
struct FileDraftCommands {
    let model: WindowModel
    let targetIDs: [UUID]

    init(model: WindowModel) {
        self.model = model
        let selected = model.visibleNotes.filter { model.selectedDraftIDs.contains($0.id) }.map(\.id)
        targetIDs = selected.isEmpty ? model.currentNote.map { [$0.id] } ?? [] : selected
    }
    var canUseTargets: Bool {
        !targetIDs.isEmpty && targetIDs.allSatisfy { id in
            model.library.notes.contains { $0.id == id }
                || (id == model.editor.noteID && !model.editor.content.isEmpty)
        }
    }
    var singleTarget: UUID? { canUseTargets && targetIDs.count == 1 ? targetIDs.first : nil }
    var syntaxNames: [String] {
        var names: [String] = []
        for name in ScriptSyntax.names + model.library.syntaxes.map(\.name) where !names.contains(name) { names.append(name) }
        return names
    }
    func sharesFlag(_ flag: Int) -> Bool {
        let notes = targetIDs.compactMap { id in model.library.notes.first { $0.id == id } ?? (model.currentNote?.id == id ? model.currentNote : nil) }
        return !notes.isEmpty && notes.allSatisfy { $0.flag == flag }
    }

    @discardableResult
    func createWithClipboard(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return model.capture(text)
    }

    @discardableResult
    func create(syntax: String) -> Bool {
        guard syntaxNames.contains(syntax), model.create(), let id = model.editor.noteID else { return false }
        model.change([id]) { $0.syntax = syntax }
        return model.library.notes.first { $0.id == id }?.syntax == syntax
    }

    @discardableResult
    func create(in workspace: Workspace) -> Bool {
        do {
            let resolved = try WorkspacePresentationResolver.resolve(workspace, groupNames: model.library.groupNames,
                groups: model.library.actionGroups, themes: model.library.themes)
            try model.validateWorkspaceThemeFiles(resolved)
            guard model.create() else { return false }
            try model.applyScriptWorkspace(resolved)
            return true
        } catch { model.library.error = error.localizedDescription; return false }
    }

    @discardableResult
    func openNewWindow() async -> Bool {
        guard model.flush() else { return false }
        do {
            if let open = model.dependencies.openDraftWindowAsync {
                return try await open(nil, false, model.window, 120)
            }
            return model.dependencies.openDraftWindow(nil, false, model.window)
        } catch { model.library.error = error.localizedDescription; return false }
    }

    func promptSyntax() {
        let ids = targetIDs
        guard !ids.isEmpty, model.flush() else { return }
        let alert = NSAlert(); alert.messageText = "Change Syntax"
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        picker.addItems(withTitles: syntaxNames)
        if let syntax = model.currentNote?.syntax { picker.selectItem(withTitle: syntax) }
        alert.accessoryView = picker; alert.addButton(withTitle: "Change"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let name = picker.titleOfSelectedItem else { return }
        model.change(Set(ids)) { $0.syntax = name }
    }

    func saveVersion() {
        guard let id = singleTarget else { return }
        model.perform {
            guard let note = try model.checkedDrafts([id]).first else { return }
            try model.library.saveRevision(Revision(noteID: note.id, content: note.content))
            model.status = "Version saved"
        }
    }

    func printDraft(using print: @MainActor ([String: Any]) async throws -> Bool = { try await NativePrintRequest.run($0) }) async {
        guard canUseTargets else { return }
        do { _ = try await print(["text": model.copyText(targetIDs, field: .contents), "format": "text"]) }
        catch is CancellationError { }
        catch { model.library.error = error.localizedDescription }
    }
}
