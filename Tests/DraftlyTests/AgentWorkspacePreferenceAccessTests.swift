import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent default Workspace preference access") @MainActor
struct AgentWorkspacePreferenceAccessTests {
    private let capabilities: Set<AgentCapability> = [.preferencesRead, .preferencesWrite, .workspacesRead]

    @Test func absentAndInvalidValuesDoNotWriteOrInventAReference() throws {
        let preferences = try TestPreferences(prefix: "Agent-Workspace-Preference-")
        defer { preferences.close() }
        var lookups = 0
        let missing = try AgentWorkspacePreferenceAccess.read(defaults: preferences.defaults,
            capabilities: capabilities, scope: .library, workspaceExists: { _ in lookups += 1; return true })
        #expect(missing.effectiveValue == .null && missing.origin == "default" && !missing.hasOverride)
        #expect((preferences.defaults.persistentDomain(forName: preferences.name) ?? [:]).isEmpty)
        preferences.defaults.set("not UUID", forKey: WorkspaceDefaults.key)
        let invalid = try AgentWorkspacePreferenceAccess.read(defaults: preferences.defaults,
            capabilities: capabilities, scope: .library, workspaceExists: { _ in lookups += 1; return true })
        #expect(invalid.effectiveValue == .null && invalid.origin == "invalid" && invalid.hasOverride)
        #expect(lookups == 0 && preferences.defaults.string(forKey: WorkspaceDefaults.key) == "not UUID")
    }

    @Test func scopedReferencesAreCheckedBeforeLookupAndNeverLeakStoredIDs() throws {
        let preferences = try TestPreferences(prefix: "Agent-Workspace-Preference-")
        defer { preferences.close() }
        let id = UUID()
        preferences.defaults.set(id.uuidString, forKey: WorkspaceDefaults.key)
        var lookups = 0
        #expect(throws: AgentErrorCode.notFound) {
            try AgentWorkspacePreferenceAccess.read(defaults: preferences.defaults, capabilities: capabilities,
                scope: .resources([]), workspaceExists: { _ in lookups += 1; return true })
        }
        #expect(throws: AgentErrorCode.notFound) {
            try AgentWorkspacePreferenceAccess.prepare(value: .string(id.uuidString), capabilities: capabilities,
                scope: .resources([.init(kind: .draft, id: id)]), workspaceExists: { _ in lookups += 1; return true })
        }
        #expect(throws: AgentErrorCode.notFound) {
            try AgentWorkspacePreferenceAccess.prepare(value: .string(id.uuidString), capabilities: [.preferencesWrite],
                scope: .library, workspaceExists: { _ in lookups += 1; return true })
        }
        #expect(lookups == 0)
        let allowed = try AgentWorkspacePreferenceAccess.read(defaults: preferences.defaults, capabilities: capabilities,
            scope: .resources([.init(kind: .workspace, id: id)]), workspaceExists: { $0 == id })
        #expect(allowed.effectiveValue == .string(id.uuidString) && allowed.origin == "stored")
    }

    @Test func missingWorkspaceAndExplicitResetKeepTheirDistinctResults() throws {
        let preferences = try TestPreferences(prefix: "Agent-Workspace-Preference-")
        defer { preferences.close() }
        let id = UUID()
        preferences.defaults.set(id.uuidString.lowercased(), forKey: WorkspaceDefaults.key)
        let missing = try AgentWorkspacePreferenceAccess.read(defaults: preferences.defaults, capabilities: capabilities,
            scope: .library, workspaceExists: { _ in false })
        #expect(missing.effectiveValue == .null && missing.origin == "invalid")
        #expect(throws: AgentErrorCode.notFound) {
            try AgentWorkspacePreferenceAccess.prepare(value: .string(id.uuidString), capabilities: capabilities,
                scope: .library, workspaceExists: { _ in false })
        }
        for value in [AgentJSONValue?.none, .some(.null)] {
            let reset = try AgentWorkspacePreferenceAccess.prepare(value: value, capabilities: [.preferencesWrite],
                scope: .resources([]), workspaceExists: { _ in Issue.record("Reset must not look up a hidden reference"); return false })
            #expect(reset.storageKey == WorkspaceDefaults.key && reset.value == nil)
        }
        #expect(preferences.defaults.string(forKey: WorkspaceDefaults.key) == id.uuidString.lowercased())
        #expect(throws: AgentErrorCode.permissionDenied) {
            try AgentWorkspacePreferenceAccess.prepare(value: nil, capabilities: [], scope: .library, workspaceExists: { _ in true })
        }
    }

    @Test func preparedIdentityKeepsExistingWorkspaceCreationSemantics() throws {
        let preferences = try TestPreferences(prefix: "Agent-Workspace-Preference-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        var workspace = Workspace(name: "QA 語法"); workspace.query = "neutral"; workspace.order = 7
        try library.saveWorkspace(workspace)
        let change = try AgentWorkspacePreferenceAccess.prepare(value: .string(workspace.id.uuidString.lowercased()),
            capabilities: capabilities, scope: .library, workspaceExists: { id in library.workspaces.contains { $0.id == id } })
        preferences.defaults.set(change.value, forKey: change.storageKey)
        let created = WorkspaceDefaults.make(in: library, defaults: preferences.defaults)
        #expect(created.id != workspace.id && created.name.isEmpty && created.order == nil)
        #expect(created.query == "neutral" && library.workspaces.first?.name == "QA 語法")
    }
}
