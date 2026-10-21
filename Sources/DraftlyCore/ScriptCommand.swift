import Foundation

// Keep wire values at the boundary. Resolve notes after any required editor save.
struct ScriptNoteInput {
    private let values: [String: Any]
    let preserveDates: Bool

    init(_ values: [String: Any]) {
        self.values = values
        preserveDates = values["_preserveDates"] as? Bool ?? false
    }

    @MainActor func resolve(in library: LibraryStore) throws -> Note {
        try ActionScriptValues.decodedNote(values, notes: library.notes)
    }
}

struct ScriptWorkspaceInput {
    private let values: [String: Any]
    init(_ values: [String: Any]) { self.values = values }
    func resolve() throws -> Workspace { try APIValues.workspace(values) }
}

struct ScriptDraftQuery {
    let workspace: Workspace
    let omitFlagged: Bool
    let flaggedToTop: Bool

    init(_ values: [String: Any]) throws {
        var workspace = Workspace(name: "Script")
        workspace.query = values["query"] as? String ?? ""
        if let error = DraftQuery(workspace.query).error { throw DraftlyError.message(error) }
        guard let folder = NoteFolder(rawValue: values["folder"] as? String ?? "all") else {
            throw DraftlyError.message("The draft query folder is invalid.")
        }
        workspace.folder = folder
        workspace.tags = values["tags"] as? [String] ?? []
        workspace.excludedTags = values["omitTags"] as? [String] ?? []
        let sortName = values["sort"] as? String ?? "modified"
        guard ["name", "title", "modified", "created", "accessed"].contains(sortName) else {
            throw DraftlyError.message("The draft query sort is invalid.")
        }
        workspace.sort = sortName == "name" ? .title : NoteSort(rawValue: sortName) ?? .modified
        workspace.ascending = !(values["descending"] as? Bool ?? true)
        self.workspace = workspace
        omitFlagged = values["omitFlagged"] as? Bool ?? false
        flaggedToTop = values["flaggedToTop"] as? Bool ?? false
    }
}

struct ScriptTextRange {
    let value: NSRange

    init(_ values: [String: Any]) {
        value = NSRange(location: values["location"] as? Int ?? 0, length: values["length"] as? Int ?? 0)
    }

    func validated(in text: String) throws -> NSRange {
        let count = (text as NSString).length
        guard value.location >= 0, value.length >= 0, value.location <= count,
              value.length <= count - value.location else {
            throw DraftlyError.message("The text range is outside the draft.")
        }
        return value
    }
}

// A nil command delegates to the remaining API and native capability adapters.
enum ScriptCommand {
    case newDraft
    case findDraft(UUID?)
    case queryDrafts(ScriptDraftQuery)
    case updateDraft(ScriptNoteInput)
    case loadDraft(ScriptNoteInput)
    case editorText
    case setEditorText(String)
    case selection
    case selectionRange
    case lineRange(ScriptTextRange, text: String?)
    case setSelection(ScriptTextRange)
    case replaceSelection(String)
    case textInRange(ScriptTextRange)
    case replaceRange(ScriptTextRange, text: String)
    case template(String, note: ScriptNoteInput, tags: [String: String])
    case setTemplateTag(String, value: String)
    case activate
    case message(String)
    case displayMessage(String, severity: String)
    case findAction(String?)
    case queueAction(id: String?, note: ScriptNoteInput)
    case findWorkspace(String?)
    case applyWorkspace(ScriptWorkspaceInput)
    case base64Encode(String)
    case base64Decode(String)

    init?(operation: String, values: [String: Any]) throws {
        switch operation {
        case "newDraft": self = .newDraft
        case "findDraft": self = .findDraft((values["uuid"] as? String).flatMap(UUID.init(uuidString:)))
        case "queryDrafts": self = .queryDrafts(try ScriptDraftQuery(values))
        case "updateDraft": self = .updateDraft(ScriptNoteInput(values))
        case "loadDraft": self = .loadDraft(ScriptNoteInput(values))
        case "editorText": self = .editorText
        case "setEditorText": self = .setEditorText(values["text"] as? String ?? "")
        case "selection": self = .selection
        case "selectionRange": self = .selectionRange
        case "lineRange": self = .lineRange(ScriptTextRange(values), text: values["text"] as? String)
        case "setSelection": self = .setSelection(ScriptTextRange(values))
        case "replaceSelection": self = .replaceSelection(values["text"] as? String ?? "")
        case "textInRange": self = .textInRange(ScriptTextRange(values))
        case "replaceRange": self = .replaceRange(ScriptTextRange(values), text: values["text"] as? String ?? "")
        case "template":
            self = .template(values["text"] as? String ?? "", note: ScriptNoteInput(values["note"] as? [String: Any] ?? [:]), tags: values["tags"] as? [String: String] ?? [:])
        case "setTemplateTag": self = .setTemplateTag(values["key"] as? String ?? "", value: values["value"] as? String ?? "")
        case "activate": self = .activate
        case "message": self = .message(values["message"] as? String ?? "")
        case "displayMessage": self = .displayMessage(values["message"] as? String ?? "", severity: values["severity"] as? String ?? "info")
        case "findAction": self = .findAction(values["name"] as? String)
        case "queueAction":
            let action = values["action"] as? [String: Any] ?? [:]
            self = .queueAction(id: action["uuid"] as? String, note: ScriptNoteInput(values["draft"] as? [String: Any] ?? [:]))
        case "findWorkspace": self = .findWorkspace(values["name"] as? String)
        case "applyWorkspace": self = .applyWorkspace(ScriptWorkspaceInput(values))
        case "base64Encode": self = .base64Encode(values["text"] as? String ?? "")
        case "base64Decode": self = .base64Decode(values["text"] as? String ?? "")
        default: return nil
        }
    }
}
