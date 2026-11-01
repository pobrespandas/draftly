import AppKit

enum HTMLPreferences {
    static let pasteKey = "html.pasteAsMarkdown"
    static let strongMarks = ["**", "__"]
    static let emphasisMarks = ["_", "*"]
    static let listMarks = ["-", "*"]
    static let booleanDefaults = [pasteKey: true, "html.inlineLinks": true,
        "html.linksEachParagraph": false, "html.ignoreLinks": false,
        "html.ignoreImages": false, "html.ignoreEmphasis": false]
    static func options(defaults: UserDefaults = .standard) -> [String: Any] {
        let strong = defaults.string(forKey: "html.strongMark") ?? strongMarks[0]
        let emphasis = defaults.string(forKey: "html.emphasisMark") ?? emphasisMarks[0]
        let list = defaults.string(forKey: "html.ulItemMark") ?? listMarks[0]
        return [
            "strongMark": strongMarks.contains(strong) ? strong : strongMarks[0],
            "emphasisMark": emphasisMarks.contains(emphasis) ? emphasis : emphasisMarks[0],
            "ulItemMark": listMarks.contains(list) ? list : listMarks[0],
            "inlineLinks": defaults.object(forKey: "html.inlineLinks") as? Bool ?? booleanDefaults["html.inlineLinks"]!,
            "linksEachParagraph": defaults.object(forKey: "html.linksEachParagraph") == nil ? booleanDefaults["html.linksEachParagraph"]! : defaults.bool(forKey: "html.linksEachParagraph"),
            "ignoreLinks": defaults.object(forKey: "html.ignoreLinks") == nil ? booleanDefaults["html.ignoreLinks"]! : defaults.bool(forKey: "html.ignoreLinks"),
            "ignoreImages": defaults.object(forKey: "html.ignoreImages") == nil ? booleanDefaults["html.ignoreImages"]! : defaults.bool(forKey: "html.ignoreImages"),
            "ignoreEmphasis": defaults.object(forKey: "html.ignoreEmphasis") == nil ? booleanDefaults["html.ignoreEmphasis"]! : defaults.bool(forKey: "html.ignoreEmphasis")
        ]
    }
}
