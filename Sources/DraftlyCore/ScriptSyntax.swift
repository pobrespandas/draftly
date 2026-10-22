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
        var tasks: [[String: Any]] = [], markers: [[String: Any]] = [], links: [[String: Any]] = [], lists: [[String: Any]] = [], completions: [[String: Any]] = []
        if isMarkdown(name) || name == "Simple List" {
            tasks = [["match": #"(\[[ xX]\])"#, "rangeType": "task", "captures": ["interactive": "1", "state": "1"], "states": ["[ ]", "[x]"], "initialState": "[ ]", "completedState": ["[x]"], "caseInsensitiveStates": true]]
        }
        if isMarkdown(name) {
            completions = [
                ["trigger": "[[", "type": "draft", "label": "[[display_title]]", "value": "[[display_title]]", "queryType": "title", "queryTagFilter": "", "prefix": "[[", "suffix": "]]"],
                ["trigger": "<<", "type": "draft", "label": "[[display_title]]", "value": "[[draft]]", "queryType": "title", "queryTagFilter": "", "prefix": "", "suffix": ""]
            ]
            tasks[0]["scopes"] = ["interactive": "text.monospace.bold"]
            markers = (1...6).map { level in ["match": "^" + String(repeating: "#", count: level) + #" ([^\r\n]*)"#, "rangeCapture": "0", "labelCapture": "1", "prefix": "H\(level)", "level": level - 1] }
            links = [["match": #"(\[\[)((?:([^:\]\r\n]+):)?([^\]\r\n]+))(\]\])"#, "captures": ["prefix": "1", "link": "2", "key": "3", "value": "4", "suffix": "5"]]]
        }
        if isMarkdown(name) {
            links[0]["templates"] = [
                "": "draftly://open?title=[[value]]&allowCreate=true",
                "d": "draftly://open?title=[[value]]&allowCreate=true",
                "u": "draftly://open?uuid=[[value]]",
                "s": "draftly://quickSearch?query=[[value]]",
                "w": "draftly://workspace?name=[[value]]",
                "google": "https://www.google.com/search?q=[[value]]",
                "wikipedia": "https://en.wikipedia.org/wiki/[[value]]",
                "bear": "bear://x-callback-url/open-note?title=[[value]]"
            ]
            links[0]["scopes"] = ["key": "text.bold", "value": "text.italic", "prefix": "markup", "suffix": "markup"]
        }
        if isMarkdown(name) || name == "Simple List" {
            lists = [
                ["match": #"^(\h*)((?:[-*+>] )(?:\[[ xX]\] )?)([^\r\n]*)"#,
                 "captures": ["indent": "1", "prefix": "2", "line": "3"],
                 "replacements": ["[x]": "[ ]", "[X]": "[ ]"]],
                ["match": #"^(\h*)((\d+)\. (?:\[[ xX]\] )?)([^\r\n]*)"#,
                 "captures": ["indent": "1", "prefix": "2", "sequence": "3", "line": "4"],
                 "sequencePadding": "0", "replacements": ["[x]": "[ ]", "[X]": "[ ]"]]
            ]
        }
        if name == "TaskPaper" {
            tasks = [["match": #"^(\h*-\h+)([^\r\n]*?)( @done(?:\([^\r\n)]*\))?|)$"#, "rangeType": "line", "captures": ["interactive": "1", "state": "3", "label": "2"], "states": ["", " @done"], "initialState": "", "completedState": [" @done"]]]
            lists = [["match": #"^(\h*)(- )([^\r\n]*)"#, "captures": ["indent": "1", "prefix": "2", "line": "3"]]]
            markers = [["match": #"^\h*([^\s-][^\r\n]*):\h*$"#, "rangeCapture": "0", "labelCapture": "1", "prefix": "Project", "level": 0]]
        }
        return try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: ["name": name, "patterns": [], "indentationPatterns": [], "taskMarkDefinitions": tasks, "navigationPatterns": markers, "linkDefinitions": links, "listCompletionDefinitions": lists, "autocompleteDefinitions": completions], options: [.sortedKeys]), type: "builtIn")
    }
}
