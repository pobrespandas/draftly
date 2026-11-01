import Foundation
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
    static let implementedOperations: Set<String> = ["server.status", "server.capabilities", "server.schemas",
        "library.summary", "drafts.list", "drafts.search", "drafts.get", "drafts.versions", "preferences.schema"]
    private let libraryID: UUID
    private let connections: AgentConnectionRegistry
    private let validateHost: () throws -> Void
    private let isLocked: () -> Bool
    private let now: () -> Date
    private let appVersion: String
    private let preferences: AgentPreferenceRegistry
    private let pages: AgentReadPages
    private let preferenceDescriptorIDs: [UUID]
    private let preferenceDescriptors: [UUID: AgentPreferenceField]
    private let drafts: AgentDraftReading
    private var sessions: [UUID: Authorization] = [:]

    init(library: LibraryStore, libraryID: UUID, connections: AgentConnectionRegistry, appVersion: String,
         validateHost: @escaping () throws -> Void, isLocked: @escaping () -> Bool, now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         editors: AgentEditorRegistry? = nil,
         pendingEditorGeneration: @escaping (UUID) -> String) throws {
        guard editors?.isBound(to: library) ?? true else { throw AgentErrorCode.invalidInput }
        self.libraryID = libraryID; self.connections = connections; self.appVersion = appVersion
        self.validateHost = validateHost
        self.isLocked = isLocked; self.now = now
        let preferences = try AgentPreferenceCatalog.make()
        self.preferences = preferences
        let descriptors = preferences.fields.map { (UUID(), $0) }
        preferenceDescriptorIDs = descriptors.map { $0.0 }
        preferenceDescriptors = Dictionary(uniqueKeysWithValues: descriptors)
        let pages = AgentReadPages(now: now, uptime: uptime)
        self.pages = pages
        drafts = AgentDraftReading(library: library, pages: pages, editors: editors, pendingEditorGeneration: pendingEditorGeneration)
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
        do {
            let grant = try authorize(session)
            switch AgentPermissionPolicy.evaluate(request, connectionID: grant.connectionID, grant: grant, now: now()) {
            case .permitted: break
            case .denied(let error): throw error
            case .needsHumanApproval, .needsEffectAuthorization: throw AgentErrorCode.unavailable
            }
            guard Self.implementedOperations.contains(request.operation) else { throw AgentErrorCode.unavailable }
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
            return encoded
        } catch let error as AgentErrorCode {
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
            if (error as? AgentErrorCode) != .busy { invalidateAll() }
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

    private func dispatch(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant,
                          sessionID: UUID) throws -> [String: AgentJSONValue] {
        switch request.operation {
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
                    "resultSchema": schema?.result.jsonSchema ?? .null, "available": .bool(Self.implementedOperations.contains(name))])
            })]
        default: return try drafts.read(request, parameters: parameters, grant: grant, sessionID: sessionID)
        }
    }
}
