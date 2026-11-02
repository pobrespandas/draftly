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

// Pairing must resolve each selected resource against the live library.
@MainActor
struct AgentLibraryResourceChoices {
    let library: LibraryStore

    func choices() -> [AgentConnectionsSettingsModel.ResourceChoice] {
        AgentDraftResourceChoices(library: library).choices() + library.actions.filter { !$0.isSeparator }.map { action in
            .init(reference: .init(kind: .action, id: action.id), title: action.name)
        }
    }

    func resolve(_ targets: Set<AgentResourceReference>) -> Set<AgentResourceReference> {
        let available = Set(choices().map(\.reference))
        return targets.intersection(available)
    }
}
