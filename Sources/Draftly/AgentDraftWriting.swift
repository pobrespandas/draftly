import Foundation
import AgentContracts
import DraftlyCore

// App-owned draft mutations share version checks and durable receipts.
@MainActor final class AgentDraftWriting {
    private let libraryID: UUID
    static let operationNames: Set<String> = ["drafts.create", "drafts.update", "drafts.patch", "drafts.duplicate", "drafts.restoreVersion", "drafts.archive", "drafts.trash", "drafts.restore", "drafts.flag", "drafts.tags"]
    static let metadataOperations: Set<String> = ["drafts.archive", "drafts.trash", "drafts.restore", "drafts.flag", "drafts.tags"]
    private let library: LibraryStore
    private let reader: AgentDraftReading
    private let editors: AgentEditorRegistry
    private let keys: AgentRetryKeys
    private let now: () -> Date
    private let validateAdmission: () throws -> Void
    private var updating = false

    init(library: LibraryStore, libraryID: UUID, reader: AgentDraftReading, editors: AgentEditorRegistry,
         keys: AgentRetryKeys, now: @escaping () -> Date, validateAdmission: @escaping () throws -> Void) throws {
        guard reader.isBound(to: library, editors: editors) else { throw AgentErrorCode.invalidInput }
        self.libraryID = libraryID
        self.library = library; self.reader = reader; self.editors = editors
        self.keys = keys; self.now = now; self.validateAdmission = validateAdmission
    }

    func prepare(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        do {
            let request = try AgentRequest.decode(JSONEncoder().encode(request))
            guard Self.operationNames.contains(request.operation) else { throw AgentErrorCode.unavailable }
            guard request.retryKey == nil else { throw AgentErrorCode.invalidInput }
            guard request.libraryID == libraryID else { throw AgentErrorCode.permissionDenied }
            try validateAdmission()
            let ticket = try keys.issue(request, connectionID: connectionID)
            let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            let parameters = try AgentDraftSchemas.validatedParameters(for: request)
            if Self.metadataOperations.contains(request.operation) {
                guard let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
                if try recoveredBatchReceipt(for: mutation, targets: request.targets) == nil {
                    guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
                    let initial = try reader.checkedSnapshots(for: request.targets.map(\.id), expectedVersion: expected)
                    let date = now()
                    for state in initial.values { _ = try applyingMetadata(request, parameters: parameters, to: state.note, at: date) }
                }
            } else if request.operation == "drafts.create" {
                _ = try creationNote(parameters)
            } else if request.operation == "drafts.duplicate" {
                guard let target = request.targets.first(where: { $0.kind == .draft }), let expected = request.expectedVersion else {
                    throw AgentErrorCode.invalidInput
                }
                if try recoveredDuplicateReceipt(for: mutation, source: target.id) == nil {
                    guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
                    let snapshot = try reader.checkedSnapshot(for: target.id, expectedVersion: expected)
                    _ = DraftOperations.duplicate(snapshot.note, at: now())
                }
            } else {
                guard let target = request.targets.first(where: { $0.kind == .draft }), let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
                if try recoveredReceipt(for: mutation, target: target.id) == nil {
                    guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
                    let snapshot = try reader.checkedSnapshot(for: target.id, expectedVersion: expected)
                    _ = try applying(request, parameters: parameters, to: snapshot.note)
                }
            }
            try validateAdmission(); _ = try keys.verify(ticket.value, request: request, connectionID: connectionID)
            return ticket
        } catch let error as LibraryMutationReceiptError { throw receiptError(error) }
        catch is AgentSchemaError { throw AgentErrorCode.invalidInput }
    }

