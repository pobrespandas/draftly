import Foundation
import DraftlyCore
import AgentContracts

// Resolve draft grants against the currently loaded library, not a cached list.
@MainActor
struct AgentDraftResourceChoices {
    let library: LibraryStore

    func choices() -> [AgentConnectionsSettingsModel.ResourceChoice] {
        library.notes.map { note in
            AgentConnectionsSettingsModel.ResourceChoice(
                reference: AgentResourceReference(kind: .draft, id: note.id), title: note.title)
        }
    }

    func resolve(_ targets: Set<AgentResourceReference>) -> Set<AgentResourceReference> {
        let existing = Set(library.notes.map(\.id))
        return Set(targets.filter { $0.kind == .draft && existing.contains($0.id) })
    }
}
