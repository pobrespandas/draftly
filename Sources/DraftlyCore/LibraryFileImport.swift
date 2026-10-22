import Foundation

@MainActor public enum LibraryFileImport {
    public struct File {
        public let data: Data
        public let fileExtension: String
        public init(data: Data, fileExtension: String) {
            self.data = data; self.fileExtension = fileExtension
        }
    }

    public static func apply(_ files: [File], to library: LibraryStore) throws {
        guard !files.isEmpty else { return }
        if files.count == 1, let file = files.first {
            try apply(file.data, fileExtension: file.fileExtension, to: library)
            return
        }
        let staging = try LibraryStore(inMemory: true, seed: false)
        try staging.restore(library.backupData())
        for file in files { try apply(file.data, fileExtension: file.fileExtension, to: staging) }
        try library.applyImportedRecords(from: staging)
    }

    public static func apply(_ data: Data, fileExtension: String, to library: LibraryStore) throws {
        if fileExtension.lowercased() == "draftssyntax" {
            let definition = try SyntaxDefinition(data: data)
            if let existing = library.syntaxes.first(where: { $0.name == definition.name }) {
                guard existing.type == "custom", existing.source == definition.source else {
                    throw DraftlyError.message("This syntax is already installed. Use Import Syntax to review its replacement.")
                }
                return
            }
            try library.saveSyntax(definition)
            return
        }
        let object = try? JSONSerialization.jsonObject(with: data)
        let dictionary = object as? [String: Any]
        let entries = object as? [[String: Any]] ?? []
        if dictionary?["version"] != nil, dictionary?["revisions"] != nil {
            try library.restore(data)
        } else if dictionary?["actions"] != nil || dictionary?["steps"] != nil && dictionary?["name"] != nil
                    || entries.contains(where: { $0["steps"] != nil }) {
            try library.saveActions(ActionImporter.decode(data))
        } else if dictionary?["drafts"] != nil || entries.contains(where: { $0["content"] != nil }) {
            try applyNotes(ActionImporter.importNotes(data), to: library)
        } else if let actions = try? ActionImporter.decode(data) {
            try library.saveActions(actions)
        } else if let notes = try? ActionImporter.importNotes(data) {
            try applyNotes(notes, to: library)
        } else if fileExtension.lowercased() != "json", let content = String(data: data, encoding: .utf8) {
            _ = try library.createNote(content: content)
        } else {
            throw DraftlyError.message("This file is not a Draftly backup, Drafts export, or action file.")
        }
    }

    private static func applyNotes(_ notes: [Note], to library: LibraryStore) throws {
        var existing = Dictionary(uniqueKeysWithValues: library.notes.map { ($0.id, $0) })
        var incoming: [Note] = []
        for var note in notes {
            if let prior = existing[note.id], prior.content != note.content { note.id = UUID() }
            existing[note.id] = note
            incoming.append(note)
        }
        try library.saveNotes(incoming, preserveDates: true)
    }
}