    func update(_ request: AgentRequest, connectionID: UUID) throws -> LibraryMutationReceipt {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        do {
            let request = try AgentRequest.decode(JSONEncoder().encode(request))
            guard Self.operationNames.contains(request.operation), let key = request.retryKey else { throw AgentErrorCode.invalidInput }
            guard request.libraryID == libraryID else { throw AgentErrorCode.permissionDenied }
            try validateAdmission()
            let ticket = try keys.verify(key, request: request, connectionID: connectionID)
            let parameters = try AgentDraftSchemas.validatedParameters(for: request)
            if Self.metadataOperations.contains(request.operation) {
                return try updateMetadata(request, parameters: parameters, ticket: ticket, connectionID: connectionID)
            }
            if request.operation == "drafts.create" {
                let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
                if let previous = try library.mutationReceipt(for: mutation, at: now()) {
                    try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                    return previous
                }
                guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
                let note = try creationNote(parameters)
                let resource = try reader.mutationResource(for: note)
                let receipt = try library.commitNotes([note], mutation: mutation, at: now(), preserveRevision: false,
                    preserveDates: true, validateCommit: {
                        try self.validateAdmission(); _ = try self.keys.verify(key, request: request, connectionID: connectionID)
                        guard !ActionRunner.isExecuting(in: self.library) else { throw AgentErrorCode.busy }
                    }, makeResources: { values in
                        guard values.count == 1, let value = values.first else { throw AgentErrorCode.storageError }
                        guard value.id == resource.id else { throw AgentErrorCode.storageError }
                        return [resource]
                    })
                try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                return receipt
            }
            guard let target = request.targets.first(where: { $0.kind == .draft }), let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
            let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            if request.operation == "drafts.duplicate" {
                if let previous = try recoveredDuplicateReceipt(for: mutation, source: target.id) {
                    try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                    return previous
                }
                guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
                let initial = try reader.checkedSnapshot(for: target.id, expectedVersion: expected)
                let copy = DraftOperations.duplicate(initial.note, at: now())
                let resource = try reader.mutationResource(for: copy)
                let copyID = resource.id
                let receipt = try library.commitNotes([copy], mutation: mutation, at: now(), preserveRevision: false,
                    preserveDates: true, validateCommit: {
                        try self.validateAdmission(); _ = try self.keys.verify(key, request: request, connectionID: connectionID)
                        guard !ActionRunner.isExecuting(in: self.library) else { throw AgentErrorCode.busy }
                        _ = try self.reader.checkedSnapshot(for: target.id, expectedVersion: expected)
                    }, makeResources: { values in
                        guard values.count == 1, values.first?.id == copyID else { throw AgentErrorCode.storageError }
                        return [resource]
                    })
                try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                return receipt
            }
            // Check authority before returning any receipt, including recovery after a lost reply.
            if let previous = try recoveredReceipt(for: mutation, target: target.id) {
                try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                return previous
            }
            guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
            let initial = try reader.checkedSnapshot(for: target.id, expectedVersion: expected)
            let source = try restorationSource(request, parent: target.id)
            let note = try applying(request, parameters: parameters, to: initial.note)
            let preserveDates: Bool
            if case .object(let changes) = parameters["changes"] { preserveDates = changes["modifiedAt"] != nil }
            else { preserveDates = false }
            var receipt: LibraryMutationReceipt?
            _ = try editors.synchronizeMutation(note) { value, generation in
                try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                receipt = try library.commitNotes([value], mutation: mutation, at: now(),
                    preserveDates: preserveDates, validateCommit: {
                        try self.validateAdmission()
                        _ = try self.keys.verify(key, request: request, connectionID: connectionID)
                        guard !ActionRunner.isExecuting(in: self.library) else { throw AgentErrorCode.busy }
                        try self.reader.validateMutationSnapshot(initial, expectedVersion: expected, reservedGeneration: generation)
                        if let source {
                            let current = try self.restorationSource(request, parent: target.id)
                            guard current?.id == source.id, current?.date == source.date,
                                  current?.content.utf8.elementsEqual(source.content.utf8) == true else {
                                throw AgentErrorCode.versionConflict
                            }
                        }
                    }, makeResources: reader.mutationResources(for: target.id, generation: generation))
                guard let stored = library.notes.first(where: { $0.id == target.id }) else { throw AgentErrorCode.storageError }
                return stored
            }
            try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
            guard let receipt else { throw AgentErrorCode.storageError }
            return receipt
        } catch let error as AgentErrorCode { throw error }
        catch let error as LibraryMutationReceiptError {
            throw receiptError(error)
        } catch is AgentSchemaError { throw AgentErrorCode.invalidInput }
        catch { throw AgentErrorCode.storageError }
    }

    private func recoveredBatchReceipt(for mutation: LibraryMutationIdentity,
                                       targets: [AgentResourceReference]) throws -> LibraryMutationReceipt? {
        guard let receipt = try library.mutationReceipt(for: mutation, at: now()) else { return nil }
        guard receipt.resources.count == targets.count,
              Set(receipt.resources.map(\.id)) == Set(targets.map(\.id)) else { throw AgentErrorCode.storageError }
        return receipt
    }

