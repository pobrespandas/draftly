import Combine
import Foundation
import DraftlyCore
import AgentContracts

// Track pending projections and coordinate explicit stored mutations.
@MainActor final class AgentEditorRegistry {
    struct Snapshot {
        let note: Note
        let storedNote: Note
        let generation: String
    }
    struct WindowSnapshot {
        let id: UUID
        let draftID: UUID?
        let generation: UUID
        let content: String
        let selection: NSRange
        let dirty: Bool
    }

    func windowSnapshots() throws -> [WindowSnapshot] {
        guard valid else { throw AgentErrorCode.cancelled }
        var seen: Set<ObjectIdentifier> = []
        return trackedModels().compactMap { model in
            guard seen.insert(ObjectIdentifier(model)).inserted, let entry = entries[ObjectIdentifier(model)] else { return nil }
            return WindowSnapshot(id: entry.windowID, draftID: model.editor.noteID, generation: entry.generation,
                content: model.editor.content, selection: model.editor.safeSelection,
                dirty: model.hasUnsavedChanges || model.editor.hasUnpersistedText)
        }
    }

    func executionModels(draftID: UUID, windowID: UUID? = nil) throws -> [WindowModel] {
        guard valid else { throw AgentErrorCode.cancelled }
        let candidates = trackedModels().filter { $0.editor.noteID == draftID }
        if let windowID {
            guard let selected = candidates.first(where: { entries[ObjectIdentifier($0)]?.windowID == windowID }) else {
                throw AgentErrorCode.notFound
            }
            return [selected]
        }
        return candidates
    }

    private func workspaceModel(_ windowID: UUID) throws -> WindowModel {
        guard valid else { throw AgentErrorCode.cancelled }
        guard let model = trackedModels().first(where: { entries[ObjectIdentifier($0)]?.windowID == windowID }) else {
            throw AgentErrorCode.notFound
        }
        guard !ActionRunner.isExecuting(in: library), !model.actionPending, !model.runner.isRunning else {
            throw AgentErrorCode.busy
        }
        return model
    }

    func validateWorkspaceApplication(windowID: UUID) throws { _ = try workspaceModel(windowID) }

    func applyWorkspace(_ workspace: Workspace, windowID: UUID, authorize: () throws -> Void) throws {
        let model = try workspaceModel(windowID)
        let draftID = model.editor.noteID, content = model.editor.content
        let selection = model.editor.safeSelection, dirty = model.hasUnsavedChanges
        try model.applyScriptWorkspace(workspace, authorize: {
            try authorize()
            guard try self.workspaceModel(windowID) === model else { throw AgentErrorCode.notFound }
        })
        guard try workspaceModel(windowID) === model, model.selectedWorkspace == workspace.id,
              model.editor.noteID == draftID, DraftOperations.sameText(model.editor.content, content),
              model.editor.safeSelection == selection, model.hasUnsavedChanges == dirty else {
            throw AgentErrorCode.outcomeUnknown
        }
    }

    func setSelection(_ expected: WindowSnapshot, range: NSRange, authorize: () throws -> Void) throws {
        guard valid else { throw AgentErrorCode.cancelled }
        try validateSelection(expected)
        try authorize()
        try validateSelection(expected)
        let model = try matchingModel(expected)
        model.editor.selection = range
        try authorize()
        guard trackedModels().contains(where: { $0 === model }), model.editor.noteID == expected.draftID,
              DraftOperations.sameText(model.editor.content, expected.content), model.editor.selection == range else {
            throw AgentErrorCode.outcomeUnknown
        }
    }

    private func matchingModel(_ expected: WindowSnapshot) throws -> WindowModel {
        guard valid else { throw AgentErrorCode.cancelled }
        guard let model = trackedModels().first(where: { entries[ObjectIdentifier($0)]?.windowID == expected.id }),
              let entry = entries[ObjectIdentifier(model)] else { throw AgentErrorCode.notFound }
        guard entry.generation == expected.generation, model.editor.noteID == expected.draftID else {
            throw AgentErrorCode.versionConflict
        }
        return model
    }

