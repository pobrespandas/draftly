import Foundation
import Testing
import AgentContracts
import DraftlyCore
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
            for _ in 0..<1000 where try !operations.snapshot(id, connectionID: connection).state.isTerminal { await Task.yield() }
            return try operations.snapshot(id, connectionID: connection)
        }
        func close() {
            operations.cancelAll(); f.operations?.cancelAll(); f.service = nil
            f.operations = nil; f.preferenceStorage = nil
            f.cleanEditorPreferences(); try? FileManager.default.removeItem(at: root)
        }
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
