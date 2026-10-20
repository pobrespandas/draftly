import AppKit

enum HTMLPreferences {
    static let pasteKey = "html.pasteAsMarkdown"
    static func options(defaults: UserDefaults = .standard) -> [String: Any] {
        let strong = defaults.string(forKey: "html.strongMark") ?? "**"
        let emphasis = defaults.string(forKey: "html.emphasisMark") ?? "_"
        let list = defaults.string(forKey: "html.ulItemMark") ?? "-"
        return [
            "strongMark": ["**", "__"].contains(strong) ? strong : "**",
            "emphasisMark": ["*", "_"].contains(emphasis) ? emphasis : "_",
            "ulItemMark": ["*", "-"].contains(list) ? list : "-",
            "inlineLinks": defaults.object(forKey: "html.inlineLinks") as? Bool ?? true,
            "linksEachParagraph": defaults.bool(forKey: "html.linksEachParagraph"),
            "ignoreLinks": defaults.bool(forKey: "html.ignoreLinks"),
            "ignoreImages": defaults.bool(forKey: "html.ignoreImages"),
            "ignoreEmphasis": defaults.bool(forKey: "html.ignoreEmphasis")
        ]
    }
}
