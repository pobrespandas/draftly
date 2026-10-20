import AppKit
import DraftlyCore

@MainActor
extension WindowModel {
    enum DraftDestination { case inbox, archive, trash, restore }
    enum DraftCopyField { case contents, title, link, uuid }

    func contextTargets(rowID: UUID, selection: Set<UUID>) -> [UUID] {
        let targets = selection.contains(rowID) ? selection : [rowID]
        return visibleNotes.filter { targets.contains($0.id) }.map(\.id)
    }
    func checkedDrafts(_ ids: [UUID]) throws -> [Note] {
        guard flush() else { throw DraftlyError.message("Save the current draft before continuing.") }
        let values = Dictionary(uniqueKeysWithValues: library.notes.map { ($0.id, $0) })
        return try ids.map { id in
            guard let note = values[id] else { throw DraftlyError.message("A selected draft is no longer available.") }
            return note
        }
    }
    @discardableResult func modifyDrafts(_ ids: [UUID], _ operation: (inout Note) -> Void) -> Bool {
        do {
            var notes = try checkedDrafts(ids)
            for index in notes.indices { operation(&notes[index]) }
            try library.saveNotes(notes)
            return true
        } catch { library.error = error.localizedDescription; return false }
    }
    func moveDrafts(_ ids: [UUID], to destination: DraftDestination) {
        let date = Date()
        modifyDrafts(ids) { note in
            switch destination {
            case .inbox: note.isArchived = false; note.trashedAt = nil
            case .archive: note.isArchived = true; note.trashedAt = nil
            case .trash: note.trashedAt = date
            case .restore: note.trashedAt = nil
            }
        }
    }
    func flagDrafts(_ ids: [UUID], value: Int) { modifyDrafts(ids) { $0.flag = value } }
    func editDraftTags(_ ids: [UUID], tags: [String], remove: Bool) {
        let tags = Set(TagRules.normalize(tags))
        modifyDrafts(ids) { note in
            note.tags = remove ? note.tags.filter { !tags.contains(TagRules.normalize($0)) }
                : TagRules.normalize(note.tags + tags)
        }
    }
    func duplicateDrafts(_ ids: [UUID]) {
        perform {
            let copies = try library.duplicateNotes(checkedDrafts(ids))
            status = "\(copies.count) " + (copies.count == 1 ? "draft duplicated in Inbox" : "drafts duplicated in Inbox")
        }
    }
    struct MergeRequest: Identifiable {
        let id = UUID()
        let draftIDs: [UUID]
    }
    func mergeDrafts(_ ids: [UUID]) {
        guard ids.count >= 2 else { return }
        mergeRequest = MergeRequest(draftIDs: ids)
    }
    func confirmMerge(_ request: MergeRequest, separator: String, includeBlankLine: Bool, destination: MergeDestination) {
        do {
            let merged = try library.mergeNotes(checkedDrafts(request.draftIDs), separator: separator,
                                               includeBlankLine: includeBlankLine, destination: destination)
            mergeRequest = nil
            folder = .inbox; clearFilters(); select(merged.id)
        } catch { library.error = error.localizedDescription }
    }
    func copyText(_ ids: [UUID], field: DraftCopyField) throws -> String {
        let notes = try checkedDrafts(ids)
        return notes.map { note in
            switch field {
            case .contents: note.content
            case .title: note.title
            case .link: "draftly://open?uuid=" + note.id.uuidString
            case .uuid: note.id.uuidString
            }
        }.joined(separator: field == .contents ? "\n\n" : "\n")
    }
    func copyDrafts(_ ids: [UUID], field: DraftCopyField) {
        perform {
            let text = try copyText(ids, field: field)
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        }
    }
    func exportDrafts(_ ids: [UUID], format: DraftExportFormat) {
        perform {
            let notes = try checkedDrafts(ids)
            let data = try DraftOperations.export(notes, as: format)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Drafts." + format.rawValue
            switch format {
            case .txt: panel.allowedContentTypes = [.plainText]
            case .csv: panel.allowedContentTypes = [.commaSeparatedText]
            case .json: panel.allowedContentTypes = [.json]
            }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
        }
    }
    func promptTags(_ ids: [UUID], remove: Bool) {
        do { _ = try checkedDrafts(ids) } catch { library.error = error.localizedDescription; return }
        let alert = NSAlert(); alert.messageText = remove ? "Remove Tags" : "Add Tags"
        alert.informativeText = "Separate tags with commas."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = field; alert.addButton(withTitle: remove ? "Remove" : "Add"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        editDraftTags(ids, tags: field.stringValue.components(separatedBy: ","), remove: remove)
    }
    func promptAction(_ ids: [UUID]) {
        guard !actionPending, !runner.isRunning else { return }
        let actions = ActionCatalogPresentation.actions(library.orderedActions(), on: .search)
        guard !actions.isEmpty else { return }
        do { _ = try checkedDrafts(ids) } catch { library.error = error.localizedDescription; return }
        let alert = NSAlert(); alert.messageText = "Run Action"
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        picker.addItems(withTitles: actions.map { $0.group + " · " + $0.name })
        alert.accessoryView = picker; alert.addButton(withTitle: "Run"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, actions.indices.contains(picker.indexOfSelectedItem) else { return }
        runAction(actions[picker.indexOfSelectedItem], on: ids)
    }
    func runAction(_ action: DraftAction, on ids: [UUID]) {
        guard !actionPending, !runner.isRunning else { return }
        actionPending = true
        actionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.actionPending = false; self.actionTask = nil }
            await self.executeActionBatch(action, on: ids)
        }
    }
    func runActionAsync(_ action: DraftAction, on ids: [UUID]) async {
        guard !actionPending, !runner.isRunning else { return }
        actionPending = true
        defer { actionPending = false }
        await executeActionBatch(action, on: ids)
    }
    private func executeActionBatch(_ action: DraftAction, on ids: [UUID]) async {
        guard !Task.isCancelled, libraryBusyReport(for: action) == nil else { return }
        do {
            _ = try checkedDrafts(ids)
            for id in ids {
                guard !Task.isCancelled, libraryBusyReport(for: action) == nil,
                      flush(), library.notes.contains(where: { $0.id == id }) else { break }
                select(id, fromAction: true)
                guard editor.noteID == id else { break }
                let navigation = actionNavigationSnapshot()
                let report = await runner.runAsync(action)
                if ids.count > 1, library.notes.contains(where: { $0.id == id }), editor.noteID != id { select(id, fromAction: true) }
                if ids.count == 1 { finishActionNavigation(action, report: report, snapshot: navigation) }
                status = runner.message ?? ""
                tagsText = currentNote?.tags.joined(separator: ", ") ?? ""
                if !report.result.succeeded { break }
            }
        } catch { library.error = error.localizedDescription }
    }
    func inspectDraft(_ id: UUID, versions: Bool) {
        perform {
            guard let draft = try checkedDrafts([id]).first else { return }
            if versions { historyDraftID = draft.id; showHistory = true }
            else { infoDraft = draft; showInfo = true }
        }
    }
    func restoreRevision(_ revision: Revision) {
        perform {
            guard var draft = try checkedDrafts([revision.noteID]).first else { return }
            draft.content = revision.content; try library.saveNote(draft)
            if editor.noteID == draft.id { editor.load(draft) }
        }
    }
    func confirmEmptyTrash() {
        perform { _ = try LibraryTrashCommand.run(library: library, models: [self]) }
    }

