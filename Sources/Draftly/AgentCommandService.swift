import Foundation
import CryptoKit
import DraftlyCore
import AgentContracts

// The transport owns a session handle. A request cannot supply its own authority.
@MainActor final class AgentCommandService {
    struct Session {
        fileprivate let id: UUID
    }
    private struct Authorization {
        let connectionID: UUID
        let grantID: UUID
    }
    private static let readOperations: Set<String> = ["server.status", "server.capabilities", "server.schemas",
        "library.summary", "drafts.list", "drafts.search", "drafts.get", "drafts.versions", "preferences.schema"]
    private static let editorReadOperations: Set<String> = ["editor.windows", "editor.get", "editor.find", "editor.markers", "editor.links", "editor.listTasks"]
    private static let actionReadOperations: Set<String> = ["actions.list", "actions.get", "actions.stepSchemas", "actions.groups", "actionGroups.get"]
    private static let workspaceReadOperations: Set<String> = ["workspaces.list", "workspaces.get", "workspaces.query"]
    static let implementedOperations = readOperations.union(actionReadOperations).union(workspaceReadOperations).union([AgentMutationSchemas.name, "actions.create", "actions.update", "actions.duplicate", "actions.move", "actions.reorder", "actions.validateShortcut", "actionGroups.create", "actionGroups.update", "actionGroups.duplicate", "actionGroups.reorder"]).union(AgentDraftWriting.operationNames).union(editorReadOperations)
    private var availableOperations: Set<String> {
        var operations = editorRegistry == nil ? Self.readOperations.union(Self.actionReadOperations).union(Self.workspaceReadOperations) : (writes == nil ? Self.readOperations.union(Self.editorReadOperations).union(Self.actionReadOperations).union(Self.workspaceReadOperations) : Self.implementedOperations)
        if readActivity != nil { operations.insert("activity.list") }
        return operations
    }
    var availableCapabilities: Set<AgentCapability> {
        availableOperations.reduce(into: Set<AgentCapability>()) { result, name in
            if let operation = AgentOperationCatalog.operation(named: name) { result.formUnion(operation.capabilities) }
        }
    }
    private let actionLibrary: LibraryStore
    private let actionVersionKey = SymmetricKey(size: .bits256)
    private let editorRegistry: AgentEditorRegistry?
    private let windowReadKey = SymmetricKey(size: .bits256)
    private let retryKeys: AgentRetryKeys
    private var writes: AgentDraftWriting?
    private let libraryID: UUID
    private let connections: AgentConnectionRegistry
    private let validateHost: () throws -> Void
    private let isLocked: () -> Bool
    private let now: () -> Date
    private let appVersion: String
    private let preferences: AgentPreferenceRegistry
    private let pages: AgentReadPages
    private let recordActivity: (UUID, UUID, UUID, String, String) -> Void
    private let readActivity: ((UUID, UUID) throws -> [AgentActivityStore.Entry])?
    private let preferenceDescriptorIDs: [UUID]
    private let preferenceDescriptors: [UUID: AgentPreferenceField]
    private let drafts: AgentDraftReading
    private var sessions: [UUID: Authorization] = [:]

    init(library: LibraryStore, libraryID: UUID, connections: AgentConnectionRegistry, appVersion: String,
         validateHost: @escaping () throws -> Void, isLocked: @escaping () -> Bool, now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         editors: AgentEditorRegistry? = nil,
         pendingEditorGeneration: @escaping (UUID) -> String,
         recordActivity: @escaping (UUID, UUID, UUID, String, String) -> Void = { _, _, _, _, _ in },
         readActivity: ((UUID, UUID) throws -> [AgentActivityStore.Entry])? = nil) throws {
        guard editors?.isBound(to: library) ?? true else { throw AgentErrorCode.invalidInput }
        self.actionLibrary = library
        self.libraryID = libraryID; self.connections = connections; self.appVersion = appVersion
        self.editorRegistry = editors
        self.validateHost = validateHost
        self.isLocked = isLocked; self.now = now
        self.recordActivity = recordActivity
        self.readActivity = readActivity
        let preferences = try AgentPreferenceCatalog.make()
        self.preferences = preferences
        let descriptors = preferences.fields.map { (UUID(), $0) }
        preferenceDescriptorIDs = descriptors.map { $0.0 }
        preferenceDescriptors = Dictionary(uniqueKeysWithValues: descriptors)
        let pages = AgentReadPages(now: now, uptime: uptime)
        self.pages = pages
        drafts = AgentDraftReading(library: library, pages: pages, editors: editors, pendingEditorGeneration: pendingEditorGeneration)
        retryKeys = AgentRetryKeys(now: now, uptime: uptime,
            currentGrant: { try? connections.grantForAuthenticatedConnection($0) }, isLocked: isLocked)
        if let editors {
            writes = try AgentDraftWriting(library: library, libraryID: libraryID, reader: drafts, editors: editors,
                keys: retryKeys, now: now, validateAdmission: { [weak self] in
                    guard let self else { throw AgentErrorCode.cancelled }; try self.validateAdmission()
                })
        }
    }

    func authenticate(connectionID: UUID, credential: Data, expectedLibraryID: UUID? = nil) throws -> Session {
        try validateAdmission()
        guard expectedLibraryID == nil || expectedLibraryID == libraryID else { throw AgentErrorCode.permissionDenied }
        let grant = try connections.authenticate(connectionID, candidate: credential, libraryID: libraryID)
        try validateAdmission()
        guard sessions.count < 128 else { throw AgentErrorCode.busy }
        let id = UUID()
        sessions[id] = Authorization(connectionID: connectionID, grantID: grant.grantID)
        return Session(id: id)
    }

