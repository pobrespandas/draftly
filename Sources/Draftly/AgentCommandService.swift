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
    static var implementedOperations: Set<String> { AgentOperationAvailability.implementedOperations }
    private var availability: AgentOperationAvailability {
        var handlers: Set<AgentOperationAvailability.Handler> = [.themeWrite]
        if editorRegistry != nil { handlers.insert(.editorRead) }
        if writes != nil { handlers.insert(.draftWrite) }
        if editorWrites != nil { handlers.insert(.editorWrite) }
        if workspaceApplication != nil { handlers.insert(.workspaceApply) }
        if preferenceWrites != nil { handlers.insert(.preferenceWrite) }
        if readActivity != nil { handlers.insert(.activityRead) }
        if operationRegistry != nil { handlers.insert(.operationControl) }
        if submitAction != nil { handlers.insert(.actionExecution) }
        if nativeExecution != nil && operationRegistry != nil { handlers.insert(.nativeExecution) }
        if deletionApprovals != nil && operationRegistry != nil {
            handlers.insert(.workspaceDelete)
            handlers.insert(.actionDelete)
            if writes != nil { handlers.insert(.draftPurge) }
        }
        return AgentOperationAvailability(handlers: handlers)
    }
    private var availableOperations: Set<String> { availability.operations }
    var availableCapabilities: Set<AgentCapability> { availability.capabilities }
    private lazy var actions = AgentActionAccess(library: actionLibrary, libraryID: libraryID, connections: connections,
            versionKey: actionVersionKey, retryKeys: retryKeys, pages: pages,
            validateAdmission: { [weak self] in
                guard let self else { throw AgentErrorCode.cancelled }
                try self.validateAdmission()
            }, now: now)
    private lazy var workspaces = AgentWorkspaceAccess(library: actionLibrary, libraryID: libraryID,
            versionKey: actionVersionKey, retryKeys: retryKeys, defaults: preferenceDefaults,
            validateAdmission: { [weak self] in
                guard let self else { throw AgentErrorCode.cancelled }
                try self.validateAdmission()
            }, now: now)
    private lazy var themes = AgentThemeReading(library: actionLibrary, defaults: preferenceDefaults, pages: pages)
    private lazy var themeWrites = AgentThemeWriting(library: actionLibrary, libraryID: libraryID,
        reader: themes, keys: retryKeys, now: now)
    private lazy var bookmarks = AgentBookmarkReading(defaults: preferenceDefaults, pages: pages)
    private lazy var backups = AgentBackupReading(library: actionLibrary, drafts: drafts, transfers: transfers)
    private let actionLibrary: LibraryStore
    private let operationRegistry: AgentOperationRegistry?
    private let deletionApprovals: AgentApprovalStore?
    private let nativeExecution: AgentNativeExecution.Environment?
    private let submitAction: ((AgentRequest, AgentGrant) throws -> UUID)?
    private let actionVersionKey = SymmetricKey(size: .bits256)
    private let editorRegistry: AgentEditorRegistry?
    private let windowReadKey = SymmetricKey(size: .bits256)
    private let retryKeys: AgentRetryKeys
    private var workspaceApplication: AgentWorkspaceApplication?
    private var writes: AgentDraftWriting?
    private var editorWrites: AgentEditorWriting?
    private var preferenceWrites: AgentPreferenceWriting?
    private let libraryID: UUID
    private let connections: AgentConnectionRegistry
    private let validateHost: () throws -> Void
    private let isLocked: () -> Bool
    private let now: () -> Date
    private let appVersion: String
    private let nativePreferenceRead: ((String) throws -> AgentPreferenceReading)?
    private let preferenceDefaults: UserDefaults
    private let preferenceVersionKey = SymmetricKey(size: .bits256)
    private let preferences: AgentPreferenceRegistry
    private let transfers: AgentTransferStore
    private let pages: AgentReadPages
    private let recordActivity: (UUID, UUID, UUID, String, String) -> Void
    private let readActivity: ((UUID, UUID) throws -> [AgentActivityStore.Entry])?
    private let preferenceDescriptorIDs: [UUID]
    private let preferenceDescriptors: [UUID: AgentPreferenceField]
    private let drafts: AgentDraftReading
    private var sessions: [UUID: Authorization] = [:]

    init(library: LibraryStore, libraryID: UUID, connections: AgentConnectionRegistry, appVersion: String,
         preferenceDefaults: UserDefaults = .standard,
         preferenceStorage: AgentPreferenceStorage? = nil,
         nativePreferenceRead: ((String) throws -> AgentPreferenceReading)? = nil,
         validateHost: @escaping () throws -> Void, isLocked: @escaping () -> Bool, now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         editors: AgentEditorRegistry? = nil,
         pendingEditorGeneration: @escaping (UUID) -> String,
         recordActivity: @escaping (UUID, UUID, UUID, String, String) -> Void = { _, _, _, _, _ in },
         readActivity: ((UUID, UUID) throws -> [AgentActivityStore.Entry])? = nil,
         operations: AgentOperationRegistry? = nil,
         submitAction: ((AgentRequest, AgentGrant) throws -> UUID)? = nil,
         deletionApprovals: AgentApprovalStore? = nil, nativeExecution: AgentNativeExecution.Environment? = nil) throws {
        guard editors?.isBound(to: library) ?? true else { throw AgentErrorCode.invalidInput }
        self.nativeExecution = nativeExecution
        self.nativePreferenceRead = nativePreferenceRead
        self.preferenceDefaults = preferenceDefaults
        self.actionLibrary = library
        self.operationRegistry = operations
        self.deletionApprovals = deletionApprovals
        self.submitAction = submitAction
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
        transfers = AgentTransferStore(now: now, uptime: uptime)
        drafts = AgentDraftReading(library: library, pages: pages, editors: editors, pendingEditorGeneration: pendingEditorGeneration)
        retryKeys = AgentRetryKeys(now: now, uptime: uptime,
            currentGrant: { try? connections.grantForAuthenticatedConnection($0) }, isLocked: isLocked)
        if let preferenceStorage {
            preferenceWrites = AgentPreferenceWriting(storage: preferenceStorage, keys: retryKeys, preferences: preferences,
                currentGrant: { try connections.grantForAuthenticatedConnection($0) }, validateAdmission: { [weak self] in
                    guard let self else { throw AgentErrorCode.cancelled }; try self.validateAdmission()
                }, plan: { [weak self] request, grant in
                    guard let self else { throw AgentErrorCode.cancelled }
                    return try AgentPreferenceBatch.prepare(request, defaults: self.preferenceDefaults, library: self.actionLibrary,
                        grant: grant, resolveSyntax: { address in
                            switch address.syntax {
                            case .builtIn(let name): return try ScriptSyntax.definition(name)
                            case .installed(let id):
                                guard grant.scope.permits(.init(kind: .syntax, id: id)),
                                      let syntax = self.actionLibrary.syntaxes.first(where: { $0.id == id && $0.type != "builtIn" }) else {
                                    throw AgentErrorCode.notFound
                                }
                                return syntax
                            case nil: throw AgentErrorCode.invalidInput
                            }
                        })
                }, readReceipt: { [weak self] request, grant in
                    guard let self else { throw AgentErrorCode.cancelled }
                    return try self.preferenceReceipt(request, grant: grant)
                })
        }
        if let editors {
            writes = try AgentDraftWriting(library: library, libraryID: libraryID, reader: drafts, editors: editors,
                keys: retryKeys, now: now, validateAdmission: { [weak self] in
                    guard let self else { throw AgentErrorCode.cancelled }; try self.validateAdmission()
                }, resolveSyntax: { parameters, connectionID in
                    guard let grant = try connections.grantForAuthenticatedConnection(connectionID) else { throw AgentErrorCode.permissionDenied }
                    return try AgentDraftWriting.syntaxDefinition(parameters, grant: grant, library: library)
                })
            workspaceApplication = AgentWorkspaceApplication(library: library, editors: editors, keys: retryKeys,
                currentGrant: { try connections.grantForAuthenticatedConnection($0) }, version: { [weak self] workspace in
                    guard let self else { throw AgentErrorCode.cancelled }
                    return try self.workspaces.version(workspace)
                })
            editorWrites = AgentEditorWriting(registry: editors, keys: retryKeys,
                currentGrant: { try connections.grantForAuthenticatedConnection($0) }, validateAdmission: { [weak self] in
                    guard let self else { throw AgentErrorCode.cancelled }; try self.validateAdmission()
                }, read: { [weak self] id, grant in
                    guard let self else { throw AgentErrorCode.cancelled }
                    return try self.editorContext(id, grant: grant)
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
        sessions.removeValue(forKey: session.id)
    }

    func authorizedLibraryID(for session: Session) throws -> UUID { try authorize(session).libraryID }

    func permitsTransportStart() throws -> Bool {
        guard !isLocked() else { return false }
        try validateAdmission()
        return try connections.permitsTransportStart()
    }

    func invalidate(connectionID: UUID) {
        for id in sessions.filter({ $0.value.connectionID == connectionID }).keys {
            sessions.removeValue(forKey: id)
        }
        pages.remove(connectionID: connectionID)
        transfers.remove(connectionID: connectionID)
    }

    func invalidateAll() { sessions.removeAll(); pages.removeAll(); transfers.removeAll() }

    // An invalid envelope has no trusted request identity and fails before dispatch.
    func respond(to data: Data, session: Session) throws -> Data {
        try respond(to: AgentRequest.decode(data), session: session)
    }

    func respondAsync(to data: Data, session: Session) async throws -> Data {
        let request = try AgentRequest.decode(data)
        guard request.operation == "operations.wait" else { return try respond(to: request, session: session) }
        var authority: (connectionID: UUID, grantID: UUID)?
        var result = AgentErrorCode.storageError.rawValue
        defer {
            if let authority { recordActivity(authority.connectionID, authority.grantID, request.requestID, request.operation, result) }
        }
        do {
            let grant = try authorize(session)
            authority = (grant.connectionID, grant.grantID)
            _ = try authorizedParameters(for: request, grant: grant)
            guard let operationRegistry else { throw AgentErrorCode.unavailable }
            let waited = try await operationRegistry.wait(request, connectionID: grant.connectionID,
                validateSession: { try self.validateSession(session.id, grant: grant) })
            let values: [String: AgentJSONValue] = ["operation": try waited.snapshot.wireValue(), "waitExpired": .bool(waited.waitExpired)]
            do { try AgentOperationSchemas.validateResult(values, for: request, preferences: preferences) }
            catch { throw AgentErrorCode.storageError }
            let encoded = try JSONEncoder().encode(AgentResponse(requestID: request.requestID, outcome: .result(.object(values))))
            guard encoded.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.unavailable }
            try validateSession(session.id, grant: grant)
            result = "success"
            return encoded
        } catch {
            let code = (error as? AgentErrorCode) ?? (error is CancellationError ? .cancelled : .storageError)
            result = code.rawValue
            return try JSONEncoder().encode(AgentResponse(requestID: request.requestID, outcome: .error(code)))
        }
    }

    private func respond(to request: AgentRequest, session: Session) throws -> Data {
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
            let parameters = try authorizedParameters(for: request, grant: grant)
            let outcome: AgentResponse.Outcome
            if AgentNativeSchemas.operationNames.contains(request.operation) {
                outcome = try submitNative(request, grant: grant, sessionID: session.id)
            } else if ["workspaces.delete", "drafts.purge", "actions.delete", "actionGroups.delete"].contains(request.operation) {
                outcome = try submitDeletion(request, grant: grant, sessionID: session.id)
            } else {
                let values = try dispatch(request, parameters: parameters, grant: grant, sessionID: session.id)
                do { try AgentOperationSchemas.validateResult(values, for: request, preferences: preferences) }
                catch { throw AgentErrorCode.storageError }
                outcome = .result(.object(values))
            }
            let response = try AgentResponse(requestID: request.requestID, outcome: outcome)
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

    private func authorizedParameters(for request: AgentRequest, grant: AgentGrant) throws -> [String: AgentJSONValue] {
        var policyGrant = grant
        if ["operations.get", "operations.cancel", "operations.wait"].contains(request.operation), let operationRegistry {
            guard request.targets.count == 1, let target = request.targets.first, target.kind == .operation else {
                throw AgentErrorCode.invalidInput
            }
            _ = try operationRegistry.snapshot(target.id, connectionID: grant.connectionID)
            // The registry checks original resource scope and operation ownership.
            policyGrant = AgentGrant(connectionID: grant.connectionID, libraryID: grant.libraryID,
                expiresAt: grant.expiresAt, revoked: grant.revoked, capabilities: grant.capabilities,
                scope: .library, grantID: grant.grantID)
        }
        if request.operation.hasPrefix("transfers."), request.operation != "transfers.beginImport" {
            guard request.targets.count == 1, let target = request.targets.first, target.kind == .operation else {
                throw AgentErrorCode.invalidInput
            }
            try transfers.authorize(target.id, grant: grant)
            // Transfer ownership retains the exact source grant and resource scope.
            policyGrant = AgentGrant(connectionID: grant.connectionID, libraryID: grant.libraryID,
                expiresAt: grant.expiresAt, revoked: grant.revoked, capabilities: grant.capabilities,
                scope: .library, grantID: grant.grantID)
        }
        switch AgentPermissionPolicy.evaluate(request, connectionID: grant.connectionID, grant: policyGrant, now: now()) {
        case .permitted: break
        case .denied(let error): throw error
        case .needsHumanApproval:
            guard ["workspaces.delete", "drafts.purge", "actions.delete", "actionGroups.delete"].contains(request.operation), deletionApprovals != nil,
                  operationRegistry != nil else { throw AgentErrorCode.unavailable }
        case .needsEffectAuthorization(_, let humanApproval):
            let reviewedAction = request.operation == "actions.run" && submitAction != nil && operationRegistry != nil
            let preferenceMutation = AgentPreferenceWriting.operationNames.contains(request.operation) && preferenceWrites != nil
            let workspaceEffect = AgentWorkspaceApplication.operationNames.contains(request.operation) && workspaceApplication != nil
            let themeRead = AgentThemeReading.effectOperations.contains(request.operation)
            let syntaxExport = request.operation == "syntaxes.export"
            let themeMutation = AgentThemeWriting.operationNames.contains(request.operation)
            let reviewedNative = AgentNativeSchemas.operationNames.contains(request.operation) && nativeExecution != nil && operationRegistry != nil
            guard reviewedAction || reviewedNative || (!humanApproval && (preferenceMutation || workspaceEffect || themeRead || themeMutation || syntaxExport)) else {
                throw AgentErrorCode.unavailable
            }
        }
        guard availableOperations.contains(request.operation) else { throw AgentErrorCode.unavailable }
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentOperationSchemas.validatedParameters(for: request, preferences: preferences) }
        catch { throw AgentErrorCode.invalidInput }
        return parameters
    }

    private func submitNative(_ request: AgentRequest, grant: AgentGrant, sessionID: UUID) throws -> AgentResponse.Outcome {
        guard let nativeExecution, let operationRegistry else { throw AgentErrorCode.unavailable }
        try validateSession(sessionID, grant: grant)
        _ = try AgentNativeExecution.plan(request, grant: grant)
        func outcome(_ snapshot: AgentOperationRegistry.Snapshot) throws -> AgentResponse.Outcome {
            if snapshot.state == .succeeded {
                guard case .object(let result) = snapshot.result else { throw AgentErrorCode.storageError }
                try AgentNativeSchemas.validateResult(result, for: request.operation)
                return .result(.object(result))
            }
            if snapshot.state.isTerminal { return .error(snapshot.error ?? .outcomeUnknown) }
            return .accepted(operationID: snapshot.id, state: snapshot.state)
        }
        if let id = try operationRegistry.existingRequest(request, grant: grant) {
            return try outcome(operationRegistry.snapshot(id, connectionID: grant.connectionID))
        }
        let id = try operationRegistry.startValueRequest(request, grant: grant) { [weak self] id in
            guard let self else { throw AgentOperationRegistry.FailureBeforeEffects(code: .cancelled) }
            return try await AgentNativeExecution.run(request, grant: grant, operationID: id, host: nativeExecution.makeHost(),
                approvals: nativeExecution.approvals, operations: operationRegistry,
                validateSession: { try self.validateSession(sessionID, grant: grant) })
        }
        return try outcome(operationRegistry.snapshot(id, connectionID: grant.connectionID))
    }

    private func submitDeletion(_ request: AgentRequest, grant: AgentGrant,
                                         sessionID: UUID) throws -> AgentResponse.Outcome {
        guard let operationRegistry, let deletionApprovals else { throw AgentErrorCode.unavailable }
        try validateSession(sessionID, grant: grant)
        let purge = request.operation == "drafts.purge"
        if purge && writes == nil { throw AgentErrorCode.unavailable }
        let receipt = try purge ? writes!.purgeReceipt(request, connectionID: grant.connectionID)
            : ["actions.delete", "actionGroups.delete"].contains(request.operation) ? actions.deletionReceipt(request, connectionID: grant.connectionID)
            : workspaces.deletionReceipt(request, connectionID: grant.connectionID)
        func outcome(_ snapshot: AgentOperationRegistry.Snapshot) throws -> AgentResponse.Outcome {
            if snapshot.state == .succeeded {
                guard case .object(let result) = snapshot.result else { throw AgentErrorCode.storageError }
                try AgentOperationSchemas.validateResult(result, for: request, preferences: preferences)
                return .result(.object(result))
            }
            if snapshot.state.isTerminal { return .error(snapshot.error ?? .outcomeUnknown) }
            return .accepted(operationID: snapshot.id, state: snapshot.state)
        }
        if let id = try operationRegistry.existingRequest(request, grant: grant) {
            var snapshot = try operationRegistry.snapshot(id, connectionID: grant.connectionID)
            if let receipt, snapshot.state == .outcomeUnknown {
                snapshot = try operationRegistry.recoverDeletion(request, grant: grant, receipt: receipt)
            }
            return try outcome(snapshot)
        }
        if receipt == nil {
            if purge { _ = try writes!.purgeEffects(request, connectionID: grant.connectionID) }
            else if ["actions.delete", "actionGroups.delete"].contains(request.operation) { _ = try actions.deletionEffects(request, connectionID: grant.connectionID) }
            else { _ = try workspaces.deletionEffects(request, connectionID: grant.connectionID) }
        }
        let id = try operationRegistry.startValueRequest(request, grant: grant) { [weak self] operationID in
            guard let self else { throw AgentOperationRegistry.FailureBeforeEffects(code: .cancelled) }
            if purge {
                guard let writes = self.writes else { throw AgentOperationRegistry.FailureBeforeEffects(code: .unavailable) }
                return try await writes.reviewAndPurge(request, connectionID: grant.connectionID,
                    operationID: operationID, approvals: deletionApprovals, operations: operationRegistry,
                    validateSession: { try self.validateSession(sessionID, grant: grant) })
            }
            if ["actions.delete", "actionGroups.delete"].contains(request.operation) {
                return try await self.actions.reviewAndDelete(request, connectionID: grant.connectionID,
                    operationID: operationID, approvals: deletionApprovals, operations: operationRegistry,
                    validateSession: { try self.validateSession(sessionID, grant: grant) })
            }
            return try await self.workspaces.reviewAndDelete(request, connectionID: grant.connectionID,
                operationID: operationID, approvals: deletionApprovals, operations: operationRegistry,
                validateSession: { try self.validateSession(sessionID, grant: grant) })
        }
        return try outcome(operationRegistry.snapshot(id, connectionID: grant.connectionID))
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

    private func readPreferences(_ parameters: [String: AgentJSONValue], grant: AgentGrant) throws -> [String: AgentJSONValue] {
        guard case .array(let items) = parameters["items"] else { throw AgentErrorCode.invalidInput }
        func version(_ value: AgentJSONValue) throws -> String {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return Data(HMAC<SHA256>.authenticationCode(for: try encoder.encode(value), using: preferenceVersionKey)).base64EncodedString()
        }
        let values: [AgentJSONValue] = try items.map { item in
            let address = try preferences.address(item)
            let reading: AgentPreferenceReading
            if AgentDevicePreferenceAccess.supportedIDs.contains(address.id) {
                reading = try AgentDevicePreferenceAccess.read(address: item, defaults: preferenceDefaults)
            } else if AgentListPreferenceAccess.supportedIDs.contains(address.id) {
                reading = try AgentListPreferenceAccess.read(address: item, defaults: preferenceDefaults)
            } else if ["application.launchAtLogin", SpotlightPreferences.enabledKey].contains(address.id) {
                guard let nativePreferenceRead else { throw AgentErrorCode.unavailable }
                reading = try nativePreferenceRead(address.id)
            } else if address.id.hasPrefix("syntax.") {
                guard grant.capabilities.contains(.appearanceRead) else { throw AgentErrorCode.permissionDenied }
                let syntax: SyntaxDefinition
                switch address.syntax {
                case .builtIn(let name): syntax = try ScriptSyntax.definition(name)
                case .installed(let id):
                    guard grant.scope.permits(.init(kind: .syntax, id: id)),
                          let installed = actionLibrary.syntaxes.first(where: { $0.id == id && $0.type != "builtIn" }) else {
                        throw AgentErrorCode.notFound
                    }
                    syntax = installed
                case nil: throw AgentErrorCode.invalidInput
                }
                let name = String(address.id.dropFirst("syntax.".count))
                let key = try AgentEncodedPreferenceAccess.syntaxStorageKey(name)
                let configuration = preferenceDefaults.object(forKey: key).map { $0 as? String ?? "null" } ?? "{}"
                let inherited: AgentJSONValue?
                if try preferences.field(address.id).defaultSource == .inherited {
                    let global = try AgentDevicePreferenceAccess.read(
                        address: .object(["id": .string("editor." + name)]), defaults: preferenceDefaults)
                    guard global.origin != "invalid" else { throw AgentErrorCode.invalidInput }
                    inherited = global.effectiveValue
                } else { inherited = nil }
                reading = try AgentEncodedPreferenceAccess.read(address: item, configuration: configuration,
                    syntax: syntax, inherited: inherited)
            } else if address.id == WorkspaceDefaults.key {
                reading = try AgentWorkspacePreferenceAccess.read(defaults: preferenceDefaults,
                    capabilities: grant.capabilities, scope: grant.scope,
                    workspaceExists: { id in actionLibrary.workspaces.contains { $0.id == id } })
            } else if address.id.hasPrefix("markdown.multi.") || address.id.hasPrefix("markdown.github.") || address.id == "commands.shortcut" {
                let key = address.id == "commands.shortcut" ? CommandShortcuts.storageKey :
                    address.id.hasPrefix("markdown.multi.") ? MarkdownPreferences.multiKey : MarkdownPreferences.githubKey
                let configuration: String
                if let stored = preferenceDefaults.object(forKey: key) { configuration = stored as? String ?? "null" }
                else { configuration = "{}" }
                reading = try AgentEncodedPreferenceAccess.read(address: item, configuration: configuration)
            } else { throw AgentErrorCode.unavailable }
            guard case .object(var fields) = item else { throw AgentErrorCode.invalidInput }
            fields["effectiveValue"] = reading.effectiveValue
            fields["valueOrigin"] = .string(reading.origin)
            fields["hasOverride"] = .bool(reading.hasOverride)
            fields["versionToken"] = .string(try version(.object(fields)))
            return .object(fields)
        }
        return ["items": .array(values), "versionToken": .string(try version(.array(values)))]
    }

    private func preferenceReceipt(_ request: AgentRequest, grant: AgentGrant) throws -> [String: AgentJSONValue] {
        let parameters = try AgentPreferenceSchemas.validatedParameters(for: request, registry: preferences)
        guard case .array(let items) = parameters["items"] else { throw AgentErrorCode.invalidInput }
        let addresses: [AgentJSONValue] = try items.map { item in
            guard case .object(var fields) = item else { throw AgentErrorCode.invalidInput }
            fields.removeValue(forKey: "value")
            return .object(fields)
        }
        let readings = try readPreferences(["items": .array(addresses)], grant: grant)
        guard case .array(let values) = readings["items"], let version = readings["versionToken"] else { throw AgentErrorCode.storageError }
        return ["items": .array(try values.map { item in
            guard case .object(var fields) = item else { throw AgentErrorCode.storageError }
            for key in ["effectiveValue", "valueOrigin", "hasOverride"] { fields.removeValue(forKey: key) }
            return .object(fields)
        }), "versionToken": version]
    }

    func actionExecutionSnapshot(_ request: AgentRequest, connectionID: UUID) throws -> [String: AgentJSONValue] {
        try validateAdmission()
        guard request.operation == "actions.run", let grant = try connections.grantForAuthenticatedConnection(connectionID) else {
            throw AgentErrorCode.permissionDenied
        }
        if case .denied(let error) = AgentPermissionPolicy.evaluate(request, connectionID: connectionID, grant: grant, now: now()) {
            throw error
        }
        guard let actionID = request.targets.first(where: { $0.kind == .action })?.id,
              let draftID = request.targets.first(where: { $0.kind == .draft })?.id,
              let action = actionLibrary.actions.first(where: { $0.id == actionID }),
              let stored = actionLibrary.notes.first(where: { $0.id == draftID }), let editorRegistry else {
            throw AgentErrorCode.notFound
        }
        let snapshot = try editorRegistry.snapshot(stored)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(snapshot.note) + encoder.encode(snapshot.storedNote) + Data(snapshot.generation.utf8)
        let draftVersion = Data(HMAC<SHA256>.authenticationCode(for: data, using: windowReadKey)).base64EncodedString()
        try validateAdmission()
        guard let current = try connections.grantForAuthenticatedConnection(connectionID),
              AgentRequestBinding.grantValue(current) == AgentRequestBinding.grantValue(grant) else {
            throw AgentErrorCode.permissionDenied
        }
        return ["actionVersion": .string(try actions.actionVersion(action)), "draftVersion": .string(draftVersion)]
    }

    private func validateSession(_ id: UUID, grant: AgentGrant) throws {
        let current = try authorize(Session(id: id))
        guard AgentRequestBinding.grantValue(current) == AgentRequestBinding.grantValue(grant) else {
            throw AgentErrorCode.permissionDenied
        }
    }

    private func dispatch(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant,
                          sessionID: UUID) throws -> [String: AgentJSONValue] {
        switch request.operation {
        case "bookmarks.list":
            return try bookmarks.read(request, parameters: parameters, sessionID: sessionID, grant: grant)
        case "backups.export", "backups.validate", "backups.previewRestore":
            return try backups.read(request, parameters: parameters, grant: grant,
                authorize: { try self.validateSession(sessionID, grant: grant) })
        case "transfers.beginImport", "transfers.appendChunk", "transfers.finishImport", "transfers.readChunk", "transfers.cancel":
            return try transfers.perform(request, parameters: parameters, grant: grant)
        case "exports.drafts":
            let data = try drafts.export(request, parameters: parameters, grant: grant)
            try validateSession(sessionID, grant: grant)
            let transfer = try transfers.export(data, resources: Set(request.targets), grant: grant)
            return ["transfer": transfer, "format": parameters["format"] ?? .string("draftly"),
                "draftIDs": .array(request.targets.map { .string($0.id.uuidString) })]
        case "themes.list", "themes.get", "themes.export", "themes.selection", "themes.exportBuiltIn":
            return try themes.read(request, parameters: parameters, grant: grant, sessionID: sessionID,
                authorize: { try self.validateSession(sessionID, grant: grant) })
        case "syntaxes.getBuiltIn":
            guard case .string(let name) = parameters["name"] else { throw AgentErrorCode.invalidInput }
            let source = try ScriptSyntax.definition(name).source
            let token = Data(HMAC<SHA256>.authenticationCode(for: Data(source.utf8), using: preferenceVersionKey)).base64EncodedString()
            return ["name": .string(name), "source": .string(source), "versionToken": .string(token)]
        case "syntaxes.exportBuiltIn":
            guard case .string(let name) = parameters["name"] else { throw AgentErrorCode.invalidInput }
            let source = try ScriptSyntax.definition(name).source
            let token = Data(HMAC<SHA256>.authenticationCode(for: Data(source.utf8), using: preferenceVersionKey)).base64EncodedString()
            let text: String
            switch parameters["format"] {
            case .string("installationURL"):
                var components = URLComponents(); components.scheme = "draftly"; components.host = "syntax"
                components.queryItems = [URLQueryItem(name: "name", value: name)]
                guard let url = components.string else { throw AgentErrorCode.storageError }
                text = url
            default: text = source
            }
            let chunk = try AgentDraftReading.chunk(text, parameters: parameters)
            return ["content": .object(chunk), "format": parameters["format"] ?? .string("source"),
                "name": .string(name), "versionToken": .string(token)]
        case "syntaxes.list":
            let syntaxes = actionLibrary.syntaxes.filter {
                $0.type != "builtIn" && grant.scope.permits(.init(kind: .syntax, id: $0.id))
            }
            let byID = Dictionary(syntaxes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var result = try pages.page(owner: .init(connectionID: grant.connectionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt,
                ids: { syntaxes.map(\.id) }, value: { id in
                    guard let syntax = byID[id] else { return nil }
                    let token = Data(HMAC<SHA256>.authenticationCode(for: Data(syntax.source.utf8), using: self.preferenceVersionKey)).base64EncodedString()
                    return .object(["id": .string(id.uuidString), "name": .string(syntax.name),
                        "type": .string(syntax.type), "versionToken": .string(token)])
                })
            result["builtInNames"] = .array(ScriptSyntax.names.map(AgentJSONValue.string))
            return result
        case "syntaxes.export":
            guard let id = request.targets.first?.id,
                  grant.scope.permits(.init(kind: .syntax, id: id)),
                  var syntax = actionLibrary.syntaxes.first(where: { $0.id == id && $0.type != "builtIn" }) else {
                throw AgentErrorCode.notFound
            }
            if syntax.type == "file" {
                guard grant.capabilities.contains(.filesRead) else { throw AgentErrorCode.permissionDenied }
                try validateSession(sessionID, grant: grant)
                do { syntax = try SyntaxFileAccess.read(syntax, defaults: preferenceDefaults, maximumBytes: AgentRequest.maximumBytes) }
                catch { throw AgentErrorCode.unavailable }
                try validateSession(sessionID, grant: grant)
            }
            let token = Data(HMAC<SHA256>.authenticationCode(for: Data(syntax.source.utf8), using: preferenceVersionKey)).base64EncodedString()
            let text: String
            if parameters["format"] == .string("installationURL") {
                var components = URLComponents(); components.scheme = "draftly"; components.host = "syntax"
                components.queryItems = [URLQueryItem(name: "data", value: syntax.source)]
                guard let url = components.string else { throw AgentErrorCode.storageError }
                text = url
            } else { text = syntax.source }
            try validateSession(sessionID, grant: grant)
            return ["resourceID": .string(id.uuidString), "format": parameters["format"] ?? .string("source"),
                "content": .object(try AgentDraftReading.chunk(text, parameters: parameters)), "versionToken": .string(token)]
        case "syntaxes.get":
            guard let id = request.targets.first?.id,
                  grant.scope.permits(.init(kind: .syntax, id: id)),
                  let syntax = actionLibrary.syntaxes.first(where: { $0.id == id && $0.type != "builtIn" }) else {
                throw AgentErrorCode.notFound
            }
            let token = Data(HMAC<SHA256>.authenticationCode(for: Data(syntax.source.utf8), using: preferenceVersionKey)).base64EncodedString()
            let definition = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(syntax))
            return ["definition": definition, "versionToken": .string(token)]
        case "actions.run":
            guard let submitAction, let operationRegistry else { throw AgentErrorCode.unavailable }
            if let id = try operationRegistry.existingRequest(request, grant: grant) {
                let snapshot = try operationRegistry.snapshot(id, connectionID: grant.connectionID)
                return ["operationID": .string(id.uuidString), "state": .string(snapshot.state.rawValue)]
            }
            guard let actionID = request.targets.first(where: { $0.kind == .action })?.id,
                  let draftID = request.targets.first(where: { $0.kind == .draft })?.id,
                  let action = actionLibrary.actions.first(where: { $0.id == actionID }),
                  actionLibrary.notes.contains(where: { $0.id == draftID }) else { throw AgentErrorCode.notFound }
            guard try actions.actionVersion(action) == request.expectedVersion else { throw AgentErrorCode.versionConflict }
            let id = try submitAction(request, grant)
            let snapshot = try operationRegistry.snapshot(id, connectionID: grant.connectionID)
            return ["operationID": .string(id.uuidString), "state": .string(snapshot.state.rawValue)]
        case "operations.get", "operations.cancel":
            guard let operationRegistry else { throw AgentErrorCode.unavailable }
            let result = try operationRegistry.control(request, connectionID: grant.connectionID)
            var values: [String: AgentJSONValue] = ["operation": try result.snapshot.wireValue()]
            if request.operation == "operations.cancel" { values["cancellationAccepted"] = .bool(result.cancellationAccepted) }
            return values
        case "workspaces.get":
            guard let id = request.targets.first?.id, grant.scope.permits(.init(kind: .workspace, id: id)),
                  let workspace = actionLibrary.workspaces.first(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
            let value = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(workspace))
            return ["workspace": value, "versionToken": .string(try workspaces.version(workspace))]
        case "workspaces.list":
            return try pages.page(owner: .init(connectionID: grant.connectionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt,
                ids: { self.actionLibrary.workspaces.filter { grant.scope.permits(.init(kind: .workspace, id: $0.id)) }.map(\.id) },
                value: { id in
                    guard grant.scope.permits(.init(kind: .workspace, id: id)),
                          let workspace = self.actionLibrary.workspaces.first(where: { $0.id == id }) else { return nil }
                    return .object(["id": .string(id.uuidString), "name": .string(workspace.name),
                        "order": workspace.order.map { .integer(Int64($0)) } ?? .null,
                        "versionToken": .string(try self.workspaces.version(workspace))])
                }, revision: grant.scope == .library ? { try self.workspaces.orderVersion() } : nil)
        case "activity.list":
            guard let readActivity else { throw AgentErrorCode.unavailable }
            let entries = try readActivity(grant.connectionID, grant.grantID).filter {
                $0.connectionID == grant.connectionID && $0.grantID == grant.grantID && $0.libraryID == libraryID
            }
            let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return try pages.page(owner: .init(connectionID: grant.connectionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt, ids: { entries.map(\.id) }, value: { id in
                    guard let entry = byID[id] else { return nil }
                    return .object(["id": .string(entry.id.uuidString), "requestID": .string(entry.requestID.uuidString),
                        "operation": .string(entry.operation), "date": .string(APIValues.date(entry.date)), "result": .string(entry.result)])
                })
        case "actions.validateShortcut", "actions.stepSchemas", "actionGroups.get", "actions.groups", "actions.get", "actions.list":
            return try actions.read(request, parameters: parameters, grant: grant, sessionID: sessionID)
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
            let input = try AgentMutationSchemas.mutation(from: parameters)
            let bound = AgentRequest(requestID: input.requestID, libraryID: input.libraryID ?? libraryID,
                operation: input.operation, targets: input.targets, expectedVersion: input.expectedVersion, parameters: input.parameters)
            guard availableOperations.contains(bound.operation) else { throw AgentErrorCode.unavailable }
            let ticket: AgentRetryKeys.Ticket
            if AgentThemeWriting.operationNames.contains(bound.operation) {
                ticket = try themeWrites.prepare(bound, grant: grant, authorize: { try self.validateSession(sessionID, grant: grant) })
            } else if AgentPreferenceWriting.operationNames.contains(bound.operation) {
                guard let preferenceWrites else { throw AgentErrorCode.unavailable }
                ticket = try preferenceWrites.prepare(bound, connectionID: grant.connectionID)
            } else if AgentEditorWriting.operationNames.contains(bound.operation) {
                guard let editorWrites else { throw AgentErrorCode.unavailable }
                ticket = try editorWrites.prepare(bound, connectionID: grant.connectionID)
            } else if AgentWorkspaceApplication.operationNames.contains(bound.operation) {
                guard let workspaceApplication else { throw AgentErrorCode.unavailable }
                ticket = try workspaceApplication.prepare(bound, connectionID: grant.connectionID) {
                    try self.validateSession(sessionID, grant: grant)
                }
            } else if bound.operation == "drafts.purge" {
                guard let writes, deletionApprovals != nil, operationRegistry != nil else { throw AgentErrorCode.unavailable }
                ticket = try writes.preparePurge(bound, connectionID: grant.connectionID)
            } else if ["actions.delete", "actionGroups.delete"].contains(bound.operation) {
                guard deletionApprovals != nil, operationRegistry != nil else { throw AgentErrorCode.unavailable }
                ticket = try actions.prepareDeletion(bound, connectionID: grant.connectionID)
            } else if bound.operation == "workspaces.delete" {
                guard deletionApprovals != nil, operationRegistry != nil else { throw AgentErrorCode.unavailable }
                ticket = try workspaces.prepareDeletion(bound, connectionID: grant.connectionID)
            } else if AgentWorkspaceAccess.operationNames.contains(bound.operation) { ticket = try workspaces.prepare(bound, connectionID: grant.connectionID) }
            else if ["actions.create", "actions.update", "actions.duplicate", "actions.move", "actions.reorder", "actionGroups.create", "actionGroups.update", "actionGroups.duplicate", "actionGroups.reorder"].contains(bound.operation) { ticket = try actions.prepareActionUpdate(bound, connectionID: grant.connectionID) }
            else {
                guard let writes else { throw AgentErrorCode.unavailable }
                ticket = try writes.prepare(bound, connectionID: grant.connectionID) {
                    try self.validateSession(sessionID, grant: grant)
                }
            }
            return ["requestID": .string(bound.requestID.uuidString), "retryKey": .string(ticket.value),
                "expiresAt": .string(APIValues.date(min(ticket.expiresAt, grant.expiresAt)))]
        case "themes.create", "themes.update", "themes.duplicate":
            let receipt = try themeWrites.update(request, grant: grant, authorize: { try self.validateSession(sessionID, grant: grant) })
            guard let resource = receipt.resources.first else { throw AgentErrorCode.storageError }
            return ["resource": .object(["id": .string(resource.id.uuidString), "versionToken": .string(resource.versionToken)])]
        case "actionGroups.reorder", "actions.reorder":
            let receipt = try actions.updateAction(request, connectionID: grant.connectionID)
            return ["resources": .array(receipt.resources.map { .object(["id": .string($0.id.uuidString), "versionToken": .string($0.versionToken)]) })]
        case "workspaces.apply":
            guard let workspaceApplication else { throw AgentErrorCode.unavailable }
            return try workspaceApplication.apply(request, connectionID: grant.connectionID) {
                try self.validateSession(sessionID, grant: grant)
            }
        case "workspaces.reorder":
            let receipt = try workspaces.update(request, connectionID: grant.connectionID)
            return ["resources": .array(receipt.resources.map { .object([
                "id": .string($0.id.uuidString), "versionToken": .string($0.versionToken)]) })]
        case "workspaces.create", "workspaces.update", "workspaces.duplicate":
            let receipt = try workspaces.update(request, connectionID: grant.connectionID)
            guard let resource = receipt.resources.first else { throw AgentErrorCode.storageError }
            return ["resource": .object(["id": .string(resource.id.uuidString), "versionToken": .string(resource.versionToken)])]
        case "actions.create", "actions.update", "actions.duplicate", "actions.move", "actionGroups.create", "actionGroups.update", "actionGroups.duplicate":
            let receipt = try actions.updateAction(request, connectionID: grant.connectionID)
            guard let resource = receipt.resources.first else { throw AgentErrorCode.storageError }
            return ["resource": .object(["id": .string(resource.id.uuidString), "versionToken": .string(resource.versionToken)])]
        case "drafts.merge":
            guard let writes else { throw AgentErrorCode.unavailable }
            let receipt = try writes.update(request, connectionID: grant.connectionID) {
                try self.validateSession(sessionID, grant: grant)
            }
            let ids = Set(request.targets.map(\.id))
            guard let merged = receipt.resources.first(where: { !ids.contains($0.id) }) else { throw AgentErrorCode.storageError }
            func value(_ resource: LibraryMutationReceipt.Resource) -> AgentJSONValue {
                .object(["id": .string(resource.id.uuidString), "versionToken": .string(resource.versionToken)])
            }
            return ["resource": value(merged), "originals": .array(receipt.resources.filter { ids.contains($0.id) }.map(value))]
        case "drafts.archive", "drafts.trash", "drafts.restore", "drafts.flag", "drafts.tags", "drafts.syntax":
            guard let writes else { throw AgentErrorCode.unavailable }
            let receipt = try writes.update(request, connectionID: grant.connectionID) {
                try self.validateSession(sessionID, grant: grant)
            }
            return ["resources": .array(receipt.resources.map { .object(["id": .string($0.id.uuidString),
                "versionToken": .string($0.versionToken)]) })]
        case "drafts.create", "drafts.update", "drafts.patch", "drafts.duplicate", "drafts.restoreVersion":
            guard let writes else { throw AgentErrorCode.unavailable }
            let receipt = try writes.update(request, connectionID: grant.connectionID) {
                try self.validateSession(sessionID, grant: grant)
            }
            guard let resource = receipt.resources.first else { throw AgentErrorCode.storageError }
            return ["resource": .object(["id": .string(resource.id.uuidString), "versionToken": .string(resource.versionToken)])]
        case "editor.setSelection", "editor.replaceRange", "editor.undo", "editor.redo", "editor.tasks", "editor.replaceAll":
            guard let editorWrites else { throw AgentErrorCode.unavailable }
            return try editorWrites.update(request, connectionID: grant.connectionID)
        case "preferences.get":
            return try readPreferences(parameters, grant: grant)
        case "preferences.update", "preferences.reset":
            guard let preferenceWrites else { throw AgentErrorCode.unavailable }
            return try preferenceWrites.update(request, connectionID: grant.connectionID)
        case "preferences.schema":
            let selected: Set<String>?
            if case .array(let ids) = parameters["ids"] {
                selected = Set(ids.compactMap { if case .string(let id) = $0 { return id }; return nil })
            } else { selected = nil }
            return try pages.page(owner: .init(connectionID: grant.connectionID, grantID: grant.grantID), request: request,
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
                    "resultSchema": schema?.result.jsonSchema ?? .null, "available": .bool(availableOperations.contains(name) && (name != AgentMutationSchemas.name || !grant.capabilities.isDisjoint(with: [.draftsWrite, .actionsManage, .workspacesManage, .workspacesApply, .preferencesWrite])))])
            })]
        default: return try drafts.read(request, parameters: parameters, grant: grant, sessionID: sessionID)
        }
    }
    private func editorContext(_ id: UUID, grant: AgentGrant) throws -> AgentEditorWriting.Context {
        guard let editorRegistry,
              let snapshot = try editorRegistry.windowSnapshots().first(where: { $0.id == id }),
              grant.scope.permits(.init(kind: .window, id: id)),
              let draft = snapshot.draftID, grant.scope.permits(.init(kind: .draft, id: draft)),
              actionLibrary.notes.contains(where: { $0.id == draft }),
              case .string(let version) = try editorValues(snapshot)["versionToken"] else { throw AgentErrorCode.notFound }
        return .init(snapshot: snapshot, version: version)
    }

    private func editorValues(_ snapshot: AgentEditorRegistry.WindowSnapshot) throws -> [String: AgentJSONValue] {
        let selection: AgentJSONValue = .object(["offset": .integer(Int64(snapshot.selection.location)),
            "length": .integer(Int64(snapshot.selection.length))])
        let syntax = try? editorRegistry?.syntaxDefinition(windowID: snapshot.id)
        let syntaxIdentity = syntax.map { $0.name + "\u{0}" + $0.source + "\u{0}" + $0.featureState }
        let state: AgentJSONValue = .object(["syntaxVersion": syntaxIdentity.map { .string($0) } ?? .null,
            "windowID": .string(snapshot.id.uuidString), "generation": .string(snapshot.generation.uuidString),
            "draftID": snapshot.draftID.map { .string($0.uuidString) } ?? .null,
            "content": .string(snapshot.content), "selection": selection, "dirty": .bool(snapshot.dirty)])
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let token = Data(HMAC<SHA256>.authenticationCode(for: try encoder.encode(state), using: windowReadKey)).base64EncodedString()
        return ["windowID": .string(snapshot.id.uuidString),
            "draftID": snapshot.draftID.map { .string($0.uuidString) } ?? .null,
            "versionToken": .string(token)]
    }

    private func readEditor(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant,
                            sessionID: UUID) throws -> [String: AgentJSONValue] {
        guard let editorRegistry else { throw AgentErrorCode.unavailable }
        func authorized(_ snapshot: AgentEditorRegistry.WindowSnapshot) -> Bool {
            guard grant.scope.permits(.init(kind: .window, id: snapshot.id)) else { return false }
            return snapshot.draftID.map { grant.scope.permits(.init(kind: .draft, id: $0)) } ?? true
        }
        if request.operation == "editor.windows" {
            return try pages.page(owner: .init(connectionID: grant.connectionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt, ids: {
                    try editorRegistry.windowSnapshots().filter(authorized).map(\.id)
                }, value: { id in
                    guard let snapshot = try editorRegistry.windowSnapshots().first(where: { $0.id == id }), authorized(snapshot) else { return nil }
                    var result = try editorValues(snapshot)
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
        var result = try editorValues(snapshot)
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
            let page = try pages.page(owner: .init(connectionID: grant.connectionID, grantID: grant.grantID), request: request,
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
