import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Atomic action URL installation") @MainActor
struct URLActionInstallationTests {
    private func link(_ entries: [[String: Any]]) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: entries)
        var url = URLComponents(); url.scheme = "draftly"; url.host = "action"
        url.queryItems = [URLQueryItem(name: "data", value: String(decoding: data, as: UTF8.self))]
        return try #require(url.url)
    }

    @Test func malformedLaterEntryLeavesExistingActionsUnchanged() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let existing = DraftAction(name: "Existing", steps: [])
        try library.saveAction(existing)
        let url = try link([["name": "Valid first", "steps": []], ["name": "Malformed later"]])
        #expect(throws: (any Error).self) { try ApplicationURLRouter.installActions(url, library: library) }
        #expect(library.actions == [existing])
        try library.reload()
        #expect(library.actions == [existing])
    }

    @Test func failedBatchRestoresReplacedAndNewActions() throws {
        enum Failure: Error { case commit }
        let library = try LibraryStore(inMemory: true, seed: false)
        let existing = DraftAction(name: "Original", steps: [])
        try library.saveAction(existing)
        let url = try link([["name": "Replacement", "uuid": existing.id.uuidString, "steps": []], ["name": "New action", "steps": []]])
        library.beforeBatchCommit = { throw Failure.commit }
        defer { library.beforeBatchCommit = nil }
        #expect(throws: Failure.commit) { try ApplicationURLRouter.installActions(url, library: library) }
        #expect(library.actions == [existing])
        try library.reload()
        #expect(library.actions == [existing])
    }

    @Test func successfulBatchPreservesDisabledUnknownPayload() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let url = try link([
            ["name": "Unknown disabled", "unknown": ["keep": [false, "café 🐼"]], "steps": [["type": "futureNeutralStep", "isEnabled": false, "data": ["unknown": "Keep"]]]],
            ["name": "Second neutral action", "steps": []]
        ])
        try ApplicationURLRouter.installActions(url, library: library)
        try library.reload()
        #expect(library.actions.count == 2)
        let imported = try #require(library.actions.first { $0.name == "Unknown disabled" })
        #expect(imported.steps.first?.isEnabled == false)
        #expect(imported.steps.first?.type == "futureNeutralStep" && imported.steps.first?.values["unknown"] == "Keep")
        let payload = try #require(imported.rawPayload?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let unknown = try #require(object["unknown"] as? [String: Any])
        #expect((unknown["keep"] as? [Any])?.last as? String == "café 🐼")
    }

    @Test func missingLibraryFailsExplicitly() throws {
        let url = try link([["name": "Neutral", "steps": []]])
        #expect(throws: (any Error).self) { try ApplicationURLRouter.installActions(url, library: nil) }
    }
}
