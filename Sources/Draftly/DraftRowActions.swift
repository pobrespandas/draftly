import AppKit
import DraftlyCore

@MainActor
struct DraftRowCommand {
    let noteID: UUID
    let destination: WindowModel.DraftDestination
    let title: String
    let symbol: String
    let destructive: Bool
    func perform(on model: WindowModel) { model.moveDrafts([noteID], to: destination) }
    func nativeAction(model: WindowModel, table: NSTableView) -> NSTableViewRowAction {
        let action = NSTableViewRowAction(style: destructive ? .destructive : .regular, title: title) { [weak model, weak table] _, _ in
            table?.rowActionsVisible = false
            guard let model else { return }
            perform(on: model)
        }
        action.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        action.backgroundColor = destructive ? .systemRed : .systemBlue
        return action
    }
}

@MainActor
extension WindowModel {
    func swipeCommands(for noteID: UUID) -> [DraftRowCommand] {
        guard let note = library.notes.first(where: { $0.id == noteID }) else { return [] }
        if note.trashedAt != nil {
            return [DraftRowCommand(noteID: noteID, destination: .restore, title: "Restore", symbol: "arrow.uturn.backward", destructive: false)]
        }
        return [
            DraftRowCommand(noteID: noteID, destination: .trash, title: "Trash", symbol: "trash", destructive: true),
            DraftRowCommand(noteID: noteID, destination: note.isArchived ? .inbox : .archive,
                            title: note.isArchived ? "Inbox" : "Archive", symbol: note.isArchived ? "tray.and.arrow.down" : "archivebox", destructive: false)
        ]
    }
}
