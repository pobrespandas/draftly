import Foundation

public enum DraftExportFormat: String, CaseIterable { case txt, csv, json }

public enum MergeDestination: String, CaseIterable, Sendable {
    case archive = "Archive", trash = "Trash", keep = "Do Not Move"
}

public enum DraftOperations {
    // Draft content identity preserves code units; it does not normalize Unicode.
    package static func sameText(_ first: String, _ second: String) -> Bool {
        first.utf8.elementsEqual(second.utf8)
    }

    public static func duplicate(_ source: Note, at date: Date = Date()) -> Note {
        Note(content: source.content, tags: source.tags, flag: source.flag,
             createdAt: date, modifiedAt: date, syntax: source.syntax)
    }
    public static func merge(_ sources: [Note], at date: Date = Date()) throws -> Note {
        guard sources.count >= 2 else { throw DraftlyError.message("Select at least two drafts to merge.") }
        let syntax = Set(sources.map(\.syntax)).count == 1 ? sources[0].syntax : "Markdown"
        return Note(content: sources.map(\.content).joined(separator: "\n\n"),
                    tags: TagRules.normalize(sources.flatMap(\.tags)), createdAt: date, modifiedAt: date, syntax: syntax)
    }
    public static func merge(_ sources: [Note], separator: String, includeBlankLine: Bool, at date: Date = Date()) throws -> Note {
        var note = try merge(sources, at: date)
        let joiner = separator.isEmpty ? "\n" : (includeBlankLine ? "\n\n" : "\n") + separator + (includeBlankLine ? "\n\n" : "\n")
        note.content = sources.map(\.content).joined(separator: joiner)
        return note
    }
    public static func export(_ notes: [Note], as format: DraftExportFormat) throws -> Data {
        let dates = ISO8601DateFormatter(); dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        switch format {
        case .txt: return Data(notes.map(\.content).joined(separator: "\n\n").utf8)
        case .json:
            let entries: [[String: Any]] = notes.map { note in
                ["uuid": note.id.uuidString, "title": note.title, "content": note.content, "tags": note.tags,
                 "flag": note.flag, "syntax": note.syntax, "isArchived": note.isArchived,
                 "trashedAt": note.trashedAt.map { dates.string(from: $0) } as Any? ?? NSNull(),
                 "createdAt": dates.string(from: note.createdAt), "modifiedAt": dates.string(from: note.modifiedAt)]
            }
            return try JSONSerialization.data(withJSONObject: ["drafts": entries], options: [.prettyPrinted, .sortedKeys])
        case .csv:
            func escape(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            var rows = ["uuid,title,content,tags,flag,syntax,isArchived,trashedAt,createdAt,modifiedAt"]
            for note in notes {
                let tags = String(data: try JSONEncoder().encode(note.tags), encoding: .utf8)!
                rows.append([note.id.uuidString, note.title, note.content, tags, String(note.flag), note.syntax,
                             String(note.isArchived), note.trashedAt.map { dates.string(from: $0) } ?? "",
                             dates.string(from: note.createdAt), dates.string(from: note.modifiedAt)].map(escape).joined(separator: ","))
            }
            return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
        }
    }
}

@MainActor
extension LibraryStore {
    public func mergeNotes(_ sources: [Note], separator: String = "", includeBlankLine: Bool = false,
                           destination: MergeDestination = .archive, at date: Date = Date()) throws -> Note {
        guard Set(sources.map(\.id)).count == sources.count else { throw DraftlyError.message("Select distinct drafts to merge.") }
        let merged = try DraftOperations.merge(sources, separator: separator, includeBlankLine: includeBlankLine, at: date)
        let originals: [Note] = destination == .keep ? [] : sources.map { source in
            var note = source
            if destination == .archive { note.isArchived = true; note.trashedAt = nil }
            else { note.trashedAt = date }
            note.modifiedAt = date
            return note
        }
        try saveNotes(originals + [merged], preserveRevision: false, preserveDates: true)
        return merged
    }
}
