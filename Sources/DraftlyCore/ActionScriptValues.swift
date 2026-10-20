import Foundation

enum ActionScriptValues {
    static func noteValue(_ note: Note, syntaxes: [SyntaxDefinition]) -> [String: Any] {
        var result: [String: Any] = ["uuid": note.id.uuidString, "content": note.content, "tags": note.tags, "isArchived": note.isArchived,
            "isTrashed": note.trashedAt != nil, "isFlagged": note.flag > 0, "flagType": note.flag, "syntax": ["name": note.syntax, "type": syntaxes.first(where: { $0.name == note.syntax })?.type ?? "builtIn"],
            "createdAt": APIValues.date(note.createdAt), "modifiedAt": APIValues.date(note.modifiedAt)]
        for key in ["createdLatitude", "createdLongitude", "modifiedLatitude", "modifiedLongitude", "selectionStart", "selectionLength"] {
            result[key] = Double(note.scriptMetadata?[key] ?? "0") ?? 0
        }
        return result
    }
    static func decodedNote(_ values: [String: Any], notes: [Note]) throws -> Note {
        guard let uuid = values["uuid"] as? String, let id = UUID(uuidString: uuid) else { throw DraftlyError.message("The draft ID is invalid.") }
        var note = notes.first(where: { $0.id == id }) ?? Note(id: id)
        note.content = values["content"] as? String ?? note.content
        note.tags = values["tags"] as? [String] ?? note.tags
        note.isArchived = values["isArchived"] as? Bool ?? note.isArchived
        if let flagged = values["isFlagged"] as? Bool { note.flag = flagged ? 1 : 0 }
        note.syntax = values["syntax"] as? String ?? (values["syntax"] as? [String: Any])?["name"] as? String ?? note.syntax
        if let flag = values["flagType"] as? Int { note.flag = min(7, max(0, flag)) }
        if let trashed = values["isTrashed"] as? Bool { note.trashedAt = trashed ? note.trashedAt ?? Date() : nil }
        note.createdAt = APIValues.parseDate(values["createdAt"]) ?? note.createdAt
        note.modifiedAt = APIValues.parseDate(values["modifiedAt"]) ?? note.modifiedAt
        for key in ["createdLatitude", "createdLongitude", "modifiedLatitude", "modifiedLongitude"] {
            if let value = values[key] as? NSNumber { note.scriptMetadata = note.scriptMetadata ?? [:]; note.scriptMetadata?[key] = value.stringValue }
        }
        return note
    }

}
