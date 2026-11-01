import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent local list preference access") @MainActor
struct AgentListPreferenceAccessTests {
    private func address(_ id: String) -> AgentJSONValue { .object(["id": .string(id)]) }
    private func apply(_ change: AgentListPreferenceAccess.Change, defaults: UserDefaults) throws {
        defaults.set(change.data, forKey: "list.options")
        if let key = change.legacyKey {
            if let value = change.legacyValue {
                switch value { case .bool(let flag): defaults.set(flag, forKey: key)
                case .integer(let count): defaults.set(count, forKey: key)
                default: Issue.record("Unexpected legacy value") }
            } else { defaults.removeObject(forKey: key) }
        }
    }

    @Test func allFieldsRoundTripAndResetWithoutDroppingOtherData() throws {
        let domain = "Draftly-List-Agent-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let original = Data(#"{"future":{"v":"保持🐼"},"showLastAction":true,"previewLines":3}"#.utf8)
        let registry = try AgentPreferenceCatalog.make()
        #expect(AgentListPreferenceAccess.supportedIDs.count == 9)
        for id in AgentListPreferenceAccess.supportedIDs {
            defaults.removePersistentDomain(forName: domain)
            defaults.set(original, forKey: "list.options")
            let field = try registry.field(id)
            let value: AgentJSONValue = id == "list.previewLines" ? .integer(1) : .bool(false)
            let change = try AgentListPreferenceAccess.prepare(address: address(id), value: value, configuration: original)
            try apply(change, defaults: defaults)
            let read = try AgentListPreferenceAccess.read(address: address(id), defaults: defaults)
            #expect(read.effectiveValue == value && read.origin == "stored" && read.hasOverride)
            let reset = try AgentListPreferenceAccess.prepare(address: address(id), value: nil, configuration: change.data)
            try apply(reset, defaults: defaults)
            let restored = try AgentListPreferenceAccess.read(address: address(id), defaults: defaults)
            #expect(restored.effectiveValue == field.defaultValue && restored.origin == "default" && !restored.hasOverride)
            let object = try JSONDecoder().decode([String: AgentJSONValue].self, from: reset.data)
            #expect(object["future"] == .object(["v": .string("保持🐼")]))
            if id != "list.showLastAction" { #expect(DraftListDefaults.load(defaults: defaults).showLastAction) }
            if id != "list.previewLines" { #expect(DraftListDefaults.load(defaults: defaults).previewLines == 3) }
        }
    }

    @Test func legacyPrecedenceAndResetMatchVisibleConsumers() throws {
        let domain = "Draftly-List-Agent-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let data = Data(#"{"previewLines":3,"showLastAction":true}"#.utf8)
        defaults.set(data, forKey: "list.options")
        defaults.set(1, forKey: "list.previewLines")
        #expect(try AgentListPreferenceAccess.read(address: address("list.previewLines"), defaults: defaults).effectiveValue == .integer(1))
        let reset = try AgentListPreferenceAccess.prepare(address: address("list.previewLines"), value: nil, configuration: data)
        try apply(reset, defaults: defaults)
        #expect(DraftListDefaults.load(defaults: defaults).previewLines == 2)
        #expect(DraftListDefaults.load(defaults: defaults).showLastAction)
        defaults.set("YES", forKey: "list.showPreview")
        let legacy = try AgentListPreferenceAccess.read(address: address("list.showPreview"), defaults: defaults)
        #expect(legacy.effectiveValue == .bool(true) && legacy.origin == "invalid")
    }

    @Test func absentAndInvalidStoresAreNotRewritten() throws {
        let domain = "Draftly-List-Agent-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        for id in AgentListPreferenceAccess.supportedIDs {
            let read = try AgentListPreferenceAccess.read(address: address(id), defaults: defaults)
            #expect(read.origin == "default" && !read.hasOverride)
        }
        #expect((defaults.persistentDomain(forName: domain) ?? [:]).isEmpty)
        for text in ["invalid", "[]", #"{"showTags":null}"#, #"{"previewLines":"bad"}"#] {
            let data = Data(text.utf8)
            defaults.set(data, forKey: "list.options")
            #expect(throws: (any Error).self) {
                try AgentListPreferenceAccess.prepare(address: address("list.showDate"), value: .bool(false), configuration: data)
            }
            let read = try AgentListPreferenceAccess.read(address: address("list.showDate"), defaults: defaults)
            #expect(read.origin == "invalid" && read.hasOverride)
            #expect(defaults.data(forKey: "list.options") == data)
        }
        #expect(throws: AgentErrorCode.unavailable) {
            try AgentListPreferenceAccess.prepare(address: address("application.launchAtLogin"), value: .bool(true), configuration: nil)
        }
    }
}
