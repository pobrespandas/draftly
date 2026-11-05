import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Agent preference storage") @MainActor
struct AgentPreferenceStorageTests {
    @Test func changedSettingsRejectTheBatchBeforeWriting() throws {
        var values: [String: Any] = ["editor.fontSize": 17]
        var writes = 0
        let store = AgentPreferenceStorage(read: { values }, replace: { _, updated in writes += 1; values = updated; return true })
        let before = try store.snapshot()
        values["editor.fontSize"] = 21
        #expect(throws: AgentErrorCode.versionConflict) {
            try store.commit(["editor.fontSize": .scalar(.integer(23))], against: before, authorize: {})
        }
        #expect(writes == 0 && values["editor.fontSize"] as? Int == 21)
    }

    @Test func finalValidationFailureDoesNotWriteThePreferenceDomain() throws {
        var values: [String: Any] = ["keep": 7]
        var writes = 0
        let store = AgentPreferenceStorage(read: { values }, replace: { _, updated in
            writes += 1; values = updated; return true
        })
        let before = try store.snapshot()
        #expect(throws: AgentErrorCode.versionConflict) {
            try store.commit(["changed": .scalar(.bool(true))], against: before,
                validateCommit: { throw AgentErrorCode.versionConflict }, authorize: {})
        }
        #expect(writes == 0 && values["keep"] as? Int == 7 && values["changed"] == nil)
    }

    @Test func writeFailureAndLostAuthorityKeepTheAppliedValueUnknown() throws {
        var values: [String: Any] = [:]
        let failing = AgentPreferenceStorage(read: { values }, replace: { _, updated in
            values = updated; throw AgentErrorCode.storageError
        })
        let before = try failing.snapshot()
        #expect(throws: AgentErrorCode.outcomeUnknown) {
            try failing.commit(["editor.fontSize": .scalar(.integer(23))], against: before, authorize: {})
        }
        #expect(values["editor.fontSize"] as? NSNumber == 23)
        var allowed = true
        let revoked = AgentPreferenceStorage(read: { values }, replace: { _, updated in
            values = updated; allowed = false; return true
        })
        let second = try revoked.snapshot()
        #expect(throws: AgentErrorCode.outcomeUnknown) {
            try revoked.commit(["editor.fontSize": .scalar(.integer(25))], against: second,
                authorize: { if !allowed { throw AgentErrorCode.permissionDenied } })
        }
        #expect(values["editor.fontSize"] as? NSNumber == 25)
    }

    @Test func realDomainPreservesUnknownValuesAndResetsOnlyReviewedKeys() throws {
        let domain = "Draftly-Preference-Storage-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let bytes = Data([0, 1, 255]), date = Date(timeIntervalSinceReferenceDate: 12345.5)
        defaults.setPersistentDomain(["future": ["bytes": bytes, "date": date], "remove": true], forName: domain)
        let store = try AgentPreferenceStorage(defaults: defaults, domain: domain)
        let before = try store.snapshot()
        #expect(try store.snapshot().version == before.version)
        let after = try store.commit(["remove": .remove, "editor.fontSize": .scalar(.number(Decimal(string: "23.5")!))],
            against: before, authorize: {})
        #expect(after.version != before.version)
        let actual = try #require(defaults.persistentDomain(forName: domain))
        let future = try #require(actual["future"] as? [String: Any])
        #expect(future["bytes"] as? Data == bytes && future["date"] as? Date == date)
        #expect(actual["remove"] == nil && defaults.double(forKey: "editor.fontSize") == 23.5)
    }

    @Test func comparisonRejectsAChangeAtTheStorageBoundary() throws {
        var values: [String: Any] = ["editor.fontSize": 17]
        let store = AgentPreferenceStorage(read: { values }, replace: { _, _ in
            values["editor.fontSize"] = 31
            return false
        })
        let before = try store.snapshot()
        #expect(throws: AgentErrorCode.versionConflict) {
            try store.commit(["editor.fontSize": .scalar(.integer(23))], against: before, authorize: {})
        }
        #expect(values["editor.fontSize"] as? Int == 31)
    }

    @Test func snapshotsPreserveRawTypesAndHaveStableKeyOrder() throws {
        var values: [String: Any] = ["flag": true, "legacy": "first"]
        let store = AgentPreferenceStorage(read: { values }, replace: { _, updated in values = updated; return true })
        let first = try store.snapshot()
        values = ["legacy": "first", "flag": true]
        #expect(try store.snapshot().version == first.version)
        values["flag"] = NSNumber(value: 1)
        #expect(try store.snapshot().version != first.version)
        let number = try store.snapshot()
        values["legacy"] = "second"
        #expect(try store.snapshot().version != number.version)
    }

    @Test func reentrantCommitCannotReplaceTheOuterBatch() throws {
        var values: [String: Any] = [:]
        let store = AgentPreferenceStorage(read: { values }, replace: { _, updated in values = updated; return true })
        let before = try store.snapshot()
        var checked = false
        _ = try store.commit(["editor.fontSize": .scalar(.integer(23))], against: before, authorize: {
            guard !checked else { return }; checked = true
            #expect(throws: AgentErrorCode.busy) {
                try store.commit(["editor.fontSize": .scalar(.integer(99))], against: before, authorize: {})
            }
        })
        #expect(checked && values["editor.fontSize"] as? NSNumber == 23)
    }

    @Test func unrepresentableNumberCannotStartAWrite() throws {
        var writes = 0
        let store = AgentPreferenceStorage(read: { [:] }, replace: { _, _ in writes += 1; return true })
        let before = try store.snapshot()
        let decimal = try #require(Decimal(string: "1.234567890123456789"))
        #expect(throws: AgentErrorCode.invalidInput) {
            try store.commit(["editor.fontSize": .scalar(.number(decimal))], against: before, authorize: {})
        }
        #expect(writes == 0)
    }
}
