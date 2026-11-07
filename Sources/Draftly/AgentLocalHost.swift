import Foundation
import DraftlyCore
import AgentContracts
import AgentLocalSecurity

// One loaded library, authority registry and transport lifetime. Normal startup
// must still provide editor/lock adapters and a provisioned signed helper.
@MainActor final class AgentLocalHost {
    let libraryID: UUID
    let connections: AgentConnectionRegistry
    let pairing: AgentPairingCoordinator
    let approvals: AgentApprovalStore
    let operations: AgentOperationRegistry
    let service: AgentCommandService
    private let library: LibraryStore
    private let editors: AgentEditorRegistry?
    private let preferenceDefaults: UserDefaults
    private let lease: AgentHostLease
    private let publications: AgentHostPublications
    private let activity: AgentActivityStore
    private(set) var activityRecordingError: AgentErrorCode?
    private var pendingActivity: [AgentActivityStore.Entry] = []
    private var activityFlushScheduled = false
    var locatorCleanupError: AgentErrorCode? { publications.cleanupError }
    private let socketParentDirectory: URL
    private let validateApplication: () throws -> Void
    private let validateHelper: @Sendable (Data) throws -> Void
    private let isLocked: () -> Bool
    private let resolveTargets: (Set<AgentResourceReference>) throws -> Set<AgentResourceReference>
    private let readCredential: (UUID) throws -> Data?
    private final class WeakChatSession {
        weak var value: AgentChatToolSession?
        init(_ value: AgentChatToolSession) { self.value = value }
    }
    private var chatSessions: [UUID: WeakChatSession] = [:]
    private var broker: AgentSocketBroker?
    private var closed = false

    var endpoint: String? { broker?.path }

    func recentActivity() throws -> [AgentActivityStore.Entry] {
        try validateOwnership()
        return try activity.entries(libraryID: libraryID)
    }

    func clearActivity() throws {
        try validateOwnership()
        try activity.clear(libraryID: libraryID)
        pendingActivity.removeAll()
        activityRecordingError = nil
    }

