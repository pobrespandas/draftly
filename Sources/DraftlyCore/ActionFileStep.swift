import Foundation

struct ActionFileStep {
    let values: [String: Any]
    init(_ step: ActionStep, text: String, render: (String) throws -> String) throws {
        if step.type == "export" {
            values = ["text": text, "name": try render(step.values["name"] ?? "[[safe_title]].txt")]
        } else {
            values = ["text": text,
                      "name": try render(step.values["fileNameTemplate"] ?? step.values["name"] ?? "[[safe_title]].md"),
                      "bookmark": step.values["useBookmark"] == "true" ? step.values["bookmarkName"] ?? "" : "",
                      "folder": try render(step.values["folderTemplate"] ?? ""),
                      "mode": step.values["writeType"] ?? "create"]
        }
    }
}
