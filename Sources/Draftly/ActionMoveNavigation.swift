import DraftlyCore
import Foundation

@MainActor extension WindowModel {
    struct ActionNavigationSnapshot {
        let note: Note?
        let visibleIDs: [UUID]
    }

    func actionNavigationSnapshot() -> ActionNavigationSnapshot {
        ActionNavigationSnapshot(note: currentNote, visibleIDs: visibleNotes.map(\.id))
    }

    func finishActionNavigation(_ action: DraftAction, report: ActionExecutionReport,
                                snapshot: ActionNavigationSnapshot) {
        guard report.result.succeeded, report.reason == .success,
              let original = snapshot.note, editor.noteID == original.id,
              let stored = library.notes.first(where: { $0.id == original.id }) else { return }
        let moved: Bool
        switch action.afterSuccess {
        case "archive", "1": moved = !original.isArchived && stored.isArchived
        case "trash", "2": moved = original.trashedAt == nil && stored.trashedAt != nil
        default: moved = false
        }
        guard moved else { return }
        if dependencies.preferences.actionMoveNavigation == .openNext {
            let available = Set(visibleNotes.map(\.id)).subtracting([original.id])
            let index = snapshot.visibleIDs.firstIndex(of: original.id)
            let candidates: [UUID]
            if let index {
                candidates = Array(snapshot.visibleIDs.dropFirst(index + 1))
                    + Array(snapshot.visibleIDs.prefix(index).reversed())
            } else { candidates = visibleNotes.map(\.id) }
            if let next = candidates.first(where: { available.contains($0) }) {
                select(next, fromAction: true)
                return
            }
        }
        _ = create(fromAction: true)
    }
}
