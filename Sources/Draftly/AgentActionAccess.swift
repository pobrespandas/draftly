import Foundation
import CryptoKit
import DraftlyCore
import AgentContracts

// Keep catalog reads and mutations under the same version and retry rules.
@MainActor final class AgentActionAccess {
    private let actionLibrary: LibraryStore
    private let libraryID: UUID
    private let connections: AgentConnectionRegistry
    private let actionVersionKey: SymmetricKey
    private let retryKeys: AgentRetryKeys
    private let pages: AgentReadPages
    private let validateAdmission: () throws -> Void
    private let now: () -> Date

    init(library: LibraryStore, libraryID: UUID, connections: AgentConnectionRegistry,
         versionKey: SymmetricKey, retryKeys: AgentRetryKeys, pages: AgentReadPages,
         validateAdmission: @escaping () throws -> Void, now: @escaping () -> Date) {
        actionLibrary = library
        self.libraryID = libraryID
        self.connections = connections
        actionVersionKey = versionKey
        self.retryKeys = retryKeys
        self.pages = pages
        self.validateAdmission = validateAdmission
        self.now = now
    }

    func actionVersion(_ action: DraftAction) throws -> String {
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

    func prepareActionUpdate(_ request: AgentRequest, connectionID: UUID) throws -> AgentRetryKeys.Ticket {
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

    func updateAction(_ request: AgentRequest, connectionID: UUID) throws -> LibraryMutationReceipt {
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

    private func groups(in scope: AgentResourceScope) -> [ActionGroupRecord] {
        let identifiers = actionLibrary.actionGroupIdentifiers
        return actionLibrary.groupNames.enumerated().compactMap { order, name in
            guard let id = identifiers[name], scope.permits(.init(kind: .actionGroup, id: id)) else { return nil }
            if let record = actionLibrary.actionGroups.first(where: { $0.name == name && $0.id == id }) { return record }
            var record = ActionGroupRecord(name: name); record.id = id; record.order = order
            return record
        }
    }

    func read(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant,
              sessionID: UUID) throws -> [String: AgentJSONValue] {
        switch request.operation {
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
        default: throw AgentErrorCode.unavailable
        }
    }
}