    init(library: LibraryStore, appVersion: String,
         editors: AgentEditorRegistry? = nil,
         enableReviewedActions: Bool = false,
         nativeHost: (@MainActor () -> any ActionHost)? = nil,
         enableReviewedMutations: Bool = false,
         nativePreferenceRead: ((String) throws -> AgentPreferenceReading)? = nil,
         preferenceDefaults: UserDefaults = .standard,
         preferenceStorage: AgentPreferenceStorage? = nil,
         isLocked: @escaping () -> Bool,
         pendingEditorGeneration: @escaping (UUID) -> String,
         resolveTargets: @escaping (Set<AgentResourceReference>) throws -> Set<AgentResourceReference>,
         socketParentDirectory: URL = FileManager.default.temporaryDirectory,
         credentials: AgentConnectionRegistry.CredentialAccess? = nil,
         validateApplication: @escaping () throws -> Void = { try AgentCredentialIdentity.validateCurrentProcess(.application) },
         validateHelper: @escaping @Sendable (Data) throws -> Void = { try AgentPeerIdentity.validate($0, role: .helper) }) throws {
        // Reject unprovisioned application builds before creating local state.
        try validateApplication()
        guard editors?.isBound(to: library) ?? true else { throw AgentErrorCode.invalidInput }
        let lease = try AgentHostLease(location: AgentLibraryLocation(library: library))
        let file: AgentConnectionFile
        let locator: AgentHostLocator
        let activity: AgentActivityStore
        let journal: AgentOperationJournal?
        do {
            let parent = lease.location.url.deletingLastPathComponent()
            file = try AgentConnectionFile(parentDirectory: parent)
            locator = try AgentHostLocator(parentDirectory: parent)
            activity = try AgentActivityStore(parentDirectory: parent)
            journal = (enableReviewedActions || enableReviewedMutations) ? try AgentOperationJournal(parentDirectory: parent) : nil
            _ = try locator.endpoints()
        }
        catch { lease.close(); throw error }
        weak var owner: AgentLocalHost?
        let validateOwner: () throws -> Void = {
            guard let owner else { throw AgentErrorCode.cancelled }
            try owner.validateOwnership()
        }
        let credentialAccess = credentials ?? AgentCredentialKeychain(role: .application).registryAccess
        self.readCredential = credentialAccess.read
        let registry = AgentConnectionRegistry(metadata: .init(read: {
            try validateOwner(); return try file.read()
        }, replace: { data, expected in
            try validateOwner(); try file.replace(data, expected: expected)
        }), credentials: credentialAccess,
            authorityChanged: { id in owner?.authorityChanged(id) })
        self.lease = lease; self.publications = AgentHostPublications(locator: locator); libraryID = lease.libraryID; connections = registry
        self.library = library; self.editors = editors; self.preferenceDefaults = preferenceDefaults
        self.activity = activity
        self.socketParentDirectory = socketParentDirectory
        self.validateApplication = validateApplication; self.validateHelper = validateHelper
        self.isLocked = isLocked; self.resolveTargets = resolveTargets
        approvals = AgentApprovalStore(currentGrant: { id in
            try? registry.grantForAuthenticatedConnection(id)
        }, isLocked: isLocked)
        operations = AgentOperationRegistry(currentGrant: { id in
            try registry.grantForAuthenticatedConnection(id)
        }, validateHost: validateOwner, isLocked: isLocked, journal: journal)
        let nativeEnvironment: AgentNativeExecution.Environment?
        if enableReviewedActions, let nativeHost {
            nativeEnvironment = .init(makeHost: nativeHost, approvals: approvals)
        } else { nativeEnvironment = nil }
        do {
            service = try AgentCommandService(library: library, libraryID: lease.libraryID, connections: registry,
                appVersion: appVersion, preferenceDefaults: preferenceDefaults, preferenceStorage: preferenceStorage,
                nativePreferenceRead: nativePreferenceRead, validateHost: validateOwner, isLocked: isLocked,
                editors: editors,
                pendingEditorGeneration: pendingEditorGeneration,
                recordActivity: { connectionID, grantID, requestID, operation, result in
                    guard let owner else { return }
                    owner.enqueueActivity(.init(id: UUID(), libraryID: owner.libraryID, connectionID: connectionID,
                                                grantID: grantID, requestID: requestID, operation: operation,
                                                date: Date(), result: result))
                }, readActivity: { connectionID, grantID in
                    guard let owner else { throw AgentErrorCode.cancelled }
                    try owner.validateOwnership()
                    return try activity.entries(libraryID: owner.libraryID, inRecordingOrder: true).filter { $0.connectionID == connectionID && $0.grantID == grantID }
                }, operations: operations, submitAction: enableReviewedActions ? { request, grant in
                    guard let owner else { throw AgentErrorCode.cancelled }
                    return try owner.submitReviewedAction(request, grant: grant)
                } : nil, deletionApprovals: enableReviewedMutations ? approvals : nil,
                nativeExecution: nativeEnvironment, saveRestoreRecovery: enableReviewedMutations ? { id, data in
                    try validateOwner()
                    let directory = try AgentStateDirectory(parentDirectory: lease.location.url.deletingLastPathComponent())
                    try directory.saveRestoreRecovery(id, data: data)
                } : nil)
        } catch { lease.close(); throw error }
        pairing = AgentPairingCoordinator(registry: registry, libraryID: lease.libraryID,
            validateHost: validateOwner, isLocked: isLocked, resolveTargets: resolveTargets)
        owner = self
        do { _ = try registry.migrateLibraryAccess(capabilities: service.availableCapabilities) }
        catch { close(); throw error }
    }

    // Explicit close is the normal shutdown path. This is a fallback for a
    // discarded host; it preserves the same ordering on MainActor.
    isolated deinit { close() }

