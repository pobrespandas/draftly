import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Agent scalar device preference access") @MainActor
struct AgentDevicePreferenceAccessTests {
    private func address(_ id: String) -> AgentJSONValue { .object(["id": .string(id)]) }

    @Test func missingValuesReadAllConsumerDefaultsWithoutPersistingThem() throws {
        let domain = "Draftly-Device-Preferences-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let registry = try AgentPreferenceCatalog.make()
        #expect(AgentDevicePreferenceAccess.supportedIDs.count == 30)
        for id in AgentDevicePreferenceAccess.supportedIDs {
            let read = try AgentDevicePreferenceAccess.read(address: address(id), defaults: defaults)
            let expected = try registry.field(id).defaultValue
            #expect(read.effectiveValue == expected)
            #expect(read.origin == "default" && !read.hasOverride)
        }
        #expect((defaults.persistentDomain(forName: domain) ?? [:]).isEmpty)
    }

    @Test func preparationDoesNotWriteAndResetNamesOnlyTheRequestedKey() throws {
        let domain = "Draftly-Device-Preferences-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("保持", forKey: "future.field")
        let registry = try AgentPreferenceCatalog.make()
        for id in AgentDevicePreferenceAccess.supportedIDs {
            let field = try registry.field(id)
            guard field.writable, let value = field.defaultValue else { continue }
            let change = try AgentDevicePreferenceAccess.prepare(address: address(id), value: value)
            #expect(change.storageKey == id && change.value == value)
            let reset = try AgentDevicePreferenceAccess.prepare(address: address(id), value: nil)
            #expect(reset.storageKey == id && reset.value == nil)
        }
        #expect(defaults.persistentDomain(forName: domain) as? [String: String] == ["future.field": "保持"])
    }

    @Test func storedNumbersBooleansAndUnicodeKeepTheirTypes() throws {
        let domain = "Draftly-Device-Preferences-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("未知 Nerd Font 🐼", forKey: "editor.fontName")
        defaults.set(23.5, forKey: "editor.fontSize")
        defaults.set(true, forKey: "editor.typewriter")
        #expect(try AgentDevicePreferenceAccess.read(address: address("editor.fontName"), defaults: defaults).effectiveValue == .string("未知 Nerd Font 🐼"))
        #expect(try AgentDevicePreferenceAccess.read(address: address("editor.fontSize"), defaults: defaults).effectiveValue == .number(Decimal(string: "23.5")!))
        #expect(try AgentDevicePreferenceAccess.read(address: address("editor.typewriter"), defaults: defaults).effectiveValue == .bool(true))
    }

    @Test func invalidLegacyValuesAreReportedAndKeptWithoutCoercion() throws {
        let domain = "Draftly-Device-Preferences-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let invalid: [(String, Any)] = [("editor.fontSize", -1), ("editor.typewriter", 1),
            ("editor.preferAdvancedFind", "YES"), ("html.strongMark", "bad"), ("editor.fontName", ["unexpected"])]
        for (id, value) in invalid {
            defaults.set(value, forKey: id)
            let read = try AgentDevicePreferenceAccess.read(address: address(id), defaults: defaults)
            #expect(read.effectiveValue == .null && read.origin == "invalid" && read.hasOverride)
            #expect(defaults.object(forKey: id) != nil)
        }
        // Existing UI consumers retain their own legacy conversion behavior.
        #expect(WindowPreferences(defaults: defaults).prefersAdvancedFind)
    }

    @Test func rejectsPrivateFieldsNativeChangesResourcesAndReadOnlyMutation() throws {
        for id in ["agent.token", "commands.bindings", "icloud.container"] {
            #expect(throws: (any Error).self) { try AgentDevicePreferenceAccess.prepare(address: address(id), value: nil) }
        }
        for id in ["application.launchAtLogin", "application.indexDraftsInSpotlight", "workspace.defaultID", "list.showPreview"] {
            #expect(throws: AgentErrorCode.unavailable) { try AgentDevicePreferenceAccess.prepare(address: address(id), value: nil) }
        }
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentDevicePreferenceAccess.prepare(address: address("editor.lineSpacing"), value: .integer(2))
        }
        #expect(throws: (any Error).self) {
            try AgentDevicePreferenceAccess.prepare(address: address("editor.fontSize"), value: .bool(true))
        }
    }
}
