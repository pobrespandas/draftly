import Foundation
import Testing
@testable import DraftlyCore

@MainActor final class APIContractHost: ActionHost {
    var calls: [(String, [String: Any])] = []
    var clipboard = ""
    var previewSuccess = true
    var callbackStatus = "success"
    var confirmation = true
    var templateFiles: [String: String] = [:]
    var selectedIndex: Int? = 0
    var onPerform: ((String) -> Void)?
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        calls.append((operation, values))
        onPerform?(operation)
        switch operation {
        case "selectPrompt": return selectedIndex.map { ["index": $0] }
        case "confirmAction": return confirmation
        case "actionNotification": return true
        case "fileAPI":
            let path = values["path"] as? String ?? ""
            if values["operation"] as? String == "listContents" { return templateFiles.keys.filter { $0.hasPrefix(path + "/") }.sorted() }
            if let text = templateFiles[path] { return text }
            throw DraftlyError.message("Missing template")
        case "clipboard": clipboard = values["text"] as? String ?? ""; return true
        case "getClipboard": return clipboard
        case "prompt":
            var fields: [String: Any] = [:]
            for field in values["fields"] as? [[String: Any]] ?? [] { if let key = field["key"] as? String { fields[key] = field["value"] } }
            return ["index": 0, "fields": fields]
        case "htmlPreview": return ["success": previewSuccess, "values": ["answer": ["value": 42]]]
        case "callbackURL": return ["status": callbackStatus, "parameters": ["result": "Returned + café"]]
        case "requireScript": return "function loadedHelper(value) { return value.toUpperCase(); }"
        case "shortcut": return "Shortcut output"
        case "appleScript": return ["value": 42]
        case "markdown": return MarkdownRenderer.render(values["text"] as? String ?? "")
        default: throw DraftlyError.message("Unexpected test operation: \(operation)")
        }
    }
}

@MainActor
func makeAPIContext(_ content: String = "# Source\nBody") throws -> (LibraryStore, EditorSession, APIContractHost, ActionRunner) {
    let fixture = try ScriptTestFixture(content: content, host: APIContractHost())
    return (fixture.library, fixture.editor, fixture.host, fixture.runner)
}

func makeAPIAction(_ script: String, async: Bool = false) -> DraftAction {
    ScriptTestAction.make(script, name: "API contract", allowAsync: async)
}
