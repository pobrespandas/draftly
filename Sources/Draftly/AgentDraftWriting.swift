import Foundation
import AgentContracts
import DraftlyCore

// App-owned draft mutations share version checks and durable receipts.
@MainActor final class AgentDraftWriting {
    private let libraryID: UUID
    static let operationNames: Set<String> = ["drafts.create", "drafts.update", "drafts.patch", "drafts.duplicate", "drafts.merge", "drafts.restoreVersion", "drafts.archive", "drafts.trash", "drafts.restore", "drafts.flag", "drafts.tags", "drafts.syntax"]
    static let metadataOperations: Set<String> = ["drafts.archive", "drafts.trash", "drafts.restore", "drafts.flag", "drafts.tags", "drafts.syntax"]
    private let library: LibraryStore
    private let reader: AgentDraftReading
    private let editors: AgentEditorRegistry
    private let keys: AgentRetryKeys
    private let now: () -> Date
    private let validateAdmission: () throws -> Void
    private let resolveSyntax: ([String: AgentJSONValue], UUID) throws -> SyntaxDefinition
    private var updating = false

    init(library: LibraryStore, libraryID: UUID, reader: AgentDraftReading, editors: AgentEditorRegistry,
         keys: AgentRetryKeys, now: @escaping () -> Date, validateAdmission: @escaping () throws -> Void,
         resolveSyntax: @escaping ([String: AgentJSONValue], UUID) throws -> SyntaxDefinition = { parameters, _ in
             guard case .string(let name) = parameters["name"], ScriptSyntax.names.contains(name) else { throw AgentErrorCode.unavailable }
             return try ScriptSyntax.definition(name)
         }) throws {
        guard reader.isBound(to: library, editors: editors) else { throw AgentErrorCode.invalidInput }
        self.libraryID = libraryID
        self.library = library; self.reader = reader; self.editors = editors
        self.keys = keys; self.now = now; self.validateAdmission = validateAdmission; self.resolveSyntax = resolveSyntax
    }

