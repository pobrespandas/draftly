import Foundation

public struct HelpArticle: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let markdown: String

    public func matches(_ query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy {
            (title + " " + category + " " + markdown).localizedStandardContains(String($0))
        }
    }
}

public enum HelpGuide {
    private static let index: [(String, String, String)] = [
        ("01-start", "Start here", "Basics"),
        ("02-install", "Install and update", "Basics"),
        ("03-capture", "Capture and multiple windows", "Writing"),
        ("04-editor", "Write, select, and undo", "Writing"),
        ("05-markdown", "Markdown and preview", "Writing"),
        ("06-organize", "Tags, flags, Archive, and Trash", "Library"),
        ("07-search", "Search and workspaces", "Library"),
        ("08-actions", "Run and manage actions", "Actions"),
        ("09-chat", "ChatGPT and Apple Intelligence", "Chat and agents"),
        ("10-tools", "Chat tools and access", "Chat and agents"),
        ("11-mcp", "CLI and MCP clients", "Chat and agents"),
        ("12-control", "Permissions, reviews, and Stop Work", "Chat and agents"),
        ("13-settings", "Fonts, themes, syntax, and shortcuts", "Settings and data"),
        ("14-cloud", "iCloud and local storage", "Settings and data"),
        ("15-backup", "Import, export, and recovery", "Settings and data"),
        ("16-maintenance", "Maintenance and default actions", "Settings and data"),
        ("17-automation", "Scripts, Shortcuts, and URLs", "Actions"),
        ("18-troubleshooting", "Troubleshooting and support", "Reference")
    ]

    public static func articles() throws -> [HelpArticle] {
        try index.map { id, title, category in
            guard let url = Bundle.module.url(forResource: "help-" + id, withExtension: "md") else {
                throw DraftlyError.message("A help article is missing: " + id)
            }
            return HelpArticle(id: id, title: title, category: category,
                markdown: try String(contentsOf: url, encoding: .utf8))
        }
    }
}
