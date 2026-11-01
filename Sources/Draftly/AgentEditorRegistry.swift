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
    @MainActor private final class Entry {
        weak var model: WindowModel?
        var noteID: UUID?
        var content: String
        var dirty: Bool
        var subscriptions: [AnyCancellable] = []

        init(_ model: WindowModel) {
            self.model = model; noteID = model.editor.noteID
            content = model.editor.content; dirty = model.hasUnsavedChanges
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
        guard valid else { throw AgentErrorCode.cancelled }
        guard !self.committing else { throw AgentErrorCode.busy }
        guard let stored = library.notes.first(where: { $0.id == note.id }) else { throw AgentErrorCode.notFound }
        _ = try snapshot(stored)
        let affected = trackedModels().filter { $0.editor.noteID == note.id }
        let originals = affected.map { (model: $0, content: $0.editor.content, dirty: $0.hasUnsavedChanges) }
        self.committing = true
        defer { self.committing = false }
        for model in affected { controlled(model) { model.hasUnsavedChanges = true } }
        let previousGeneration = generations[note.id]
        let generation = UUID()
        generations[note.id] = generation
        do {
            let saved = try committing(note, generation.uuidString)
            guard saved.id == note.id, DraftOperations.sameText(saved.content, note.content) else { throw AgentErrorCode.storageError }
            guard valid else { throw AgentErrorCode.cancelled }
            guard originals.allSatisfy({ $0.model.editor.noteID == note.id && DraftOperations.sameText($0.model.editor.content, $0.content) }) else {
                throw AgentErrorCode.editorConflict
            }
            for original in originals {
                let model = original.model
                guard model.editor.noteID == note.id, DraftOperations.sameText(model.editor.content, original.content) else {
                    throw AgentErrorCode.editorConflict
                }
                controlled(model) {
                    model.editor.content = saved.content
                    model.editor.selection = model.editor.safeSelection
                    model.editor.acknowledgeSaved(saved)
                    if DraftOperations.sameText(model.tagsText, stored.tags.joined(separator: ", ")) {
                        model.tagsText = saved.tags.joined(separator: ", ")
                    }
                    model.hasUnsavedChanges = false
                }
                // Keep callbacks outside the controlled assignments. New edits must invalidate the version.
                model.editor.synchronizeScriptEdit?()
            }
            return try snapshot(saved)
        } catch {
            for original in originals where original.model.editor.noteID == note.id
                && DraftOperations.sameText(original.model.editor.content, original.content) {
                controlled(original.model) {
                    original.model.hasUnsavedChanges = original.dirty || original.model.editor.hasUnpersistedText
                }
            }
            if generations[note.id] == generation { generations[note.id] = previousGeneration }
            throw error
        }
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
                    self.touch(entry.noteID); self.touch(id); entry.noteID = id
                },
                model.editor.$content.dropFirst().sink { [weak self, weak entry] content in
                    guard let self, let entry, !DraftOperations.sameText(entry.content, content) else { return }
                    if !self.controlledChanges.contains(id) { self.touch(entry.noteID) }; entry.content = content
                },
                model.$hasUnsavedChanges.dropFirst().sink { [weak self, weak entry] dirty in
                    guard let self, let entry, entry.dirty != dirty else { return }
                    if !self.controlledChanges.contains(id) { self.touch(entry.noteID) }; entry.dirty = dirty
                }
            ]
        }
    }
}
