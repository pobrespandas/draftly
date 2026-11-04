import Foundation
import AgentContracts
import DraftlyCore

// A theme definition and its receipt commit together. Selection is separate.
@MainActor final class AgentThemeWriting {
    static let operationNames: Set<String> = ["themes.create", "themes.update", "themes.duplicate"]
    private let library: LibraryStore
    private let libraryID: UUID
    private let reader: AgentThemeReading
    private let keys: AgentRetryKeys
    private let now: () -> Date
    private var updating = false

    init(library: LibraryStore, libraryID: UUID, reader: AgentThemeReading,
         keys: AgentRetryKeys, now: @escaping () -> Date) {
        self.library = library; self.libraryID = libraryID; self.reader = reader; self.keys = keys; self.now = now
    }

    private func identity(_ request: AgentRequest, ticket: AgentRetryKeys.Ticket) -> LibraryMutationIdentity {
        .init(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
    }

    private func receipt(_ request: AgentRequest, ticket: AgentRetryKeys.Ticket) throws -> LibraryMutationReceipt? {
        do {
            guard let previous = try library.mutationReceipt(for: identity(request, ticket: ticket), at: now()) else { return nil }
            guard previous.resources.count == 1, let resource = previous.resources.first else { throw AgentErrorCode.storageError }
            if request.operation == "themes.update" {
                guard resource.id == request.targets.first?.id else { throw AgentErrorCode.storageError }
            } else if request.operation == "themes.duplicate" {
                guard resource.id != request.targets.first?.id else { throw AgentErrorCode.storageError }
            } else if case .object(let input) = request.parameters["theme"], case .string(let rawID) = input["id"] {
                guard UUID(uuidString: rawID) == resource.id else { throw AgentErrorCode.storageError }
            }
            return previous
        } catch let error as LibraryMutationReceiptError {
            switch error {
            case .requestConflict: throw AgentErrorCode.invalidInput
            case .retryWindowExpired: throw AgentErrorCode.retryWindowExpired
            case .pendingChanges: throw AgentErrorCode.busy
            case .invalidReceipt: throw AgentErrorCode.storageError
            }
        }
    }

    private func plan(_ request: AgentRequest, grant: AgentGrant, newID: UUID = UUID(),
                      authorize: () throws -> Void) throws -> EditorThemeDefinition {
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentAppearanceSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        var value: EditorThemeDefinition
        if request.operation == "themes.create" {
            guard case .object(let input) = parameters["theme"],
                  case .object(var base) = try JSONDecoder().decode(AgentJSONValue.self,
                    from: JSONEncoder().encode(EditorThemeDefinition(id: newID))) else { throw AgentErrorCode.invalidInput }
            base.merge(input) { _, new in new }
            do { value = try JSONDecoder().decode(EditorThemeDefinition.self, from: JSONEncoder().encode(AgentJSONValue.object(base))) }
            catch { throw AgentErrorCode.invalidInput }
        } else {
            guard let id = request.targets.first?.id, let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
            let original = try reader.definition(id, grant: grant, authorize: authorize)
            guard try reader.version(original) == expected else { throw AgentErrorCode.versionConflict }
            if request.operation == "themes.update" {
                // File themes use Reload or targeted replacement in the native app.
                guard original.type == "custom" else { throw AgentErrorCode.interactionRequired }
                guard let input = parameters["theme"] else { throw AgentErrorCode.invalidInput }
                do { value = try JSONDecoder().decode(EditorThemeDefinition.self, from: JSONEncoder().encode(input)) }
                catch { throw AgentErrorCode.invalidInput }
                guard value.id == id else { throw AgentErrorCode.invalidInput }
            } else {
                value = original; value.id = newID; value.type = "custom"
                if case .string(let name) = parameters["name"] { value.name = name }
                else { value.name += " Copy" }
            }
        }
        guard value.type == "custom" else { throw AgentErrorCode.invalidInput }
        do { value = try DraftsThemeImport.applyingEditorChanges(value); try value.validate() }
        catch { throw AgentErrorCode.invalidInput }
        if request.operation != "themes.update", library.themes.contains(where: { $0.id == value.id }) { throw AgentErrorCode.versionConflict }
        guard !library.themes.contains(where: { $0.id != value.id && $0.type == value.type && $0.name == value.name }) else {
            throw AgentErrorCode.versionConflict
        }
        return value
    }

    func prepare(_ request: AgentRequest, grant: AgentGrant, authorize: () throws -> Void) throws -> AgentRetryKeys.Ticket {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        guard Self.operationNames.contains(request.operation), request.libraryID == libraryID,
              request.retryKey == nil else { throw AgentErrorCode.invalidInput }
        try authorize()
        let ticket = try keys.issue(request, connectionID: grant.connectionID)
        if try receipt(request, ticket: ticket) == nil { _ = try plan(request, grant: grant, authorize: authorize) }
        try authorize(); _ = try keys.verify(ticket.value, request: request, connectionID: grant.connectionID)
        return ticket
    }

    func update(_ request: AgentRequest, grant: AgentGrant, authorize: () throws -> Void) throws -> LibraryMutationReceipt {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        guard Self.operationNames.contains(request.operation), request.libraryID == libraryID,
              let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try authorize()
        let ticket = try keys.verify(key, request: request, connectionID: grant.connectionID)
        if let previous = try receipt(request, ticket: ticket) { try authorize(); return previous }
        let value = try plan(request, grant: grant, authorize: authorize)
        do {
            return try library.commitTheme(value, mutation: identity(request, ticket: ticket), at: now(), validateCommit: {
                try Task.checkCancellation(); try authorize()
                _ = try self.keys.verify(key, request: request, connectionID: grant.connectionID)
                guard try self.plan(request, grant: grant, newID: value.id, authorize: authorize) == value else {
                    throw AgentErrorCode.versionConflict
                }
                try Task.checkCancellation(); try authorize()
                _ = try self.keys.verify(key, request: request, connectionID: grant.connectionID)
            }, makeResource: { .init(id: $0.id, versionToken: try self.reader.version($0)) })
        } catch is CancellationError { throw AgentErrorCode.cancelled }
        catch let error as AgentErrorCode { throw error }
        catch { throw AgentErrorCode.storageError }
    }
}
