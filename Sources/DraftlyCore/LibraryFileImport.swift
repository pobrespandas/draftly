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
        if fileExtension.lowercased() == "draftsactiongroup" {
            let (group, actions) = try DraftsActionGroupImport.decode(data)
            guard Set(actions.map(\.id)).count == actions.count else { throw DraftlyError.message("The action group has duplicate action identities.") }
            let identities = library.actionGroupIdentifiers
            guard (identities[group.name] == nil || identities[group.name] == group.id),
                  !identities.contains(where: { $0.key != group.name && $0.value == group.id }),
                  !library.actionGroups.contains(where: { $0.id == group.id && $0 != group }),
                  !actions.contains(where: { incoming in library.actions.contains { $0.id == incoming.id && !equivalentImportedActions($0, incoming) } }) else {
                throw DraftlyError.message("The action group conflicts with installed data. Review it before importing.")
            }
            let existingIDs = Set(library.actions.map(\.id))
            let backup = Backup(notes: [], revisions: [], workspaces: [], actions: actions.filter { !existingIDs.contains($0.id) }, actionGroups: [group])
            try library.restore(JSONEncoder().encode(backup))
            return
        }
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

    private static func equivalentImportedActions(_ left: DraftAction, _ right: DraftAction) -> Bool {
        func normalized(_ action: DraftAction) -> DraftAction {
            var result = action
            for index in result.steps.indices {
                for key in ["data", "parameters", "values"] {
                    guard let value = result.steps[index].values[key],
                          let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)),
                          JSONSerialization.isValidJSONObject(object),
                          let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { continue }
                    result.steps[index].values[key] = String(decoding: data, as: UTF8.self)
                }
            }
            return result
        }
        return normalized(left) == normalized(right)
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
