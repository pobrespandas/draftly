import Foundation
import Testing
import Security
import LocalAuthentication
import AgentContracts
import AgentLocalSecurity
@testable import Draftly

@Suite("Device-local agent credential keychain") @MainActor
struct AgentCredentialKeychainTests {
    @MainActor private final class Fixture {
        var identities: [AgentCredentialRole] = []
        var queries: [(String, [String: Any])] = []
        var items: [String: Data] = [:]
        var copyResult: (OSStatus, Any?)?
        var addStatus: OSStatus = errSecSuccess
        var removeStatus: OSStatus = errSecSuccess
        var denied = false
        func store(_ role: AgentCredentialRole = .application) -> AgentCredentialKeychain {
            AgentCredentialKeychain(role: role, backend: .init(validateIdentity: { [unowned self] role in
                self.identities.append(role)
                if self.denied { throw AgentErrorCode.permissionDenied }
            }, copy: { [unowned self] query in
                self.queries.append(("copy", query))
                if let copyResult = self.copyResult { return copyResult }
                if let account = query[kSecAttrAccount as String] as? String, let data = self.items[account] { return (errSecSuccess, data) }
                return (errSecItemNotFound, nil)
            }, add: { [unowned self] query in
                self.queries.append(("add", query))
                guard self.addStatus == errSecSuccess else { return self.addStatus }
                guard let account = query[kSecAttrAccount as String] as? String,
                      let data = query[kSecValueData as String] as? Data else { return errSecParam }
                guard self.items[account] == nil else { return errSecDuplicateItem }
                self.items[account] = data; return errSecSuccess
            }, remove: { [unowned self] query in
                self.queries.append(("remove", query))
                guard self.removeStatus == errSecSuccess else { return self.removeStatus }
                guard let account = query[kSecAttrAccount as String] as? String,
                      self.items.removeValue(forKey: account) != nil else { return errSecItemNotFound }
                return errSecSuccess
            }))
        }
    }

    @Test func allQueriesUseTheExactDeviceLocalGroupAndForbidAuthenticationUI() throws {
        let f = Fixture(), store = f.store(), id = UUID(), secret = Data(repeating: 7, count: 32)
        try store.create(id, credential: secret)
        #expect(try store.read(id) == secret)
        try store.remove(id)
        #expect(f.queries.map(\.0) == ["add", "copy", "remove"])
        for (_, query) in f.queries {
            #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
            #expect(query[kSecAttrService as String] as? String == "com.pobrespandas.draftly.agent-connections.v1")
            #expect(query[kSecAttrAccount as String] as? String == id.uuidString.lowercased())
            #expect(query[kSecAttrAccessGroup as String] as? String == "NM92LU2KKV.com.pobrespandas.draftly.agent-access")
            #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
            #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
            #expect(query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            #expect((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
            #expect(query[kSecAttrAccess as String] == nil)
        }
        let read = f.queries[1].1, removal = f.queries[2].1
        #expect(read[kSecReturnData as String] as? Bool == true)
        #expect(read[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        #expect(read[kSecValueData as String] == nil && removal[kSecValueData as String] == nil)
        #expect(f.identities == [.application, .application, .application])
    }

    @Test func createIsExclusiveAndCannotOverwriteAnotherCredential() throws {
        let f = Fixture(), store = f.store(), id = UUID(), original = Data(repeating: 1, count: 32)
        try store.create(id, credential: original)
        #expect(throws: AgentErrorCode.versionConflict) { try store.create(id, credential: Data(repeating: 2, count: 32)) }
        #expect(try store.read(id) == original)
        #expect(f.queries.map(\.0) == ["add", "add", "copy"])
    }

    @Test func helperCanReadButCannotCreateOrDelete() throws {
        let f = Fixture(), id = UUID(), app = f.store(), helper = f.store(.helper)
        let secret = Data(repeating: 9, count: 32)
        try app.create(id, credential: secret)
        #expect(try helper.read(id) == secret)
        #expect(throws: AgentErrorCode.permissionDenied) { try helper.create(id, credential: secret) }
        #expect(throws: AgentErrorCode.permissionDenied) { try helper.remove(id) }
        #expect(f.queries.map(\.0) == ["add", "copy"])
        #expect(f.identities == [.application, .helper])
    }

    @Test func identityFailureStopsAllKeychainCallsAndNeverFallsBack() throws {
        let f = Fixture(), store = f.store(), id = UUID()
        f.denied = true
        #expect(throws: AgentErrorCode.permissionDenied) { try store.create(id, credential: Data(repeating: 0, count: 32)) }
        #expect(throws: AgentErrorCode.permissionDenied) { try store.read(id) }
        #expect(throws: AgentErrorCode.permissionDenied) { try store.remove(id) }
        #expect(f.queries.isEmpty)
    }

    @Test func wrongCredentialLengthsAndMalformedKeychainValuesFailExplicitly() throws {
        let f = Fixture(), store = f.store(), id = UUID()
        for count in [0, 31, 33] {
            #expect(throws: AgentErrorCode.invalidInput) { try store.create(id, credential: Data(repeating: 1, count: count)) }
        }
        #expect(f.identities.isEmpty && f.queries.isEmpty)
        for data: Any? in [nil, "wrong type", Data(), Data(repeating: 1, count: 31), Data(repeating: 1, count: 33)] {
            f.copyResult = (errSecSuccess, data)
            #expect(throws: AgentErrorCode.storageError) { try store.read(id) }
        }
    }

