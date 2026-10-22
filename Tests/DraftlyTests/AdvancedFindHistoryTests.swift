import Foundation
import Testing
@testable import Draftly

@Suite("Advanced Find request history") @MainActor
struct AdvancedFindHistoryTests {
    @Test func reversalPreservesOptionsAndUnicodeWithoutInterpretingTemplates() throws {
        var request = AdvancedFindRequest(text: "🐼\r\ncafé", replacement: "$1\\tail\n", caseSensitive: true, regularExpression: true)
        #expect(request.historyTitle == "Find: 🐼\r\ncafé, Replace: $1\\tail\n")
        let original = request
        request.reverseValues()
        #expect(request.text == original.replacement && request.replacement == original.text)
        #expect(request.caseSensitive && request.regularExpression)
        request.reverseValues()
        #expect(request == original)
    }

    @Test func historyPersistsCompleteRequestsAndMovesExactDuplicatesToTheFront() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindHistory.")
        defer { preferences.close() }
        let store = AdvancedFindHistory(defaults: preferences.defaults)
        let first = AdvancedFindRequest(text: "🐼 café\r\n", replacement: "$1\\", caseSensitive: false, regularExpression: false)
        var second = first; second.caseSensitive = true; second.replacement = "té"
        try store.record(first); try store.record(second)
        #expect(store.requests == [second, first])
        let reopened = try #require(UserDefaults(suiteName: preferences.name))
        let reloaded = AdvancedFindHistory(defaults: reopened)
        #expect(reloaded.requests == [second, first])
        try reloaded.record(first)
        #expect(store.requests == [first, second])
        preferences.defaults.set("keep", forKey: "unrelated")
        reloaded.clear()
        #expect(store.requests.isEmpty && preferences.defaults.string(forKey: "unrelated") == "keep")
    }

    @Test func invalidRegexDoesNotReplaceHistoryAndDefaultsRemainIsolated() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindHistoryInvalid.")
        defer { preferences.close() }
        let other = try TestPreferences(prefix: "Draftly.FindHistoryOther.")
        defer { other.close() }
        let store = AdvancedFindHistory(defaults: preferences.defaults)
        let valid = AdvancedFindRequest(text: "[", replacement: "", caseSensitive: false, regularExpression: false)
        #expect(valid.historyTitle == "Find: [")
        try store.record(valid)
        var invalid = valid; invalid.regularExpression = true
        #expect(throws: (any Error).self) { try store.record(invalid) }
        #expect(store.requests == [valid])
        #expect(AdvancedFindHistory(defaults: other.defaults).requests.isEmpty)
        preferences.defaults.set(Data("invalid JSON".utf8), forKey: AdvancedFindHistory.storageKey)
        #expect(store.requests.isEmpty)
        try store.record(valid)
        #expect(store.requests == [valid])
    }
}
