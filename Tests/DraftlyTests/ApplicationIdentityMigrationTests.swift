import Foundation
import Testing
@testable import Draftly

@Suite("Main application identity migration") @MainActor
struct ApplicationIdentityMigrationTests {
    private final class MemoryDomains {
        var values: [String: [String: Any]] = [:]
        var writes = 0
        var failWrite: Int?
        var discardWrites = false
        var failRead = false
        var adapter: ApplicationIdentityMigration.Domains {
            .init(read: { domain in
                if self.failRead { throw ApplicationIdentityMigration.MigrationError.persistence }
                return self.values[domain]
            }, write: { domain, values in
                self.writes += 1
                if self.writes == self.failWrite { throw ApplicationIdentityMigration.MigrationError.persistence }
                if !self.discardWrites { self.values[domain] = values }
            })
        }
    }
    private let source = ApplicationIdentityMigration.legacyIdentifier
    private let destination = ApplicationIdentityMigration.identifier
    private let marker = ApplicationIdentityMigration.completionKey

    @Test func copiesUnknownValuesAndPreservesSource() throws {
        let store = MemoryDomains()
        let original: [String: Any] = ["font": "Neutral Nerd Font", "capture": "línea 🐼\n二",
            "bookmark": Data([0, 255, 3]), "unknown": ["nested": [1, 2, 3]]]
        store.values[source] = original
        #expect(try ApplicationIdentityMigration.migrate(domains: store.adapter))
        var expected = original; expected[marker] = true
        #expect(NSDictionary(dictionary: try #require(store.values[destination])).isEqual(to: expected))
        #expect(NSDictionary(dictionary: try #require(store.values[source])).isEqual(to: original))
    }

    @Test func explicitDestinationWinsWithoutRegisteredDefaultsOrGlobals() throws {
        let store = MemoryDomains()
        store.values[source] = ["size": 15, "visible": true]
        store.values[destination] = ["size": 19, "visible": false, "new": "keep"]
        try ApplicationIdentityMigration.migrate(domains: store.adapter)
        #expect(store.values[destination]?["size"] as? Int == 19)
        #expect(store.values[destination]?["visible"] as? Bool == false)
        #expect(store.values[destination]?["new"] as? String == "keep")
    }

    @Test func completedMigrationDoesNotReintroduceRemovedPreferences() throws {
        let store = MemoryDomains()
        store.values[source] = ["old": "original"]
        try ApplicationIdentityMigration.migrate(domains: store.adapter)
        store.values[destination]?.removeValue(forKey: "old")
        store.values[source]?["later"] = "do not import"
        #expect(try !ApplicationIdentityMigration.migrate(domains: store.adapter))
        #expect(store.writes == 2)
        #expect(store.values[destination]?["old"] == nil)
        #expect(store.values[destination]?["later"] == nil)
    }

    @Test func missingSourceKeepsDestinationAndCompletes() throws {
        let store = MemoryDomains()
        store.values[destination] = ["new": "existing"]
        try ApplicationIdentityMigration.migrate(domains: store.adapter)
        #expect(store.values[source] == nil)
        #expect(store.values[destination]?["new"] as? String == "existing")
        #expect(store.values[destination]?[marker] as? Bool == true)
    }

    @Test(arguments: [1, 2]) func failedWriteKeepsSourceAndCanRetry(failedWrite: Int) throws {
        let store = MemoryDomains()
        store.values[source] = ["capture": "unsaved neutral text"]
        store.values[destination] = ["size": 20]
        store.failWrite = failedWrite
        #expect(throws: (any Error).self) { try ApplicationIdentityMigration.migrate(domains: store.adapter) }
        #expect(store.values[destination]?[marker] == nil)
        #expect(store.values[source]?["capture"] as? String == "unsaved neutral text")
        store.failWrite = nil
        try ApplicationIdentityMigration.migrate(domains: store.adapter)
        #expect(store.values[destination]?["capture"] as? String == "unsaved neutral text")
        #expect(store.values[destination]?["size"] as? Int == 20)
    }

    @Test func unreadableSourceAndLostWritesNeverComplete() throws {
        let store = MemoryDomains()
        store.failRead = true
        #expect(throws: (any Error).self) { try ApplicationIdentityMigration.migrate(domains: store.adapter) }
        #expect(store.writes == 0)
        store.failRead = false
        store.values[source] = ["capture": "preserve"]
        store.discardWrites = true
        #expect(throws: (any Error).self) { try ApplicationIdentityMigration.migrate(domains: store.adapter) }
        #expect(store.values[destination]?[marker] == nil)
    }

    @Test func onlyMainIdentityOutsideIsolationMigrates() {
        #expect(ApplicationIdentityMigration.isRequired(bundleIdentifier: destination, isolated: false))
        for id in [source, source + ".engine-qa", source + ".visual-close", source + ".cloud-qa", source + ".callback-helper"] {
            #expect(!ApplicationIdentityMigration.isRequired(bundleIdentifier: id, isolated: false))
        }
        #expect(!ApplicationIdentityMigration.isRequired(bundleIdentifier: destination, isolated: true))
        #expect(!ApplicationIdentityMigration.isRequired(bundleIdentifier: nil, isolated: false))
    }

    @Test func freshInstallWithNoPersistentDomainsCompletesAndIsIdempotent() throws {
        let old = try TestPreferences(prefix: "Draftly.Identity.FreshOld.")
        let new = try TestPreferences(prefix: "Draftly.Identity.FreshNew.")
        defer { old.close(); new.close() }
        #expect(new.defaults.persistentDomain(forName: old.name) == nil)
        #expect(new.defaults.persistentDomain(forName: new.name) == nil)
        let domains = ApplicationIdentityMigration.Domains.persistent(defaults: new.defaults)
        #expect(try ApplicationIdentityMigration.migrate(domains: domains,
            source: old.name, destination: new.name))
        #expect(new.defaults.persistentDomain(forName: new.name)?[marker] as? Bool == true)
        #expect(new.defaults.persistentDomain(forName: old.name) == nil)
        #expect(try !ApplicationIdentityMigration.migrate(domains: domains,
            source: old.name, destination: new.name))
    }

    @Test func persistentAdapterCopiesOnlyExplicitDomains() throws {
        let old = try TestPreferences(prefix: "Draftly.Identity.Old.")
        let new = try TestPreferences(prefix: "Draftly.Identity.New.")
        defer { old.close(); new.close() }
        old.defaults.register(defaults: ["registered.only": "do not copy"])
        old.defaults.set(Data([42, 0, 255]), forKey: "bookmark")
        old.defaults.set("Monospace", forKey: "font")
        new.defaults.set("Keep Font", forKey: "font")
        try ApplicationIdentityMigration.migrate(domains: .persistent(defaults: old.defaults),
            source: old.name, destination: new.name)
        let result = try #require(new.defaults.persistentDomain(forName: new.name))
        #expect(result["registered.only"] == nil)
        #expect(result["font"] as? String == "Keep Font")
        #expect(result["bookmark"] as? Data == Data([42, 0, 255]))
        #expect(old.defaults.string(forKey: "font") == "Monospace")
    }
}