    func validateSelection(_ expected: WindowSnapshot) throws {
        let model = try matchingModel(expected)
        guard model.editor.canApplyExternalEdit?() != false else { throw AgentErrorCode.interactionRequired }
    }

    func validateReplacement(_ expected: WindowSnapshot) throws {
        let model = try matchingModel(expected)
        guard !ActionRunner.isExecuting(in: library), !model.actionPending, !model.runner.isRunning else { throw AgentErrorCode.busy }
        guard model.editor.synchronizeScriptEdit != nil, model.editor.canApplyExternalEdit?() == true else {
            throw AgentErrorCode.interactionRequired
        }
    }

    func validateUndo(_ expected: WindowSnapshot) throws {
        try validateReplacement(expected)
        guard try matchingModel(expected).editor.performUndo != nil else { throw AgentErrorCode.interactionRequired }
    }

    func undo(_ expected: WindowSnapshot, redo: Bool, authorize: () throws -> Void) throws -> NSRange {
        try validateUndo(expected)
        try authorize()
        try validateUndo(expected)
        let model = try matchingModel(expected)
        guard let perform = model.editor.performUndo else { throw AgentErrorCode.interactionRequired }
        perform(redo)
        guard valid, trackedModels().contains(where: { $0 === model }), model.editor.noteID == expected.draftID else {
            throw AgentErrorCode.outcomeUnknown
        }
        try authorize()
        return model.editor.safeSelection
    }

    func replaceRange(_ expected: WindowSnapshot, range: NSRange, text: String, preservingSelection: Bool = false, authorize: () throws -> Void) throws {
        try validateReplacement(expected)
        try authorize()
        try validateReplacement(expected)
        let model = try matchingModel(expected)
        let result = (expected.content as NSString).replacingCharacters(in: range, with: text)
        try model.editor.replace(range, with: text)
        if preservingSelection {
            let offset = min(expected.selection.location, result.utf16.count)
            model.editor.selection = NSRange(location: offset, length: min(expected.selection.length, result.utf16.count - offset))
        }
        func validateProjection() throws {
            guard valid, trackedModels().contains(where: { $0 === model }), model.editor.noteID == expected.draftID,
                  DraftOperations.sameText(model.editor.content, result) else { throw AgentErrorCode.outcomeUnknown }
        }
        try validateProjection()
        model.contentChanged()
        try validateProjection()
        model.editor.synchronizeScriptEdit?()
        try validateProjection()
        try authorize()
    }

    func syntaxDefinition(windowID: UUID) throws -> SyntaxDefinition {
        guard valid else { throw AgentErrorCode.cancelled }
        guard let model = trackedModels().first(where: { entries[ObjectIdentifier($0)]?.windowID == windowID }) else {
            throw AgentErrorCode.notFound
        }
        do {
            return try library.syntaxDefinition(named: model.currentNote?.syntax ?? "Markdown",
                defaults: model.dependencies.preferences.defaults)
        } catch { throw AgentErrorCode.unavailable }
    }

    @MainActor private final class Entry {
        let windowID = UUID()
        var generation = UUID()
        var selection: NSRange
        weak var model: WindowModel?
        var noteID: UUID?
        var content: String
        var dirty: Bool
        var subscriptions: [AnyCancellable] = []

        init(_ model: WindowModel) {
            self.model = model; noteID = model.editor.noteID
            content = model.editor.content; dirty = model.hasUnsavedChanges
            selection = model.editor.selection
        }
    }
    private let library: LibraryStore
    private let models: () -> [WindowModel]
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var generations: [UUID: UUID] = [:]
    private var valid = true
    private var committing = false
    private var controlledChanges: Set<ObjectIdentifier> = []

    init(library: LibraryStore, models: @escaping () -> [WindowModel]) {
        self.library = library; self.models = models
    }

    func isBound(to library: LibraryStore) -> Bool { valid && self.library === library }

    func invalidate() {
        valid = false
        entries.removeAll(); generations.removeAll()
    }

    // Call at window registration and removal, even when no agent is reading.
    func refreshMembership() { if valid { _ = trackedModels() } }

