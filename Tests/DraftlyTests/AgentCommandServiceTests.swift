import Foundation
import Testing
import AgentContracts
@testable import DraftlyCore
@testable import Draftly

@Suite("Authenticated agent reads") @MainActor
struct AgentCommandServiceTests {
    @MainActor private final class Fixture {
        let library: LibraryStore
        let libraryID = UUID()
        var bytes: Data?
        var secrets: [UUID: Data] = [:]
        var wall = Date(timeIntervalSince1970: 1_700_000_000)
        var uptime: TimeInterval = 100
        var locked = false
        var generation = ""
        var onGeneration: (() -> Void)?
        lazy var connections = AgentConnectionRegistry(metadata: .init(read: { [unowned self] in self.bytes },
            replace: { [unowned self] data, expected in
                guard self.bytes == expected else { throw AgentErrorCode.versionConflict }
                self.bytes = data
            }), credentials: .init(read: { [unowned self] in self.secrets[$0] },
                create: { [unowned self] in self.secrets[$0] = $1 },
                remove: { [unowned self] in self.secrets.removeValue(forKey: $0) }),
            now: { [unowned self] in self.wall }, authorityChanged: { _ in })
        var service: AgentCommandService!

        init() throws {
            library = try LibraryStore(inMemory: true, seed: false)
            service = try makeService()
            try connections.setEnabledFromUserInterface(true)
        }
        func makeService() throws -> AgentCommandService {
            try AgentCommandService(library: library, libraryID: libraryID, connections: connections,
                appVersion: "QA", isLocked: { [unowned self] in self.locked }, now: { [unowned self] in self.wall },
                uptime: { [unowned self] in self.uptime }, pendingEditorGeneration: { [unowned self] _ in
                    self.onGeneration?(); return self.generation
                })
        }
        func connect(scope: AgentResourceScope = .library, capabilities: Set<AgentCapability> = [.draftsRead]) throws
            -> (AgentConnectionRecord, AgentCommandService.Session) {
            let record = try connections.connectFromUserInterface(name: "Neutral QA", libraryID: libraryID,
                capabilities: capabilities, scope: scope)
            return (record, try service.authenticate(connectionID: record.id, credential: #require(secrets[record.id])))
        }
        func note(_ content: String, tags: [String] = [], archived: Bool = false, trashed: Bool = false,
                  accessed: Date? = nil) throws -> Note {
            let value = Note(content: content, tags: tags, isArchived: archived, trashedAt: trashed ? wall : nil,
                             createdAt: wall, modifiedAt: wall, accessedAt: accessed)
            try library.saveNote(value, preserveRevision: false, preserveDates: true)
            return value
        }
        func response(_ operation: String, session: AgentCommandService.Session,
                      targets: [AgentResourceReference] = [], parameters: [String: AgentJSONValue] = [:],
                      libraryID: UUID? = nil) throws -> AgentResponse {
            let request = AgentRequest(requestID: UUID(), libraryID: libraryID ?? self.libraryID, operation: operation,
                targets: targets, parameters: parameters)
            let data = try service.respond(to: JSONEncoder().encode(request), session: session)
            let result = try JSONDecoder().decode(AgentResponse.self, from: data)
            #expect(result.requestID == request.requestID)
            return result
        }
        func values(_ operation: String, session: AgentCommandService.Session,
                    targets: [AgentResourceReference] = [], parameters: [String: AgentJSONValue] = [:]) throws -> [String: AgentJSONValue] {
            let result = try response(operation, session: session, targets: targets, parameters: parameters)
            guard case .result(.object(let values)) = result.outcome else {
                Issue.record("Unexpected read outcome: \(result.outcome)"); throw AgentErrorCode.executionError
            }
            return values
        }
        func get(_ note: Note, session: AgentCommandService.Session, parameters: [String: AgentJSONValue] = [:]) throws -> [String: AgentJSONValue] {
            try values("drafts.get", session: session, targets: [.init(kind: .draft, id: note.id)], parameters: parameters)
        }
    }
    private func items(_ values: [String: AgentJSONValue]) throws -> [[String: AgentJSONValue]] {
        guard case .array(let items) = values["items"] else { throw AgentErrorCode.executionError }
        return try items.map { guard case .object(let fields) = $0 else { throw AgentErrorCode.executionError }; return fields }
    }
    private func summary(_ values: [String: AgentJSONValue]) throws -> [String: AgentJSONValue] {
        guard case .object(let value) = values["draft"] else { throw AgentErrorCode.executionError }; return value
    }

    @Test func scopedCountsSearchAndGetNeverExposeOtherNotesOrChangeAccess() throws {
        let f = try Fixture(), allowed = try f.note("Allowed\nneutral café 🐼", tags: ["work/one"])
        let hidden = try f.note("Secret\nneutral hidden"), trash = try f.note("Trash", trashed: true)
        let (_, session) = try f.connect(scope: .resources([.init(kind: .draft, id: allowed.id)]))
        let before = try f.library.backupData()
        #expect(try f.values("library.summary", session: session)["draftCount"] == .integer(1))
        let matches = try items(f.values("drafts.search", session: session, parameters: ["query": .string("neutral")]))
        #expect(matches.count == 1 && matches.first?["id"] == .string(allowed.id.uuidString))
        #expect(matches.first?["preview"] == .string("2: neutral café 🐼"))
        let listed = try items(f.values("drafts.list", session: session))
        #expect(listed.first?["preview"] == .string("neutral café 🐼"))
        #expect(try summary(f.get(allowed, session: session))["accessedAt"] == .null)
        for id in [hidden.id, trash.id, UUID()] {
            #expect(try f.response("drafts.get", session: session, targets: [.init(kind: .draft, id: id)]).outcome == .error(.notFound))
        }
        #expect(try f.library.backupData() == before)
    }

    @Test func listUsesWorkspaceFolderTagSortAndCaseRules() throws {
        let f = try Fixture(), a = try f.note("alpha\nneedle", tags: ["Work/one"])
        let b = try f.note("Beta\nNeedle", tags: ["work/two"], archived: true, accessed: f.wall)
        _ = try f.note("Trash\nneedle", tags: ["work"], trashed: true)
        let (_, session) = try f.connect()
        let params: [String: AgentJSONValue] = ["query": .string("needle"), "tags": .array([.string("work")]),
            "sort": .string("accessed"), "ascending": .bool(true)]
        #expect(try items(f.values("drafts.list", session: session, parameters: params)).map { $0["id"] } == [.string(b.id.uuidString), .string(a.id.uuidString)])
        var exact = params; exact["caseSensitive"] = .bool(true)
        #expect(try items(f.values("drafts.search", session: session, parameters: exact)).map { $0["id"] } == [.string(a.id.uuidString)])
        exact = params; exact["folder"] = .string("archive")
        #expect(try items(f.values("drafts.list", session: session, parameters: exact)).map { $0["id"] } == [.string(b.id.uuidString)])
        exact["excludedTags"] = .array([.string("work/two")])
        #expect(try items(f.values("drafts.list", session: session, parameters: exact)).isEmpty)
    }

    @Test func utf16ChunksRejectSplitScalarsAndNeverReturnANonprogressingPage() throws {
        let f = try Fixture(), note = try f.note("a🐼e\u{301}\n"), (_, session) = try f.connect()
        let first = try f.get(note, session: session, parameters: ["length": .integer(2)])
        guard case .object(let content) = first["content"] else { Issue.record("Missing chunk"); return }
        #expect(content["text"] == .string("a") && content["length"] == .integer(1) && content["hasMore"] == .bool(true))
        let emoji = try f.get(note, session: session, parameters: ["offset": .integer(1), "length": .integer(2)])
        guard case .object(let chunk) = emoji["content"] else { Issue.record("Missing chunk"); return }
        #expect(chunk["text"] == .string("🐼") && chunk["offset"] == .integer(1))
        for p: [String: AgentJSONValue] in [["offset": .integer(2)], ["offset": .integer(1), "length": .integer(1)],
                                           ["offset": .integer(100)], ["length": .integer(0)]] {
            #expect(try f.response("drafts.get", session: session, targets: [.init(kind: .draft, id: note.id)], parameters: p).outcome == .error(.invalidInput))
        }
        let empty = try f.note("")
        guard case .object(let end) = try f.get(empty, session: session)["content"] else { Issue.record("Missing empty chunk"); return }
        #expect(end["length"] == .integer(0) && end["hasMore"] == .bool(false))
    }

    @Test func paginationFreezesMembershipAndOrderButReadsFreshValues() throws {
        let f = try Fixture(), a = try f.note("a"), b = try f.note("b"), (_, session) = try f.connect()
        let params: [String: AgentJSONValue] = ["limit": .integer(1), "sort": .string("title"), "ascending": .bool(true)]
        let page = try f.values("drafts.list", session: session, parameters: params)
        #expect(try items(page).first?["id"] == .string(a.id.uuidString))
        let cursor = try #require(page["nextCursor"])
        _ = try f.note("aa")
        var updated = b; updated.content = "z\nfresh"
        try f.library.saveNote(updated, preserveRevision: false, preserveDates: true)
        var next = params; next["cursor"] = cursor
        let result = try f.values("drafts.list", session: session, parameters: next)
        #expect(try items(result).count == 1)
        #expect(try items(result).first?["title"] == .string("z"))
        #expect(result["nextCursor"] == .null)
        #expect(try f.values("drafts.list", session: session, parameters: next) == result)
    }

    @Test func cursorsRejectOtherSessionsChangedQueriesForgeryExpiryAndRestart() throws {
        let f = try Fixture(); _ = try f.note("a"); _ = try f.note("b")
        let (record, session) = try f.connect(), (_, other) = try f.connect()
        let cursor = try #require(f.values("drafts.list", session: session, parameters: ["limit": .integer(1)])["nextCursor"])
        let parameters: [String: AgentJSONValue] = ["cursor": cursor]
        #expect(try f.response("drafts.list", session: other, parameters: parameters).outcome == .error(.invalidInput))
        var changed = parameters; changed["folder"] = .string("archive")
        #expect(try f.response("drafts.list", session: session, parameters: changed).outcome == .error(.invalidInput))
        #expect(try f.response("drafts.list", session: session, parameters: ["cursor": .string("forged")]).outcome == .error(.invalidInput))
        if case .string(let token) = cursor {
            var parts = token.split(separator: ".").map(String.init)
            parts[1] = "0"
            #expect(try f.response("drafts.list", session: session,
                parameters: ["cursor": .string(parts.joined(separator: "."))]).outcome == .error(.invalidInput))
        }
        f.uptime += 300
        #expect(try f.response("drafts.list", session: session, parameters: parameters).outcome == .error(.invalidInput))
        f.service = try f.makeService()
        #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        #expect(try f.response("drafts.list", session: reopened, parameters: parameters).outcome == .error(.invalidInput))
    }

