import Foundation
import DraftlyCore

// Presentation keeps imported separators in the catalog without executable rows.
enum ActionCatalogPresentation {
    private struct Appearance: Sendable { let name: String; let group: String; let symbol: String }
    private static let defaults = Dictionary(uniqueKeysWithValues: DefaultActionCatalog.actions.map {
        ($0.id, Appearance(name: $0.name, group: $0.group, symbol: $0.symbol))
    })
    private static let defaultGroups = Dictionary(uniqueKeysWithValues: DefaultActionCatalog.groups.map {
        ($0.id, Appearance(name: $0.name, group: $0.name, symbol: $0.symbol))
    })

    static func groupColor(_ name: String, groups: [ActionGroupRecord]) -> String {
        guard let group = groups.first(where: { $0.name == name }),
              defaultGroups[group.id] != nil else { return "gray" }
        return ["Basic", "Processing"].contains(name) ? "blue" : "gray"
    }

    static func groupSymbol(_ name: String, groups: [ActionGroupRecord], searching: Bool = false) -> String {
        if searching { return "magnifyingglass" }
        guard let group = groups.first(where: { $0.name == name }) else { return "arrow.up.right.square" }
        guard let original = defaultGroups[group.id], group.symbol == original.symbol else { return group.symbol }
        return ["Editing": "character.cursor.ibeam", "Markdown": "text.badge.star", "Tools": "curlybraces",
                "Processing": "arrow.left.arrow.right"][original.name] ?? group.symbol
    }

    // Apply reference appearance only to unchanged catalog fields. Keep custom actions intact.
    static func displayAction(_ source: DraftAction) -> DraftAction {
        guard let original = defaults[source.id], source.name == original.name, source.group == original.group else { return source }
        var action = source
        action = DefaultActionAppearance.applying(to: source)
        if source.symbol != original.symbol { action.symbol = source.symbol }
        return action
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
            if case .bar? = surface, action.isSeparator, defaults[action.id] != nil { return false }
            if let group, action.group != group { return false }
            if (searching || !query.isEmpty), action.isSeparator { return false }
            return query.isEmpty || action.name.localizedStandardContains(query) || action.presentation.description.localizedStandardContains(query)
        }
        var previousGroup: String?, previousSection: String?
        return filtered.map { source in
            let action = displayAction(source)
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
