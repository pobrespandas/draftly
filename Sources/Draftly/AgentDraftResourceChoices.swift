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
    var bookmarkDefaults: UserDefaults? = nil

    func page(search: String, offset: Int, limit: Int) -> [AgentConnectionsSettingsModel.ResourceChoice] {
        var result: [AgentConnectionsSettingsModel.ResourceChoice] = []
        var skipped = 0
        func append(_ kind: AgentResourceKind, _ id: UUID, _ title: @autoclosure () -> String) -> Bool {
            let value = title()
            guard search.isEmpty || value.localizedCaseInsensitiveContains(search) || id.uuidString.localizedCaseInsensitiveContains(search) else { return false }
            if skipped < offset { skipped += 1; return false }
            result.append(.init(reference: .init(kind: kind, id: id), title: value))
            return result.count >= limit
        }
        guard limit > 0 else { return [] }
        for note in library.notes { if append(.draft, note.id, note.title) { return result } }
        for revision in library.revisions {
            if append(.revision, revision.id, "Version · " + revision.date.formatted()) { return result }
        }
        for action in library.actions where !action.isSeparator { if append(.action, action.id, action.name) { return result } }
        for name in library.groupNames { if let id = library.actionGroupIdentifiers[name], append(.actionGroup, id, name) { return result } }
        for workspace in library.workspaces { if append(.workspace, workspace.id, workspace.name) { return result } }
        for theme in library.themes { if append(.theme, theme.id, theme.name) { return result } }
        for syntax in library.syntaxes where syntax.type != "builtIn" { if append(.syntax, syntax.id, syntax.name) { return result } }
        for bookmark in bookmarkDefaults.flatMap({ try? BookmarkPreferences.agentRecords(defaults: $0) }) ?? [] {
            if append(.bookmark, bookmark.id, bookmark.name) { return result }
        }
        for window in (try? editors?.windowSnapshots()) ?? [] { if append(.window, window.id, "Editor window") { return result } }
        return result
    }

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
        } + (bookmarkDefaults.flatMap { try? BookmarkPreferences.agentRecords(defaults: $0) } ?? []).map { bookmark in
            .init(reference: .init(kind: .bookmark, id: bookmark.id), title: bookmark.name)
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
