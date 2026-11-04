import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Theme import preparation") @MainActor
struct AgentThemeImportPlanningTests {
    @Test(arguments: ["install", "replace", "stale", "name", "identity", "scope", "selection", "revoked"])
    func preparationChecksConflictsWithoutSaving(mode: String) throws {
        let f = try AgentCommandServiceTests.Fixture(); defer { f.cleanEditorPreferences() }
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        let reader = AgentThemeReading(library: f.library, defaults: defaults,
            pages: AgentReadPages(now: Date.init, uptime: { ProcessInfo.processInfo.systemUptime }))
        let original = EditorThemeDefinition(name: "Original café 🐼"), other = EditorThemeDefinition(name: "Other")
        try f.library.saveTheme(original); try f.library.saveTheme(other)
        let replacement = mode != "install"
        let target = AgentResourceReference(kind: .theme, id: original.id)
        let grant = AgentGrant(connectionID: UUID(), libraryID: f.libraryID, expiresAt: Date().addingTimeInterval(300),
            capabilities: [.appearanceManage, .filesRead], scope: .resources(mode == "scope" ? [] : [target]))
        var incoming = EditorThemeDefinition(name: "Incoming")
        if mode == "name" { incoming.name = other.name }
        if mode == "identity" { incoming.id = other.id }
        var parameters: [String: AgentJSONValue] = ["source": .object(["kind": .string("inline"), "text": .string("resolved input")])]
        if mode == "selection" { parameters["selectAppearance"] = .string("light"); parameters["expectedSelectionVersion"] = .string("stale") }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: replacement ? "themes.replace" : "themes.install",
            targets: replacement ? [target] : [], expectedVersion: replacement ? (mode == "stale" ? "stale" : try reader.version(original)) : nil, parameters: parameters)
        let before = try f.library.backupData(), preferences = defaults.persistentDomain(forName: f.editorDefaultsName) ?? [:]
        func prepare() throws -> AgentThemeImportPlanning.Plan {
            try AgentThemeImportPlanning.prepare(request, input: .definition(incoming), grant: grant,
                library: f.library, reader: reader, authorize: { if mode == "revoked" { throw AgentErrorCode.permissionDenied } })
        }
        if ["install", "replace"].contains(mode) {
            let plan = try prepare()
            #expect(plan.definition?.id == (replacement ? original.id : incoming.id))
            #expect(plan.definition?.name == "Incoming" && plan.bookmark == nil && plan.builtInName == nil)
        } else { #expect(throws: (any Error).self) { try prepare() } }
        #expect(try f.library.backupData() == before)
        #expect(NSDictionary(dictionary: defaults.persistentDomain(forName: f.editorDefaultsName) ?? [:]).isEqual(to: preferences))
    }

    @Test(arguments: [false, true])
    func filePlansKeepThePermissionAndExplicitReplacementIdentity(replace: Bool) throws {
        let f = try AgentCommandServiceTests.Fixture(); defer { f.cleanEditorPreferences() }
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let originalURL = root.appendingPathComponent("Original.json"), inputURL = root.appendingPathComponent("Input.json")
        try JSONEncoder().encode(EditorThemeDefinition(name: "Original file")).write(to: originalURL)
        try JSONEncoder().encode(EditorThemeDefinition(name: "Incoming file")).write(to: inputURL)
        let original = try ThemeFileAccess.prepare(originalURL), incoming = try ThemeFileAccess.prepare(inputURL)
        if replace { try ThemeFileAccess.install(original, in: f.library, defaults: defaults) }
        let reader = AgentThemeReading(library: f.library, defaults: defaults, pages: AgentReadPages(now: Date.init, uptime: { ProcessInfo.processInfo.systemUptime }))
        let bookmark = AgentResourceReference(kind: .bookmark, id: UUID()), target = AgentResourceReference(kind: .theme, id: original.definition.id)
        let grant = AgentGrant(connectionID: UUID(), libraryID: f.libraryID, expiresAt: Date().addingTimeInterval(300), capabilities: [.appearanceManage, .filesRead], scope: .resources([bookmark, target]))
        guard case .string(let selection) = try reader.selection(appearance: "light", grant: grant)["versionToken"] else { Issue.record("Missing selection token"); return }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: replace ? "themes.replace" : "themes.install", targets: replace ? [target] : [], expectedVersion: replace ? try reader.version(original.definition) : nil,
            parameters: ["mode": .string("file"), "source": .object(["kind": .string("bookmark"), "bookmarkID": .string(bookmark.id.uuidString), "path": .string("Input.json")]), "selectAppearance": .string("light"), "expectedSelectionVersion": .string(selection)])
        let before = try f.library.backupData(), preferences = defaults.persistentDomain(forName: f.editorDefaultsName) ?? [:]
        let plan = try AgentThemeImportPlanning.prepare(request, input: .file(incoming), grant: grant, library: f.library, reader: reader, authorize: {})
        #expect(plan.definition?.id == (replace ? original.definition.id : incoming.definition.id))
        #expect(plan.definition?.type == "file" && plan.bookmark == incoming.bookmark)
        #expect(plan.appearance == "light" && plan.selectionVersion == selection)
        #expect(try f.library.backupData() == before)
        #expect(NSDictionary(dictionary: defaults.persistentDomain(forName: f.editorDefaultsName) ?? [:]).isEqual(to: preferences))
    }

    @Test func builtInInputMustMatchItsInstallationLink() throws {
        let f = try AgentCommandServiceTests.Fixture(); defer { f.cleanEditorPreferences() }
        let defaults = try #require(UserDefaults(suiteName: f.editorDefaultsName))
        let reader = AgentThemeReading(library: f.library, defaults: defaults,
            pages: AgentReadPages(now: Date.init, uptime: { ProcessInfo.processInfo.systemUptime }))
        let grant = AgentGrant(connectionID: UUID(), libraryID: f.libraryID, expiresAt: Date().addingTimeInterval(300), capabilities: [.appearanceManage, .filesRead], scope: .resources([]))
        let url = try ThemeInstallation.builtIn("Dark").url.absoluteString
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.install",
            parameters: ["source": .object(["kind": .string("installationURL"), "url": .string(url)])])
        let plan = try AgentThemeImportPlanning.prepare(request, input: .builtIn("Dark"), grant: grant, library: f.library, reader: reader, authorize: {})
        #expect(plan.builtInName == "Dark" && plan.definition == nil && f.library.themes.isEmpty)
        #expect(throws: (any Error).self) {
            try AgentThemeImportPlanning.prepare(request, input: .builtIn("Light"), grant: grant, library: f.library, reader: reader, authorize: {})
        }
    }
}
