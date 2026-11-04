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
    var editors: AgentEditorRegistry? = nil

    func choices() -> [AgentConnectionsSettingsModel.ResourceChoice] {
        let titles = Dictionary(library.notes.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return AgentDraftResourceChoices(library: library).choices() + library.revisions.compactMap { revision in
            guard let title = titles[revision.noteID] else { return nil }
            let date = revision.date.formatted(date: .abbreviated, time: .shortened)
            return .init(reference: .init(kind: .revision, id: revision.id), title: title + " · " + date)
        } + library.actions.filter { !$0.isSeparator }.map { action in
            .init(reference: .init(kind: .action, id: action.id), title: action.name)
        } + library.groupNames.compactMap { name in
            guard let id = library.actionGroupIdentifiers[name] else { return nil }
            return .init(reference: .init(kind: .actionGroup, id: id), title: name)
        } + library.workspaces.map { workspace in
            .init(reference: .init(kind: .workspace, id: workspace.id), title: workspace.name)
        } + library.themes.map { theme in
            .init(reference: .init(kind: .theme, id: theme.id), title: theme.name)
        } + library.syntaxes.filter { $0.type != "builtIn" }.map { syntax in
            .init(reference: .init(kind: .syntax, id: syntax.id), title: syntax.name)
        } + ((try? editors?.windowSnapshots()) ?? []).map { window in
            let title = window.draftID.flatMap { titles[$0] } ?? "Editor window"
            return .init(reference: .init(kind: .window, id: window.id), title: title)
        }
    }

    func resolve(_ targets: Set<AgentResourceReference>) -> Set<AgentResourceReference> {
        let available = Set(choices().map(\.reference))
        return targets.intersection(available)
    }
}
