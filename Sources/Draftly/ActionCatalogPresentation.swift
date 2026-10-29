import Foundation
import DraftlyCore

// Presentation keeps imported separators in the catalog without executable rows.
enum ActionCatalogPresentation {
    static func groupSymbol(_ name: String, groups: [ActionGroupRecord], searching: Bool = false) -> String {
        if searching { return "magnifyingglass" }
        return groups.first { $0.name == name }?.symbol ?? "arrow.up.right.square"
    }
    struct Entry: Identifiable {
        enum Kind: Equatable { case action, separator }
        let source: DraftAction
        let kind: Kind
        let sectionHeading: String?
        var id: UUID { source.id }
        var runnableAction: DraftAction? { kind == .action ? source : nil }
    }

    static func entries(_ orderedActions: [DraftAction], on surface: ActionSurface? = nil,
                        group: String? = nil, query: String = "") -> [Entry] {
        let searching: Bool
        if case .search? = surface { searching = true } else { searching = false }
        let filtered = orderedActions.filter { action in
            if let surface, !action.appears(on: surface) { return false }
            if let group, action.group != group { return false }
            if (searching || !query.isEmpty), action.isSeparator { return false }
            return query.isEmpty || action.name.localizedStandardContains(query) || action.presentation.description.localizedStandardContains(query)
        }
        var previousGroup: String?, previousSection: String?
        return filtered.map { action in
            let section = action.presentation.section
            let heading = !section.isEmpty && (previousGroup != action.group || previousSection != section) ? section : nil
            previousGroup = action.group; previousSection = section
            return Entry(source: action, kind: action.isSeparator ? .separator : .action, sectionHeading: heading)
        }
    }

    static func actions(_ orderedActions: [DraftAction], on surface: ActionSurface? = nil,
                        group: String? = nil, query: String = "") -> [DraftAction] {
        entries(orderedActions, on: surface, group: group, query: query).compactMap(\.runnableAction)
    }
}
