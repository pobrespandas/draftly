import Foundation
import Testing
@testable import AgentContracts

@Suite("Agent capability and target isolation")
struct AgentPermissionPolicyTests {
    private let connection = UUID()
    private let library = UUID()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let draft = AgentResourceReference(kind: .draft, id: UUID())

    private func grant(_ capabilities: Set<AgentCapability>, scope: AgentResourceScope,
                       expiresAt: Date? = nil, revoked: Bool = false) -> AgentGrant {
        AgentGrant(connectionID: connection, libraryID: library,
            expiresAt: expiresAt ?? now.addingTimeInterval(60), revoked: revoked,
            capabilities: capabilities, scope: scope)
    }

    private func evaluate(_ operation: String, targets: [AgentResourceReference] = [], version: String? = nil,
                          grant: AgentGrant?, connectionID: UUID? = nil, libraryID: UUID? = nil) -> AgentPermissionDecision {
        AgentPermissionPolicy.evaluate(AgentRequest(requestID: UUID(), libraryID: libraryID ?? library,
            operation: operation, targets: targets, expectedVersion: version),
            connectionID: connectionID ?? connection, grant: grant, now: now)
    }

    @Test func readGrantDoesNotAuthorizeWritingOrActionExecution() {
        let access = grant([.draftsRead], scope: .resources([draft]))
        #expect(evaluate("drafts.get", targets: [draft], grant: access) == .permitted(.resources([draft])))
        #expect(evaluate("drafts.update", targets: [draft], version: "v1", grant: access) == .denied(.permissionDenied))
        #expect(evaluate("actions.run", grant: access) == .denied(.permissionDenied))
    }

    @Test func queryDecisionRetainsTheFilterRatherThanAuthorizingTheWholeLibrary() {
        let scope = AgentResourceScope.resources([draft])
        #expect(evaluate("drafts.search", grant: grant([.draftsRead], scope: scope)) == .permitted(scope))
        let outside = AgentResourceReference(kind: .draft, id: UUID())
        #expect(evaluate("drafts.get", targets: [outside], grant: grant([.draftsRead], scope: scope)) == .denied(.notFound))
    }

    @Test func resourceKindsDoNotShareAuthorityEvenWhenUUIDsMatch() {
        let scope = AgentResourceScope.resources([draft])
        let action = AgentResourceReference(kind: .action, id: draft.id)
        #expect(evaluate("actions.get", targets: [action], grant: grant([.actionsRead], scope: scope)) == .denied(.notFound))
        #expect(evaluate("drafts.get", targets: [action], grant: grant([.draftsRead], scope: .library)) == .denied(.invalidInput))
    }

    @Test func credentialsCannotCrossConnectionsLibrariesOrExpiry() {
        let access = grant([.draftsRead], scope: .library)
        #expect(evaluate("drafts.get", targets: [draft], grant: access, connectionID: UUID()) == .denied(.permissionDenied))
        #expect(evaluate("drafts.get", targets: [draft], grant: access, libraryID: UUID()) == .denied(.permissionDenied))
        #expect(evaluate("drafts.get", targets: [draft], grant: nil) == .denied(.permissionDenied))
        for date in [now, now.addingTimeInterval(-1)] {
            #expect(evaluate("drafts.get", targets: [draft], grant: grant([.draftsRead], scope: .library, expiresAt: date)) == .denied(.permissionDenied))
        }
        #expect(evaluate("drafts.get", targets: [draft], grant: grant([.draftsRead], scope: .library, revoked: true)) == .denied(.permissionDenied))
    }

    @Test func writesNeedAVersionAndPurgeNeedsSeparateCapabilityAndHumanApproval() {
        let access = grant([.draftsWrite], scope: .resources([draft]))
        #expect(evaluate("drafts.update", targets: [draft], grant: access) == .denied(.invalidInput))
        #expect(evaluate("drafts.update", targets: [draft], version: "v1", grant: access) == .permitted(.resources([draft])))
        #expect(evaluate("drafts.purge", targets: [draft], version: "v1", grant: access) == .denied(.permissionDenied))
        let purge = grant([.draftsWrite, .destructiveRequest], scope: .resources([draft]))
        #expect(evaluate("drafts.purge", targets: [draft], version: "v1", grant: purge) == .needsHumanApproval(.resources([draft])))
    }

    @Test func fullBackupCannotUseAnExplicitDraftSubset() {
        let caps: Set<AgentCapability> = [.backupsExport, .draftsRead, .actionsRead, .workspacesRead, .appearanceRead, .filesWrite]
        #expect(evaluate("backups.export", grant: grant(caps, scope: .resources([draft]))) == .denied(.permissionDenied))
        #expect(evaluate("backups.export", grant: grant(caps, scope: .library)) == .permitted(.library))
    }

    @Test func actionIdentityAndTargetDraftAreBothRequired() {
        let action = AgentResourceReference(kind: .action, id: UUID())
        let access = grant([.actionsRun, .draftsRead], scope: .resources([action, draft]))
        #expect(evaluate("actions.run", targets: [action], version: "v1", grant: access) == .denied(.invalidInput))
        #expect(evaluate("actions.run", targets: [draft, action], version: "v1", grant: access) == .needsEffectAuthorization(.resources([action, draft]), humanApproval: false))
    }

    @Test func nativeCapabilityNeverSubstitutesForDestinationOrUnrestrictedApproval() {
        let scoped = grant([.nativeUse], scope: .library)
        #expect(evaluate("native.http", grant: scoped) == .needsEffectAuthorization(.library, humanApproval: true))
        #expect(evaluate("native.shell", grant: scoped) == .denied(.permissionDenied))
        let unrestricted = grant([.nativeUse, .scriptsUnrestricted], scope: .library)
        #expect(evaluate("native.shell", grant: unrestricted) == .needsEffectAuthorization(.library, humanApproval: true))
    }

    @Test func noCapabilityAuthorizesAnUnknownOperation() {
        #expect(evaluate("agent.grantEverything", grant: grant(Set(AgentCapability.allCases), scope: .library)) == .denied(.unavailable))
    }

    @Test func preferenceChangesAndImportedPayloadsNeedContextualEffectChecks() {
        let settings = grant([.preferencesWrite], scope: .library)
        for name in ["preferences.update", "preferences.reset"] {
            #expect(evaluate(name, version: "v1", grant: settings) == .needsEffectAuthorization(.library, humanApproval: false))
        }
        let imported = grant([.draftsWrite, .filesRead], scope: .library)
        #expect(evaluate("imports.commit", version: "v1", grant: imported) == .needsEffectAuthorization(.library, humanApproval: false))
    }
    @Test func workspaceQueriesNeedDraftReadAuthorityAndApplicationNeedsEffectReview() {
        let workspace = AgentResourceReference(kind: .workspace, id: UUID())
        let window = AgentResourceReference(kind: .window, id: UUID())
        #expect(evaluate("workspaces.query", targets: [workspace],
            grant: grant([.workspacesRead], scope: .library)) == .denied(.permissionDenied))
        #expect(evaluate("workspaces.query", targets: [workspace],
            grant: grant([.workspacesRead, .draftsRead], scope: .library)) == .permitted(.library))
        #expect(evaluate("workspaces.apply", targets: [workspace, window], version: "snapshot",
            grant: grant([.workspacesApply, .presentUI], scope: .library))
            == .needsEffectAuthorization(.library, humanApproval: false))
    }

}