    @Test func versionsRequireParentScopeAndNeverReadAnotherParentsContent() throws {
        let f = try Fixture(), parent = try f.note("Parent"), hidden = try f.note("Hidden")
        let revision = Revision(noteID: parent.id, content: "neutral revision 🐼")
        try f.library.saveRevision(revision); try f.library.saveRevision(Revision(noteID: hidden.id, content: "private"))
        let (_, session) = try f.connect(scope: .resources([.init(kind: .draft, id: parent.id)]))
        let target = [AgentResourceReference(kind: .draft, id: parent.id)]
        let metadata = try items(f.values("drafts.versions", session: session, targets: target))
        #expect(metadata.count == 1 && metadata.first?["content"] == nil)
        #expect(try items(f.values("drafts.versions", session: session, targets: target,
            parameters: ["includeContent": .bool(true)])).first?["content"] == .string(revision.content))
        #expect(try f.response("drafts.versions", session: session, targets: [.init(kind: .draft, id: hidden.id)]).outcome == .error(.notFound))
        let (_, revisionOnly) = try f.connect(scope: .resources([.init(kind: .revision, id: revision.id)]))
        #expect(try f.response("drafts.versions", session: revisionOnly, targets: target).outcome == .error(.notFound))
    }

    @Test func everyRequestRechecksExpiryRevocationReplacementDisableAndLock() throws {
        for change in 0..<5 {
            let f = try Fixture(), (record, session) = try f.connect()
            _ = try f.values("server.status", session: session)
            switch change {
            case 0: f.wall = record.expiresAt
            case 1: _ = try f.connections.revokeFromUserInterface(record.id)
            case 2: _ = try f.connections.replaceGrantFromUserInterface(record.id, capabilities: [.draftsRead], scope: .library)
            case 3: try f.connections.setEnabledFromUserInterface(false)
            default: f.locked = true
            }
            #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
            if change == 4 {
                f.locked = false
                #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
            }
        }
    }

    @Test func credentialsLibraryIdentityAndCapabilitiesCannotBeChosenByRequests() throws {
        let f = try Fixture(), (record, session) = try f.connect(capabilities: [])
        #expect(throws: AgentErrorCode.permissionDenied) {
            try f.service.authenticate(connectionID: record.id, credential: Data(repeating: 0, count: 32))
        }
        #expect(try f.response("server.status", session: session, libraryID: UUID()).outcome == .error(.permissionDenied))
        #expect(try f.response("library.summary", session: session).outcome == .error(.permissionDenied))
        #expect(throws: AgentErrorCode.invalidInput) { try f.service.respond(to: Data("{}".utf8), session: session) }
        f.service.close(session)
        #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
    }

    @Test func schemasReportActualHandlersAndUnsupportedOperationsNeverSimulateSuccess() throws {
        let f = try Fixture(), (_, session) = try f.connect(capabilities: [.draftsRead, .draftsWrite])
        let values = try f.values("server.schemas", session: session)
        guard case .array(let operations) = values["operations"] else { Issue.record("Missing schemas"); return }
        let available = Set(operations.compactMap { item -> String? in
            guard case .object(let fields) = item, fields["available"] == .bool(true), case .string(let name) = fields["name"] else { return nil }
            return name
        })
        #expect(operations.count == 136 && available == AgentReadSchemas.operationNames && available.count == 8)
        #expect(try f.response("drafts.create", session: session, parameters: ["content": .string("Not saved")]).outcome == .error(.unavailable))
        #expect(f.library.notes.isEmpty)
        #expect(try f.values("server.capabilities", session: session)["capabilities"] == .array([.string("drafts.read"), .string("drafts.write")]))
    }

    @Test func versionTokensIgnoreAccessButTrackTextMetadataEditorGenerationAndRestart() throws {
        let f = try Fixture(), note = try f.note("Neutral"), (_, session) = try f.connect()
        let token = try summary(f.get(note, session: session))["versionToken"]
        try f.library.recordAccess(note.id, at: f.wall)
        #expect(try summary(f.get(note, session: session))["versionToken"] == token)
        f.generation = "pending-1"
        let pending = try summary(f.get(note, session: session))["versionToken"]
        #expect(pending != token)
        var updated = try #require(f.library.notes.first); updated.tags = ["new"]
        try f.library.saveNote(updated, preserveRevision: false, preserveDates: true)
        #expect(try summary(f.get(note, session: session))["versionToken"] != pending)
        f.service = try f.makeService()
        let (_, fresh) = try f.connect()
        #expect(try summary(f.get(note, session: fresh))["versionToken"] != token)
    }

    @Test func invalidQueriesAndParametersLeaveLibraryAndRevisionsUnchanged() throws {
        let f = try Fixture(); _ = try f.note("Neutral\ntext")
        let (_, session) = try f.connect(), before = try f.library.backupData()
        for query in ["/[/", "OR term", "term OR"] {
            #expect(try f.response("drafts.search", session: session, parameters: ["query": .string(query)]).outcome == .error(.invalidInput))
        }
        #expect(try f.response("drafts.list", session: session, parameters: ["limit": .integer(201)]).outcome == .error(.invalidInput))
        #expect(try f.response("server.status", session: session, parameters: ["credential": .string("untrusted")]).outcome == .error(.invalidInput))
        #expect(try f.library.backupData() == before)
    }

    @Test func pagedRevisionsSkipDeletedMembersWithoutAddingNewRevisions() throws {
        let f = try Fixture(), note = try f.note("Neutral"), (_, session) = try f.connect()
        var revisions = [Revision(noteID: note.id, content: "one"), Revision(noteID: note.id, content: "two"),
                         Revision(noteID: note.id, content: "three")]
        for index in revisions.indices { revisions[index].date = f.wall.addingTimeInterval(Double(index))
            try f.library.saveRevision(revisions[index]) }
        let targets = [AgentResourceReference(kind: .draft, id: note.id)]
        let page = try f.values("drafts.versions", session: session, targets: targets, parameters: ["limit": .integer(1)])
        #expect(try items(page).first?["id"] == .string(revisions[2].id.uuidString))
        try f.library.deleteRevision(revisions[1].id)
        try f.library.saveRevision(Revision(noteID: note.id, content: "new outside snapshot"))
        let next = try f.values("drafts.versions", session: session, targets: targets,
            parameters: ["cursor": #require(page["nextCursor"]), "limit": .integer(1)])
        #expect(try items(next).map { $0["id"] } == [.string(revisions[0].id.uuidString)])
        #expect(next["nextCursor"] == .null)
    }

    @Test func explicitInvalidationAndReplacementCannotReuseSessionsOrCursors() throws {
        let f = try Fixture(); _ = try f.note("a"); _ = try f.note("b")
        let (record, session) = try f.connect(), (_, other) = try f.connect()
        let page = try f.values("drafts.list", session: session, parameters: ["limit": .integer(1)])
        f.service.invalidate(connectionID: record.id)
        #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
        _ = try f.values("server.status", session: other)
        _ = try f.connections.replaceGrantFromUserInterface(record.id, capabilities: [.draftsRead], scope: .library)
        let renewed = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        #expect(try f.response("drafts.list", session: renewed, parameters: ["cursor": #require(page["nextCursor"])]).outcome == .error(.invalidInput))
        f.service.invalidateAll()
        #expect(try f.response("server.status", session: other).outcome == .error(.permissionDenied))
        f.locked = true
        #expect(throws: AgentErrorCode.permissionDenied) { try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id])) }
    }

    @Test func frameBudgetReturnsExplicitUnavailabilityInsteadOfTruncatedContent() throws {
        let f = try Fixture(), note = try f.note("Neutral"), (_, session) = try f.connect()
        try f.library.saveRevision(Revision(noteID: note.id, content: String(repeating: "n", count: AgentRequest.maximumBytes)))
        let before = try f.library.backupData()
        #expect(try f.response("drafts.versions", session: session, targets: [.init(kind: .draft, id: note.id)],
            parameters: ["includeContent": .bool(true)]).outcome == .error(.unavailable))
        #expect(try items(f.values("drafts.versions", session: session, targets: [.init(kind: .draft, id: note.id)])).count == 1)
        #expect(try f.library.backupData() == before)
    }

    @Test func authorityChangeDuringReadingDiscardsTheWholeResponse() throws {
        let f = try Fixture(), note = try f.note("Neutral"), (record, session) = try f.connect()
        f.onGeneration = {
            do { _ = try f.connections.revokeFromUserInterface(record.id) }
            catch { Issue.record(error) }
        }
        #expect(try f.response("drafts.get", session: session, targets: [.init(kind: .draft, id: note.id)]).outcome == .error(.permissionDenied))
    }

    @Test func unreadableAuthorityMetadataNeverFallsBackToAnOldGrant() throws {
        let f = try Fixture(), (_, session) = try f.connect()
        f.bytes = Data("invalid private authority metadata".utf8)
        #expect(try f.response("server.status", session: session).outcome == .error(.storageError))
    }

    @Test func largeUnicodeDraftCanBeReassembledExactlyAcrossTheMaximumChunkBoundary() throws {
        let f = try Fixture(), text = String(repeating: "x", count: 65_535) + "🐼" + String(repeating: "é", count: 34_465)
        let note = try f.note(text), (_, session) = try f.connect()
        var offset: Int64 = 0, recovered = ""
        while true {
            let value = try f.get(note, session: session, parameters: ["offset": .integer(offset)])
            guard case .object(let chunk) = value["content"], case .string(let part) = chunk["text"],
                  case .integer(let length) = chunk["length"] else { Issue.record("Missing chunk"); return }
            recovered += part; offset += length
            if chunk["hasMore"] == .bool(false) { break }
            #expect(length > 0)
            if length == 0 { return }
        }
        #expect(recovered == text && offset == Int64(text.utf16.count))
        #expect(f.library.notes.first?.accessedAt == nil && f.library.revisions.isEmpty)
    }
}
