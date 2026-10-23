import DraftlyCore

enum EditorSettingsSection: String, CaseIterable, Identifiable {
    case editing, syntax, themes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editing: "Editing"
        case .syntax: "Syntax Settings"
        case .themes: "Themes"
        }
    }

    var symbol: String {
        switch self {
        case .editing: "pencil"
        case .syntax: "curlybraces"
        case .themes: "paintpalette"
        }
    }
}

struct EditorSettingsNavigation {
    var section: EditorSettingsSection = .editing
    var syntax = "Markdown"

    static func syntaxes(installed: [String]) -> [String] {
        var seen = Set<String>()
        return (ScriptSyntax.names + installed.sorted()).filter {
            seen.insert($0).inserted
        }
    }

    mutating func reconcile(installed: [String]) {
        if !Self.syntaxes(installed: installed).contains(syntax) {
            syntax = "Markdown"
        }
    }
}
