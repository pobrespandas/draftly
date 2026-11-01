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
        let symbols: [String: String] = [
            "Mail": "envelope.fill", "Message": "message.fill", "Google Search": "doc.text.magnifyingglass",
            "List in Reminders": "checklist", "Save to Files": "rectangle.portrait.and.arrow.right",
            "Save to Files as...": "rectangle.portrait.and.arrow.right", "Save to iCloud Drive": "icloud",
            "Append to iCloud Journal": "book.closed.fill", "Save to OneDrive": "cloud.fill",
            "Append to OneDrive Journal": "cloud.fill", "Move Left": "chevron.left", "Move Right": "chevron.right",
            "Move Back by Word": "chevron.left.2", "Move Forward by Word": "chevron.right.2",
            "Advanced Find": "plus.magnifyingglass", "Toggle Tasks": "checklist",
            "Markdown Footnote (^)": "chevron.up", "Inline Code (`)": "command", "Code Block (```)": "command",
            "Quote-Increase (>)": "chevron.right", "Quote-Decrease": "chevron.left",
            "UPPER": "arrow.up.circle.fill", "lower": "arrow.down.circle.fill", "Title": "textformat",
            "Straighten Quotes": "textformat", "Strip Diacritics": "textformat",
            "Strip Line Feed": "chevron.left.circle.fill", "Strip Extra Blank Lines": "chevron.left.circle.fill",
            "Hard Wrap": "line.3.horizontal.circle", "Trim Whitespace": "minus.square.fill",
            "Smart Parentheses": "pencil.line", "Smart Brackets": "pencil.line", "Smart Braces": "pencil.line",
            "Encode...": "chevron.right.2", "Decode...": "chevron.left.2",
            "Update Tags...": "tag.fill", "Rename Tag...": "tag.fill", "Flag": "flag.fill",
            "Unflag": "flag.slash", "Apply Template": "doc.badge.plus",
            "Previous Placeholder <|>": "chevron.up", "Next Placeholder <|>": "chevron.down"
        ]
        if source.symbol == original.symbol, let symbol = symbols[source.name] { action.symbol = symbol }
        if source.presentation.tintColor == nil {
            let colors: [String: String] = [
                "Message": "green", "Google Search": "green", "Send to Reminders": "gray",
                "Save to Files": "orange", "Save to Files as...": "green", "Save to iCloud Drive": "green",
                "Append to iCloud Journal": "green", "Save to Google Drive": "red",
                "Append to Google Drive Journal": "green", "Save to OneDrive": "orange", "Append to OneDrive Journal": "orange",
                "Move Left": "yellow", "Move Right": "yellow", "Move Back by Word": "orange",
                "Move Forward by Word": "orange", "Find": "green", "Toggle Tasks": "indigo",
                "Dictate New Draft": "green", "Indent": "orange", "Outdent": "orange",
                "Toggle Theme": "gray", "Inline Code (`)": "gray", "Markdown Footnote (^)": "gray",
                "Code Block (```)": "gray", "Markdown List": "yellow", "Markdown Table": "purple",
                "Edit Markdown Table": "indigo", "Preview": "gray", "Preview - RTL": "gray",
                "Copy as HTML": "gray", "Copy as Rich Text": "gray", "Copy as Rich Text w/o Styles": "gray",
                "Straighten Quotes": "yellow", "Strip Diacritics": "yellow", "Strip Line Feed": "indigo",
                "Hard Wrap": "indigo", "Strip Extra Blank Lines": "orange", "Trim Whitespace": "yellow",
                "Remove Blank Lines": "yellow", "Format Number": "yellow", "Archive": "gray", "Trash": "red",
                "Update Tags...": "orange", "Rename Tag...": "red", "Flag": "orange", "Unflag": "gray",
                "Select Workspace": "gray", "Filter by Tag": "gray", "New Draft in Workspace": "green",
                "Apply Template": "indigo", "Previous Placeholder <|>": "yellow", "Next Placeholder <|>": "yellow"
            ]
            action.presentation.tintColor = colors[source.name] ?? "blue"
        }
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