    private func submitReviewedAction(_ request: AgentRequest, grant: AgentGrant) throws -> UUID {
        try validateOwnership()
        guard let editors, case .string(let rawWindow) = request.parameters["windowID"],
              let windowID = UUID(uuidString: rawWindow),
              let draftID = request.targets.first(where: { $0.kind == .draft })?.id,
              let actionID = request.targets.first(where: { $0.kind == .action })?.id,
              let action = library.actions.first(where: { $0.id == actionID }) else { throw AgentErrorCode.interactionRequired }
        guard grant.capabilities.isSuperset(of: [.draftsWrite, .editorWrite]),
              grant.scope.permits(.init(kind: .window, id: windowID)) else { throw AgentErrorCode.permissionDenied }
        let models = try editors.executionModels(draftID: draftID, windowID: windowID)
        guard let model = models.first else { throw AgentErrorCode.notFound }
        let approved = library.actions.filter { grant.scope.permits(.init(kind: .action, id: $0.id)) }
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { [weak self] in
            guard let self else { throw AgentErrorCode.cancelled }
            return try self.connections.grantForAuthenticatedConnection(grant.connectionID)
        }, validateHost: { [weak self, weak model] in
            guard let self, let model else { throw AgentErrorCode.cancelled }
            try self.validateOwnership()
            guard try editors.executionModels(draftID: draftID, windowID: windowID).first === model else {
                throw AgentErrorCode.notFound
            }
        }, isLocked: isLocked, draftExists: { [weak self] id in self?.library.notes.contains { $0.id == id } == true },
            targetDraftID: draftID, editorDraftID: { [weak model] in model?.editor.noteID }, windowID: windowID,
            approvedActions: Dictionary(uniqueKeysWithValues: approved.map { ($0.id, $0) }),
            currentAction: { [weak self] id in self?.library.actions.first { $0.id == id } }, reviewedNativeEffects: true)
        return try operations.startRequest(request, grant: grant) { [self] id in
            let answerablePrompt: AgentAuthorizedActionHost.AnswerablePrompt? =
                request.parameters["promptMode"] == .string("agent") ? { stepID, payload in
                    try await self.operations.waitForPrompt(id, stepID: stepID, payload: payload)
                } : nil
            return try await AgentReviewedActionExecution.run(action: action, draftID: draftID, request: request,
                connectionID: grant.connectionID, library: library, models: models, host: model.host,
                authority: authority, approvals: approvals,
                currentSnapshot: { try self.service.actionExecutionSnapshot(request, connectionID: grant.connectionID) },
                waitingForUser: { try self.operations.setWaitingForUser(id, waiting: $0) },
                recordEffect: { effectID, kind, outcome in
                    try self.operations.recordEffect(id, effectID: effectID, kind: kind, outcome: outcome)
                },
                answerablePrompt: answerablePrompt, resolveModel: { models, _ in models.first })
        }
    }

    func isBound(to library: LibraryStore, editors: AgentEditorRegistry) -> Bool {
        !closed && self.library === library && self.editors === editors && editors.isBound(to: library)
    }

    func makeChatToolsFromUserInterface(capabilities: Set<AgentCapability>, targets: Set<AgentResourceReference>,
                                       providerName: String = "ChatGPT", wholeLibrary: Bool = false,
                                       onRevocationError: @escaping @MainActor (Error) -> Void,
                                       validateContext: @escaping @MainActor () throws -> Void = {}) throws -> AgentChatToolSession {
        try requireReady()
        guard broker != nil, try service.permitsTransportStart(), (wholeLibrary || !targets.isEmpty),
              try (wholeLibrary || resolveTargets(targets) == targets) else { throw AgentErrorCode.permissionDenied }
        let permitted: Set<AgentCapability> = [.draftsRead, .draftsWrite, .editorRead, .editorWrite]
        guard capabilities.isSubset(of: wholeLibrary ? service.availableCapabilities : permitted) else { throw AgentErrorCode.invalidInput }
        let record = try connections.connectFromUserInterface(name: "Draftly Chat · " + String(providerName.prefix(80)), libraryID: libraryID,
            capabilities: capabilities, scope: wholeLibrary ? .library : .resources(targets), expiresAt: Date().addingTimeInterval(900))
        do {
            guard let credential = try readCredential(record.id) else { throw AgentErrorCode.permissionDenied }
            let authenticated = try service.authenticate(connectionID: record.id, credential: credential, expectedLibraryID: libraryID)
            let drafts = targets.filter { $0.kind == .draft }
            let tools = AgentChatToolSession(service: service, session: authenticated,
                currentDraftID: drafts.count == 1 ? drafts.first?.id : nil, onDisconnect: { [weak self] in
                guard let self else { return }
                do {
                    _ = try self.connections.revokeFromUserInterface(record.id)
                    try self.connections.forgetRevokedFromUserInterface(record.id)
                }
                catch { onRevocationError(error) }
            }, validateContext: validateContext)
            tools.expiresAt = record.expiresAt
            tools.followsDraftSelection = wholeLibrary
            chatSessions[record.id] = WeakChatSession(tools)
            return tools
        } catch {
            do { _ = try connections.revokeFromUserInterface(record.id) }
            catch { onRevocationError(error) }
            throw error
        }
    }

    func close() {
        guard !closed else { publications.withdraw(); return }
        suspend()
        flushActivity()
        closed = true
        lease.close()
    }

    private func enqueueActivity(_ entry: AgentActivityStore.Entry) {
        guard pendingActivity.count < 1024 else { activityRecordingError = .busy; return }
        pendingActivity.append(entry)
        guard !activityFlushScheduled else { return }
        activityFlushScheduled = true
        Task { @MainActor [weak self] in self?.flushActivity() }
    }

    private func flushActivity() {
        activityFlushScheduled = false
        let entries = pendingActivity
        pendingActivity.removeAll()
        guard !entries.isEmpty else { return }
        do {
            try validateOwnership()
            try activity.append(entries)
        } catch { activityRecordingError = (error as? AgentErrorCode) ?? .storageError }
    }

    func suspend() {
        let chats = chatSessions.values.compactMap(\.value)
        chats.forEach { $0.invalidate() }
        chatSessions.removeAll()
        broker?.stop(); broker = nil
        service.invalidateAll(); pairing.invalidatePending()
        approvals.invalidateForScreenLock()
        operations.cancelAll()
        publications.withdraw()
    }

    // Reopen only by an explicit lifecycle command. Construction never listens.
    func resumeIfEnabled() throws {
        do {
            try requireReady()
            guard try connections.permitsTransportStart() else { suspend(); return }
            guard broker == nil else { return }
            let candidate = try AgentSocketBroker(service: service, parentDirectory: socketParentDirectory,
                pairing: pairing, validateHelper: validateHelper)
            let entry = try AgentHostLocator.Endpoint(libraryID: libraryID, socketPath: candidate.path)
            do {
                try validateOwnership()
                try publications.publish(entry)
                try validateOwnership()
                publications.finishPublication(entry)
                broker = candidate
            } catch {
                candidate.stop()
                publications.withdraw()
                throw error
            }
        } catch {
            if (error as? AgentErrorCode) != .busy { suspend() }
            throw error
        }
    }

    func setEnabledFromUserInterface(_ enabled: Bool) throws {
        if !enabled {
            suspend()
            try connections.setEnabledFromUserInterface(false)
            return
        }
        try requireReady()
        let previouslyEnabled = try connections.configurationForUserInterface().enabled
        try connections.setEnabledFromUserInterface(true)
        do { try resumeIfEnabled() }
        catch {
            let failure = error
            suspend()
            if !previouslyEnabled {
                do { try connections.setEnabledFromUserInterface(false) }
                catch { throw AgentErrorCode.outcomeUnknown }
            }
            throw failure
        }
    }

    func makeSettingsModel(choices: @escaping () -> [AgentConnectionsSettingsModel.ResourceChoice],
                           initialTargets: @escaping () -> Set<AgentResourceReference> = { [] }) throws -> AgentConnectionsSettingsModel {
        try validateOwnership()
        return try AgentConnectionsSettingsModel(libraryID: libraryID, registry: connections, pairing: pairing,
            choices: choices, initialTargets: initialTargets, resolveTargets: resolveTargets,
            setAccessEnabled: { [weak self] enabled in
                guard let self else { throw AgentErrorCode.cancelled }
                try self.setEnabledFromUserInterface(enabled)
            }, isAccessActive: { [weak self] in self?.endpoint != nil },
            pairingCommand: Self.pairingCommand(libraryID: libraryID,
                stateDirectory: lease.location.url.deletingLastPathComponent(), bundleURL: Bundle.main.bundleURL),
            availableCapabilities: service.availableCapabilities,
            makeMCPConfiguration: { [weak self] connectionID in
                guard let self else { return nil }
                return Self.mcpConfiguration(connectionID: connectionID, libraryID: self.libraryID,
                    stateDirectory: self.lease.location.url.deletingLastPathComponent(), bundleURL: Bundle.main.bundleURL)
            }, readActivity: { [weak self] in
                guard let self else { throw AgentErrorCode.cancelled }
                return try self.recentActivity()
            }, eraseActivity: { [weak self] in
                guard let self else { throw AgentErrorCode.cancelled }
                try self.clearActivity()
            }, activityRecordingError: { [weak self] in self?.activityRecordingError },
            pendingReviews: { [weak self] in
                guard let self else { throw AgentErrorCode.cancelled }
                try self.validateOwnership()
                return self.approvals.pendingFromUserInterface()
            }, decideReview: { [weak self] review, approved in
                guard let self else { throw AgentErrorCode.cancelled }
                try self.validateOwnership()
                guard self.endpoint != nil else { throw AgentErrorCode.permissionDenied }
                if approved { try self.approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint) }
                else { try self.approvals.denyFromUserInterface(review.id) }
            })
    }

    static func pairingCommand(libraryID: UUID, stateDirectory: URL, bundleURL: URL) -> String? {
        let helper = bundleURL.appendingPathComponent("Contents/Helpers/DraftlyAgent.app/Contents/MacOS/draftly-agent")
        guard stateDirectory.isFileURL, helper.isFileURL, FileManager.default.isExecutableFile(atPath: helper.path) else { return nil }
        func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return quoted(helper.path) + " connect --name 'Local agent' --library " + libraryID.uuidString
            + " --state-parent " + quoted(stateDirectory.path)
    }

    static func mcpConfiguration(connectionID: UUID, libraryID: UUID, stateDirectory: URL, bundleURL: URL) -> String? {
        let helper = bundleURL.appendingPathComponent("Contents/Helpers/DraftlyAgent.app/Contents/MacOS/draftly-agent")
        guard stateDirectory.isFileURL, helper.isFileURL, FileManager.default.isExecutableFile(atPath: helper.path),
              let configuration = try? AgentClientConfiguration(helperPath: helper.path, connectionID: connectionID,
                  libraryID: libraryID, stateParent: stateDirectory.path),
              let data = try? configuration.encoded() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func makeDraftSettingsModel() throws -> AgentConnectionsSettingsModel {
        let resources = AgentDraftResourceChoices(library: library)
        return try makeSettingsModel(choices: { resources.choices() })
    }

    func makeLibrarySettingsModel() throws -> AgentConnectionsSettingsModel {
        let resources = AgentLibraryResourceChoices(library: library, editors: editors, bookmarkDefaults: preferenceDefaults)
        let model = try makeSettingsModel(choices: { resources.choices() })
        model.pagedChoices = { resources.page(search: $0, offset: $1, limit: $2) }
        return model
    }

    private func requireReady() throws {
        do {
            try validateOwnership()
            guard !isLocked() else { throw AgentErrorCode.permissionDenied }
            try validateApplication()
        } catch {
            if (error as? AgentErrorCode) != .busy { suspend() }
            throw error
        }
    }

    private func validateOwnership() throws {
        guard !closed else { throw AgentErrorCode.cancelled }
        do { try lease.validate() }
        catch {
            if (error as? AgentErrorCode) != .busy { suspend() }
            throw error
        }
    }

    private func authorityChanged(_ id: UUID) {
        chatSessions.removeValue(forKey: id)?.value?.invalidate(revoke: false)
        service.invalidate(connectionID: id)
        pairing.invalidatePending()
        approvals.invalidateConnection(id)
        operations.cancelConnection(id)
    }
}
