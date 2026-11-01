import Combine
import Foundation
import DraftlyCore
import AgentContracts

// Read pending text without saving, selecting or synchronizing an editor.
@MainActor final class AgentEditorRegistry {
    struct Snapshot {
        let note: Note
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

    init(library: LibraryStore, models: @escaping () -> [WindowModel]) {
        self.library = library; self.models = models
    }

    func isBound(to library: LibraryStore) -> Bool { self.library === library }

    // Call at window registration and removal, even when no agent is reading.
    func refreshMembership() { _ = trackedModels() }

    private func trackedModels() -> [WindowModel] {
        let current = models().filter { $0.library === library }
        refresh(current)
        return current
    }

    func snapshot(_ stored: Note) throws -> Snapshot {
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
        return Snapshot(note: note, generation: generation.uuidString)
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
                    guard let self, let entry, !entry.content.utf8.elementsEqual(content.utf8) else { return }
                    self.touch(entry.noteID); entry.content = content
                },
                model.$hasUnsavedChanges.dropFirst().sink { [weak self, weak entry] dirty in
                    guard let self, let entry, entry.dirty != dirty else { return }
                    self.touch(entry.noteID); entry.dirty = dirty
                }
            ]
        }
    }
}
