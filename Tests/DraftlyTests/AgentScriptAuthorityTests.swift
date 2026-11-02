import Foundation
import Testing
import AgentContracts
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
}
