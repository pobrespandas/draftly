import Foundation

struct ActionPromptStep {
    let key: String
    let titles: [String]
    let values: [String: Any]

    init(_ step: ActionStep, render: (String) throws -> String) throws {
        key = step.values["key"] ?? "prompt"
        titles = (step.values["buttons"] ?? "OK").split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard !key.isEmpty, !titles.contains(where: { $0.isEmpty }) else {
            throw DraftlyError.message("The prompt key and button titles must not be empty.")
        }
        let includeText = ["true", "1"].contains(step.values["includeTextField"] ?? "false")
        let fields: [[String: Any]] = includeText ? [["key": "text", "label": "", "kind": "text", "value": try render(step.values["textFieldDefault"] ?? "")]] : []
        values = ["title": try render(step.values["title"] ?? "Prompt"),
                  "message": try render(step.values["message"] ?? ""),
                  "isCancellable": step.values["includeCancelButton"] != "false",
                  "fields": fields, "buttons": titles.map { ["title": $0] }]
    }

    func tags(from result: Any?) throws -> [String: String]? {
        guard let result = result as? [String: Any] else { return nil }
        guard let index = result["index"] as? Int, titles.indices.contains(index) else {
            throw DraftlyError.message("The prompt returned an invalid button.")
        }
        return [key + "_button": titles[index],
                key + "_text": (result["fields"] as? [String: Any])?["text"] as? String ?? ""]
    }
}
