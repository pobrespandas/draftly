import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent preference batch preparation") @MainActor
struct AgentPreferenceBatchTests {
    @Test func sharedStoresCombineChangesWithoutWritingDefaults() throws {
        let domain = "Draftly-Preference-Batch-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let original = #"{"future":{"keep":"🐼"}}"#
        defaults.set(original, forKey: MarkdownPreferences.multiKey)
        defaults.set(Data(#"{"future":"kept"}"#.utf8), forKey: "list.options")
        let library = try LibraryStore(inMemory: true, seed: false)
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: Date().addingTimeInterval(60),
            capabilities: [.preferencesWrite], scope: .library)
        let entries: [(String, AgentJSONValue)] = [("markdown.multi.smartQuotesEnabled", .bool(false)),
            ("markdown.multi.footnotesEnabled", .bool(false)), ("list.showPreview", .bool(false)), ("list.showTags", .bool(false))]
        let request = AgentRequest(requestID: UUID(), libraryID: nil, operation: "preferences.update", expectedVersion: "v1",
            parameters: ["items": .array(entries.map { .object(["id": .string($0.0), "value": $0.1]) })])
        let batch = try AgentPreferenceBatch.prepare(request, defaults: defaults, library: library, grant: grant,
            resolveSyntax: { _ in throw AgentErrorCode.unavailable })
        guard case .scalar(.string(let encoded)) = batch.storage[MarkdownPreferences.multiKey],
              case .data(let list) = batch.storage["list.options"] else { Issue.record("Missing combined stores"); return }
        let markdown = try JSONDecoder().decode([String: AgentJSONValue].self, from: Data(encoded.utf8))
        #expect(markdown["smartQuotesEnabled"] == .bool(false) && markdown["footnotesEnabled"] == .bool(false))
        #expect(markdown["future"] == .object(["keep": .string("🐼")]))
        let options = try JSONDecoder().decode([String: AgentJSONValue].self, from: list)
        #expect(options["showPreview"] == .bool(false) && options["showTags"] == .bool(false))
        #expect(options["future"] == .string("kept"))
        #expect(defaults.string(forKey: MarkdownPreferences.multiKey) == original)
        #expect(defaults.object(forKey: "list.showPreview") == nil)
        #expect(batch.native.isEmpty && !batch.requiresHumanApproval)
    }

    @Test func invalidTailCannotApplyAnEarlierPreparedChange() throws {
        let domain = "Draftly-Preference-Batch-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: Date().addingTimeInterval(60),
            capabilities: [.preferencesWrite], scope: .library)
        let request = AgentRequest(requestID: UUID(), libraryID: nil, operation: "preferences.update", expectedVersion: "v1",
            parameters: ["items": .array([
                .object(["id": .string("editor.fontSize"), "value": .integer(23)]),
                .object(["id": .string("editor.lineSpacing"), "value": .integer(9)])])])
        #expect(throws: AgentSchemaError.invalidValue) {
            try AgentPreferenceBatch.prepare(request, defaults: defaults, library: library, grant: grant,
                resolveSyntax: { _ in throw AgentErrorCode.unavailable })
        }
        #expect(defaults.object(forKey: "editor.fontSize") == nil)
    }

    @Test func resetPreservesUnknownFieldsAndNativeChangesRequireReview() throws {
        let domain = "Draftly-Preference-Batch-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let original = #"{"smartQuotesEnabled":false,"footnotesEnabled":false,"future":7}"#
        defaults.set(original, forKey: MarkdownPreferences.multiKey)
        let library = try LibraryStore(inMemory: true, seed: false)
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: Date().addingTimeInterval(60),
            capabilities: [.preferencesWrite], scope: .library)
        let reset = AgentRequest(requestID: UUID(), libraryID: nil, operation: "preferences.reset", expectedVersion: "v1",
            parameters: ["items": .array([
                .object(["id": .string("markdown.multi.smartQuotesEnabled")]),
                .object(["id": .string("markdown.multi.footnotesEnabled")])])])
        let batch = try AgentPreferenceBatch.prepare(reset, defaults: defaults, library: library, grant: grant,
            resolveSyntax: { _ in throw AgentErrorCode.unavailable })
        guard case .scalar(.string(let value)) = batch.storage[MarkdownPreferences.multiKey] else {
            Issue.record("Missing reset configuration"); return
        }
        #expect(try JSONDecoder().decode([String: AgentJSONValue].self, from: Data(value.utf8)) == ["future": .integer(7)])
        let native = AgentRequest(requestID: UUID(), libraryID: nil, operation: "preferences.update", expectedVersion: "v1",
            parameters: ["items": .array([.object(["id": .string(SpotlightPreferences.enabledKey), "value": .bool(true)])])])
        let effect = try AgentPreferenceBatch.prepare(native, defaults: defaults, library: library, grant: grant,
            resolveSyntax: { _ in throw AgentErrorCode.unavailable })
        #expect(effect.requiresHumanApproval && effect.native.count == 1 && effect.storage.isEmpty)
        let limited = AgentGrant(connectionID: grant.connectionID, libraryID: grant.libraryID, expiresAt: grant.expiresAt,
            capabilities: [.preferencesWrite], scope: .resources([]))
        #expect(throws: AgentErrorCode.permissionDenied) {
            try AgentPreferenceBatch.prepare(native, defaults: defaults, library: library, grant: limited,
                resolveSyntax: { _ in throw AgentErrorCode.unavailable })
        }
        #expect(defaults.string(forKey: MarkdownPreferences.multiKey) == original)
        #expect(defaults.object(forKey: SpotlightPreferences.enabledKey) == nil)
    }

}