    private func updateMetadata(_ request: AgentRequest, parameters: [String: AgentJSONValue],
                                ticket: AgentRetryKeys.Ticket, connectionID: UUID) throws -> LibraryMutationReceipt {
        guard let expected = request.expectedVersion, let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        if let receipt = try recoveredBatchReceipt(for: mutation, targets: request.targets) {
            try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
            return receipt
        }
        guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
        let initial = try reader.checkedSnapshots(for: request.targets.map(\.id), expectedVersion: expected)
        let mutationDate = now()
        let notes = try request.targets.map { target in
            guard let state = initial[target.id] else { throw AgentErrorCode.storageError }
            return try applyingMetadata(request, parameters: parameters, to: state.note, at: mutationDate)
        }
        var receipt: LibraryMutationReceipt?
        _ = try editors.synchronizeMutations(notes) { values, generations in
            try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
            var builders: [UUID: @Sendable ([Note]) throws -> [LibraryMutationReceipt.Resource]] = [:]
            for value in values {
                guard let generation = generations[value.id] else { throw AgentErrorCode.storageError }
                builders[value.id] = reader.mutationResources(for: value.id, generation: generation)
            }
            let resourceBuilders = builders
            receipt = try library.commitNotes(values, mutation: mutation, at: now(), validateCommit: {
                try self.validateAdmission(); _ = try self.keys.verify(key, request: request, connectionID: connectionID)
                guard !ActionRunner.isExecuting(in: self.library) else { throw AgentErrorCode.busy }
                try self.reader.validateMutationSnapshots(initial, expectedVersion: expected, reservedGenerations: generations)
            }, makeResources: { saved in
                try saved.flatMap { note in
                    guard let builder = resourceBuilders[note.id] else { throw AgentErrorCode.storageError }
                    return try builder([note])
                }
            })
            return try values.map { value in
                guard let saved = library.notes.first(where: { $0.id == value.id }) else { throw AgentErrorCode.storageError }
                return saved
            }
        }
        try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
        guard let receipt else { throw AgentErrorCode.storageError }
        return receipt
    }

    private func applyingMetadata(_ request: AgentRequest, parameters: [String: AgentJSONValue], to original: Note, at date: Date) throws -> Note {
        var note = original
        switch request.operation {
        case "drafts.archive": note.isArchived = true; note.trashedAt = nil
        case "drafts.trash": note.trashedAt = date
        case "drafts.restore": note.trashedAt = nil
        case "drafts.flag":
            guard case .integer(let flag) = parameters["flag"] else { throw AgentErrorCode.invalidInput }
            note.flag = Int(flag)
        case "drafts.tags":
            guard case .string(let mode) = parameters["mode"], case .array(let values) = parameters["tags"] else { throw AgentErrorCode.invalidInput }
            let tags = TagRules.normalize(values.compactMap { if case .string(let value) = $0 { value } else { nil } })
            switch mode {
            case "replace": note.tags = tags
            case "add": note.tags = TagRules.normalize(note.tags + tags)
            case "remove": note.tags.removeAll { tags.contains(TagRules.normalize($0)) }
            default: throw AgentErrorCode.invalidInput
            }
        default: throw AgentErrorCode.unavailable
        }
        return note
    }

    private func recoveredReceipt(for mutation: LibraryMutationIdentity, target: UUID) throws -> LibraryMutationReceipt? {
        guard let value = try library.mutationReceipt(for: mutation, at: now()) else { return nil }
        guard value.resources.count == 1, value.resources.first?.id == target else { throw AgentErrorCode.storageError }
        return value
    }

    private func recoveredDuplicateReceipt(for mutation: LibraryMutationIdentity, source: UUID) throws -> LibraryMutationReceipt? {
        guard let value = try library.mutationReceipt(for: mutation, at: now()) else { return nil }
        guard value.resources.count == 1, let resource = value.resources.first,
              resource.id != source, library.notes.contains(where: { $0.id == resource.id }) else {
            throw AgentErrorCode.storageError
        }
        return value
    }

    private func receiptError(_ error: LibraryMutationReceiptError) -> AgentErrorCode {
        switch error {
        case .requestConflict: .invalidInput
        case .retryWindowExpired: .retryWindowExpired
        case .pendingChanges: .busy
        case .invalidReceipt: .storageError
        }
    }