    @Test func onlyItemNotFoundMeansAnAbsentCredentialAndDeletionIsIdempotent() throws {
        let f = Fixture(), store = f.store(), id = UUID()
        #expect(try store.read(id) == nil)
        try store.remove(id); try store.remove(id)
        f.copyResult = (errSecItemNotFound, Data(repeating: 1, count: 32))
        #expect(try store.read(id) == nil)
    }

    @Test func nativeFailuresKeepDistinctOutcomesWithoutRetriesOrUpdates() throws {
        let f = Fixture(), store = f.store(), id = UUID()
        let failures: [(OSStatus, AgentErrorCode)] = [
            (errSecInteractionNotAllowed, .interactionRequired), (errSecInteractionRequired, .interactionRequired),
            (errSecAuthFailed, .permissionDenied), (errSecMissingEntitlement, .permissionDenied),
            (errSecUserCanceled, .cancelled), (errSecNotAvailable, .unavailable), (errSecParam, .storageError)
        ]
        for (status, error) in failures {
            let before = f.queries.count
            f.copyResult = (status, nil); f.addStatus = status; f.removeStatus = status
            #expect(throws: error) { try store.read(id) }
            #expect(throws: error) { try store.create(id, credential: Data(repeating: 1, count: 32)) }
            #expect(throws: error) { try store.remove(id) }
            #expect(f.queries.count == before + 3)
        }
        #expect(f.items.isEmpty)
    }

    @Test func registryUsesDedicatedStoreWithoutPuttingCredentialsInMetadata() throws {
        let f = Fixture(), store = f.store(), libraryID = UUID(), now = Date(timeIntervalSince1970: 1_700_000_000)
        var metadata: Data?
        let registry = AgentConnectionRegistry(metadata: .init(read: { metadata }, replace: { data, expected in
            guard metadata == expected else { throw AgentErrorCode.versionConflict }; metadata = data
        }), credentials: store.registryAccess, now: { now }, authorityChanged: { _ in })
        let connection = try registry.connectFromUserInterface(name: "Neutral 🐼", libraryID: libraryID)
        let secret = try #require(f.items[connection.id.uuidString.lowercased()])
        #expect(secret.count == 32)
        #expect(!String(decoding: try #require(metadata), as: UTF8.self).contains(secret.base64EncodedString()))
        try registry.setEnabledFromUserInterface(true)
        #expect(try registry.authenticate(connection.id, candidate: secret, libraryID: libraryID).grantID == connection.grantID)
        _ = try registry.revokeFromUserInterface(connection.id)
        #expect(f.items.isEmpty)
        #expect(try registry.grantForAuthenticatedConnection(connection.id) == nil)
    }

    @Test func entitlementPolicyRequiresAnExactGroupAndRejectsDebugAndMalformedClaims() throws {
        let group = ["keychain-access-groups": [AgentCredentialIdentity.accessGroup]] as [String: Any]
        try AgentCredentialIdentity.validateEntitlements(group)
        for groups: Any in [[], ["NM92LU2KKV.*"], ["OTHER.com.pobrespandas.draftly.agent-access"],
                            ["NM92LU2KKV.com.pobrespandas.draftly.qa.agent-access"], AgentCredentialIdentity.accessGroup] {
            #expect(throws: AgentErrorCode.permissionDenied) { try AgentCredentialIdentity.validateEntitlements(["keychain-access-groups": groups]) }
        }
        for key in AgentCredentialIdentity.prohibitedEntitlements {
            for invalid: Any in [true, "false", 0, 1] {
                var values = group; values[key] = invalid
                #expect(throws: AgentErrorCode.permissionDenied) { try AgentCredentialIdentity.validateEntitlements(values) }
            }
            var values = group; values[key] = false
            try AgentCredentialIdentity.validateEntitlements(values)
        }
    }

    @Test func signingRequirementsPinTeamAndSeparateApplicationAndHelperIdentities() {
        #expect(AgentCredentialIdentity.requirement(for: .application) ==
            "anchor apple generic and certificate leaf[subject.OU] = \"NM92LU2KKV\" and identifier \"com.pobrespandas.draftly\"")
        #expect(AgentCredentialIdentity.requirement(for: .helper) ==
            "anchor apple generic and certificate leaf[subject.OU] = \"NM92LU2KKV\" and identifier \"com.pobrespandas.draftly.agent\"")
        for role: AgentCredentialRole in [.application, .helper] {
            var requirement: SecRequirement?
            #expect(SecRequirementCreateWithString(AgentCredentialIdentity.requirement(for: role) as CFString,
                SecCSFlags(rawValue: 0), &requirement) == errSecSuccess)
            #expect(requirement != nil)
        }
    }

    @Test func actualTestProcessCannotReachKeychainThroughProductionIdentityValidation() {
        let backend = AgentCredentialKeychain.Backend(validateIdentity: AgentCredentialIdentity.validateCurrentProcess,
            copy: { _ in Issue.record("A test process reached the real-identity copy boundary."); return (errSecSuccess, nil) },
            add: { _ in Issue.record("A test process reached the real-identity add boundary."); return errSecSuccess },
            remove: { _ in Issue.record("A test process reached the real-identity remove boundary."); return errSecSuccess })
        let store = AgentCredentialKeychain(role: .application, backend: backend)
        #expect(throws: AgentErrorCode.permissionDenied) { try store.read(UUID()) }
        #expect(throws: AgentErrorCode.permissionDenied) { try store.create(UUID(), credential: Data(repeating: 1, count: 32)) }
        #expect(throws: AgentErrorCode.permissionDenied) { try store.remove(UUID()) }
    }
}
