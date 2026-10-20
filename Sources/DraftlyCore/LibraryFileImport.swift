import Foundation

@MainActor public enum LibraryFileImport {
    public static func apply(_ data: Data, fileExtension: String, to library: LibraryStore) throws {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["version"] != nil, object["revisions"] != nil {
            try library.restore(data)
        } else if let actions = try? ActionImporter.decode(data) {
            try library.saveActions(actions)
        } else if let notes = try? ActionImporter.importNotes(data) {
            var existing = Dictionary(uniqueKeysWithValues: library.notes.map { ($0.id, $0) })
            var incoming: [Note] = []
            for var note in notes {
                if let prior = existing[note.id], prior.content != note.content { note.id = UUID() }
                existing[note.id] = note
                incoming.append(note)
            }
            try library.saveNotes(incoming, preserveDates: true)
        } else if fileExtension.lowercased() != "json", let content = String(data: data, encoding: .utf8) {
            _ = try library.createNote(content: content)
        } else {
            throw DraftlyError.message("This file is not a Draftly backup, Drafts export, or action file.")
        }
    }
}