    private func trackedModels() -> [WindowModel] {
        let current = models().filter { $0.library === library }
        refresh(current)
        return current
    }

    func snapshot(_ stored: Note) throws -> Snapshot {
        guard valid else { throw AgentErrorCode.cancelled }
        let current = trackedModels()
        let pending = current.filter {
            $0.editor.noteID == stored.id && ($0.hasUnsavedChanges || $0.editor.hasUnpersistedText)
        }
        // Swift String equality folds canonically equivalent Unicode. Different
        // code units still represent different pending edits for this boundary.
        guard Set(pending.map { Data($0.editor.content.utf8) }).count <= 1 else {
            throw AgentErrorCode.editorConflict
        }
        var note = stored
        if let owner = pending.first { note.content = owner.editor.content }
        let generation = generations[stored.id] ?? UUID()
        generations[stored.id] = generation
        return Snapshot(note: note, storedNote: stored, generation: generation.uuidString)
    }

    // The caller owns authority, expected-version checks and the durable transaction.
    func synchronizeMutation(_ note: Note, committing: (Note, String) throws -> Note) throws -> Snapshot {
        let values = try synchronizeMutations([note]) { notes, generations in
            guard let value = notes.first, let generation = generations[value.id] else { throw AgentErrorCode.storageError }
            return [try committing(value, generation)]
        }
        guard let value = values.first else { throw AgentErrorCode.storageError }
        return value
    }

    func synchronizeMutations(_ notes: [Note],
                              committing: ([Note], [UUID: String]) throws -> [Note]) throws -> [Snapshot] {
        guard valid else { throw AgentErrorCode.cancelled }
        guard !self.committing else { throw AgentErrorCode.busy }
        let ids = Set(notes.map(\.id))
        guard !notes.isEmpty, ids.count == notes.count else { throw AgentErrorCode.invalidInput }
        var stored: [UUID: Note] = [:]
        for note in notes {
            guard let value = library.notes.first(where: { $0.id == note.id }) else { throw AgentErrorCode.notFound }
            _ = try snapshot(value); stored[note.id] = value
        }
        let affected = trackedModels().filter { $0.editor.noteID.map(ids.contains) ?? false }
        let originals = affected.map { (model: $0, id: $0.editor.noteID!, content: $0.editor.content, dirty: $0.hasUnsavedChanges) }
        self.committing = true
        defer { self.committing = false }
        for model in affected { controlled(model) { model.hasUnsavedChanges = true } }
        let previousGenerations = generations.filter { ids.contains($0.key) }
        let reserved = Dictionary(uniqueKeysWithValues: ids.map { ($0, UUID()) })
        for (id, generation) in reserved { generations[id] = generation }
        do {
            let saved = try committing(notes, reserved.mapValues(\.uuidString))
            let byID = Dictionary(grouping: saved, by: \.id)
            guard byID.count == ids.count, saved.count == notes.count,
                  notes.allSatisfy({ note in
                      guard let value = byID[note.id]?.first else { return false }
                      return DraftOperations.sameText(value.content, note.content)
                  }) else { throw AgentErrorCode.storageError }
            guard valid else { throw AgentErrorCode.cancelled }
            guard originals.allSatisfy({ $0.model.editor.noteID == $0.id && DraftOperations.sameText($0.model.editor.content, $0.content) }) else {
                throw AgentErrorCode.editorConflict
            }
            for original in originals {
                let model = original.model
                guard model.editor.noteID == original.id, DraftOperations.sameText(model.editor.content, original.content),
                      let value = byID[original.id]?.first, let previous = stored[original.id] else { throw AgentErrorCode.editorConflict }
                controlled(model) {
                    model.editor.content = value.content
                    model.editor.selection = model.editor.safeSelection
                    model.editor.acknowledgeSaved(value)
                    if DraftOperations.sameText(model.tagsText, previous.tags.joined(separator: ", ")) {
                        model.tagsText = value.tags.joined(separator: ", ")
                    }
                    model.hasUnsavedChanges = false
                }
                model.editor.synchronizeScriptEdit?()
            }
            return try saved.map { try snapshot($0) }
        } catch {
            for original in originals where original.model.editor.noteID == original.id
                && DraftOperations.sameText(original.model.editor.content, original.content) {
                controlled(original.model) {
                    original.model.hasUnsavedChanges = original.dirty || original.model.editor.hasUnpersistedText
                }
            }
            for (id, generation) in reserved where generations[id] == generation { generations[id] = previousGenerations[id] }
            throw error
        }
    }

