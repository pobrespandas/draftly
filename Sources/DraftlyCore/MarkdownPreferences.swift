import Foundation

public enum MarkdownPreferences {
    public static let engineKey = "markdown.processor"
    public static let multiKey = "markdown.options.multi"
    public static let githubKey = "markdown.options.github"

    public struct Option: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let defaultValue: Bool
    }

    public static let multiOptions: [Option] = [
        Option(id: "markdownCompatibilityMode", title: "Compatibility mode", defaultValue: false),
        Option(id: "smartQuotesEnabled", title: "Smart quotes", defaultValue: true),
        Option(id: "footnotesEnabled", title: "Footnotes", defaultValue: true),
        Option(id: "randomFootnotes", title: "Random footnotes", defaultValue: false),
        Option(id: "noLabels", title: "No labels", defaultValue: true),
        Option(id: "processHTML", title: "Process HTML", defaultValue: true),
        Option(id: "noMetadata", title: "No metadata", defaultValue: false),
        Option(id: "obfuscate", title: "Obfuscate", defaultValue: false),
        Option(id: "criticMarkup", title: "Critic markup", defaultValue: false),
        Option(id: "criticMarkupAccept", title: "Critic markup: Accept", defaultValue: false),
        Option(id: "criticMarkupReject", title: "Critic markup: Reject", defaultValue: false)
    ]
    public static let githubOptions: [Option] = [
        Option(id: "tables", title: "Tables", defaultValue: true),
        Option(id: "autoLinks", title: "Auto Links", defaultValue: true),
        Option(id: "strikethrough", title: "Strikethrough", defaultValue: true),
        Option(id: "tagFilters", title: "Tag filters", defaultValue: true),
        Option(id: "taskLists", title: "Task lists", defaultValue: true),
        Option(id: "sourcePOS", title: "Source POS", defaultValue: true),
        Option(id: "hardBreaks", title: "Hard breaks", defaultValue: false),
        Option(id: "safe", title: "Safe tags", defaultValue: true),
        Option(id: "unsafe", title: "Unsafe tags", defaultValue: false),
        Option(id: "validateUTF8", title: "Validate UTF-8", defaultValue: false),
        Option(id: "smartQuotes", title: "Smart quotes", defaultValue: true),
        Option(id: "footnotes", title: "Footnotes", defaultValue: true)
    ]

    public static func options(engine: String, json: String) -> [String: Bool] {
        let stored = (try? JSONDecoder().decode([String: Bool].self, from: Data(json.utf8))) ?? [:]
        return (engine == "multi" ? multiOptions : githubOptions).reduce(into: stored) {
            if $0[$1.id] == nil { $0[$1.id] = $1.defaultValue }
        }
    }

    public static func render(_ text: String, syntax: String = "Markdown", defaults: UserDefaults = .standard) throws -> String {
        let preferred = defaults.string(forKey: engineKey) ?? "multi"
        let engine = syntax == "MultiMarkdown" ? "multi" : syntax == "GitHub Markdown" ? "github" : preferred == "github" ? "github" : "multi"
        let json = defaults.string(forKey: engine == "multi" ? multiKey : githubKey) ?? "{}"
        return try ScriptMarkdown.render(text, engine: engine, options: options(engine: engine, json: json))
    }
}
