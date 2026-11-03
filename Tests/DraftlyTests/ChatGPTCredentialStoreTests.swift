import Foundation
import Security
import Testing
@testable import Draftly

@Suite("ChatGPT credential storage") @MainActor
struct ChatGPTCredentialStoreTests {
    @Test func separateAccountsAndQAIdentitiesUseDeviceLocalItems() throws {
        var updates: [[String: Any]] = []
        var additions: [[String: Any]] = []
        let backend = ChatGPTCredentialStore.Backend(copy: { _ in (errSecItemNotFound, nil) },
            update: { query, _ in updates.append(query); return errSecItemNotFound },
            add: { additions.append($0); return errSecSuccess }, remove: { _ in errSecSuccess })
        let production = ChatGPTCredentialStore(bundleID: "com.example.app", backend: backend)
        let qa = ChatGPTCredentialStore(bundleID: "com.example.qa", backend: backend)
        let first = UUID(), second = UUID()
        try production.write(Data("neutral-record".utf8), accountID: first)
        try production.write(Data("neutral-record".utf8), accountID: second)
        try qa.write(Data("neutral-record".utf8), accountID: first)
        #expect(updates.count == 3 && additions.count == 3)
        #expect(updates[0][kSecAttrAccount as String] as? String != updates[1][kSecAttrAccount as String] as? String)
        #expect(updates[0][kSecAttrService as String] as? String != updates[2][kSecAttrService as String] as? String)
        #expect(additions.allSatisfy { $0[kSecAttrSynchronizable as String] as? Bool == false })
        #expect(additions.allSatisfy { $0[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String })
    }

    @Test func updateFailureNeverDeletesOrFallsBackToAnotherStore() throws {
        var added = false, removed = false
        let backend = ChatGPTCredentialStore.Backend(copy: { _ in (errSecInteractionNotAllowed, nil) },
            update: { _, _ in errSecInteractionNotAllowed }, add: { _ in added = true; return errSecSuccess },
            remove: { _ in removed = true; return errSecSuccess })
        let store = ChatGPTCredentialStore(backend: backend)
        let failure = ChatGPTCredentialStore.Failure(status: errSecInteractionNotAllowed)
        #expect(throws: failure) { try store.write(Data("neutral".utf8), accountID: UUID()) }
        #expect(throws: failure) { try store.read(UUID()) }
        #expect(!added && !removed)
    }

    @Test func missingItemAndMissingDataAreDifferent() throws {
        var status = errSecItemNotFound
        let backend = ChatGPTCredentialStore.Backend(copy: { _ in (status, nil) },
            update: { _, _ in errSecSuccess }, add: { _ in errSecSuccess }, remove: { _ in errSecItemNotFound })
        let store = ChatGPTCredentialStore(backend: backend)
        #expect(try store.read(UUID()) == nil)
        status = errSecSuccess
        #expect(throws: ChatGPTCredentialStore.Failure(status: errSecDecode)) { try store.read(UUID()) }
        try store.remove(UUID())
    }
}
