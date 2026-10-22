import Foundation

struct ActionCreateDraftStep {
    let note: Note
    let opensInEditor: Bool

    init(_ step: ActionStep, text: String, validateSyntax: (String) throws -> Void,
         render: (String) throws -> String) throws {
        let location = step.values["folder"] ?? step.values["location"] ?? "inbox"
        guard ["inbox", "archive"].contains(location) else { throw DraftlyError.message("The new draft location is invalid.") }
        let syntax = ["syntax", "assignSyntax", "syntaxName", "grammarName", "grammarType"].compactMap { step.values[$0] }.first { !$0.isEmpty } ?? "Markdown"
        try validateSyntax(syntax)
        opensInEditor = ActionStepValueRules.createdDraftOpensInEditor(step.values)
        var note = Note(content: text, tags: TagRules.normalize((try render(step.values["tags"] ?? step.values["assignTags"] ?? "")).split(separator: ",").map(String.init)), flag: ["true", "1"].contains(step.values["flagged"] ?? "false") ? 1 : 0, isArchived: location == "archive", syntax: syntax, accessedAt: opensInEditor ? Date() : nil)
        if let flag = step.values["flagType"].flatMap(Int.init) {
            guard (0...7).contains(flag) else { throw DraftlyError.message("The new draft flag is invalid.") }
            note.flag = flag
        }
        self.note = note
    }
}