    func openDraft(_ id: UUID, tab: Bool) {
        perform {
            _ = try checkedDrafts([id])
            _ = try actionUIOperation(["operation": tab ? "openInNewTab" : "openInNewWindow", "draft": ["uuid": id.uuidString]])
        }
    }
}

@MainActor
enum LibraryTrashCommand {
    @discardableResult
    static func run(library: LibraryStore, models: [WindowModel], confirm: @MainActor (Int) throws -> Bool = presentConfirmation) throws -> Bool {
        for model in models {
            guard model.flush() else { throw DraftlyError.message("Pending edits could not be saved. Trash was not emptied.") }
        }
        let ids = Set(library.notes.filter { $0.trashedAt != nil }.map(\.id))
        guard !ids.isEmpty, try confirm(ids.count) else { return false }
        guard Set(library.notes.filter { $0.trashedAt != nil }.map(\.id)) == ids else {
            throw DraftlyError.message("Trash changed. Review it and try again.")
        }
        try library.emptyTrash()
        for model in models where model.editor.noteID.map(ids.contains) == true { model.create() }
        return true
    }

    private static func presentConfirmation(_ count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Permanently delete \(count) " + (count == 1 ? "draft?" : "drafts?")
        alert.informativeText = "This empties the entire Trash and deletes their revisions. This cannot be undone. Action history will remain."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Empty Trash")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
