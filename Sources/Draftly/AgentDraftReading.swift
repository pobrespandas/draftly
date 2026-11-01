import Foundation
import CryptoKit
import DraftlyCore
import AgentContracts

@MainActor final class AgentDraftReading {
    private let library: LibraryStore
    private let pages: AgentReadPages
    private let versionKey = SymmetricKey(size: .bits256)
    private let pendingEditorGeneration: (UUID) -> String
    private let editors: AgentEditorRegistry?

    init(library: LibraryStore, pages: AgentReadPages, editors: AgentEditorRegistry? = nil,
         pendingEditorGeneration: @escaping (UUID) -> String) {
        self.library = library; self.pages = pages; self.pendingEditorGeneration = pendingEditorGeneration
        self.editors = editors
    }

    func read(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant,
              sessionID: UUID) throws -> [String: AgentJSONValue] {
        func permitted(_ id: UUID) -> Bool { grant.scope.permits(.init(kind: .draft, id: id)) }
        switch request.operation {
        case "library.summary":
            return ["draftCount": .integer(Int64(library.notes.lazy.filter { permitted($0.id) }.count))]
        case "drafts.get":
            guard let note = library.notes.first(where: { $0.id == request.targets[0].id && permitted($0.id) }) else {
                throw AgentErrorCode.notFound
            }
            let state = try snapshot(note)
            return ["draft": .object(try summary(state)), "content": .object(try Self.chunk(state.note.content, parameters: parameters))]
        case "drafts.list", "drafts.search":
            let workspace = try query(parameters)
            return try pages.page(owner: .init(sessionID: sessionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt, ids: {
                    try workspace.filter(library.notes.filter { permitted($0.id) }.map { try snapshot($0).note }).map(\.id)
                }, value: { id in
                    guard permitted(id), let note = library.notes.first(where: { $0.id == id }) else { return nil }
                    return .object(try summary(snapshot(note), query: request.operation == "drafts.search" ? workspace.query : ""))
                })
        case "drafts.versions":
            let parent = request.targets[0].id
            guard permitted(parent), library.notes.contains(where: { $0.id == parent }) else { throw AgentErrorCode.notFound }
            return try pages.page(owner: .init(sessionID: sessionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt, ids: {
                    library.revisions.filter { $0.noteID == parent }.sorted {
                        $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
                    }.map(\.id)
                }, value: { id in
                    guard let revision = library.revisions.first(where: { $0.id == id && $0.noteID == parent }) else { return nil }
                    var result: [String: AgentJSONValue] = ["id": .string(id.uuidString), "noteID": .string(parent.uuidString),
                        "date": .string(APIValues.date(revision.date))]
                    if parameters["includeContent"] == .bool(true) { result["content"] = .string(revision.content) }
                    return .object(result)
                })
        default: throw AgentErrorCode.unavailable
        }
    }

    // This checks draft state, not authority. It does not reserve the state across an await.
    func checkedSnapshot(for id: UUID, expectedVersion: String) throws -> AgentEditorRegistry.Snapshot {
        guard !expectedVersion.isEmpty, expectedVersion.utf8.count <= 4096 else { throw AgentErrorCode.invalidInput }
        guard let note = library.notes.first(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
        let state = try snapshot(note)
        guard try versionToken(state) == expectedVersion else { throw AgentErrorCode.versionConflict }
        return state
    }

    func isBound(to library: LibraryStore, editors: AgentEditorRegistry) -> Bool {
        self.library === library && self.editors === editors && editors.isBound(to: library)
    }

    func validateMutationSnapshot(_ initial: AgentEditorRegistry.Snapshot, expectedVersion: String,
                                  reservedGeneration: String) throws {
        guard let editors else { throw AgentErrorCode.unavailable }
        try editors.validateMutationGeneration(for: initial.note.id, expected: reservedGeneration)
        guard let current = library.notes.first(where: { $0.id == initial.note.id }) else { throw AgentErrorCode.notFound }
        let state = AgentEditorRegistry.Snapshot(note: initial.note, storedNote: current, generation: initial.generation)
        guard try versionToken(state) == expectedVersion else { throw AgentErrorCode.versionConflict }
    }

    func mutationResources(for id: UUID, generation: String) -> @Sendable ([Note]) throws -> [LibraryMutationReceipt.Resource] {
        let key = versionKey, external = pendingEditorGeneration(id)
        return { notes in
            guard notes.count == 1, let note = notes.first, note.id == id else { throw AgentErrorCode.storageError }
            return [LibraryMutationReceipt.Resource(id: id,
                versionToken: try Self.version(note: note, stored: note, generation: generation, external: external, key: key))]
        }
    }

    private func snapshot(_ note: Note) throws -> AgentEditorRegistry.Snapshot {
        try editors?.snapshot(note) ?? .init(note: note, storedNote: note, generation: "")
    }

    private func versionToken(_ state: AgentEditorRegistry.Snapshot) throws -> String {
        try Self.version(note: state.note, stored: state.storedNote, generation: state.generation,
            external: pendingEditorGeneration(state.note.id), key: versionKey)
    }

    nonisolated private static func version(note: Note, stored: Note, generation: String,
                                           external: String, key: SymmetricKey) throws -> String {
        var versioned = note
        versioned.accessedAt = nil
        var storedVersioned = stored
        storedVersioned.accessedAt = nil
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        // A pending projection must not hide a concurrent stored-text change.
        let data = try encoder.encode([storedVersioned, versioned])
        // Length framing separates content bytes from the trusted editor generation.
        let generation = "\(external.utf8.count):" + external + generation
        var input = Data("\(data.count):".utf8); input.append(data); input.append(Data(generation.utf8))
        return Data(HMAC<SHA256>.authenticationCode(for: input, using: key)).base64EncodedString()
    }

    private func summary(_ state: AgentEditorRegistry.Snapshot, query: String = "") throws -> [String: AgentJSONValue] {
        let note = state.note
        let version = try versionToken(state)
        return ["id": .string(note.id.uuidString), "title": .string(note.title),
            "preview": .string(String(DraftRowPresentation.preview(note, query: query).prefix(1024))),
            "tags": .array(note.tags.map(AgentJSONValue.string)), "flag": .integer(Int64(note.flag)),
            "isArchived": .bool(note.isArchived), "trashedAt": note.trashedAt.map { .string(APIValues.date($0)) } ?? .null,
            "syntax": .string(note.syntax), "createdAt": .string(APIValues.date(note.createdAt)),
            "modifiedAt": .string(APIValues.date(note.modifiedAt)),
            "accessedAt": note.accessedAt.map { .string(APIValues.date($0)) } ?? .null, "versionToken": .string(version)]
    }

    private func query(_ values: [String: AgentJSONValue]) throws -> Workspace {
        func text(_ key: String) -> String { if case .string(let value) = values[key] { return value }; return "" }
        func strings(_ key: String) -> [String] {
            guard case .array(let items) = values[key] else { return [] }
            return items.compactMap { if case .string(let value) = $0 { return value }; return nil }
        }
        var workspace = Workspace(name: "")
        workspace.query = text("query")
        var options = DraftListOptions(); options.caseSensitiveSearch = values["caseSensitive"] == .bool(true)
        if DraftQuery(workspace.query, caseSensitive: options.caseSensitiveSearch).error != nil { throw AgentErrorCode.invalidInput }
        workspace.listOptions = options
        guard let folder = NoteFolder(rawValue: text("folder")), let sort = NoteSort(rawValue: text("sort")) else {
            throw AgentErrorCode.invalidInput
        }
        workspace.folder = folder; workspace.sort = sort; workspace.ascending = values["ascending"] == .bool(true)
        workspace.tags = strings("tags"); workspace.excludedTags = strings("excludedTags")
        workspace.matchAnyTag = values["matchAnyTag"] == .bool(true)
        if case .bool(let tagged) = values["tagged"] { workspace.tagged = tagged }
        return workspace
    }

    static func chunk(_ content: String, parameters: [String: AgentJSONValue]) throws -> [String: AgentJSONValue] {
        let text = content as NSString, total = text.length
        let offset = try AgentTextShapes.count(parameters["offset"]), requested = try AgentTextShapes.count(parameters["length"])
        guard offset <= Int64(total) else { throw AgentErrorCode.invalidInput }
        let start = Int(offset)
        guard AgentTextShapes.isScalarBoundary(start, in: text) else { throw AgentErrorCode.invalidInput }
        var end = start + min(Int(requested), total - start)
        if !AgentTextShapes.isScalarBoundary(end, in: text) { end -= 1 }
        guard end > start || start == total else { throw AgentErrorCode.invalidInput }
        return ["text": .string(text.substring(with: NSRange(location: start, length: end - start))),
            "offset": .integer(offset), "length": .integer(Int64(end - start)),
            "totalLength": .integer(Int64(total)), "hasMore": .bool(end < total)]
    }
}