    private func checkedPurge(_ request: AgentRequest) throws -> [UUID: AgentEditorRegistry.Snapshot] {
        guard request.operation == "drafts.purge", request.libraryID == libraryID,
              !request.targets.isEmpty, request.targets.allSatisfy({ $0.kind == .draft }),
              let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
        do { _ = try AgentDraftSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
        let states = try reader.checkedSnapshots(for: request.targets.map(\.id), expectedVersion: expected)
        guard states.values.allSatisfy({ $0.storedNote.trashedAt != nil }) else { throw AgentErrorCode.invalidInput }
        return states
    }

    func preparePurge(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
        guard request.operation == "drafts.purge", request.retryKey == nil,
              request.libraryID == libraryID else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try keys.issue(request, connectionID: connectionID)
        let identity = LibraryMutationIdentity(requestID: request.requestID,
            connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        do {
            if try recoveredBatchReceipt(for: identity, targets: request.targets) == nil { _ = try checkedPurge(request) }
        } catch let error as LibraryMutationReceiptError { throw receiptError(error) }
        try validateAdmission()
        _ = try keys.verify(ticket.value, request: request, connectionID: connectionID)
        return ticket
    }

    func purgeReceipt(_ request: AgentRequest, connectionID: UUID) throws -> LibraryMutationReceipt? {
        guard request.operation == "drafts.purge", request.libraryID == libraryID,
              let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try keys.verify(key, request: request, connectionID: connectionID)
        do {
            return try recoveredBatchReceipt(for: .init(requestID: request.requestID,
                connectionHash: ticket.connectionHash, requestHash: ticket.requestHash), targets: request.targets)
        } catch let error as LibraryMutationReceiptError { throw receiptError(error) }
    }

    func purgeEffects(_ request: AgentRequest, connectionID: UUID) throws -> AgentApprovalStore.Effects {
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        _ = try keys.verify(key, request: request, connectionID: connectionID)
        let states = try checkedPurge(request)
        return .init(capabilities: [.draftsWrite, .destructiveRequest], targets: Set(request.targets),
            requiresLibraryScope: false, snapshot: ["drafts": .array(request.targets.map { target in
                .object(["id": .string(target.id.uuidString),
                    "title": .string(String(states[target.id]!.note.title.prefix(80)))])
            }), "draftVersions": .string(request.expectedVersion!), "deletesRevisions": .bool(true),
                "preservesActionHistory": .bool(true), "cannotUndo": .bool(true)])
    }

    func reviewAndPurge(_ request: AgentRequest, connectionID: UUID, operationID: UUID,
                        approvals: AgentApprovalStore, operations: AgentOperationRegistry,
                        validateSession: () throws -> Void) async throws -> [String: AgentJSONValue] {
        var submitted = false
        do {
            try Task.checkCancellation(); try validateSession()
            if let receipt = try purgeReceipt(request, connectionID: connectionID) {
                return ["deletedIDs": .array(receipt.resources.map { .string($0.id.uuidString) })]
            }
            try operations.setWaitingForUser(operationID, waiting: true)
            try await approvals.waitForApproval(request, connectionID: connectionID, resolveEffects: {
                try validateSession()
                return try self.purgeEffects(request, connectionID: connectionID)
            })
            try operations.setWaitingForUser(operationID, waiting: false)
            try Task.checkCancellation(); try validateSession(); try validateAdmission()
            guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
            let ticket = try keys.verify(key, request: request, connectionID: connectionID)
            let states = try checkedPurge(request)
            let resources = try request.targets.map { try reader.mutationResource(for: states[$0.id]!.storedNote) }
            let identity = LibraryMutationIdentity(requestID: request.requestID,
                connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            let effectID = UUID()
            var receipt: LibraryMutationReceipt?
            try editors.synchronizeDeletion(Set(request.targets.map(\.id))) { validateEditors in
                receipt = try library.commitTrashedNoteDeletion(resources, mutation: identity, at: now(), validateCommit: {
                    try Task.checkCancellation(); try self.validateAdmission(); try validateSession()
                    _ = try self.keys.verify(key, request: request, connectionID: connectionID)
                    _ = try self.checkedPurge(request)
                    try validateEditors()
                    try operations.recordEffect(operationID, effectID: effectID, kind: "drafts.purge", outcome: "submitted")
                    submitted = true
                })
            }
            guard let receipt else { throw AgentErrorCode.storageError }
            try operations.recordEffect(operationID, effectID: effectID, kind: "drafts.purge", outcome: "completed")
            return ["deletedIDs": .array(receipt.resources.map { .string($0.id.uuidString) })]
        } catch {
            if submitted { throw AgentErrorCode.outcomeUnknown }
            let code = error is CancellationError ? AgentErrorCode.cancelled : (error as? AgentErrorCode ?? .storageError)
            throw AgentOperationRegistry.FailureBeforeEffects(code: code)
        }
    }

    func prepare(_ request: AgentRequest, connectionID: UUID, validateSession: () throws -> Void = {}) throws -> AgentRetryKeys.Ticket {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        do {
            let request = try AgentRequest.decode(JSONEncoder().encode(request))
            guard Self.operationNames.contains(request.operation) else { throw AgentErrorCode.unavailable }
            guard request.retryKey == nil else { throw AgentErrorCode.invalidInput }
            guard request.libraryID == libraryID else { throw AgentErrorCode.permissionDenied }
            try validateAdmission(); try validateSession()
            let ticket = try keys.issue(request, connectionID: connectionID)
            let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            let parameters = try AgentDraftSchemas.validatedParameters(for: request)
            if Self.metadataOperations.contains(request.operation) {
                guard let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
                if try recoveredBatchReceipt(for: mutation, targets: request.targets) == nil {
                    guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
                    let initial = try reader.checkedSnapshots(for: request.targets.map(\.id), expectedVersion: expected)
                    let syntax = request.operation == "drafts.syntax" ? try resolveSyntax(parameters, connectionID) : nil
                    let date = now()
                    for state in initial.values {
                        _ = try applyingMetadata(request, parameters: parameters, to: state.note, at: date, syntaxName: syntax?.name)
                    }
                }
            } else if request.operation == "drafts.merge" {
                guard let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
                if try recoveredMergeReceipt(for: mutation, targets: request.targets) == nil {
                    guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
                    let initial = try reader.checkedSnapshots(for: request.targets.map(\.id), expectedVersion: expected)
                    _ = try mergePlan(parameters, initial: initial, at: now())
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
            try validateAdmission(); try validateSession(); _ = try keys.verify(ticket.value, request: request, connectionID: connectionID)
            return ticket
        } catch let error as LibraryMutationReceiptError { throw receiptError(error) }
        catch is AgentSchemaError { throw AgentErrorCode.invalidInput }
    }

    func update(_ request: AgentRequest, connectionID: UUID, validateSession: () throws -> Void = {}) throws -> LibraryMutationReceipt {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        do {
            let request = try AgentRequest.decode(JSONEncoder().encode(request))
            guard Self.operationNames.contains(request.operation), let key = request.retryKey else { throw AgentErrorCode.invalidInput }
            guard request.libraryID == libraryID else { throw AgentErrorCode.permissionDenied }
            try validateAdmission(); try validateSession()
            let ticket = try keys.verify(key, request: request, connectionID: connectionID)
            let parameters = try AgentDraftSchemas.validatedParameters(for: request)
            if Self.metadataOperations.contains(request.operation) {
                return try updateMetadata(request, parameters: parameters, ticket: ticket, connectionID: connectionID, validateSession: validateSession)
            }
            if request.operation == "drafts.merge" {
                return try updateMerge(request, parameters: parameters, ticket: ticket,
                    connectionID: connectionID, validateSession: validateSession)
            }
            if request.operation == "drafts.create" {
                let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
                if let previous = try library.mutationReceipt(for: mutation, at: now()) {
                    try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                    return previous
                }
                guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
                let note = try creationNote(parameters)
                let resource = try reader.mutationResource(for: note)
                let receipt = try library.commitNotes([note], mutation: mutation, at: now(), preserveRevision: false,
                    preserveDates: true, validateCommit: {
                        try self.validateAdmission(); try validateSession(); _ = try self.keys.verify(key, request: request, connectionID: connectionID)
                        guard !ActionRunner.isExecuting(in: self.library) else { throw AgentErrorCode.busy }
                    }, makeResources: { values in
                        guard values.count == 1, let value = values.first else { throw AgentErrorCode.storageError }
                        guard value.id == resource.id else { throw AgentErrorCode.storageError }
                        return [resource]
                    })
                try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                return receipt
            }
            guard let target = request.targets.first(where: { $0.kind == .draft }), let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
            let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            if request.operation == "drafts.duplicate" {
                if let previous = try recoveredDuplicateReceipt(for: mutation, source: target.id) {
                    try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                    return previous
                }
                guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
                let initial = try reader.checkedSnapshot(for: target.id, expectedVersion: expected)
                let copy = DraftOperations.duplicate(initial.note, at: now())
                let resource = try reader.mutationResource(for: copy)
                let copyID = resource.id
                let receipt = try library.commitNotes([copy], mutation: mutation, at: now(), preserveRevision: false,
                    preserveDates: true, validateCommit: {
                        try self.validateAdmission(); try validateSession(); _ = try self.keys.verify(key, request: request, connectionID: connectionID)
                        guard !ActionRunner.isExecuting(in: self.library) else { throw AgentErrorCode.busy }
                        _ = try self.reader.checkedSnapshot(for: target.id, expectedVersion: expected)
                    }, makeResources: { values in
                        guard values.count == 1, values.first?.id == copyID else { throw AgentErrorCode.storageError }
                        return [resource]
                    })
                try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                return receipt
            }
            // Check authority before returning any receipt, including recovery after a lost reply.
            if let previous = try recoveredReceipt(for: mutation, target: target.id) {
                try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
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
                try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
                receipt = try library.commitNotes([value], mutation: mutation, at: now(),
                    preserveDates: preserveDates, validateCommit: {
                        try self.validateAdmission(); try validateSession()
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
            try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
            guard let receipt else { throw AgentErrorCode.storageError }
            return receipt
        } catch let error as AgentErrorCode { throw error }
        catch let error as LibraryMutationReceiptError {
            throw receiptError(error)
        } catch is AgentSchemaError { throw AgentErrorCode.invalidInput }
        catch { throw AgentErrorCode.storageError }
    }

    private func recoveredMergeReceipt(for mutation: LibraryMutationIdentity,
                                       targets: [AgentResourceReference]) throws -> LibraryMutationReceipt? {
        guard let receipt = try library.mutationReceipt(for: mutation, at: now()) else { return nil }
        let originals = Set(targets.map(\.id)), recorded = Set(receipt.resources.map(\.id))
        guard receipt.resources.count == originals.count + 1, originals.isSubset(of: recorded),
              recorded.subtracting(originals).count == 1 else { throw AgentErrorCode.storageError }
        return receipt
    }

    private func mergePlan(_ parameters: [String: AgentJSONValue],
                           initial: [UUID: AgentEditorRegistry.Snapshot], at date: Date) throws -> (merged: Note, originals: [Note]) {
        guard case .array(let order) = parameters["order"], case .string(let separator) = parameters["separator"],
              case .bool(let blank) = parameters["includeBlankLine"], case .string(let destination) = parameters["destination"] else {
            throw AgentErrorCode.invalidInput
        }
        let states = try order.map { value -> AgentEditorRegistry.Snapshot in
            guard case .string(let rawID) = value, let id = UUID(uuidString: rawID), let state = initial[id] else {
                throw AgentErrorCode.invalidInput
            }
            return state
        }
        let merged = try DraftOperations.merge(states.map(\.note), separator: separator, includeBlankLine: blank, at: date)
        let originals = try states.map { state -> Note in
            var note = state.note
            switch destination {
            case "archive": note.isArchived = true; note.trashedAt = nil; note.modifiedAt = date
            case "trash": note.trashedAt = date; note.modifiedAt = date
            case "keep":
                if !DraftOperations.sameText(note.content, state.storedNote.content) { note.modifiedAt = date }
            default: throw AgentErrorCode.invalidInput
            }
            return note
        }
        return (merged, originals)
    }

    private func updateMerge(_ request: AgentRequest, parameters: [String: AgentJSONValue],
                             ticket: AgentRetryKeys.Ticket, connectionID: UUID,
                             validateSession: () throws -> Void) throws -> LibraryMutationReceipt {
        guard let expected = request.expectedVersion, let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        if let receipt = try recoveredMergeReceipt(for: mutation, targets: request.targets) {
            try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
            return receipt
        }
        guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
        let initial = try reader.checkedSnapshots(for: request.targets.map(\.id), expectedVersion: expected)
        let date = now()
        let plan = try mergePlan(parameters, initial: initial, at: date)
        guard !library.notes.contains(where: { $0.id == plan.merged.id }) else { throw AgentErrorCode.versionConflict }
        let mergedResource = try reader.mutationResource(for: plan.merged)
        var receipt: LibraryMutationReceipt?
        _ = try editors.synchronizeMutations(plan.originals) { originals, generations in
            try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
            var builders: [UUID: @Sendable ([Note]) throws -> [LibraryMutationReceipt.Resource]] = [:]
            for note in originals {
                guard let generation = generations[note.id] else { throw AgentErrorCode.storageError }
                builders[note.id] = reader.mutationResources(for: note.id, generation: generation)
            }
            let resourceBuilders = builders
            receipt = try library.commitNotes(originals + [plan.merged], mutation: mutation, at: date,
                preserveDates: true, validateCommit: {
                    try self.validateAdmission(); try validateSession()
                    _ = try self.keys.verify(key, request: request, connectionID: connectionID)
                    guard !ActionRunner.isExecuting(in: self.library) else { throw AgentErrorCode.busy }
                    guard !self.library.notes.contains(where: { $0.id == plan.merged.id }) else { throw AgentErrorCode.versionConflict }
                    try self.reader.validateMutationSnapshots(initial, expectedVersion: expected, reservedGenerations: generations)
                }, makeResources: { values in
                    try values.flatMap { note in
                        if note.id == mergedResource.id { return [mergedResource] }
                        guard let builder = resourceBuilders[note.id] else { throw AgentErrorCode.storageError }
                        return try builder([note])
                    }
                })
            return try originals.map { note in
                guard let saved = library.notes.first(where: { $0.id == note.id }) else { throw AgentErrorCode.storageError }
                return saved
            }
        }
        try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
        guard let receipt else { throw AgentErrorCode.storageError }
        return receipt
    }

    private func recoveredBatchReceipt(for mutation: LibraryMutationIdentity,
                                       targets: [AgentResourceReference]) throws -> LibraryMutationReceipt? {
        guard let receipt = try library.mutationReceipt(for: mutation, at: now()) else { return nil }
        guard receipt.resources.count == targets.count,
              Set(receipt.resources.map(\.id)) == Set(targets.map(\.id)) else { throw AgentErrorCode.storageError }
        return receipt
    }

    private func updateMetadata(_ request: AgentRequest, parameters: [String: AgentJSONValue],
                                ticket: AgentRetryKeys.Ticket, connectionID: UUID, validateSession: () throws -> Void) throws -> LibraryMutationReceipt {
        guard let expected = request.expectedVersion, let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        let mutation = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        if let receipt = try recoveredBatchReceipt(for: mutation, targets: request.targets) {
            try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
            return receipt
        }
        guard !ActionRunner.isExecuting(in: library) else { throw AgentErrorCode.busy }
        let initial = try reader.checkedSnapshots(for: request.targets.map(\.id), expectedVersion: expected)
        let syntax = request.operation == "drafts.syntax" ? try resolveSyntax(parameters, connectionID) : nil
        let mutationDate = now()
        let notes = try request.targets.map { target in
            guard let state = initial[target.id] else { throw AgentErrorCode.storageError }
            return try applyingMetadata(request, parameters: parameters, to: state.note, at: mutationDate, syntaxName: syntax?.name)
        }
        var receipt: LibraryMutationReceipt?
        _ = try editors.synchronizeMutations(notes) { values, generations in
            try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
            var builders: [UUID: @Sendable ([Note]) throws -> [LibraryMutationReceipt.Resource]] = [:]
            for value in values {
                guard let generation = generations[value.id] else { throw AgentErrorCode.storageError }
                builders[value.id] = reader.mutationResources(for: value.id, generation: generation)
            }
            let resourceBuilders = builders
            receipt = try library.commitNotes(values, mutation: mutation, at: now(), validateCommit: {
                try self.validateAdmission(); try validateSession(); _ = try self.keys.verify(key, request: request, connectionID: connectionID)
                guard !ActionRunner.isExecuting(in: self.library) else { throw AgentErrorCode.busy }
                try self.reader.validateMutationSnapshots(initial, expectedVersion: expected, reservedGenerations: generations)
                if let syntax {
                    let current = try self.resolveSyntax(parameters, connectionID)
                    guard current.type == syntax.type, current.name.utf8.elementsEqual(syntax.name.utf8),
                          current.source.utf8.elementsEqual(syntax.source.utf8),
                          syntax.type == "builtIn" || current.id == syntax.id else { throw AgentErrorCode.versionConflict }
                }
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
        try validateAdmission(); try validateSession(); _ = try keys.verify(key, request: request, connectionID: connectionID)
        guard let receipt else { throw AgentErrorCode.storageError }
        return receipt
    }

    private func applyingMetadata(_ request: AgentRequest, parameters: [String: AgentJSONValue], to original: Note, at date: Date, syntaxName: String? = nil) throws -> Note {
        var note = original
        switch request.operation {
        case "drafts.archive": note.isArchived = true; note.trashedAt = nil
        case "drafts.trash": note.trashedAt = date
        case "drafts.restore": note.trashedAt = nil
        case "drafts.syntax":
            guard let syntaxName else { throw AgentErrorCode.unavailable }
            note.syntax = syntaxName
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

    static func syntaxDefinition(_ parameters: [String: AgentJSONValue], grant: AgentGrant,
                                 library: LibraryStore) throws -> SyntaxDefinition {
        if case .string(let name) = parameters["name"], ScriptSyntax.names.contains(name) {
            return try ScriptSyntax.definition(name)
        }
        guard grant.capabilities.contains(.appearanceRead) else { throw AgentErrorCode.permissionDenied }
        let candidates = library.syntaxes.filter { $0.type != "builtIn" && grant.scope.permits(.init(kind: .syntax, id: $0.id)) }
        let value: SyntaxDefinition?
        if case .string(let rawID) = parameters["syntaxID"], let id = UUID(uuidString: rawID) {
            value = candidates.first { $0.id == id }
        } else if case .string(let name) = parameters["name"] {
            value = candidates.first { $0.name == name }
        } else { throw AgentErrorCode.invalidInput }
        guard let value else { throw AgentErrorCode.notFound }
        return value
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
