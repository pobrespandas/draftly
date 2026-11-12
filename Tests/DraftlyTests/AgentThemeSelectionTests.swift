import Foundation
import Testing
import AgentContracts
@testable import DraftlyCore
@testable import Draftly

@Suite("Authorized direct theme selection") @MainActor
struct AgentThemeSelectionTests {
    @MainActor private final class Fixture {
        let f: AgentCommandServiceTests.Fixture
        let defaults: UserDefaults
        let root: URL
        let operations: AgentOperationRegistry
        init() throws {
            let f = try AgentCommandServiceTests.Fixture()
            self.f = f
            defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
            root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-Theme-Select-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
                validateHost: {}, isLocked: { f.locked }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: root))
            f.operations = operations; try f.enablePreferenceWrites()
        }
        func token(_ appearance: String, session: AgentCommandService.Session) throws -> String {
            guard case .string(let value) = try f.values("themes.selection", session: session,
                parameters: ["appearance": .string(appearance)])["versionToken"] else { throw AgentErrorCode.storageError }
            return value
        }
        func themeToken(_ id: UUID, session: AgentCommandService.Session) throws -> String {
            guard case .string(let value) = try f.values("themes.get", session: session,
                targets: [.init(kind: .theme, id: id)])["versionToken"] else { throw AgentErrorCode.storageError }
            return value
        }
        func wait(_ id: UUID, connection: UUID) async throws -> AgentOperationRegistry.Snapshot {
            let deadline = ContinuousClock.now + .seconds(5)
            while try !operations.snapshot(id, connectionID: connection).state.isTerminal,
                  ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(1))
            }
            let result = try operations.snapshot(id, connectionID: connection)
            try #require(result.state.isTerminal, "Operation did not finish: \(result.state), error: \(String(describing: result.error))")
            return result
        }
        func close() {
            operations.cancelAll(); f.operations?.cancelAll(); f.service = nil
            f.operations = nil; f.preferenceStorage = nil
            f.cleanEditorPreferences(); try? FileManager.default.removeItem(at: root)
        }
    }

    @Test(arguments: ["inline", "transfer", "file", "builtIn", "replace", "fileReplace"], [false, true])
    func installationPreservesDataAndRecoversWithoutResolvingAgain(mode: String, select: Bool) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        let retained = EditorThemeDefinition(name: "Keep theme"), original = EditorThemeDefinition(name: "Before café 🐼")
        try f.library.saveTheme(retained)
        if mode == "replace" { try f.library.saveTheme(original) }
        let note = try f.note("Keep draft café 🐼")
        defaults.set("keep", forKey: "unknown.setting")
        let (connection, session) = try f.connect(capabilities: [.appearanceRead, .appearanceManage, .filesRead])
        let incoming = EditorThemeDefinition(name: "Incoming café 🐼", background: "112233")
        let bytes = try JSONEncoder().encode(incoming)
        var source: AgentJSONValue = .object(["kind": .string("inline"), "text": .string(String(decoding: bytes, as: UTF8.self))])
        let file = fixture.root.appendingPathComponent("Incoming.json")
        try bytes.write(to: file)
        var replacementID = original.id
        if mode == "fileReplace" {
            let oldFile = fixture.root.appendingPathComponent("Old.json")
            try JSONEncoder().encode(original).write(to: oldFile)
            let old = try ThemeFileAccess.prepare(oldFile)
            try ThemeFileAccess.install(old, in: f.library, defaults: defaults)
            replacementID = old.definition.id
            try FileManager.default.removeItem(at: oldFile)
        }
        if ["file", "fileReplace"].contains(mode) {
            BookmarkPreferences.store(try BookmarkPreferences.data(for: fixture.root), named: "Input", defaults: defaults)
            let bookmark = try #require(try BookmarkPreferences.agentRecords(defaults: defaults).first)
            source = .object(["kind": .string("bookmark"), "bookmarkID": .string(bookmark.id.uuidString), "path": .string("Incoming.json")])
        }
        if mode == "builtIn" { source = .object(["kind": .string("installationURL"), "url": .string(try ThemeInstallation.builtIn("Dark").url.absoluteString)]) }
        if mode == "transfer" {
            let started = try f.values("transfers.beginImport", session: session, parameters: ["byteLength": .integer(Int64(bytes.count)), "sha256": .string(AgentTransferStore.digest(bytes))])
            guard case .object(let transfer) = started["transfer"], case .string(let raw) = transfer["transferID"], let id = UUID(uuidString: raw) else { Issue.record("Missing transfer"); return }
            let target = AgentResourceReference(kind: .operation, id: id)
            _ = try f.values("transfers.appendChunk", session: session, targets: [target], parameters: ["offset": .integer(0), "data": .string(bytes.base64EncodedString())])
            _ = try f.values("transfers.finishImport", session: session, targets: [target])
            source = .object(["kind": .string("transfer"), "transferID": .string(raw)])
        }
        var parameters: [String: AgentJSONValue] = ["source": source, "mode": .string(["file", "fileReplace"].contains(mode) ? "file" : "custom")]
        if select { parameters["selectAppearance"] = .string("light"); parameters["expectedSelectionVersion"] = .string(try fixture.token("light", session: session)) }
        let replacing = ["replace", "fileReplace"].contains(mode)
        var expected: String?
        if replacing {
            guard case .array(let rows) = try f.values("themes.list", session: session)["items"],
                  let row = rows.first(where: { if case .object(let fields) = $0 { return fields["id"] == .string(replacementID.uuidString) }; return false }),
                  case .object(let fields) = row, case .string(let token) = fields["versionToken"] else { Issue.record("Missing stored version"); return }
            expected = token
        }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: replacing ? "themes.replace" : "themes.install", targets: replacing ? [.init(kind: .theme, id: replacementID)] : [], expectedVersion: expected, parameters: parameters)
        let beforeReferences = defaults.data(forKey: EditorThemePreferences.key)
        let response = try f.send(request, session: session)
        guard case .accepted(let id, _) = response.outcome else { Issue.record("Missing install: \(response)"); return }
        f.service.close(session)
        let completed = try await fixture.wait(id, connection: connection.id)
        #expect(completed.state == .succeeded)
        guard case .object(let result) = completed.result else { Issue.record("Missing install result"); return }
        if mode == "builtIn" {
            #expect(result["builtInName"] == .string("Dark") && result["resource"] == .null)
            #expect(f.library.themes == [retained])
        } else {
            guard case .object(let resource) = result["resource"], case .string(let raw) = resource["id"], let resourceID = UUID(uuidString: raw) else { Issue.record("Missing resource"); return }
            let installed = try #require(f.library.themes.first { $0.id == resourceID })
            #expect(installed.name == incoming.name && installed.background == "112233")
            #expect(!replacing || resourceID == replacementID)
            if ["file", "fileReplace"].contains(mode) {
                #expect(defaults.data(forKey: ThemeFileAccess.bookmarkKey(for: resourceID)) != nil)
                #expect(try ThemeFileAccess.read(installed, defaults: defaults) == installed)
                let inspection = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
                #expect(try f.values("themes.get", session: inspection, targets: [.init(kind: .theme, id: resourceID)])["versionToken"] == resource["versionToken"])
                f.service.close(inspection)
            }
            #expect(f.library.themes.contains(retained) && f.library.themes.count == 2)
        }
        #expect(f.library.notes == [note] && defaults.string(forKey: "unknown.setting") == "keep")
        if !select { #expect(defaults.data(forKey: EditorThemePreferences.key) == beforeReferences && result["selection"] == .null) }
        try FileManager.default.removeItem(at: file)
        let reopened = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) }, validateHost: {}, isLocked: { f.locked }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: fixture.root))
        f.operations = reopened; f.service = try f.makeService()
        let next = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        let references = defaults.data(forKey: EditorThemePreferences.key), revision = defaults.integer(forKey: ThemeCatalog.revisionKey), themes = f.library.themes
        #expect(try f.send(request, session: next).outcome == .result(.object(result)))
        #expect(defaults.data(forKey: EditorThemePreferences.key) == references && defaults.integer(forKey: ThemeCatalog.revisionKey) == revision && f.library.themes == themes)
    }

    @Test(arguments: ["preferenceFailure", "stopWork", "libraryFailure"])
    func installationDoesNotRepeatPartialEffects(mode: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        var writes = 0
        f.preferenceStorage = AgentPreferenceStorage(read: { defaults.persistentDomain(forName: f.editorDefaultsName) ?? [:] }, replace: { [weak f] _, updated in
            guard let f else { throw AgentErrorCode.cancelled }
            writes += 1; defaults.setPersistentDomain(updated, forName: f.editorDefaultsName)
            if mode == "preferenceFailure" { throw AgentErrorCode.storageError }
            f.service.invalidateAll(); return true
        })
        f.service = try f.makeService()
        let (connection, session) = try f.connect(capabilities: [.appearanceRead, .appearanceManage, .filesRead])
        let incoming = EditorThemeDefinition(name: "Partial café 🐼")
        let bytes = try JSONEncoder().encode(incoming)
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.install", parameters: ["source": .object(["kind": .string("inline"), "text": .string(String(decoding: bytes, as: UTF8.self))])])
        if mode == "libraryFailure" { f.library.beforeBatchCommit = { throw DraftlyError.message("Disk failed") } }
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing operation"); return }
        let result = try await fixture.wait(id, connection: connection.id)
        if mode == "libraryFailure" {
            #expect(result.state == .failed && result.error == .storageError && f.library.themes.isEmpty && writes == 0)
        } else {
            #expect(result.state == .outcomeUnknown && result.error == .outcomeUnknown && f.library.themes == [incoming] && writes == 1)
            let next = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
            let revision = defaults.integer(forKey: ThemeCatalog.revisionKey)
            #expect(try f.send(request, session: next).outcome == .error(.outcomeUnknown))
            #expect(writes == 1 && defaults.integer(forKey: ThemeCatalog.revisionKey) == revision && f.library.themes == [incoming])
        }
    }

    @Test(arguments: ["fileChanged", "fileChangedNFD", "bookmarkRevoked", "selectionChanged"])
    func pendingInstallationRechecksItsInputsBeforeSaving(mode: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        var sourceTheme = EditorThemeDefinition(name: "Pending café 🐼")
        let file = fixture.root.appendingPathComponent("Pending.json")
        try JSONEncoder().encode(sourceTheme).write(to: file)
        BookmarkPreferences.store(try BookmarkPreferences.data(for: fixture.root), named: "Pending", defaults: defaults)
        let bookmark = try #require(try BookmarkPreferences.agentRecords(defaults: defaults).first)
        let (connection, session) = try f.connect(capabilities: [.appearanceRead, .appearanceManage, .filesRead])
        var parameters: [String: AgentJSONValue] = ["mode": .string("file"), "source": .object(["kind": .string("bookmark"), "bookmarkID": .string(bookmark.id.uuidString), "path": .string("Pending.json")])]
        if mode == "selectionChanged" { parameters["selectAppearance"] = .string("light"); parameters["expectedSelectionVersion"] = .string(try fixture.token("light", session: session)) }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.install", parameters: parameters)
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing operation"); return }
        if mode == "fileChanged" { sourceTheme.background = "ABCDEF"; try JSONEncoder().encode(sourceTheme).write(to: file) }
        if mode == "fileChangedNFD" { sourceTheme.name = sourceTheme.name.decomposedStringWithCanonicalMapping; try JSONEncoder().encode(sourceTheme).write(to: file) }
        if mode == "bookmarkRevoked" { BookmarkPreferences.forget("Pending", defaults: defaults) }
        if mode == "selectionChanged" { try EditorThemePreferences(defaults: defaults).set(reference: ["type": "builtIn", "name": "Dark"], dark: false, themes: f.library.themes) }
        let preferences = defaults.persistentDomain(forName: f.editorDefaultsName) ?? [:]
        let result = try await fixture.wait(id, connection: connection.id)
        #expect(result.state == .failed && result.error == (mode == "bookmarkRevoked" ? .permissionDenied : .versionConflict))
        #expect(f.library.themes.isEmpty)
        #expect(NSDictionary(dictionary: defaults.persistentDomain(forName: f.editorDefaultsName) ?? [:]).isEqual(to: preferences))
    }

    @Test(arguments: ["replaceBefore", "replaceQueued", "reload", "select", "deleteReview"])
    func retargetedFilePermissionInvalidatesStaleThemeWork(mode: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        let approvals = AgentApprovalStore(now: { f.wall }, currentGrant: { try? f.connections.grantForAuthenticatedConnection($0) }, isLocked: { false })
        f.deletionApprovals = approvals; f.service = try f.makeService()
        let bytes = try JSONEncoder().encode(EditorThemeDefinition(name: "Same café 🐼"))
        let firstURL = fixture.root.appendingPathComponent("First.json"), secondURL = fixture.root.appendingPathComponent("Second.json")
        try bytes.write(to: firstURL); try bytes.write(to: secondURL)
        let first = try ThemeFileAccess.prepare(firstURL), second = try ThemeFileAccess.prepare(secondURL, id: first.definition.id)
        try ThemeFileAccess.install(first, in: f.library, defaults: defaults)
        BookmarkPreferences.store(try BookmarkPreferences.data(for: fixture.root), named: "Source", defaults: defaults)
        let bookmark = try #require(try BookmarkPreferences.agentRecords(defaults: defaults).first)
        let (connection, session) = try f.connect(capabilities: [.appearanceRead, .appearanceManage, .filesRead, .destructiveRequest])
        let target = AgentResourceReference(kind: .theme, id: first.definition.id)
        let originalVersion = try fixture.themeToken(target.id, session: session)
        guard case .array(let rows) = try f.values("themes.list", session: session)["items"], case .object(let row) = rows.first else { Issue.record("Missing theme"); return }
        #expect(row["versionToken"] == .string(originalVersion))
        let permissionKey = ThemeFileAccess.bookmarkKey(for: target.id)
        #expect(defaults.data(forKey: permissionKey) != second.bookmark)
        let operation = mode.hasPrefix("replace") ? "themes.replace" : mode == "deleteReview" ? "themes.delete" : mode == "select" ? "themes.select" : "themes.reload"
        var parameters: [String: AgentJSONValue] = [:]
        var expected = originalVersion
        if mode.hasPrefix("replace") {
            parameters = ["mode": .string("file"), "source": .object(["kind": .string("bookmark"), "bookmarkID": .string(bookmark.id.uuidString), "path": .string("Second.json")])]
        }
        if mode == "select" { expected = try fixture.token("light", session: session); parameters = ["appearance": .string("light"), "expectedThemeVersion": .string(originalVersion)] }
        var request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: operation, targets: [target], expectedVersion: expected, parameters: parameters)
        if mode == "deleteReview" { request = try f.preparedMutation(request, session: session) }
        var accepted: UUID?
        if ["replaceQueued", "deleteReview"].contains(mode) {
            guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing operation"); return }
            accepted = id
            if mode == "deleteReview" {
                let reviewDeadline = ContinuousClock.now + .seconds(5)
                while approvals.pendingFromUserInterface().isEmpty, ContinuousClock.now < reviewDeadline {
                    try await Task.sleep(for: .milliseconds(1))
                }
                try #require(!approvals.pendingFromUserInterface().isEmpty)
            }
        }
        defaults.set(second.bookmark, forKey: permissionKey)
        let revision = defaults.integer(forKey: ThemeCatalog.revisionKey), references = defaults.data(forKey: EditorThemePreferences.key)
        if let accepted {
            if mode == "deleteReview" {
                let review = try #require(approvals.pendingFromUserInterface().first)
                try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
            }
            let result = try await fixture.wait(accepted, connection: connection.id)
            #expect(result.state == .failed && result.error == .versionConflict)
        } else { #expect(try f.send(request, session: session).outcome == .error(.versionConflict)) }
        let currentVersion = try fixture.themeToken(target.id, session: session)
        #expect(currentVersion != originalVersion)
        guard case .array(let updatedRows) = try f.values("themes.list", session: session)["items"], case .object(let updated) = updatedRows.first else { Issue.record("Missing current theme"); return }
        #expect(updated["versionToken"] == .string(currentVersion))
        #expect(defaults.data(forKey: permissionKey) == second.bookmark && f.library.themes == [first.definition])
        #expect(defaults.integer(forKey: ThemeCatalog.revisionKey) == revision && defaults.data(forKey: EditorThemePreferences.key) == references)
    }

    @Test(arguments: [false, true], ["light", "dark"])
    func selectionPreservesTheOtherSlotAndRecoveryNeverReapplies(builtIn: Bool, appearance: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        let selected = EditorThemeDefinition(name: "Selected café 🐼"), hidden = EditorThemeDefinition(name: "Private other slot", isDark: true)
        try f.library.saveTheme(selected); try f.library.saveTheme(hidden)
        let opposite = appearance == "light" ? "dark" : "light"
        let fields: [String: Any] = [opposite: ["type": "custom", "uuid": hidden.id.uuidString, "future": ["keep": true]],
            "future": [false, "café 🐼"] as [Any]]
        defaults.set(try JSONSerialization.data(withJSONObject: fields), forKey: EditorThemePreferences.key)
        defaults.set(7, forKey: ThemeCatalog.revisionKey); defaults.set("preserve", forKey: "unrelated")
        let (record, session) = try f.connect(scope: .resources(builtIn ? [] : [.init(kind: .theme, id: selected.id)]),
            capabilities: [.appearanceRead, .appearanceManage])
        let connection = record.id
        var parameters: [String: AgentJSONValue] = ["appearance": .string(appearance)]
        if builtIn { parameters["name"] = .string("Default") }
        else { parameters["expectedThemeVersion"] = .string(try fixture.themeToken(selected.id, session: session)) }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: builtIn ? "themes.selectBuiltIn" : "themes.select",
            targets: builtIn ? [] : [.init(kind: .theme, id: selected.id)], expectedVersion: try fixture.token(appearance, session: session), parameters: parameters)
        let before = f.library.themes
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing selection"); return }
        f.service.close(session)
        let result = try await fixture.wait(id, connection: connection)
        #expect(result.state == .succeeded && defaults.integer(forKey: ThemeCatalog.revisionKey) == 8)
        #expect(defaults.string(forKey: "unrelated") == "preserve" && f.library.themes == before)
        let storedData = try #require(defaults.data(forKey: EditorThemePreferences.key))
        let stored = try #require(JSONSerialization.jsonObject(with: storedData) as? [String: Any])
        let afterOther = try #require(stored[opposite] as? [String: Any])
        let beforeOther = try #require(fields[opposite] as? [String: Any])
        #expect(NSDictionary(dictionary: afterOther).isEqual(to: beforeOther))
        #expect(stored["future"] as? [AnyHashable] == fields["future"] as? [AnyHashable])
        let reopened = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { f.locked }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: fixture.root))
        f.operations = reopened; f.service = try f.makeService()
        let next = try f.service.authenticate(connectionID: connection, credential: #require(f.secrets[connection]))
        try EditorThemePreferences(defaults: defaults).set(reference: ["type": "builtIn", "name": "Light"],
            dark: appearance == "dark", themes: f.library.themes)
        let changed = defaults.data(forKey: EditorThemePreferences.key), revision = defaults.integer(forKey: ThemeCatalog.revisionKey)
        guard case .object(let values) = result.result else { Issue.record("Missing result"); return }
        #expect(try f.send(request, session: next).outcome == .result(.object(values)))
        #expect(defaults.data(forKey: EditorThemePreferences.key) == changed && defaults.integer(forKey: ThemeCatalog.revisionKey) == revision)
    }

    @Test(arguments: ["scope", "selectionVersion", "themeVersion", "corrupt", "revoked", "cancel"])
    func deniedOrStaleSelectionNeverWrites(reason: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        var theme = EditorThemeDefinition(name: "Selected")
        try f.library.saveTheme(theme)
        let (connection, session) = try f.connect(scope: .resources(reason == "scope" ? [] : [.init(kind: .theme, id: theme.id)]),
            capabilities: [.appearanceRead, .appearanceManage])
        let expectedTheme = reason == "scope" ? "not-visible" : try fixture.themeToken(theme.id, session: session)
        let version = try fixture.token("light", session: session)
        if reason == "themeVersion" { theme.foreground = "ABCDEF"; try f.library.saveTheme(theme) }
        if reason == "corrupt" { defaults.set(Data("broken".utf8), forKey: EditorThemePreferences.key) }
        let original = defaults.data(forKey: EditorThemePreferences.key), revision = defaults.integer(forKey: ThemeCatalog.revisionKey)
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.select",
            targets: [.init(kind: .theme, id: theme.id)], expectedVersion: reason == "selectionVersion" ? "old" : version,
            parameters: ["appearance": .string("light"), "expectedThemeVersion": .string(expectedTheme)])
        let response = try f.send(request, session: session)
        if reason == "cancel" || reason == "revoked" {
            guard case .accepted(let id, _) = response.outcome else { Issue.record("Missing selection"); return }
            if reason == "cancel" { #expect(try fixture.operations.cancel(id, connectionID: connection.id)) }
            else { _ = try f.connections.revokeFromUserInterface(connection.id) }
            for _ in 0..<1000 { await Task.yield() }
        } else {
            let error: AgentErrorCode = reason == "scope" ? .notFound : reason == "corrupt" ? .storageError : .versionConflict
            #expect(response.outcome == .error(error))
        }
        #expect(defaults.data(forKey: EditorThemePreferences.key) == original && defaults.integer(forKey: ThemeCatalog.revisionKey) == revision)
    }
    @Test(arguments: ["select", "changed", "denied"])
    func fileSelectionUsesCurrentAuthorizedBytes(mode: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        let url = fixture.root.appendingPathComponent("Theme.json")
        var source = EditorThemeDefinition(name: "File café 🐼")
        try JSONEncoder().encode(source).write(to: url)
        let prepared = try ThemeFileAccess.prepare(url)
        try ThemeFileAccess.install(prepared, in: f.library, defaults: defaults)
        let target = AgentResourceReference(kind: .theme, id: prepared.definition.id)
        let (_, reader) = try f.connect(scope: .resources([target]), capabilities: [.appearanceRead, .filesRead])
        let expectedTheme = try fixture.themeToken(target.id, session: reader)
        let capabilities: Set<AgentCapability> = mode == "denied" ? [.appearanceRead, .appearanceManage]
            : [.appearanceRead, .appearanceManage, .filesRead]
        let (connection, session) = try f.connect(scope: .resources([target]), capabilities: capabilities)
        let expectedSelection = try fixture.token("light", session: session)
        if mode == "changed" { source.foreground = "ABCDEF"; try JSONEncoder().encode(source).write(to: url) }
        let before = defaults.data(forKey: EditorThemePreferences.key), revision = defaults.integer(forKey: ThemeCatalog.revisionKey)
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.select", targets: [target],
            expectedVersion: expectedSelection, parameters: ["appearance": .string("light"), "expectedThemeVersion": .string(expectedTheme)])
        let response = try f.send(request, session: session)
        if mode == "select" {
            guard case .accepted(let id, _) = response.outcome else { Issue.record("Missing selection"); return }
            #expect(try await fixture.wait(id, connection: connection.id).state == .succeeded)
            #expect(EditorThemePreferences(defaults: defaults).reference(dark: false, themes: f.library.themes)["uuid"] as? String == target.id.uuidString)
            #expect(defaults.integer(forKey: ThemeCatalog.revisionKey) == revision &+ 1)
        } else {
            #expect(response.outcome == .error(mode == "denied" ? .permissionDenied : .versionConflict))
            #expect(defaults.data(forKey: EditorThemePreferences.key) == before && defaults.integer(forKey: ThemeCatalog.revisionKey) == revision)
        }
    }

    @Test(arguments: [false, true])
    func reloadPreservesReferencesAndRejectsStaleFile(stale: Bool) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        let url = fixture.root.appendingPathComponent("Reload.json")
        var source = EditorThemeDefinition(name: "Reload café 🐼")
        try JSONEncoder().encode(source).write(to: url)
        let prepared = try ThemeFileAccess.prepare(url)
        try ThemeFileAccess.install(prepared, in: f.library, defaults: defaults)
        let target = AgentResourceReference(kind: .theme, id: prepared.definition.id)
        defaults.set(Data("opaque preserved reference".utf8), forKey: EditorThemePreferences.key)
        defaults.set(12, forKey: ThemeCatalog.revisionKey)
        let references = defaults.data(forKey: EditorThemePreferences.key), themes = f.library.themes
        let (connection, session) = try f.connect(scope: .resources([target]), capabilities: [.appearanceRead, .appearanceManage, .filesRead])
        let version = try fixture.themeToken(target.id, session: session)
        if stale { source.foreground = "ABCDEF"; try JSONEncoder().encode(source).write(to: url) }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.reload", targets: [target], expectedVersion: version)
        let response = try f.send(request, session: session)
        if stale {
            #expect(response.outcome == .error(.versionConflict))
            #expect(defaults.integer(forKey: ThemeCatalog.revisionKey) == 12)
        } else {
            guard case .accepted(let id, _) = response.outcome else { Issue.record("Missing reload"); return }
            let result = try await fixture.wait(id, connection: connection.id)
            #expect(result.state == .succeeded)
            #expect(defaults.integer(forKey: ThemeCatalog.revisionKey) == 13)
            source.foreground = "FEDCBA"; try JSONEncoder().encode(source).write(to: url)
            guard case .object(let values) = result.result else { Issue.record("Missing result"); return }
            #expect(try f.send(request, session: session).outcome == .result(.object(values)))
            #expect(defaults.integer(forKey: ThemeCatalog.revisionKey) == 13)
        }
        #expect(defaults.data(forKey: EditorThemePreferences.key) == references)
        #expect(f.library.themes == themes)
    }

    @Test func reloadInvalidatesTheWindowPresentationCache() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        let url = fixture.root.appendingPathComponent("Visible.json")
        var source = EditorThemeDefinition(name: "Visible café 🐼", background: "112233")
        try JSONEncoder().encode(source).write(to: url)
        let prepared = try ThemeFileAccess.prepare(url)
        try ThemeFileAccess.install(prepared, in: f.library, defaults: defaults)
        try EditorThemePreferences(defaults: defaults).set(reference: ["type": "file", "uuid": prepared.definition.id.uuidString], dark: false, themes: f.library.themes)
        let model = WindowModel(library: f.library, dependencies: WindowDependencies(preferences: WindowPreferences(defaults: defaults)))
        #expect(model.editorThemePresentation(systemIsDark: false).theme?.background == "112233")
        source.background = "445566"; try JSONEncoder().encode(source).write(to: url)
        #expect(model.editorThemePresentation(systemIsDark: false).theme?.background == "112233")
        let target = AgentResourceReference(kind: .theme, id: prepared.definition.id)
        let (connection, session) = try f.connect(scope: .resources([target]), capabilities: [.appearanceRead, .appearanceManage, .filesRead])
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.reload", targets: [target], expectedVersion: try fixture.themeToken(target.id, session: session))
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing reload"); return }
        #expect(try await fixture.wait(id, connection: connection.id).state == .succeeded)
        #expect(model.editorThemePresentation(systemIsDark: false).theme?.background == "445566")
    }

    @Test(arguments: ["scope", "files", "custom", "invalid", "renamed"])
    func deniedReloadDoesNotChangePreferences(reason: String) throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        let url = fixture.root.appendingPathComponent("Denied.json")
        var source = EditorThemeDefinition(name: "Denied")
        try JSONEncoder().encode(source).write(to: url)
        let definition: EditorThemeDefinition
        if reason == "custom" { try f.library.saveTheme(source); definition = source }
        else {
            let prepared = try ThemeFileAccess.prepare(url)
            try ThemeFileAccess.install(prepared, in: f.library, defaults: defaults)
            definition = prepared.definition
        }
        let target = AgentResourceReference(kind: .theme, id: definition.id)
        let (_, readSession) = try f.connect(scope: .resources([target]), capabilities: [.appearanceRead, .filesRead])
        let version = try fixture.themeToken(target.id, session: readSession)
        if reason == "invalid" { try Data("invalid".utf8).write(to: url) }
        if reason == "renamed" { source.name = "Changed name"; try JSONEncoder().encode(source).write(to: url) }
        let caps: Set<AgentCapability> = reason == "files" ? [.appearanceRead, .appearanceManage] : [.appearanceRead, .appearanceManage, .filesRead]
        let (_, session) = try f.connect(scope: .resources(reason == "scope" ? [] : [target]), capabilities: caps)
        let before = defaults.persistentDomain(forName: f.editorDefaultsName) ?? [:]
        let response = try f.send(AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.reload", targets: [target], expectedVersion: version), session: session)
        guard case .error = response.outcome else { Issue.record("Reload must fail"); return }
        #expect(NSDictionary(dictionary: defaults.persistentDomain(forName: f.editorDefaultsName) ?? [:]).isEqual(to: before))
    }

    @Test(arguments: ["writeError", "stopWork"])
    func uncertainPreferenceWritesCannotBeRepeated(mode: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        var writes = 0
        f.preferenceStorage = AgentPreferenceStorage(read: { defaults.persistentDomain(forName: f.editorDefaultsName) ?? [:] },
            replace: { [weak f] _, updated in
                guard let f else { throw AgentErrorCode.cancelled }
                writes += 1
                defaults.setPersistentDomain(updated, forName: f.editorDefaultsName)
                if mode == "writeError" { throw AgentErrorCode.storageError }
                f.service.invalidateAll()
                return true
            })
        f.service = try f.makeService()
        let (connection, session) = try f.connect(capabilities: [.appearanceRead, .appearanceManage])
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.selectBuiltIn",
            expectedVersion: try fixture.token("light", session: session), parameters: ["appearance": .string("light"), "name": .string("Dark")])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing selection"); return }
        let result = try await fixture.wait(id, connection: connection.id)
        #expect(result.state == .outcomeUnknown && result.result == nil && writes == 1)
        #expect(EditorThemePreferences(defaults: defaults).reference(dark: false, themes: f.library.themes)["name"] as? String == "Dark")
        let next = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        #expect(try f.send(request, session: next).outcome == .error(.outcomeUnknown))
        #expect(writes == 1)
    }

    @Test func sequentialSelectionsReleaseCapacityAndKeepEveryRetryIdentity() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let f = fixture.f, defaults = fixture.defaults
        let (connection, session) = try f.connect(scope: .resources([]), capabilities: [.appearanceRead, .appearanceManage])
        var requests: [AgentRequest] = []
        for _ in 0..<140 {
            let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.selectBuiltIn",
                expectedVersion: try fixture.token("light", session: session), parameters: ["appearance": .string("light"), "name": .string("Default")])
            guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing selection"); return }
            #expect(try await fixture.wait(id, connection: connection.id).state == .succeeded)
            requests.append(request)
        }
        let revision = defaults.integer(forKey: ThemeCatalog.revisionKey)
        #expect(revision == 140)
        for request in requests {
            guard case .result = try f.send(request, session: session).outcome else { Issue.record("Missing recovered selection"); return }
        }
        #expect(defaults.integer(forKey: ThemeCatalog.revisionKey) == revision)
    }

}
