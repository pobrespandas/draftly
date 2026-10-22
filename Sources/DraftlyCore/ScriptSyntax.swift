import Foundation

public enum ScriptSyntax {
    public static let names = ["Plain Text", "Markdown", "TaskPaper", "JavaScript", "Simple List", "MultiMarkdown", "GitHub Markdown"]
    public static func isMarkdown(_ syntax: String) -> Bool { ["Markdown", "MultiMarkdown", "GitHub Markdown"].contains(syntax) }
    public static func preview(_ content: String, syntax: String) throws -> String {
        if isMarkdown(syntax) { return try MarkdownPreferences.render(content, syntax: syntax) }
        return "<pre>" + MarkdownRenderer.escape(content) + "</pre>"
    }
}

public extension ScriptSyntax {
    static func definition(_ name: String) throws -> SyntaxDefinition {
        guard names.contains(name) else { throw DraftlyError.message("The syntax is not installed: \(name)") }
        var tasks: [[String: Any]] = [], markers: [[String: Any]] = [], links: [[String: Any]] = []
        if isMarkdown(name) || name == "Simple List" {
            tasks = [["match": #"(\[[ xX]\])"#, "rangeType": "task", "captures": ["interactive": "1", "state": "1"], "states": ["[ ]", "[x]"], "initialState": "[ ]", "completedState": ["[x]"], "caseInsensitiveStates": true]]
        }
        if isMarkdown(name) {
            tasks[0]["scopes"] = ["interactive": "text.monospace.bold"]
            markers = (1...6).map { level in ["match": "^" + String(repeating: "#", count: level) + #" ([^\r\n]*)"#, "rangeCapture": "0", "labelCapture": "1", "prefix": "H\(level)", "level": level - 1] }
            links = [["match": #"(\[\[)((?:([^:\]\r\n]+):)?([^\]\r\n]+))(\]\])"#, "captures": ["prefix": "1", "link": "2", "key": "3", "value": "4", "suffix": "5"]]]
        }
        if name == "TaskPaper" {
            tasks = [["match": #"^(\h*-\h+)([^\r\n]*?)( @done(?:\([^\r\n)]*\))?|)$"#, "rangeType": "line", "captures": ["interactive": "1", "state": "3", "label": "2"], "states": ["", " @done"], "initialState": "", "completedState": [" @done"]]]
            markers = [["match": #"^\h*([^\s-][^\r\n]*):\h*$"#, "rangeCapture": "0", "labelCapture": "1", "prefix": "Project", "level": 0]]
        }
        return try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: ["name": name, "patterns": [], "indentationPatterns": [], "taskMarkDefinitions": tasks, "navigationPatterns": markers, "linkDefinitions": links]), type: "builtIn")
    }
}
