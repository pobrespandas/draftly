import Foundation
import AgentContracts
import DraftlyCore

// Editor receipts belong to this host lifetime. Old keys cannot select a new window.
@MainActor final class AgentEditorWriting {
    static let operationNames: Set<String> = ["editor.setSelection", "editor.replaceRange", "editor.undo", "editor.redo", "editor.tasks", "editor.replaceAll"]
    struct Context {
        let snapshot: AgentEditorRegistry.WindowSnapshot
        let version: String
    }
    private struct Receipt {
        let owner: String
        let requestHash: String
        let authority: AgentJSONValue
        var result: [String: AgentJSONValue]?
    }
    private let registry: AgentEditorRegistry
    private let keys: AgentRetryKeys
    private let currentGrant: (UUID) throws -> AgentGrant?
    private let validateAdmission: () throws -> Void
    private let read: (UUID, AgentGrant) throws -> Context
    private var receipts: [String: Receipt] = [:]
    private var updating = false

    init(registry: AgentEditorRegistry, keys: AgentRetryKeys,
         currentGrant: @escaping (UUID) throws -> AgentGrant?, validateAdmission: @escaping () throws -> Void,
         read: @escaping (UUID, AgentGrant) throws -> Context) {
        self.registry = registry; self.keys = keys; self.currentGrant = currentGrant
        self.validateAdmission = validateAdmission; self.read = read
    }

    func prepare(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        guard request.retryKey == nil else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try keys.issue(request, connectionID: connectionID)
        if try previous(ticket, requestID: request.requestID, connectionID: connectionID) == nil {
            guard receipts.count < 128 else { throw AgentErrorCode.busy }
            _ = try checked(request, connectionID: connectionID)
        }
        try validateAdmission()
        _ = try keys.verify(ticket.value, request: request, connectionID: connectionID)
        return ticket
    }

    func update(_ request: AgentRequest, connectionID: UUID) throws -> [String: AgentJSONValue] {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try keys.verify(key, request: request, connectionID: connectionID)
        if let result = try previous(ticket, requestID: request.requestID, connectionID: connectionID) { return result }
        guard receipts.count < 128 else { throw AgentErrorCode.busy }
        let (context, range, replacementText) = try checked(request, connectionID: connectionID)
        _ = try keys.verify(key, request: request, connectionID: connectionID)
        guard let originalGrant = try currentGrant(connectionID) else { throw AgentErrorCode.permissionDenied }
        let identity = ticket.connectionHash + "/" + request.requestID.uuidString
        receipts[identity] = Receipt(owner: ticket.connectionHash, requestHash: ticket.requestHash,
            authority: AgentRequestBinding.grantValue(originalGrant))
        do {
            let authorize = {
                try self.validateAdmission()
                _ = try self.keys.verify(key, request: request, connectionID: connectionID)
            }
            let selection: NSRange
            if request.operation == "editor.replaceRange" {
                guard case .string(let text) = request.parameters["text"] else { throw AgentErrorCode.invalidInput }
                try registry.replaceRange(context.snapshot, range: range, text: text, authorize: authorize)
                selection = NSRange(location: range.location + text.utf16.count, length: 0)
            } else if request.operation == "editor.replaceAll" {
                guard let text = replacementText else { throw AgentErrorCode.invalidInput }
                try registry.replaceRange(context.snapshot, range: range, text: text, preservingSelection: true, authorize: authorize)
                let offset = min(context.snapshot.selection.location, text.utf16.count)
                selection = NSRange(location: offset, length: min(context.snapshot.selection.length, text.utf16.count - offset))
            } else if request.operation == "editor.tasks" {
                guard let text = replacementText else { throw AgentErrorCode.invalidInput }
                try registry.replaceRange(context.snapshot, range: range, text: text, authorize: authorize)
                selection = NSRange(location: range.location + text.utf16.count, length: 0)
            } else if request.operation == "editor.undo" || request.operation == "editor.redo" {
                selection = try registry.undo(context.snapshot, redo: request.operation == "editor.redo", authorize: authorize)
            } else {
                try registry.setSelection(context.snapshot, range: range, authorize: authorize)
                selection = range
            }
            guard let grant = try currentGrant(connectionID) else { throw AgentErrorCode.permissionDenied }
            let updated = try read(context.snapshot.id, grant)
            guard updated.snapshot.draftID == context.snapshot.draftID, updated.snapshot.selection == selection else {
                throw AgentErrorCode.outcomeUnknown
            }
            try validateAdmission()
            _ = try keys.verify(key, request: request, connectionID: connectionID)
            let result: [String: AgentJSONValue] = [
                "windowID": .string(updated.snapshot.id.uuidString),
                "draftID": updated.snapshot.draftID.map { .string($0.uuidString) } ?? .null,
                "versionToken": .string(updated.version),
                "selection": .object(["offset": .integer(Int64(selection.location)), "length": .integer(Int64(selection.length))])
            ]
            receipts[identity]?.result = result
            return result
        } catch { throw AgentErrorCode.outcomeUnknown }
    }