    func close(_ session: Session) {
        sessions.removeValue(forKey: session.id); pages.remove(sessionID: session.id)
    }

    func authorizedLibraryID(for session: Session) throws -> UUID { try authorize(session).libraryID }

    func permitsTransportStart() throws -> Bool {
        guard !isLocked() else { return false }
        try validateAdmission()
        return try connections.permitsTransportStart()
    }

    func invalidate(connectionID: UUID) {
        for id in sessions.filter({ $0.value.connectionID == connectionID }).keys {
            sessions.removeValue(forKey: id); pages.remove(sessionID: id)
        }
    }

    func invalidateAll() { sessions.removeAll(); pages.removeAll() }

    // An invalid envelope has no trusted request identity and fails before dispatch.
    func respond(to data: Data, session: Session) throws -> Data {
        let request = try AgentRequest.decode(data)
        var authority: (connectionID: UUID, grantID: UUID)?
        var result = AgentErrorCode.storageError.rawValue
        defer {
            if let authority, AgentOperationCatalog.operation(named: request.operation) != nil {
                recordActivity(authority.connectionID, authority.grantID, request.requestID, request.operation, result)
            }
        }
        do {
            let grant = try authorize(session)
            authority = (grant.connectionID, grant.grantID)
            switch AgentPermissionPolicy.evaluate(request, connectionID: grant.connectionID, grant: grant, now: now()) {
            case .permitted: break
            case .denied(let error): throw error
            case .needsHumanApproval, .needsEffectAuthorization: throw AgentErrorCode.unavailable
            }
            guard availableOperations.contains(request.operation) else { throw AgentErrorCode.unavailable }
            let parameters: [String: AgentJSONValue]
            do { parameters = try AgentOperationSchemas.validatedParameters(for: request, preferences: preferences) }
            catch { throw AgentErrorCode.invalidInput }
            let values = try dispatch(request, parameters: parameters, grant: grant, sessionID: session.id)
            do { try AgentOperationSchemas.validateResult(values, for: request, preferences: preferences) }
            catch { throw AgentErrorCode.storageError }
            let response = try AgentResponse(requestID: request.requestID, outcome: .result(.object(values)))
            let encoded = try JSONEncoder().encode(response)
            guard encoded.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.unavailable }
            // Encoding can take time. Recheck authority after it, before returning bytes.
            let current = try authorize(session)
            guard current.grantID == grant.grantID, current.capabilities == grant.capabilities,
                  current.scope == grant.scope, current.expiresAt == grant.expiresAt else { throw AgentErrorCode.permissionDenied }
            result = "success"
            return encoded
        } catch let error as AgentErrorCode {
            result = error.rawValue
            return try JSONEncoder().encode(AgentResponse(requestID: request.requestID, outcome: .error(error)))
        } catch {
            return try JSONEncoder().encode(AgentResponse(requestID: request.requestID, outcome: .error(.storageError)))
        }
    }

    private func validateAdmission() throws {
        guard !isLocked() else { invalidateAll(); throw AgentErrorCode.permissionDenied }
        do { try validateHost() }
        catch {
            // A transient lock collision denies this attempt. A lost owner must
            // not regain old sessions after a new host epoch.
            if (error as? AgentErrorCode) != .busy { invalidateAll(); retryKeys.close(); writes = nil }
            throw error
        }
    }

    private func authorize(_ session: Session) throws -> AgentGrant {
        try validateAdmission()
        guard let authority = sessions[session.id],
              let grant = try connections.grantForAuthenticatedConnection(authority.connectionID),
              grant.grantID == authority.grantID, grant.libraryID == libraryID else {
            close(session); throw AgentErrorCode.permissionDenied
        }
        return grant
    }

    private func actionVersion(_ action: DraftAction) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return Data(HMAC<SHA256>.authenticationCode(for: try encoder.encode(action), using: actionVersionKey)).base64EncodedString()
    }

    private func checkedActionUpdate(_ request: AgentRequest, connectionID: UUID) throws -> DraftAction {
        guard let target = request.targets.first?.id, let expected = request.expectedVersion,
              let original = actionLibrary.actions.first(where: { $0.id == target }) else { throw AgentErrorCode.notFound }
        guard try actionVersion(original) == expected else { throw AgentErrorCode.versionConflict }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentActionSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard let value = parameters["action"] else { throw AgentErrorCode.invalidInput }
        let edited: DraftAction
        do { edited = try JSONDecoder().decode(DraftAction.self, from: JSONEncoder().encode(value)) }
        catch { throw AgentErrorCode.invalidInput }
        guard edited.id == target, edited.group == original.group,
              !edited.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentErrorCode.invalidInput }
        if edited.shortcut != original.shortcut || edited.shortcutModifiers != original.shortcutModifiers {
            guard let grant = try connections.grantForAuthenticatedConnection(connectionID), grant.scope == .library else {
                throw AgentErrorCode.permissionDenied
            }
            guard ActionShortcut.conflict(for: edited, in: actionLibrary.actions) == nil else { throw AgentErrorCode.invalidInput }
        }
        return edited
    }

    private func newAction(_ request: AgentRequest) throws -> DraftAction {
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentActionSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard case .object(let input) = parameters["action"], case .string(let name) = input["name"],
              case .array(let steps) = input["steps"], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentErrorCode.invalidInput
        }
        let base = DraftAction(name: name, steps: [])
        guard case .object(var definition) = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(base)) else {
            throw AgentErrorCode.storageError
        }
        definition.merge(input) { _, new in new }
        definition["steps"] = .array(try steps.map { value in
            guard case .object(let input) = value, case .string(let type) = input["type"] else { throw AgentErrorCode.invalidInput }
            let base = ActionStep(type, ActionStepCreationDefaults.values(for: type))
            guard case .object(var fields) = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(base)) else {
                throw AgentErrorCode.storageError
            }
            fields.merge(input) { _, new in new }
            return .object(fields)
        })
        do { return try JSONDecoder().decode(DraftAction.self, from: JSONEncoder().encode(AgentJSONValue.object(definition))) }
        catch { throw AgentErrorCode.invalidInput }
    }

    private func validateNewAction(_ action: DraftAction) throws {
        guard !actionLibrary.actions.contains(where: { $0.id == action.id }) else { throw AgentErrorCode.versionConflict }
        guard ActionShortcut.conflict(for: action, in: actionLibrary.actions) == nil else { throw AgentErrorCode.invalidInput }
    }

    private func checkedActionMove(_ request: AgentRequest) throws -> DraftAction {
        guard let actionID = request.targets.first(where: { $0.kind == .action })?.id,
              let groupID = request.targets.first(where: { $0.kind == .actionGroup })?.id,
              let expected = request.expectedVersion,
              var action = actionLibrary.actions.first(where: { $0.id == actionID }),
              let group = groups(in: .library).first(where: { $0.id == groupID }) else { throw AgentErrorCode.notFound }
        guard try actionVersion(action) == expected else { throw AgentErrorCode.versionConflict }
        action.group = group.name
        return action
    }

    private func checkedActionDuplicate(_ request: AgentRequest, newID: UUID = UUID()) throws -> DraftAction {
        guard let target = request.targets.first?.id, let expected = request.expectedVersion,
              var copy = actionLibrary.actions.first(where: { $0.id == target }) else { throw AgentErrorCode.notFound }
        guard try actionVersion(copy) == expected else { throw AgentErrorCode.versionConflict }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentActionSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        if case .string(let name) = parameters["name"] { copy.name = name }
        else { copy.name += " Copy" }
        guard !copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentErrorCode.invalidInput }
        copy.id = newID
        copy.shortcut = ""
        return copy
    }

    private func newActionGroup(_ request: AgentRequest) throws -> ActionGroupRecord {
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentActionSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard case .object(let input) = parameters["group"], case .string(let name) = input["name"],
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentErrorCode.invalidInput }
        var base = ActionGroupRecord(name: name.trimmingCharacters(in: .whitespacesAndNewlines)); base.id = UUID()
        guard case .object(var definition) = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(base)) else {
            throw AgentErrorCode.storageError
        }
        definition.merge(input) { _, new in new }
        definition["name"] = .string(base.name)
        do { return try JSONDecoder().decode(ActionGroupRecord.self, from: JSONEncoder().encode(AgentJSONValue.object(definition))) }
        catch { throw AgentErrorCode.invalidInput }
    }

    private func validateNewGroup(_ group: ActionGroupRecord) throws {
        guard !actionLibrary.groupNames.contains(group.name),
              !actionLibrary.actionGroupIdentifiers.values.contains(group.id) else { throw AgentErrorCode.versionConflict }
    }

    private func checkedGroupUpdate(_ request: AgentRequest) throws -> (updated: ActionGroupRecord, original: ActionGroupRecord, actions: [DraftAction]) {
        guard let id = request.targets.first?.id, let expected = request.expectedVersion,
              let original = groups(in: .library).first(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
        guard try groupVersion(original) == expected else { throw AgentErrorCode.versionConflict }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentActionSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard let input = parameters["group"] else { throw AgentErrorCode.invalidInput }
        var updated: ActionGroupRecord
        do { updated = try JSONDecoder().decode(ActionGroupRecord.self, from: JSONEncoder().encode(input)) }
        catch { throw AgentErrorCode.invalidInput }
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard updated.id == id, !updated.name.isEmpty else { throw AgentErrorCode.invalidInput }
        guard updated.name == original.name || !actionLibrary.groupNames.contains(updated.name) else { throw AgentErrorCode.versionConflict }
        return (updated, original, actionLibrary.actions.filter { $0.group == original.name })
    }

    private func checkedGroupCopy(_ request: AgentRequest) throws -> (original: ActionGroupRecord, actions: [DraftAction], name: String) {
        guard let id = request.targets.first?.id, let expected = request.expectedVersion,
              let original = groups(in: .library).first(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
        guard try groupVersion(original) == expected else { throw AgentErrorCode.versionConflict }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentActionSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        let proposed: String
        if case .string(let value) = parameters["name"] { proposed = value }
        else { proposed = original.name + " Copy" }
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AgentErrorCode.invalidInput }
        guard !actionLibrary.groupNames.contains(name) else { throw AgentErrorCode.versionConflict }
        return (original, actionLibrary.actions.filter { $0.group == original.name }, name)
    }

    private func checkedGroupOrder(_ request: AgentRequest) throws -> [ActionGroupRecord] {
        guard let expected = request.expectedVersion, try groupOrderVersion() == expected else { throw AgentErrorCode.versionConflict }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentActionSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard case .array(let values) = parameters["order"] else { throw AgentErrorCode.invalidInput }
        let existing = groups(in: .library)
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let ids = values.compactMap { value -> UUID? in
            guard case .string(let text) = value else { return nil }; return UUID(uuidString: text)
        }
        guard !ids.isEmpty, ids.count == existing.count, Set(ids) == Set(byID.keys) else { throw AgentErrorCode.versionConflict }
        return try ids.enumerated().map { order, id in
            guard var group = byID[id] else { throw AgentErrorCode.versionConflict }
            group.order = order; return group
        }
    }

    private func checkedActionOrder(_ request: AgentRequest) throws -> [DraftAction] {
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentActionSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        guard case .array(let values) = parameters["order"], let firstID = request.targets.first?.id,
              let first = actionLibrary.actions.first(where: { $0.id == firstID }),
              let groupID = actionLibrary.actionGroupIdentifiers[first.group], let expected = request.expectedVersion else {
            throw AgentErrorCode.notFound
        }
        guard try actionOrderVersion(groupID: groupID) == expected else { throw AgentErrorCode.versionConflict }
        let existing = actionLibrary.actions.filter { $0.group == first.group }
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let ids = values.compactMap { value -> UUID? in
            guard case .string(let text) = value else { return nil }; return UUID(uuidString: text)
        }
        guard !ids.isEmpty, ids.count == existing.count, Set(ids) == Set(byID.keys) else { throw AgentErrorCode.versionConflict }
        return try ids.enumerated().map { order, id in
            guard var action = byID[id] else { throw AgentErrorCode.versionConflict }
            action.presentation.order = order; return action
        }
    }

    private func actionMutationReceipt(_ request: AgentRequest, ticket: AgentRetryKeys.Ticket) throws -> LibraryMutationReceipt? {
        let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        do {
            let receipt = try actionLibrary.mutationReceipt(for: identity, at: now())
            if request.operation == "actionGroups.reorder" || request.operation == "actions.reorder" {
                if let receipt, Set(receipt.resources.map(\.id)) != Set(request.targets.map(\.id)) { throw AgentErrorCode.storageError }
                return receipt
            }
            let expected: UUID?
            if request.operation == "actionGroups.create", case .object(let group) = request.parameters["group"],
               case .string(let raw) = group["id"] { expected = UUID(uuidString: raw) }
            else if request.operation == "actions.create", case .object(let action) = request.parameters["action"],
               case .string(let raw) = action["id"] { expected = UUID(uuidString: raw) }
            else if request.operation == "actions.duplicate" || request.operation == "actionGroups.duplicate" { expected = nil }
            else if request.operation == "actionGroups.update" { expected = request.targets.first(where: { $0.kind == .actionGroup })?.id }
            else { expected = request.targets.first(where: { $0.kind == .action })?.id }
            guard receipt == nil || (receipt?.resources.count == 1 && (expected == nil || receipt?.resources.first?.id == expected)) else {
                throw AgentErrorCode.storageError
            }
            return receipt
        } catch let error as LibraryMutationReceiptError {
            switch error {
            case .requestConflict: throw AgentErrorCode.invalidInput
            case .retryWindowExpired: throw AgentErrorCode.retryWindowExpired
            case .pendingChanges: throw AgentErrorCode.busy
            case .invalidReceipt: throw AgentErrorCode.storageError
            }
        }
    }

    private func prepareActionUpdate(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
        guard request.retryKey == nil, request.libraryID == libraryID else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try retryKeys.issue(request, connectionID: connectionID)
        if try actionMutationReceipt(request, ticket: ticket) == nil {
            if request.operation == "actionGroups.create" { try validateNewGroup(newActionGroup(request)) }
            else if request.operation == "actionGroups.update" { _ = try checkedGroupUpdate(request) }
            else if request.operation == "actionGroups.duplicate" { _ = try checkedGroupCopy(request) }
            else if request.operation == "actionGroups.reorder" { _ = try checkedGroupOrder(request) }
            else if request.operation == "actions.reorder" { _ = try checkedActionOrder(request) }
            else if request.operation == "actions.create" { try validateNewAction(newAction(request)) }
            else if request.operation == "actions.duplicate" { try validateNewAction(checkedActionDuplicate(request)) }
            else if request.operation == "actions.move" { _ = try checkedActionMove(request) }
            else { _ = try checkedActionUpdate(request, connectionID: connectionID) }
        }
        try validateAdmission(); _ = try retryKeys.verify(ticket.value, request: request, connectionID: connectionID)
        return ticket
    }

    private func updateAction(_ request: AgentRequest, connectionID: UUID) throws -> LibraryMutationReceipt {
        guard let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try validateAdmission()
        let ticket = try retryKeys.verify(key, request: request, connectionID: connectionID)
        if let previous = try actionMutationReceipt(request, ticket: ticket) {
            try validateAdmission(); _ = try retryKeys.verify(key, request: request, connectionID: connectionID)
            return previous
        }
        if request.operation == "actions.reorder" {
            let actions = try checkedActionOrder(request)
            let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            do {
                return try actionLibrary.commitActions(actions, mutation: identity, at: now(), validateCommit: {
                    try self.validateAdmission(); _ = try self.retryKeys.verify(key, request: request, connectionID: connectionID)
                    guard try self.checkedActionOrder(request) == actions else { throw AgentErrorCode.versionConflict }
                }, makeResources: { actions in
                    try actions.map { .init(id: $0.id, versionToken: try self.actionVersion($0)) }
                })
            } catch let error as AgentErrorCode { throw error }
            catch { throw AgentErrorCode.storageError }
        }
        if request.operation == "actionGroups.reorder" {
            let records = try checkedGroupOrder(request)
            let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            do {
                return try actionLibrary.commitActionGroups(records, mutation: identity, at: now(), validateCommit: {
                    try self.validateAdmission(); _ = try self.retryKeys.verify(key, request: request, connectionID: connectionID)
                    guard try self.checkedGroupOrder(request) == records else { throw AgentErrorCode.versionConflict }
                }, makeResources: { groups in
                    try groups.map { .init(id: $0.id, versionToken: try self.groupVersion($0)) }
                })
            } catch let error as AgentErrorCode { throw error }
            catch { throw AgentErrorCode.storageError }
        }
        if request.operation == "actionGroups.duplicate" {
            let source = try checkedGroupCopy(request)
            var group = source.original; group.id = UUID(); group.name = source.name
            let lastOrder = groups(in: .library).map(\.order).max() ?? -1
            guard lastOrder < Int.max else { throw AgentErrorCode.invalidInput }
            group.order = lastOrder + 1
            let copies = source.actions.map { action in
                var copy = action; copy.id = UUID(); copy.group = group.name; copy.shortcut = ""
                return copy
            }
            let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            do {
                return try actionLibrary.commitActionGroupCopy(group, actions: copies, mutation: identity, at: now(), validateCommit: {
                    try self.validateAdmission(); _ = try self.retryKeys.verify(key, request: request, connectionID: connectionID)
                    let current = try self.checkedGroupCopy(request)
                    guard current.original == source.original, current.actions == source.actions,
                          current.name == source.name else { throw AgentErrorCode.versionConflict }
                }, makeResource: { .init(id: $0.id, versionToken: try self.groupVersion($0)) })
            } catch let error as AgentErrorCode { throw error }
            catch { throw AgentErrorCode.storageError }
        }
        if request.operation == "actionGroups.create" || request.operation == "actionGroups.update" {
            let checked = request.operation == "actionGroups.update" ? try checkedGroupUpdate(request) : nil
            let group = try checked?.updated ?? newActionGroup(request)
            if checked == nil { try validateNewGroup(group) }
            let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
            do {
                return try actionLibrary.commitActionGroup(group, mutation: identity, at: now(), previousName: checked?.original.name, validateCommit: {
                    try self.validateAdmission(); _ = try self.retryKeys.verify(key, request: request, connectionID: connectionID)
                    if let checked {
                        let current = try self.checkedGroupUpdate(request)
                        guard current.updated == checked.updated, current.original == checked.original,
                              current.actions == checked.actions else { throw AgentErrorCode.versionConflict }
                    } else { try self.validateNewGroup(group) }
                }, makeResource: { .init(id: $0.id, versionToken: try self.groupVersion($0)) })
            } catch let error as AgentErrorCode { throw error }
            catch { throw AgentErrorCode.storageError }
        }
        let action: DraftAction
        if request.operation == "actions.create" { action = try newAction(request); try validateNewAction(action) }
        else if request.operation == "actions.duplicate" { action = try checkedActionDuplicate(request); try validateNewAction(action) }
        else if request.operation == "actions.move" { action = try checkedActionMove(request) }
        else { action = try checkedActionUpdate(request, connectionID: connectionID) }
        let identity = LibraryMutationIdentity(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
        do {
            return try actionLibrary.commitActions([action], mutation: identity, at: now(), validateCommit: {
                try self.validateAdmission(); _ = try self.retryKeys.verify(key, request: request, connectionID: connectionID)
                if request.operation == "actions.create" { try self.validateNewAction(action) }
                else if request.operation == "actions.duplicate" {
                    try self.validateNewAction(action)
                    guard try self.checkedActionDuplicate(request, newID: action.id) == action else { throw AgentErrorCode.versionConflict }
                }
                else if request.operation == "actions.move" {
                    guard try self.checkedActionMove(request) == action else { throw AgentErrorCode.versionConflict }
                }
                else { _ = try self.checkedActionUpdate(request, connectionID: connectionID) }
            }, makeResources: { actions in
                try actions.map { .init(id: $0.id, versionToken: try self.actionVersion($0)) }
            })
        } catch let error as AgentErrorCode { throw error }
        catch { throw AgentErrorCode.storageError }
    }

    private func groupVersion(_ group: ActionGroupRecord) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return Data(HMAC<SHA256>.authenticationCode(for: try encoder.encode(group), using: actionVersionKey)).base64EncodedString()
    }

    private func groupOrderVersion() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return Data(HMAC<SHA256>.authenticationCode(for: try encoder.encode(groups(in: .library)), using: actionVersionKey)).base64EncodedString()
    }

    private func actionOrderVersion(groupID: UUID) throws -> String {
        guard let group = groups(in: .library).first(where: { $0.id == groupID }) else { throw AgentErrorCode.versionConflict }
        let actions = actionLibrary.orderedActions().filter { $0.group == group.name }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(group) + encoder.encode(actions)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: actionVersionKey)).base64EncodedString()
    }

    private func workspaceVersion(_ workspace: Workspace) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return Data(HMAC<SHA256>.authenticationCode(for: try encoder.encode(workspace), using: actionVersionKey)).base64EncodedString()
    }

    private func groups(in scope: AgentResourceScope) -> [ActionGroupRecord] {
        let identifiers = actionLibrary.actionGroupIdentifiers
        return actionLibrary.groupNames.enumerated().compactMap { order, name in
            guard let id = identifiers[name], scope.permits(.init(kind: .actionGroup, id: id)) else { return nil }
            if let record = actionLibrary.actionGroups.first(where: { $0.name == name && $0.id == id }) { return record }
            var record = ActionGroupRecord(name: name); record.id = id; record.order = order
            return record
        }
    }

    private func dispatch(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant,
                          sessionID: UUID) throws -> [String: AgentJSONValue] {
        switch request.operation {
        case "workspaces.get":
            guard let id = request.targets.first?.id, grant.scope.permits(.init(kind: .workspace, id: id)),
                  let workspace = actionLibrary.workspaces.first(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
            let value = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(workspace))
            return ["workspace": value, "versionToken": .string(try workspaceVersion(workspace))]
        case "workspaces.list":
            return try pages.page(owner: .init(sessionID: sessionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt,
                ids: { self.actionLibrary.workspaces.filter { grant.scope.permits(.init(kind: .workspace, id: $0.id)) }.map(\.id) },
                value: { id in
                    guard grant.scope.permits(.init(kind: .workspace, id: id)),
                          let workspace = self.actionLibrary.workspaces.first(where: { $0.id == id }) else { return nil }
                    return .object(["id": .string(id.uuidString), "name": .string(workspace.name),
                        "order": workspace.order.map { .integer(Int64($0)) } ?? .null,
                        "versionToken": .string(try self.workspaceVersion(workspace))])
                })
        case "actions.validateShortcut":
            guard case .string(let key) = parameters["key"] else { throw AgentErrorCode.invalidInput }
            let modifiers: [String]?
            if case .array(let values) = parameters["modifiers"] {
                modifiers = try values.map { guard case .string(let value) = $0 else { throw AgentErrorCode.invalidInput }; return value }
            } else { modifiers = nil }
            var candidate: DraftAction
            if case .string(let value) = parameters["actionID"] {
                guard let id = UUID(uuidString: value), let existing = actionLibrary.actions.first(where: { $0.id == id }) else {
                    throw AgentErrorCode.notFound
                }
                candidate = existing
            } else { candidate = DraftAction(name: "", steps: []) }
            candidate.shortcut = key; candidate.shortcutModifiers = modifiers
            return ["available": .bool(ActionShortcut.conflict(for: candidate, in: actionLibrary.actions) == nil)]
        case "actions.stepSchemas":
            return ["steps": .array(DraftAction.supportedSteps.sorted().map { type in
                .object(["type": .string(type), "creationDefaults": .object(
                    ActionStepCreationDefaults.values(for: type).mapValues { .string($0) })])
            })]
        case "activity.list":
            guard let readActivity else { throw AgentErrorCode.unavailable }
            let entries = try readActivity(grant.connectionID, grant.grantID).filter {
                $0.connectionID == grant.connectionID && $0.grantID == grant.grantID && $0.libraryID == libraryID
            }
            let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return try pages.page(owner: .init(sessionID: sessionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt, ids: { entries.map(\.id) }, value: { id in
                    guard let entry = byID[id] else { return nil }
                    return .object(["id": .string(entry.id.uuidString), "requestID": .string(entry.requestID.uuidString),
                        "operation": .string(entry.operation), "date": .string(APIValues.date(entry.date)), "result": .string(entry.result)])
                })
        case "actionGroups.get":
            guard let id = request.targets.first?.id, let group = groups(in: grant.scope).first(where: { $0.id == id }) else {
                throw AgentErrorCode.notFound
            }
            let encoded = try JSONEncoder().encode(group)
            return ["group": try JSONDecoder().decode(AgentJSONValue.self, from: encoded), "versionToken": .string(try groupVersion(group))]
        case "actions.groups":
            return try pages.page(owner: .init(sessionID: sessionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt, ids: { self.groups(in: grant.scope).map(\.id) }, value: { id in
                    guard let group = self.groups(in: grant.scope).first(where: { $0.id == id }) else { return nil }
                    let token = try self.groupVersion(group)
                    return .object(["id": .string(id.uuidString), "name": .string(group.name),
                        "symbol": .string(group.symbol), "order": .integer(Int64(group.order)), "versionToken": .string(token)])
                }, revision: grant.scope == .library ? { try self.groupOrderVersion() } : nil)
        case "actions.get":
            guard let id = request.targets.first?.id,
                  grant.scope.permits(.init(kind: .action, id: id)),
                  let action = actionLibrary.actions.first(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
            let encoded = try JSONEncoder().encode(action)
            let value = try JSONDecoder().decode(AgentJSONValue.self, from: encoded)
            return ["action": value, "versionToken": .string(try actionVersion(action))]
        case "actions.list":
            let surface: ActionSurface?
            switch parameters["surface"] {
            case .string("bar"): surface = .bar
            case .string("search"): surface = .search
            case .string("all"): surface = nil
            default: surface = .list
            }
            let requestedGroup: UUID?
            if case .string(let value) = parameters["groupID"] { requestedGroup = UUID(uuidString: value) }
            else { requestedGroup = nil }
            let orderGroup = grant.scope == .library && surface == nil ? requestedGroup : nil
            func permitted(_ action: DraftAction) -> Bool {
                guard grant.scope.permits(.init(kind: .action, id: action.id)),
                      let group = actionLibrary.actionGroupIdentifiers[action.group] else { return false }
                return requestedGroup == nil || requestedGroup == group
            }
            return try pages.page(owner: .init(sessionID: sessionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt,
                ids: { self.actionLibrary.orderedActions(on: surface).filter(permitted).map(\.id) },
                value: { id in
                    guard let action = self.actionLibrary.actions.first(where: { $0.id == id }), permitted(action),
                          let group = self.actionLibrary.actionGroupIdentifiers[action.group],
                          surface.map({ action.appears(on: $0) }) ?? true else { return nil }
                    let token = try self.actionVersion(action)
                    return .object(["id": .string(action.id.uuidString), "name": .string(action.name),
                        "symbol": .string(action.symbol), "groupID": .string(group.uuidString),
                        "group": .string(action.group), "versionToken": .string(token)])
                }, revision: orderGroup.map { id in { try self.actionOrderVersion(groupID: id) } })
        case "server.status":
            return ["apiVersion": .integer(Int64(AgentRequest.version)), "appVersion": .string(appVersion), "accessEnabled": .bool(true)]
        case "server.capabilities":
            let references: [AgentResourceReference]
            switch grant.scope { case .library: references = []; case .resources(let targets):
                references = targets.sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }
            }
            return ["capabilities": .array(grant.capabilities.map(\.rawValue).sorted().map(AgentJSONValue.string)),
                "scope": .object(["allResources": .bool(grant.scope == .library), "resources": .array(references.map {
                    .object(["kind": .string($0.kind.rawValue), "id": .string($0.id.uuidString)])
                })]), "expiresAt": .string(APIValues.date(grant.expiresAt))]
        case "editor.windows", "editor.get", "editor.find", "editor.markers", "editor.links", "editor.listTasks":
            return try readEditor(request, parameters: parameters, grant: grant, sessionID: sessionID)
        case "mutations.prepare":
            guard let writes else { throw AgentErrorCode.unavailable }
            let input = try AgentMutationSchemas.mutation(from: parameters)
            let bound = AgentRequest(requestID: input.requestID, libraryID: input.libraryID ?? libraryID,
                operation: input.operation, targets: input.targets, expectedVersion: input.expectedVersion, parameters: input.parameters)
            let ticket = try ["actions.create", "actions.update", "actions.duplicate", "actions.move", "actions.reorder", "actionGroups.create", "actionGroups.update", "actionGroups.duplicate", "actionGroups.reorder"].contains(bound.operation) ? prepareActionUpdate(bound, connectionID: grant.connectionID) : writes.prepare(bound, connectionID: grant.connectionID)
            return ["requestID": .string(bound.requestID.uuidString), "retryKey": .string(ticket.value),
                "expiresAt": .string(APIValues.date(min(ticket.expiresAt, grant.expiresAt)))]
        case "actionGroups.reorder", "actions.reorder":
            let receipt = try updateAction(request, connectionID: grant.connectionID)
            return ["resources": .array(receipt.resources.map { .object(["id": .string($0.id.uuidString), "versionToken": .string($0.versionToken)]) })]
        case "actions.create", "actions.update", "actions.duplicate", "actions.move", "actionGroups.create", "actionGroups.update", "actionGroups.duplicate":
            let receipt = try updateAction(request, connectionID: grant.connectionID)
            guard let resource = receipt.resources.first else { throw AgentErrorCode.storageError }
            return ["resource": .object(["id": .string(resource.id.uuidString), "versionToken": .string(resource.versionToken)])]
        case "drafts.update", "drafts.patch", "drafts.restoreVersion":
            guard let writes else { throw AgentErrorCode.unavailable }
            let receipt = try writes.update(request, connectionID: grant.connectionID)
            guard let resource = receipt.resources.first else { throw AgentErrorCode.storageError }
            return ["resource": .object(["id": .string(resource.id.uuidString), "versionToken": .string(resource.versionToken)])]
        case "preferences.schema":
            let selected: Set<String>?
            if case .array(let ids) = parameters["ids"] {
                selected = Set(ids.compactMap { if case .string(let id) = $0 { return id }; return nil })
            } else { selected = nil }
            return try pages.page(owner: .init(sessionID: sessionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt, ids: {
                    preferenceDescriptorIDs.filter { id in
                        guard let field = preferenceDescriptors[id] else { return false }
                        return selected?.contains(field.id) ?? true
                    }
                }, value: { id in preferenceDescriptors[id].map { preferences.descriptor($0) } })
        case "server.schemas":
            let names: [String]
            if case .array(let selected) = parameters["operations"] {
                names = selected.compactMap { if case .string(let name) = $0 { return name }; return nil }
            } else { names = AgentOperationCatalog.operations.map(\.name) }
            return ["operations": .array(names.map { name in
                let schema = AgentOperationSchemas.schema(for: name, preferences: preferences)
                return .object(["name": .string(name), "inputSchema": schema?.parameters.jsonSchema ?? .null,
                    "resultSchema": schema?.result.jsonSchema ?? .null, "available": .bool(availableOperations.contains(name) && (name != AgentMutationSchemas.name || !grant.capabilities.isDisjoint(with: [.draftsWrite, .actionsManage])))])
            })]
        default: return try drafts.read(request, parameters: parameters, grant: grant, sessionID: sessionID)
        }
    }
    private func readEditor(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant,
                            sessionID: UUID) throws -> [String: AgentJSONValue] {
        guard let editorRegistry else { throw AgentErrorCode.unavailable }
        func authorized(_ snapshot: AgentEditorRegistry.WindowSnapshot) -> Bool {
            guard grant.scope.permits(.init(kind: .window, id: snapshot.id)) else { return false }
            return snapshot.draftID.map { grant.scope.permits(.init(kind: .draft, id: $0)) } ?? true
        }
        func values(_ snapshot: AgentEditorRegistry.WindowSnapshot) throws -> [String: AgentJSONValue] {
            let selection: AgentJSONValue = .object(["offset": .integer(Int64(snapshot.selection.location)),
                "length": .integer(Int64(snapshot.selection.length))])
            let state: AgentJSONValue = .object(["windowID": .string(snapshot.id.uuidString), "generation": .string(snapshot.generation.uuidString),
                "draftID": snapshot.draftID.map { .string($0.uuidString) } ?? .null,
                "content": .string(snapshot.content), "selection": selection, "dirty": .bool(snapshot.dirty)])
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let token = Data(HMAC<SHA256>.authenticationCode(for: try encoder.encode(state), using: windowReadKey)).base64EncodedString()
            return ["windowID": .string(snapshot.id.uuidString),
                "draftID": snapshot.draftID.map { .string($0.uuidString) } ?? .null,
                "versionToken": .string(token)]
        }
        if request.operation == "editor.windows" {
            return try pages.page(owner: .init(sessionID: sessionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt, ids: {
                    try editorRegistry.windowSnapshots().filter(authorized).map(\.id)
                }, value: { id in
                    guard let snapshot = try editorRegistry.windowSnapshots().first(where: { $0.id == id }), authorized(snapshot) else { return nil }
                    var result = try values(snapshot)
                    result["title"] = .string(Note(content: snapshot.content).title)
                    result["hasUnsavedChanges"] = .bool(snapshot.dirty)
                    return .object(result)
                })
        }
        guard let id = request.targets.first?.id,
              let snapshot = try editorRegistry.windowSnapshots().first(where: { $0.id == id }), authorized(snapshot) else {
            throw AgentErrorCode.notFound
        }
        guard snapshot.draftID != nil || (snapshot.content.isEmpty && !snapshot.dirty) else { throw AgentErrorCode.unavailable }
        var result = try values(snapshot)
        if request.operation != "editor.get" {
            let items: [AgentJSONValue]
            var bound = parameters; bound["editorVersion"] = result["versionToken"]
            if request.operation == "editor.find" {
                guard case .string(let query) = parameters["query"] else { throw AgentErrorCode.invalidInput }
                let matches: [NSRange]
                do {
                    matches = try EditorFindQuery(query, caseSensitive: parameters["caseSensitive"] == .bool(true),
                        regularExpression: parameters["regularExpression"] == .bool(true)).matches(in: snapshot.content)
                } catch { throw AgentErrorCode.invalidInput }
                items = matches.map { .object(["range": .object(["offset": .integer(Int64($0.location)),
                    "length": .integer(Int64($0.length))])]) }
            } else {
                let definition = try editorRegistry.syntaxDefinition(windowID: snapshot.id)
                let identity = definition.source + "\u{0}" + definition.featureState
                bound["syntaxVersion"] = .string(Data(HMAC<SHA256>.authenticationCode(for: Data(identity.utf8),
                    using: windowReadKey)).base64EncodedString())
                items = try Self.syntaxItems(definition, operation: request.operation, content: snapshot.content)
            }
            guard items.count <= 1_000_000 else { throw AgentErrorCode.busy }
            // Bind cursors to editor and syntax state. Never return ranges from old text or rules.
            let members = items.indices.map { index in
                UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    UInt8(truncatingIfNeeded: index >> 24), UInt8(truncatingIfNeeded: index >> 16),
                    UInt8(truncatingIfNeeded: index >> 8), UInt8(truncatingIfNeeded: index)))
            }
            let entries = Dictionary(uniqueKeysWithValues: zip(members, items))
            let page = try pages.page(owner: .init(sessionID: sessionID, grantID: grant.grantID), request: request,
                parameters: bound, expiresAt: grant.expiresAt, ids: { members }, value: { entries[$0] })
            result.merge(page, uniquingKeysWith: { _, new in new })
            return result
        }
        result["content"] = .object(try AgentDraftReading.chunk(snapshot.content, parameters: parameters))
        result["selection"] = .object(["offset": .integer(Int64(snapshot.selection.location)),
            "length": .integer(Int64(snapshot.selection.length))])
        result["hasUnsavedChanges"] = .bool(snapshot.dirty)
        return result
    }

    private static func syntaxItems(_ definition: SyntaxDefinition, operation: String,
                                    content: String) throws -> [AgentJSONValue] {
        let raw: [[String: Any]], fields: Set<String>, ranges: Set<String>
        switch operation {
        case "editor.markers":
            raw = definition.markers(in: content); fields = ["label", "prefix", "level", "range"]; ranges = ["range"]
        case "editor.links":
            raw = definition.links(in: content); fields = ["key", "value", "link", "prefix", "suffix", "range"]; ranges = ["range"]
        case "editor.listTasks":
            raw = definition.tasks(in: content)
            fields = ["line", "label", "state", "interactive", "isCompleted", "lineRange", "labelRange", "stateRange", "interactiveRange"]
            ranges = ["lineRange", "labelRange", "stateRange", "interactiveRange"]
        default: throw AgentErrorCode.unavailable
        }
        return try raw.map { value in
            var result = value.filter { fields.contains($0.key) }
            for key in ranges {
                guard let range = result[key] as? [Int], range.count == 2 else { throw AgentErrorCode.storageError }
                result[key] = ["offset": range[0], "length": range[1]]
            }
            return try JSONDecoder().decode(AgentJSONValue.self, from: JSONSerialization.data(withJSONObject: result))
        }
    }

}
