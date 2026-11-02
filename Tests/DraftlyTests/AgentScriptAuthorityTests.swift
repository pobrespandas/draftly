import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent script draft authority") @MainActor
struct AgentScriptAuthorityTests {
    @Test func checksScopeCapabilitiesAndCurrentGrant() throws {
        let target = UUID(), other = UUID(), connection = UUID(), library = UUID(), id = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func grant(_ capabilities: Set<AgentCapability>, _ scope: AgentResourceScope, revoked: Bool = false) -> AgentGrant {
            .init(connectionID: connection, libraryID: library, expiresAt: now.addingTimeInterval(60), revoked: revoked,
                  capabilities: capabilities, scope: scope, grantID: id)
        }
        let allowed = grant([.actionsRun, .draftsRead, .draftsWrite], .resources([.init(kind: .draft, id: target)]))
        var current: AgentGrant? = allowed, locked = false
        let authority = AgentScriptAuthority(grant: allowed, currentGrant: { current }, validateHost: {},
            isLocked: { locked }, now: { now }, draftExists: { $0 == target || $0 == other })
        let payload = "{\"uuid\":\"\(target.uuidString)\"}"
        try authority.authorize("findDraft", payload: payload)
        try authority.authorize("updateDraft", payload: payload)
        #expect(throws: AgentErrorCode.notFound) {
            try authority.authorize("findDraft", payload: "{\"uuid\":\"\(other.uuidString)\"}")
        }
        try authority.authorize("queryDrafts", payload: "{}")
        #expect(throws: AgentErrorCode.unavailable) { try authority.authorize("renameTag", payload: "{}") }
        current = grant([.actionsRun, .draftsRead], .library)
        try authority.authorize("queryDrafts", payload: "{}")
        current = grant([.actionsRun, .draftsRead], allowed.scope)
        #expect(throws: AgentErrorCode.permissionDenied) { try authority.authorize("updateDraft", payload: payload) }
        current = grant([.actionsRun, .draftsWrite], allowed.scope)
        #expect(throws: AgentErrorCode.permissionDenied) { try authority.authorize("updateDraft", payload: payload) }
        current = grant([.actionsRun, .draftsRead, .draftsWrite], allowed.scope, revoked: true)
        #expect(throws: AgentErrorCode.permissionDenied) { try authority.authorize("findDraft", payload: payload) }
        current = allowed; locked = true
        #expect(throws: AgentErrorCode.permissionDenied) { try authority.authorize("findDraft", payload: payload) }
    }

    @Test func authorityChangesDuringResourceLookupDenyTheCall() throws {
        let target = UUID(), now = Date(timeIntervalSince1970: 1_700_000_000)
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: [.actionsRun, .draftsRead], scope: .resources([.init(kind: .draft, id: target)]))
        var current: AgentGrant? = grant
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { current }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { _ in current = nil; return true })
        #expect(throws: AgentErrorCode.permissionDenied) {
            try authority.authorize("findDraft", payload: "{\"uuid\":\"\(target.uuidString)\"}")
        }
    }

    @Test func queryCannotReturnAfterItsGrantIsRevoked() throws {
        let visible = Note(content: "Visible"), hidden = Note(content: "Hidden")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: [.actionsRun, .draftsRead], scope: .resources([.init(kind: .draft, id: visible.id)]))
        var checks = 0
        let authority = AgentScriptAuthority(grant: grant, currentGrant: {
            checks += 1; return checks < 4 ? grant : nil
        }, validateHost: {}, isLocked: { false }, now: { now }, draftExists: { _ in true })
        #expect(throws: AgentErrorCode.permissionDenied) { try authority.visibleDrafts([visible, hidden]) }
    }

    @Test func actionStepsAndCompletionRequireCurrentTargetAndPermissions() throws {
        let step = ActionStep("insertText", ["template": "Neutral"])
        let share = ActionStep("share")
        let draft = UUID(), action = DraftAction(name: "Write", steps: [step, share]), window = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000), connection = UUID(), library = UUID(), grantID = UUID()
        let scope = AgentResourceScope.resources([.init(kind: .draft, id: draft), .init(kind: .action, id: action.id),
                                                  .init(kind: .window, id: window)])
        func makeGrant(_ permissions: Set<AgentCapability>) -> AgentGrant {
            .init(connectionID: connection, libraryID: library, expiresAt: now.addingTimeInterval(60),
                  capabilities: permissions, scope: scope, grantID: grantID)
        }
        let full = makeGrant([.actionsRun, .draftsRead, .draftsWrite, .editorWrite, .actionsManage])
        var current: AgentGrant? = full, selected: UUID? = draft, currentDefinition = action
        let authority = AgentScriptAuthority(grant: full, currentGrant: { current }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { $0 == draft },
            targetDraftID: draft, editorDraftID: { selected }, windowID: window,
            approvedActions: [action.id: action], currentAction: { $0 == action.id ? currentDefinition : nil })
        try authority.authorizeStep(owner: action.id, step: step)
        try authority.authorizeCompletion(action, draftID: draft)
        try authority.authorizeConfiguration(action)
        #expect(throws: AgentErrorCode.notFound) { try authority.authorizeStep(owner: UUID(), step: step) }
        #expect(throws: AgentErrorCode.unavailable) { try authority.authorizeStep(owner: action.id, step: share) }
        currentDefinition.name = "Changed"
        #expect(throws: AgentErrorCode.versionConflict) { try authority.authorizeStep(owner: action.id, step: step) }
        currentDefinition = action
        selected = UUID()
        #expect(throws: AgentErrorCode.permissionDenied) { try authority.authorizeStep(owner: action.id, step: step) }
        selected = draft; current = makeGrant([.actionsRun, .draftsRead, .draftsWrite])
        #expect(throws: AgentErrorCode.permissionDenied) { try authority.authorizeStep(owner: action.id, step: step) }
        #expect(throws: AgentErrorCode.permissionDenied) { try authority.authorizeConfiguration(action) }
        current = nil
        #expect(throws: AgentErrorCode.permissionDenied) { try authority.authorizeCompletion(action, draftID: draft) }
    }

    @Test func catalogExcludesChangedAndUnapprovedDefinitions() throws {
        let action = DraftAction(name: "Approved", steps: []), other = DraftAction(name: "Other", steps: [])
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: [.actionsRun, .draftsRead], scope: .library)
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { _ in true }, approvedActions: [action.id: action])
        var changed = action; changed.name = "Changed"
        #expect(try authority.visibleActions([action, other]) == [action])
        #expect(try authority.visibleActions([changed, other]).isEmpty)
    }

    @Test func configurationRebindRejectsOtherDefinitionChanges() throws {
        let draft = UUID(), before = DraftAction(name: "Approved", steps: []), now = Date(timeIntervalSince1970: 1_700_000_000)
        var after = before; after.name = "Unapproved"; after.configuredValues["value"] = "neutral"
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: [.actionsRun, .draftsRead, .actionsManage],
            scope: .resources([.init(kind: .draft, id: draft), .init(kind: .action, id: before.id)]))
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { $0 == draft }, targetDraftID: draft,
            approvedActions: [before.id: before], currentAction: { $0 == before.id ? after : nil })
        #expect(throws: AgentErrorCode.versionConflict) { try authority.acceptConfiguredAction(before: before, after: after) }
        #expect(try authority.visibleActions([after]).isEmpty)
    }

    @Test(arguments: ["share", "openIn", "print"])
    func reviewedNativeStepsRequireNativePermissionAndCurrentDefinition(stepType: String) throws {
        let draft = UUID(), step = ActionStep(stepType)
        let action = DraftAction(name: "Reviewed", steps: [step])
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: [.actionsRun, .draftsRead, .nativeUse],
            scope: .resources([.init(kind: .draft, id: draft), .init(kind: .action, id: action.id)]))
        var current = grant, definition = action
        let operation = stepType == "openIn" ? "shareFile" : stepType
        func authority(reviewed: Bool) -> AgentScriptAuthority {
            AgentScriptAuthority(grant: grant, currentGrant: { current }, validateHost: {}, isLocked: { false },
                now: { now }, draftExists: { $0 == draft }, targetDraftID: draft,
                approvedActions: [action.id: action], currentAction: { $0 == action.id ? definition : nil },
                reviewedNativeEffects: reviewed)
        }
        let enabled = authority(reviewed: true)
        try enabled.authorizeStep(owner: action.id, step: step)
        try enabled.authorizeNative(operation, rootActionID: action.id)
        #expect(throws: AgentErrorCode.unavailable) {
            try authority(reviewed: false).authorizeStep(owner: action.id, step: step)
        }
        current = AgentGrant(connectionID: grant.connectionID, libraryID: grant.libraryID, expiresAt: grant.expiresAt,
            capabilities: [.actionsRun, .draftsRead], scope: grant.scope, grantID: grant.grantID)
        #expect(throws: AgentErrorCode.permissionDenied) { try enabled.authorizeStep(owner: action.id, step: step) }
        #expect(throws: AgentErrorCode.permissionDenied) { try enabled.authorizeNative(operation, rootActionID: action.id) }
        current = grant; definition.name = "Changed"
        #expect(throws: AgentErrorCode.versionConflict) { try enabled.authorizeNative(operation, rootActionID: action.id) }
    }

}