    private func previous(_ ticket: AgentRetryKeys.Ticket, requestID: UUID, connectionID: UUID) throws -> [String: AgentJSONValue]? {
        guard let receipt = receipts[ticket.connectionHash + "/" + requestID.uuidString] else { return nil }
        guard receipt.owner == ticket.connectionHash else { throw AgentErrorCode.permissionDenied }
        guard let grant = try currentGrant(connectionID), grant.connectionID == connectionID,
              AgentRequestBinding.grantValue(grant) == receipt.authority else { throw AgentErrorCode.permissionDenied }
        guard receipt.requestHash == ticket.requestHash else { throw AgentErrorCode.invalidInput }
        guard let result = receipt.result else { throw AgentErrorCode.outcomeUnknown }
        return result
    }

    private func replacement(_ request: AgentRequest, context: Context) throws -> String {
        guard case .string(let query) = request.parameters["query"],
              case .string(let replacement) = request.parameters["replacement"] else { throw AgentErrorCode.invalidInput }
        do {
            let search = try EditorFindQuery(query, caseSensitive: request.parameters["caseSensitive"] == .bool(true),
                regularExpression: request.parameters["regularExpression"] == .bool(true))
            let deadline = ContinuousClock.now.advanced(by: .milliseconds(250))
            return try search.replacingAll(in: context.snapshot.content, with: replacement,
                maximumUTF16Length: AgentRequest.maximumBytes, continueMatching: {
                    ContinuousClock.now < deadline && !Task.isCancelled
                })
        } catch EditorFindQuery.ReplacementError.interrupted {
            throw Task.isCancelled ? AgentErrorCode.cancelled : AgentErrorCode.busy
        } catch { throw AgentErrorCode.invalidInput }
    }

    private func taskChange(_ request: AgentRequest, context: Context) throws -> (NSRange, String) {
        guard case .string(let state) = request.parameters["state"],
              case .string(let operation) = request.parameters["operation"] else { throw AgentErrorCode.invalidInput }
        do {
            let bounds = try AgentTextShapes.bounds(request.parameters["stateRange"],
                totalLength: Int64(context.snapshot.content.utf16.count))
            guard let offset = Int(exactly: bounds.offset), let end = Int(exactly: bounds.end) else {
                throw AgentErrorCode.invalidInput
            }
            let syntax = try registry.syntaxDefinition(windowID: context.snapshot.id)
            return try syntax.taskChange(in: context.snapshot.content,
                task: ["stateRange": [offset, end - offset], "state": state], operation: operation)
        } catch let error as AgentErrorCode { throw error }
        catch { throw AgentErrorCode.invalidInput }
    }

    private func checked(_ request: AgentRequest, connectionID: UUID) throws -> (Context, NSRange, String?) {
        guard Self.operationNames.contains(request.operation), request.targets.count == 1,
              let target = request.targets.first, target.kind == .window,
              let grant = try currentGrant(connectionID), grant.connectionID == connectionID else {
            throw AgentErrorCode.invalidInput
        }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentEditorSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        let context = try read(target.id, grant)
        guard context.snapshot.draftID != nil else { throw AgentErrorCode.notFound }
        guard context.version == request.expectedVersion else { throw AgentErrorCode.versionConflict }
        if request.operation == "editor.undo" || request.operation == "editor.redo" {
            try registry.validateUndo(context.snapshot)
            return (context, context.snapshot.selection, nil)
        }
        if request.operation == "editor.tasks" {
            let change = try taskChange(request, context: context)
            try registry.validateReplacement(context.snapshot)
            return (context, change.0, change.1)
        }
        if request.operation == "editor.replaceAll" {
            let text = try replacement(request, context: context)
            try registry.validateReplacement(context.snapshot)
            return (context, NSRange(location: 0, length: context.snapshot.content.utf16.count), text)
        }
        let text = context.snapshot.content as NSString
        let bounds: (offset: Int64, end: Int64)
        do { bounds = try AgentTextShapes.bounds(parameters["range"], totalLength: Int64(text.length)) }
        catch { throw AgentErrorCode.invalidInput }
        guard let start = Int(exactly: bounds.offset), let end = Int(exactly: bounds.end),
              AgentTextShapes.isScalarBoundary(start, in: text), AgentTextShapes.isScalarBoundary(end, in: text) else {
            throw AgentErrorCode.invalidInput
        }
        if request.operation == "editor.replaceRange" { try registry.validateReplacement(context.snapshot) }
        else { try registry.validateSelection(context.snapshot) }
        return (context, NSRange(location: start, length: end - start), nil)
    }
}