    private func restorationSource(_ request: AgentRequest, parent: UUID) throws -> Revision? {
        guard request.operation == "drafts.restoreVersion" else { return nil }
        guard let id = request.targets.first(where: { $0.kind == .revision })?.id,
              let revision = library.revisions.first(where: { $0.id == id && $0.noteID == parent }) else {
            throw AgentErrorCode.notFound
        }
        return revision
    }

    private func applying(_ request: AgentRequest, parameters: [String: AgentJSONValue], to original: Note) throws -> Note {
        let operation = request.operation
        if let revision = try restorationSource(request, parent: original.id) {
            var note = original; note.content = revision.content
            return note
        }
        if operation == "drafts.update", case .object(let changes) = parameters["changes"] {
            return try applying(changes, to: original)
        }
        guard operation == "drafts.patch", case .array(let edits) = parameters["edits"] else { throw AgentErrorCode.invalidInput }
        let source = original.content as NSString
        let replacements = try edits.map { edit -> (NSRange, String) in
            guard case .object(let fields) = edit, case .string(let replacement) = fields["text"] else { throw AgentErrorCode.invalidInput }
            let bounds = try AgentTextShapes.bounds(.object(["offset": fields["offset"] ?? .null,
                "length": fields["length"] ?? .null]), totalLength: Int64(source.length))
            guard let start = Int(exactly: bounds.offset), let end = Int(exactly: bounds.end),
                  AgentTextShapes.isScalarBoundary(start, in: source), AgentTextShapes.isScalarBoundary(end, in: source) else {
                throw AgentErrorCode.invalidInput
            }
            return (NSRange(location: start, length: end - start), replacement)
        }
        let text = NSMutableString(string: original.content)
        for (range, replacement) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            text.replaceCharacters(in: range, with: replacement)
        }
        var note = original; note.content = text as String
        return note
    }

    private func creationNote(_ parameters: [String: AgentJSONValue]) throws -> Note {
        guard case .string(let content) = parameters["content"],
              case .array(let tags) = parameters["tags"],
              case .integer(let rawFlag) = parameters["flag"],
              let flag = Int(exactly: rawFlag),
              case .string(let syntax) = parameters["syntax"],
              case .string(let folder) = parameters["folder"] else { throw AgentErrorCode.invalidInput }
        let rawTags = try tags.map {
            guard case .string(let value) = $0 else { throw AgentErrorCode.invalidInput }
            return value
        }
        var note = Note(content: content, tags: TagRules.normalize(rawTags), flag: flag,
                        isArchived: folder == "archive", syntax: syntax)
        if case .object(let metadata) = parameters["scriptMetadata"] {
            note.scriptMetadata = try metadata.mapValues {
                guard case .string(let value) = $0 else { throw AgentErrorCode.invalidInput }
                return value
            }
        }
        return note
    }

    private func applying(_ changes: [String: AgentJSONValue], to original: Note) throws -> Note {
        var note = original
        if case .string(let value) = changes["content"] { note.content = value }
        if case .array(let values) = changes["tags"] {
            note.tags = try values.map { guard case .string(let text) = $0 else { throw AgentErrorCode.invalidInput }; return text }
        }
        if let flag = changes["flag"] { note.flag = Int(try AgentTextShapes.count(flag)) }
        if case .string(let value) = changes["syntax"] { note.syntax = value }
        if case .bool(let value) = changes["isArchived"] { note.isArchived = value }
        if let value = changes["trashedAt"] { note.trashedAt = value == .null ? nil : try date(value) }
        if let value = changes["createdAt"] { note.createdAt = try date(value) }
        if let value = changes["modifiedAt"] { note.modifiedAt = try date(value) }
        if let value = changes["scriptMetadata"] {
            if value == .null { note.scriptMetadata = nil }
            else if case .object(let values) = value {
                note.scriptMetadata = try values.mapValues { guard case .string(let text) = $0 else { throw AgentErrorCode.invalidInput }; return text }
            } else { throw AgentErrorCode.invalidInput }
        }
        return note
    }

    private func date(_ value: AgentJSONValue) throws -> Date {
        guard case .string(let text) = value, let date = APIValues.parseDate(text) else { throw AgentErrorCode.invalidInput }
        return date
    }
}
