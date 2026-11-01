import Foundation
import AgentContracts
import DraftlyCore

// Existing-draft writes only. No transport or normal-startup activation.
@MainActor final class AgentDraftWriting {
    private let libraryID: UUID
    static let operationNames: Set<String> = ["drafts.update", "drafts.patch"]
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
            guard let target = request.targets.first, let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
            let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            if try recoveredReceipt(for: mutation, target: target.id) == nil {
                guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
                let snapshot = try reader.checkedSnapshot(for: target.id, expectedVersion: expected)
                _ = try applying(request.operation, parameters: AgentDraftSchemas.validatedParameters(for: request), to: snapshot.note)
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
            guard let target = request.targets.first, let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
            let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            // Check authority before returning any receipt, including recovery after a lost reply.
            if let previous = try recoveredReceipt(for: mutation, target: target.id) {
                try validateAdmission(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                return previous
            }
            guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
            let initial = try reader.checkedSnapshot(for: target.id, expectedVersion: expected)
            let note = try applying(request.operation, parameters: parameters, to: initial.note)
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

    private func recoveredReceipt(for mutation: LibraryMutationIdentity, target: UUID) throws -> LibraryMutationReceipt? {
        guard let value = try library.mutationReceipt(for: mutation, at: now()) else { return nil }
        guard value.resources.count == 1, value.resources.first?.id == target else { throw AgentErrorCode.storageError }
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

    private func applying(_ operation: String, parameters: [String: AgentJSONValue], to original: Note) throws -> Note {
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