    // Recheck this boundary inside the storage transaction, before its commit.
    func synchronizeDeletion(_ ids: Set<UUID>, committing: (() throws -> Void) throws -> Void) throws {
        guard valid else { throw AgentErrorCode.cancelled }
        guard !self.committing else { throw AgentErrorCode.busy }
        guard !ids.isEmpty else { throw AgentErrorCode.invalidInput }
        var expected: [UUID: String] = [:]
        for id in ids {
            guard let stored = library.notes.first(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
            expected[id] = try snapshot(stored).generation
        }
        func validate() throws {
            guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
            for (id, generation) in expected { try validateMutationGeneration(for: id, expected: generation) }
            for model in trackedModels() where model.editor.noteID.map(ids.contains) == true {
                guard !model.actionPending, !model.runner.isRunning else { throw AgentErrorCode.busy }
                guard model.editor.canApplyExternalEdit?() != false else { throw AgentErrorCode.interactionRequired }
            }
        }
        try validate()
        self.committing = true
        defer { self.committing = false }
        try committing(validate)
        guard !library.notes.contains(where: { ids.contains($0.id) }) else { throw AgentErrorCode.storageError }
        // Keep cleanup synchronous even if a storage publication ended authority.
        for model in models() where model.library === library {
            if let id = model.editor.noteID, ids.contains(id) {
                controlled(model) { model.discardDeletedDraft(id) }
            }
        }
        for id in ids { generations.removeValue(forKey: id) }
    }

    func validateMutationGeneration(for id: UUID, expected: String) throws {
        guard valid else { throw AgentErrorCode.cancelled }
        _ = trackedModels()
        guard generations[id]?.uuidString == expected else { throw AgentErrorCode.editorConflict }
    }

    private func controlled(_ model: WindowModel, update: () -> Void) {
        let id = ObjectIdentifier(model)
        controlledChanges.insert(id)
        defer { controlledChanges.remove(id) }
        update()
    }

    private func touch(_ id: UUID?) {
        guard let id, generations[id] != nil else { return }
        generations[id] = UUID()
    }

    private func refresh(_ models: [WindowModel]) {
        let live = Set(models.map(ObjectIdentifier.init))
        for id in entries.keys.filter({ !live.contains($0) }) {
            touch(entries[id]?.noteID); entries.removeValue(forKey: id)
        }
        for model in models {
            let id = ObjectIdentifier(model)
            if entries[id]?.model === model { continue }
            // A released object's address can be reused by another window.
            touch(entries[id]?.noteID)
            let entry = Entry(model)
            entries[id] = entry
            touch(entry.noteID)
            entry.subscriptions = [
                model.editor.$noteID.dropFirst().sink { [weak self, weak entry] id in
                    guard let self, let entry, entry.noteID != id else { return }
                    self.touch(entry.noteID); self.touch(id); entry.noteID = id; entry.generation = UUID()
                },
                model.editor.$content.dropFirst().sink { [weak self, weak entry] content in
                    guard let self, let entry, !DraftOperations.sameText(entry.content, content) else { return }
                    if !self.controlledChanges.contains(id) { self.touch(entry.noteID) }; entry.content = content; entry.generation = UUID()
                },
                model.editor.$selection.dropFirst().sink { [weak entry] selection in
                    guard let entry, entry.selection != selection else { return }
                    entry.selection = selection; entry.generation = UUID()
                },
                model.$hasUnsavedChanges.dropFirst().sink { [weak self, weak entry] dirty in
                    guard let self, let entry, entry.dirty != dirty else { return }
                    if !self.controlledChanges.contains(id) { self.touch(entry.noteID) }; entry.dirty = dirty; entry.generation = UUID()
                }
            ]
        }
    }
}
