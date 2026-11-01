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
        var hostError: AgentErrorCode?
        var locked = false
        var generation = ""
        var editors: [WindowModel] = [] { didSet { editorRegistry.refreshMembership() } }
        let editorDefaultsName = "Draftly-Agent-Editor-Tests-" + UUID().uuidString
        lazy var editorRegistry = AgentEditorRegistry(library: library, models: { [weak self] in self?.editors ?? [] })
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
                appVersion: "QA", validateHost: { [unowned self] in
                    if let error = self.hostError { throw error }
                }, isLocked: { [unowned self] in self.locked }, now: { [unowned self] in self.wall },
                uptime: { [unowned self] in self.uptime }, editors: editorRegistry, pendingEditorGeneration: { [unowned self] _ in
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
        func window(_ note: Note, content: String? = nil, dirty: Bool = false, library: LibraryStore? = nil) throws -> WindowModel {
            var dependencies = WindowDependencies()
            dependencies.preferences = WindowPreferences(defaults: try #require(UserDefaults(suiteName: editorDefaultsName)))
            let model = WindowModel(library: library ?? self.library, dependencies: dependencies)
            model.editor.load(note, focusEditor: false)
            if let content { model.editor.content = content }
            model.hasUnsavedChanges = dirty
            return model
        }
        func cleanEditorPreferences() { UserDefaults.standard.removePersistentDomain(forName: editorDefaultsName) }
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

    @Test func preferenceDescriptorsPageFromTheAuthoritativeCatalogWithoutReadingSettings() throws {
        let f = try Fixture(), (_, session) = try f.connect(capabilities: [.preferencesRead])
        let catalog = try AgentPreferenceCatalog.make()
        var returned: [AgentJSONValue] = [], cursor: AgentJSONValue?
        repeat {
            var parameters: [String: AgentJSONValue] = ["limit": .integer(7)]
            if let cursor { parameters["cursor"] = cursor }
            let page = try f.values("preferences.schema", session: session, parameters: parameters)
            guard case .array(let descriptors) = page["items"] else { throw AgentErrorCode.executionError }
            returned += descriptors
            cursor = page["nextCursor"] == .null ? nil : page["nextCursor"]
        } while cursor != nil
        let expected = try JSONDecoder().decode([AgentJSONValue].self,
            from: JSONEncoder().encode(catalog.fields.map { catalog.descriptor($0) }))
        #expect(returned == expected)
        #expect(AgentCommandService.implementedOperations.contains("preferences.schema"))
    }

    @Test func preferenceDiscoveryRequiresReadCapabilityAndValidKnownIDs() throws {
        let f = try Fixture(), (_, reader) = try f.connect(), (_, settings) = try f.connect(capabilities: [.preferencesRead])
        #expect(try f.response("preferences.schema", session: reader).outcome == .error(.permissionDenied))
        #expect(try f.response("preferences.schema", session: settings,
            parameters: ["ids": .array([.string("secret.credential")])]).outcome == .error(.invalidInput))
        let page = try f.values("preferences.schema", session: settings,
            parameters: ["ids": .array([.string("editor.fontSize")])])
        #expect(try items(page).map { $0["id"] } == [.string("editor.fontSize")])
    }

    @Test func preferenceCursorCannotCrossSessionsOrFiltersAndExpires() throws {
        let f = try Fixture(), (_, first) = try f.connect(capabilities: [.preferencesRead]),
            (_, other) = try f.connect(capabilities: [.preferencesRead])
        let page = try f.values("preferences.schema", session: first, parameters: ["limit": .integer(1)])
        let cursor = try #require(page["nextCursor"])
        #expect(cursor != .null)
        #expect(try f.response("preferences.schema", session: other,
            parameters: ["cursor": cursor]).outcome == .error(.invalidInput))
        #expect(try f.response("preferences.schema", session: first,
            parameters: ["cursor": cursor, "ids": .array([.string("editor.fontSize")])]).outcome == .error(.invalidInput))
        f.wall += 601; f.uptime += 601
        #expect(try f.response("preferences.schema", session: first,
            parameters: ["cursor": cursor]).outcome == .error(.invalidInput))
    }

    @Test func lostHostDeniesStartupAuthenticationAndExistingSessions() throws {
        let f = try Fixture(), (record, session) = try f.connect()
        f.hostError = .versionConflict
        #expect(throws: AgentErrorCode.versionConflict) { try f.service.permitsTransportStart() }
        #expect(throws: AgentErrorCode.versionConflict) {
            try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        }
        #expect(try f.response("server.status", session: session).outcome == .error(.versionConflict))
        f.hostError = nil
        #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
    }

    @Test func temporaryHostContentionDeniesOnlyTheCurrentAttempt() throws {
        let f = try Fixture(), (_, session) = try f.connect()
        f.hostError = .busy
        #expect(try f.response("server.status", session: session).outcome == .error(.busy))
        f.hostError = nil
        #expect(try f.values("server.status", session: session)["accessEnabled"] == .bool(true))
    }

    @Test func hostLostDuringReadingDiscardsContentAndInvalidatesTheSession() throws {
        let f = try Fixture(), note = try f.note("Neutral ownership"), (_, session) = try f.connect()
        f.onGeneration = { f.hostError = .versionConflict }
        #expect(try f.response("drafts.get", session: session,
            targets: [.init(kind: .draft, id: note.id)]).outcome == .error(.versionConflict))
        f.onGeneration = nil; f.hostError = nil
        #expect(try f.response("server.status", session: session).outcome == .error(.permissionDenied))
    }

    private func items(_ values: [String: AgentJSONValue]) throws -> [[String: AgentJSONValue]] {
        guard case .array(let items) = values["items"] else { throw AgentErrorCode.executionError }
        return try items.map { guard case .object(let fields) = $0 else { throw AgentErrorCode.executionError }; return fields }
    }
    private func summary(_ values: [String: AgentJSONValue]) throws -> [String: AgentJSONValue] {
        guard case .object(let value) = values["draft"] else { throw AgentErrorCode.executionError }; return value
    }

    @Test func currentReadsUsePendingEditorTextWithoutSavingOrChangingSelection() throws {
        let f = try Fixture(), note = try f.note("Stored\nold text"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let model = try f.window(note)
        model.editor.content = "Pending 🐼\ncurrent needle"
        model.editor.selection = NSRange(location: 8, length: 2)
        model.hasUnsavedChanges = true; f.editors = [model]
        var effects = 0
        model.editor.synchronizeScriptEdit = { effects += 1 }
        model.editor.performUndo = { _ in effects += 1 }
        let before = try f.library.backupData(), focus = model.editor.focusToken
        let value = try f.get(note, session: session)
        #expect(try summary(value)["title"] == .string("Pending 🐼"))
        guard case .object(let chunk) = value["content"] else { Issue.record("Missing text chunk"); return }
        #expect(chunk["text"] == .string(model.editor.content))
        let matches = try items(f.values("drafts.search", session: session, parameters: ["query": .string("needle")]))
        #expect(matches.count == 1 && matches.first?["id"] == .string(note.id.uuidString))
        #expect(model.editor.selection == NSRange(location: 8, length: 2) && model.editor.focusToken == focus)
        #expect(model.hasUnsavedChanges && f.library.notes.first?.content == note.content)
        #expect(effects == 0)
        #expect(try f.library.backupData() == before)
    }

    @Test func divergentPendingEditorsReturnConflictRatherThanStoredTextOrOneWindow() throws {
        let f = try Fixture(), note = try f.note("Stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        f.editors = try ["First neutral", "Second neutral"].map { try f.window(note, content: $0, dirty: true) }
        let before = try f.library.backupData()
        #expect(try f.response("drafts.get", session: session,
            targets: [.init(kind: .draft, id: note.id)]).outcome == .error(.editorConflict))
        #expect(try f.response("drafts.list", session: session).outcome == .error(.editorConflict))
        #expect(try f.library.backupData() == before)
    }

    @Test func matchingPendingWindowsIgnoreCleanStaleAndOtherLibraryEditors() throws {
        let f = try Fixture(), note = try f.note("Stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let foreign = try LibraryStore(inMemory: true, seed: false)
        let a = try f.window(note, content: "Matching 🐼", dirty: true)
        let b = try f.window(note, content: "Matching 🐼", dirty: true)
        var staleNote = note; staleNote.content = "Old clean text"
        let stale = try f.window(staleNote)
        let other = try f.window(note, content: "Foreign pending", dirty: true, library: foreign)
        f.editors = [stale, a, other, b]
        let first = try summary(f.get(note, session: session))
        #expect(first["title"] == .string("Matching 🐼"))
        f.editors.reverse()
        #expect(try summary(f.get(note, session: session)) == first)
        #expect(stale.editor.content == "Old clean text" && other.editor.content == "Foreign pending")
    }

    @Test func editorGenerationTracksUnobservedRevertsAndClosureButNotSelection() throws {
        let f = try Fixture(), note = try f.note("Stored 🐼"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let model = try f.window(note); f.editors = [model]
        let original = try summary(f.get(note, session: session))["versionToken"]
        model.editor.selection = NSRange(location: 7, length: 2); model.editor.focusToken = UUID()
        #expect(try summary(f.get(note, session: session))["versionToken"] == original)
        model.editor.content = "Intermediate"; model.hasUnsavedChanges = true
        model.editor.content = note.content
        let reverted = try summary(f.get(note, session: session))["versionToken"]
        #expect(reverted != original)
        f.editors = []
        let closed = try summary(f.get(note, session: session))["versionToken"]
        #expect(closed != original && closed != reverted)
        model.editor.content = "Disconnected editor"
        #expect(try summary(f.get(note, session: session))["versionToken"] == closed)
        #expect(f.library.notes.first?.content == note.content)
    }

    @Test func canonicallyEquivalentPendingStringsStillConflictWhenTheirCodeUnitsDiffer() throws {
        let f = try Fixture(), note = try f.note("Stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        f.editors = try ["café", "cafe\u{0301}"].map { try f.window(note, content: $0, dirty: true) }
        #expect(try f.response("drafts.get", session: session,
            targets: [.init(kind: .draft, id: note.id)]).outcome == .error(.editorConflict))
    }

    @Test func hiddenEditorConflictsDoNotChangeAuthorizedReadsOrVersionTokens() throws {
        let f = try Fixture(), allowed = try f.note("Allowed"), hidden = try f.note("Hidden")
        defer { f.cleanEditorPreferences() }
        let (_, session) = try f.connect(scope: .resources([.init(kind: .draft, id: allowed.id)]))
        f.editors = try ["First", "Second"].map { try f.window(hidden, content: $0, dirty: true) }
        let before = try summary(f.get(allowed, session: session))["versionToken"]
        let values = try items(f.values("drafts.list", session: session))
        #expect(values.count == 1 && values.first?["id"] == .string(allowed.id.uuidString))
        f.editors[0].editor.content = "Changed hidden text"
        #expect(try summary(f.get(allowed, session: session))["versionToken"] == before)
        #expect(try f.response("drafts.get", session: session,
            targets: [.init(kind: .draft, id: hidden.id)]).outcome == .error(.notFound))
    }

    @Test func pendingTextDoesNotHideChangesToStoredContentFromTheVersionToken() throws {
        let f = try Fixture(), note = try f.note("Original stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let model = try f.window(note, content: "Pending neutral", dirty: true); f.editors = [model]
        let first = try summary(f.get(note, session: session))["versionToken"]
        var stored = note; stored.accessedAt = f.wall.addingTimeInterval(5)
        try f.library.saveNote(stored, preserveRevision: false, preserveDates: true)
        #expect(try summary(f.get(note, session: session))["versionToken"] == first)
        stored.content = "Concurrent stored text"
        try f.library.saveNote(stored, preserveRevision: false, preserveDates: true)
        let values = try f.get(note, session: session)
        #expect(try summary(values)["versionToken"] != first)
        guard case .object(let chunk) = values["content"] else { Issue.record("Missing pending text"); return }
        #expect(chunk["text"] == .string("Pending neutral"))
        #expect(model.hasUnsavedChanges && model.editor.content == "Pending neutral")
    }

    @Test func aWindowOpenedEditedAndClosedBetweenReadsChangesTheVersion() throws {
        let f = try Fixture(), note = try f.note("Stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let before = try summary(f.get(note, session: session))["versionToken"]
        let model = try f.window(note); f.editors = [model]
        model.editor.content = "Intermediate"; model.hasUnsavedChanges = true
        model.editor.content = note.content; f.editors = []
        #expect(try summary(f.get(note, session: session))["versionToken"] != before)
        #expect(f.library.notes.first?.content == note.content)
    }

    @Test func codeUnitOnlyEditsAreReadEvenBeforeTheWindowDirtyFlagChanges() throws {
        let f = try Fixture(), note = try f.note("café"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        let model = try f.window(note); f.editors = [model]
        model.editor.content = "cafe\u{0301}"
        #expect(!model.hasUnsavedChanges)
        let result = try f.get(note, session: session)
        guard case .object(let chunk) = result["content"], case .string(let text) = chunk["text"] else {
            Issue.record("Missing pending text"); return
        }
        #expect(Data(text.utf8) == Data(model.editor.content.utf8))
        #expect(Data(try #require(f.library.notes.first).content.utf8) == Data(note.content.utf8))
    }

    @Test func registryObservationDoesNotRetainClosedWindowModels() throws {
        let f = try Fixture(), note = try f.note("Stored"), (_, session) = try f.connect()
        defer { f.cleanEditorPreferences() }
        var model: WindowModel? = try f.window(note)
        weak var observed = model
        f.editors = [try #require(model)]
        _ = try f.get(note, session: session)
        f.editors = []; model = nil
        #expect(observed == nil)
        #expect(try summary(f.get(note, session: session))["title"] == .string("Stored"))
    }

    @Test func aRegistryForAnotherLibraryIsRejectedAtServiceConstruction() throws {
        let f = try Fixture(), other = try LibraryStore(inMemory: true, seed: false)
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentCommandService(library: other, libraryID: f.libraryID, connections: f.connections,
                appVersion: "QA", validateHost: {}, isLocked: { false }, editors: f.editorRegistry,
                pendingEditorGeneration: { _ in "" })
        }
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

    @Test func cursorLivesForTenMinutesButNotBeyondEitherClockBoundary() throws {
        let f = try Fixture(); _ = try f.note("a"); _ = try f.note("b")
        let (_, session) = try f.connect()
        let cursor = try #require(f.values("drafts.list", session: session,
            parameters: ["limit": .integer(1)])["nextCursor"])
        f.wall += 599; f.uptime += 599
        #expect(try items(f.values("drafts.list", session: session,
            parameters: ["cursor": cursor])).count == 1)
        f.uptime += 1
        #expect(try f.response("drafts.list", session: session,
            parameters: ["cursor": cursor]).outcome == .error(.invalidInput))
    }

    @Test func cursorDoesNotExtendAShortGrantOrSurviveMonotonicRollback() throws {
        let f = try Fixture(); _ = try f.note("a"); _ = try f.note("b")
        let record = try f.connections.connectFromUserInterface(name: "Neutral short grant", libraryID: f.libraryID,
            scope: .library, expiresAt: f.wall.addingTimeInterval(90))
        let session = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let cursor = try #require(f.values("drafts.list", session: session,
            parameters: ["limit": .integer(1)])["nextCursor"])
        f.uptime -= 1
        #expect(try f.response("drafts.list", session: session,
            parameters: ["cursor": cursor]).outcome == .error(.invalidInput))
        f.wall += 90; f.uptime += 91
        #expect(try f.response("drafts.list", session: session,
            parameters: ["cursor": cursor]).outcome == .error(.permissionDenied))
    }

    @Test func cursorWallDeadlineCanExpireBeforeTheMonotonicDeadline() throws {
        let f = try Fixture(); _ = try f.note("a"); _ = try f.note("b")
        let (_, session) = try f.connect()
        let cursor = try #require(f.values("drafts.list", session: session,
            parameters: ["limit": .integer(1)])["nextCursor"])
        f.wall += 600
        #expect(try f.response("drafts.list", session: session,
            parameters: ["cursor": cursor]).outcome == .error(.invalidInput))
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
        f.uptime += 600
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
        #expect(operations.count == 137 && available == AgentReadSchemas.operationNames.union(["preferences.schema", AgentMutationSchemas.name, "drafts.update", "drafts.patch", "drafts.restoreVersion", "editor.windows", "editor.get"]) && available.count == 15)
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
    @Test func editorReadsUseExplicitWindowIDsAndKeepPendingTextUnchanged() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Stored neutral")
        let model = try f.window(note, content: "Pending e\u{0301} 🐼", dirty: true)
        model.editor.selection = NSRange(location: 8, length: 2)
        f.editors = [model]
        let (_, session) = try f.connect(capabilities: [.draftsRead, .editorRead])
        let entries = try items(f.values("editor.windows", session: session))
        #expect(entries.count == 1)
        guard let first = entries.first, case .string(let rawID) = first["windowID"], let id = UUID(uuidString: rawID) else {
            Issue.record("Missing editor identity"); return
        }
        let values = try f.values("editor.get", session: session, targets: [.init(kind: .window, id: id)])
        #expect(values["draftID"] == .string(note.id.uuidString))
        guard case .object(let content) = values["content"] else { Issue.record("Missing editor chunk"); return }
        #expect(content["text"] == .string(model.editor.content))
        #expect(values["selection"] == .object(["offset": .integer(8), "length": .integer(2)]))
        #expect(values["hasUnsavedChanges"] == .bool(true))
        #expect(try items(f.values("editor.windows", session: session)).first?["windowID"] == first["windowID"])
        #expect(f.library.notes.first?.content == note.content)
        #expect(model.hasUnsavedChanges && model.editor.selection == NSRange(location: 8, length: 2))
        model.hasUnsavedChanges = false
    }

    @Test func editorWindowEnumerationFiltersBothWindowAndDraftScopes() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Allowed neutral"), hidden = try f.note("Hidden neutral")
        let allowed = try f.window(note), other = try f.window(hidden)
        f.editors = [allowed, other]
        let (_, all) = try f.connect(capabilities: [.draftsRead, .editorRead])
        let entries = try items(f.values("editor.windows", session: all))
        let entry = try #require(entries.first { $0["draftID"] == .string(note.id.uuidString) })
        guard case .string(let rawID) = entry["windowID"], let id = UUID(uuidString: rawID) else { Issue.record("Missing window"); return }
        let window = AgentResourceReference(kind: .window, id: id)
        let (_, onlyWindow) = try f.connect(scope: .resources([window]), capabilities: [.draftsRead, .editorRead])
        #expect(try items(f.values("editor.windows", session: onlyWindow)).isEmpty)
        #expect(try f.response("editor.get", session: onlyWindow, targets: [window]).outcome == .error(.notFound))
        let (_, scoped) = try f.connect(scope: .resources([window, .init(kind: .draft, id: note.id)]), capabilities: [.draftsRead, .editorRead])
        #expect(try items(f.values("editor.windows", session: scoped)).count == 1)
        f.editors = []
        #expect(try f.response("editor.get", session: scoped, targets: [window]).outcome == .error(.notFound))
    }

    @Test func editorVersionsTrackSelectionAndReadsRejectSplitUTF16Scalars() throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("A🐼B"), model = try f.window(note)
        f.editors = [model]
        let (_, session) = try f.connect(capabilities: [.draftsRead, .editorRead])
        let first = try #require(try items(f.values("editor.windows", session: session)).first)
        guard case .string(let rawID) = first["windowID"], let id = UUID(uuidString: rawID) else { Issue.record("Missing window"); return }
        let target = AgentResourceReference(kind: .window, id: id)
        let before = try f.values("editor.get", session: session, targets: [target])
        model.editor.selection = NSRange(location: 1, length: 2)
        let after = try f.values("editor.get", session: session, targets: [target])
        #expect(before["versionToken"] != after["versionToken"])
        model.editor.selection = NSRange(location: 0, length: 0)
        let reverted = try f.values("editor.get", session: session, targets: [target])
        #expect(reverted["versionToken"] != before["versionToken"])
        #expect(try f.response("editor.get", session: session, targets: [target],
            parameters: ["offset": .integer(2), "length": .integer(1)]).outcome == .error(.invalidInput))
        let chunk = try f.values("editor.get", session: session, targets: [target],
            parameters: ["offset": .integer(1), "length": .integer(2)])
        guard case .object(let content) = chunk["content"] else { Issue.record("Missing chunk"); return }
        #expect(content["text"] == .string("🐼"))
        f.editors = []
        f.editors = [model]
        let reopened = try #require(try items(f.values("editor.windows", session: session)).first)
        #expect(reopened["windowID"] != first["windowID"])
        #expect(try f.response("editor.get", session: session, targets: [target]).outcome == .error(.notFound))
        #expect(f.library.notes.first?.content == note.content && f.library.revisions.isEmpty)
    }

    @Test func missingEditorTrackingKeepsMutationRoutesUnavailable() throws {
        let f = try Fixture()
        f.service = try AgentCommandService(library: f.library, libraryID: f.libraryID, connections: f.connections,
            appVersion: "QA", validateHost: {}, isLocked: { false }, now: { f.wall },
            uptime: { f.uptime }, pendingEditorGeneration: { _ in "" })
        let (_, session) = try f.connect(capabilities: [.draftsRead, .draftsWrite])
        let schemas = try f.values("server.schemas", session: session)
        guard case .array(let entries) = schemas["operations"] else { Issue.record("Missing schema entries"); return }
        for name in ["mutations.prepare", "drafts.update", "drafts.patch", "drafts.restoreVersion"] {
            let entry = entries.first { value in
                guard case .object(let fields) = value else { return false }
                return fields["name"] == .string(name)
            }
            guard case .object(let fields) = entry else { Issue.record("Missing mutation descriptor"); continue }
            #expect(fields["available"] == .bool(false))
        }
        #expect(try f.response("mutations.prepare", session: session).outcome == .error(.unavailable))
        #expect(f.library.notes.isEmpty)
    }

    @Test func preparesAndExecutesAnAuthorizedUpdateWithoutChangingDuringPreparation() throws {
        let f = try Fixture(), note = try f.note("Neutral original 🐼")
        let (record, session) = try f.connect(scope: .resources([.init(kind: .draft, id: note.id)]), capabilities: [.draftsRead, .draftsWrite])
        guard case .string(let version) = try summary(f.get(note, session: session))["versionToken"] else { Issue.record("Missing version"); return }
        let mutation = AgentRequest(requestID: UUID(), libraryID: nil, operation: "drafts.update",
            targets: [.init(kind: .draft, id: note.id)], expectedVersion: version,
            parameters: ["changes": .object(["content": .string("Updated 🐼")])])
        let frame = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(mutation))
        let prepared = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        #expect(f.library.notes.first?.content == note.content)
        guard case .string(let key) = prepared["retryKey"] else { Issue.record("Missing key"); return }
        #expect(prepared["requestID"] == .string(mutation.requestID.uuidString))
        let signed = AgentRequest(requestID: mutation.requestID, libraryID: f.libraryID, operation: mutation.operation,
            targets: mutation.targets, expectedVersion: version, retryKey: key, parameters: mutation.parameters)
        let reply = try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed), session: session))
        guard case .result(.object(let result)) = reply.outcome else { Issue.record("Update failed: \(reply.outcome)"); return }
        #expect(f.library.notes.first?.content == "Updated 🐼")
        try AgentOperationSchemas.validateResult(result, for: signed)
        let recovered = try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(signed), session: session))
        #expect(recovered == reply)
        // Explicit preparation of the committed intent must recover, not edit again.
        let preparedAgain = try f.values("mutations.prepare", session: session, parameters: ["request": frame])
        guard case .string(let recoveryKey) = preparedAgain["retryKey"] else { Issue.record("Missing recovery key"); return }
        let recovery = AgentRequest(requestID: mutation.requestID, libraryID: f.libraryID, operation: mutation.operation,
            targets: mutation.targets, expectedVersion: version, retryKey: recoveryKey, parameters: mutation.parameters)
        let response = try JSONDecoder().decode(AgentResponse.self, from: f.service.respond(to: JSONEncoder().encode(recovery), session: session))
        #expect(response == reply)
        #expect(f.library.notes.first?.content == "Updated 🐼")
        f.service = try f.makeService()
        let reopened = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let oldKeyResponse = try JSONDecoder().decode(AgentResponse.self,
            from: f.service.respond(to: JSONEncoder().encode(signed), session: reopened))
        #expect(oldKeyResponse.outcome == .error(.invalidInput))
        let afterRestart = try f.values("mutations.prepare", session: reopened, parameters: ["request": frame])
        guard case .string(let freshKey) = afterRestart["retryKey"] else { Issue.record("Missing fresh key"); return }
        let fresh = AgentRequest(requestID: mutation.requestID, libraryID: f.libraryID, operation: mutation.operation,
            targets: mutation.targets, expectedVersion: version, retryKey: freshKey, parameters: mutation.parameters)
        let receipt = try JSONDecoder().decode(AgentResponse.self,
            from: f.service.respond(to: JSONEncoder().encode(fresh), session: reopened))
        #expect(receipt == reply)
        #expect(f.library.notes.first?.content == "Updated 🐼")
    }

    @Test func preparationCannotBypassWriteScopeOrRefreshAnExistingKey() throws {
        let f = try Fixture(), note = try f.note("Neutral unchanged")
        let (_, readSession) = try f.connect()
        let (_, writeSession) = try f.connect(capabilities: [.draftsRead, .draftsWrite])
        let (_, excludedSession) = try f.connect(scope: .resources([]), capabilities: [.draftsRead, .draftsWrite])
        guard case .string(let version) = try summary(f.get(note, session: readSession))["versionToken"] else {
            Issue.record("Missing version"); return
        }
        func frame(libraryID: UUID? = nil, retryKey: String? = nil, version: String? = nil) throws -> AgentJSONValue {
            let request = AgentRequest(requestID: UUID(), libraryID: libraryID, operation: "drafts.update",
                targets: [.init(kind: .draft, id: note.id)], expectedVersion: version,
                retryKey: retryKey, parameters: ["changes": .object(["content": .string("Not committed")])])
            return try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(request))
        }
        let intent = try frame(version: version)
        #expect(try f.response("mutations.prepare", session: readSession, parameters: ["request": intent]).outcome == .error(.permissionDenied))
        #expect(try f.response("mutations.prepare", session: excludedSession, parameters: ["request": intent]).outcome == .error(.notFound))
        let invalid: [(AgentJSONValue, AgentErrorCode)] = [
            (try frame(libraryID: UUID(), version: version), .permissionDenied),
            (try frame(retryKey: "existing-key", version: version), .invalidInput),
            (try frame(version: "stale-version"), .versionConflict)]
        for (intent, error) in invalid {
            #expect(try f.response("mutations.prepare", session: writeSession, parameters: ["request": intent]).outcome == .error(error))
        }
        #expect(f.library.notes.first?.content == note.content)
    }

}
