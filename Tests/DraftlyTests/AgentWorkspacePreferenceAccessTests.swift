import Foundation
import CryptoKit
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

@Suite("Agent Workspace deletion access") @MainActor
struct AgentWorkspaceDeletionAccessTests {
    @Test func deletionBindsReviewToVersionAndRecoversWithoutAnotherEffect() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = try TestPreferences(prefix: "Agent-Workspace-Delete-")
        defer { preferences.close() }
        let library = try LibraryStore(directory: root, seed: false)
        let workspace = Workspace(name: "Delete café 🐼"), retained = Workspace(name: "Keep")
        try library.saveWorkspaces([workspace, retained])
        let note = try library.createNote(content: "Keep this draft")
        let libraryID = UUID(), connection = UUID(), clock = Date()
        let grant = AgentGrant(connectionID: connection, libraryID: libraryID,
            expiresAt: clock.addingTimeInterval(600), capabilities: [.workspacesManage, .destructiveRequest],
            scope: .resources([.init(kind: .workspace, id: workspace.id)]))
        let keys = AgentRetryKeys(currentGrant: { _ in grant }, isLocked: { false })
        let versionKey = SymmetricKey(size: .bits256)
        let access = AgentWorkspaceAccess(library: library, libraryID: libraryID, versionKey: versionKey,
            retryKeys: keys, defaults: preferences.defaults, validateAdmission: {}, now: { clock })
        let intent = AgentRequest(requestID: UUID(), libraryID: libraryID, operation: "workspaces.delete",
            targets: [.init(kind: .workspace, id: workspace.id)], expectedVersion: try access.version(workspace))
        let ticket = try access.prepareDeletion(intent, connectionID: connection)
        let request = AgentRequest(requestID: intent.requestID, libraryID: libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: intent.expectedVersion, retryKey: ticket.value)
        let journal = try AgentOperationJournal(parentDirectory: root)
        let operationID = UUID()
        _ = try journal.reserve(request, grant: grant, operationID: operationID)
        let effects = try access.deletionEffects(request, connectionID: connection)
        #expect(effects.snapshot["workspaceName"] == .string(workspace.name))
        #expect(effects.snapshot["deletesDrafts"] == .bool(false))
        #expect(effects.targets == Set(intent.targets) && !effects.requiresLibraryScope)
        #expect(throws: AgentErrorCode.cancelled) {
            try access.delete(request, connectionID: connection, validateCommit: { throw AgentErrorCode.cancelled })
        }
        #expect(library.workspaces.count == 2)
        #expect(try access.deletionReceipt(request, connectionID: connection) == nil)
        let receipt = try access.delete(request, connectionID: connection, validateCommit: {})
        #expect(library.workspaces == [retained] && library.notes == [note])
        let reopened = try LibraryStore(directory: root, seed: false)
        let nextAccess = AgentWorkspaceAccess(library: reopened, libraryID: libraryID, versionKey: versionKey,
            retryKeys: keys, defaults: preferences.defaults, validateAdmission: {}, now: { clock })
        #expect(try nextAccess.delete(request, connectionID: connection,
            validateCommit: { Issue.record("A completed deletion must not run again") }) == receipt)
        #expect(try nextAccess.prepareDeletion(intent, connectionID: connection).requestHash == ticket.requestHash)
        #expect(reopened.notes == [note] && reopened.workspaces == [retained])
        let registry = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: root))
        #expect(try registry.snapshot(operationID, connectionID: connection).state == .outcomeUnknown)
        let changedIntent = AgentRequest(requestID: request.requestID, libraryID: libraryID,
            operation: request.operation, targets: request.targets, expectedVersion: "changed")
        #expect(throws: AgentErrorCode.versionConflict) {
            try registry.recoverWorkspaceDeletion(changedIntent, grant: grant, receipt: receipt)
        }
        let wrongTarget = AgentRequest(requestID: request.requestID, libraryID: libraryID,
            operation: request.operation, targets: [.init(kind: .workspace, id: retained.id)], expectedVersion: request.expectedVersion)
        #expect(throws: AgentErrorCode.invalidInput) {
            try registry.recoverWorkspaceDeletion(wrongTarget, grant: grant, receipt: receipt)
        }
        #expect(try registry.snapshot(operationID, connectionID: connection).state == .outcomeUnknown)
        let recovered = try registry.recoverWorkspaceDeletion(request, grant: grant, receipt: receipt)
        #expect(recovered.state == .succeeded && recovered.effects.map(\.outcome) == ["completed"])
        #expect(recovered.result == .object(["deletedIDs": .array([.string(workspace.id.uuidString)])]))
        let finalRegistry = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false },
            journal: try AgentOperationJournal(parentDirectory: root))
        #expect(try finalRegistry.snapshot(operationID, connectionID: connection).wireValue() == recovered.wireValue())
        #expect(try finalRegistry.recoverWorkspaceDeletion(request, grant: grant, receipt: receipt).state == .succeeded)
    }

    @Test(arguments: ["approve", "deny", "cancel", "stale", "session"])
    func reviewedDeletionDoesNotRunBeforeTheDecision(decision: String) async throws {
        let preferences = try TestPreferences(prefix: "Agent-Workspace-Delete-Review-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        var workspace = Workspace(name: "Review café 🐼")
        try library.saveWorkspace(workspace)
        let note = try library.createNote(content: "Preserve")
        let libraryID = UUID(), connection = UUID()
        let grant = AgentGrant(connectionID: connection, libraryID: libraryID,
            expiresAt: Date().addingTimeInterval(600), capabilities: [.workspacesManage, .destructiveRequest],
            scope: .resources([.init(kind: .workspace, id: workspace.id)]))
        let keys = AgentRetryKeys(currentGrant: { _ in grant }, isLocked: { false })
        let access = AgentWorkspaceAccess(library: library, libraryID: libraryID, versionKey: .init(size: .bits256),
            retryKeys: keys, defaults: preferences.defaults, validateAdmission: {}, now: Date.init)
        let intent = AgentRequest(requestID: UUID(), libraryID: libraryID, operation: "workspaces.delete",
            targets: [.init(kind: .workspace, id: workspace.id)], expectedVersion: try access.version(workspace))
        let ticket = try access.prepareDeletion(intent, connectionID: connection)
        let request = AgentRequest(requestID: intent.requestID, libraryID: libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: intent.expectedVersion, retryKey: ticket.value)
        let approvals = AgentApprovalStore(currentGrant: { _ in grant }, isLocked: { false })
        let operations = AgentOperationRegistry(currentGrant: { _ in grant }, validateHost: {}, isLocked: { false })
        defer { operations.cancelAll() }
        var sessionValid = true
        let id = try operations.startValueRequest(request, grant: grant) { operationID in
            try await access.reviewAndDelete(request, connectionID: connection, operationID: operationID,
                approvals: approvals, operations: operations, validateSession: {
                    guard sessionValid else { throw AgentErrorCode.permissionDenied }
                })
        }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        #expect(try operations.snapshot(id, connectionID: connection).state == .waitingForUser)
        #expect(library.workspaces == [workspace] && library.notes == [note])
        switch decision {
        case "cancel": _ = try operations.cancel(id, connectionID: connection)
        case "deny": try approvals.denyFromUserInterface(review.id)
        default:
            if decision == "stale" { workspace.name = "Changed"; try library.saveWorkspace(workspace) }
            if decision == "session" { sessionValid = false }
            try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        }
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: connection).state.isTerminal {
            try await Task.sleep(for: .milliseconds(1))
        }
        let result = try operations.snapshot(id, connectionID: connection)
        #expect(result.state.isTerminal)
        #expect(library.notes == [note])
        if decision == "approve" {
            #expect(result.state == .succeeded && library.workspaces.isEmpty)
            #expect(result.effects.map(\.outcome) == ["completed"])
            #expect(result.result == .object(["deletedIDs": .array([.string(workspace.id.uuidString)])]))
        } else {
            #expect(library.workspaces == [workspace] && result.effects.isEmpty)
            let expected: AgentErrorCode = decision == "cancel" ? .cancelled : decision == "stale" ? .versionConflict : .permissionDenied
            #expect(result.error == expected)
        }
        #expect(approvals.pendingFromUserInterface().isEmpty)
        #expect(try operations.existingRequest(request, grant: grant) == id)
    }

    @Test func staleOrRevokedRequestsCannotDelete() throws {
        let preferences = try TestPreferences(prefix: "Agent-Workspace-Delete-Stale-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        var workspace = Workspace(name: "Original")
        try library.saveWorkspace(workspace)
        let libraryID = UUID(), connection = UUID()
        var grant: AgentGrant? = AgentGrant(connectionID: connection, libraryID: libraryID,
            expiresAt: Date().addingTimeInterval(600), capabilities: [.workspacesManage, .destructiveRequest], scope: .library)
        let keys = AgentRetryKeys(currentGrant: { _ in grant }, isLocked: { false })
        let access = AgentWorkspaceAccess(library: library, libraryID: libraryID, versionKey: .init(size: .bits256),
            retryKeys: keys, defaults: preferences.defaults, validateAdmission: {}, now: Date.init)
        let intent = AgentRequest(requestID: UUID(), libraryID: libraryID, operation: "workspaces.delete",
            targets: [.init(kind: .workspace, id: workspace.id)], expectedVersion: try access.version(workspace))
        let ticket = try access.prepareDeletion(intent, connectionID: connection)
        let request = AgentRequest(requestID: intent.requestID, libraryID: libraryID, operation: intent.operation,
            targets: intent.targets, expectedVersion: intent.expectedVersion, retryKey: ticket.value)
        workspace.name = "Changed after preparation"
        try library.saveWorkspace(workspace)
        #expect(throws: AgentErrorCode.versionConflict) { try access.deletionEffects(request, connectionID: connection) }
        #expect(throws: AgentErrorCode.versionConflict) { try access.delete(request, connectionID: connection, validateCommit: {}) }
        grant = nil
        #expect(throws: AgentErrorCode.permissionDenied) { try access.deletionReceipt(request, connectionID: connection) }
        #expect(library.workspaces == [workspace])
    }
}
