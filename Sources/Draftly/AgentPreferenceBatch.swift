import Foundation
import AgentContracts
import DraftlyCore

// Prepare a complete batch before the caller authorizes and commits storage.
@MainActor struct AgentPreferenceBatch {
    enum StoredValue: Equatable {
        case remove
        case scalar(AgentJSONValue)
        case data(Data)
    }
    let storage: [String: StoredValue]
    let native: [AgentNativePreferenceAccess.Change]
    let requiresHumanApproval: Bool

    static func prepare(_ request: AgentRequest, defaults: UserDefaults, library: LibraryStore,
                        grant: AgentGrant,
                        resolveSyntax: (AgentPreferenceAddress) throws -> SyntaxDefinition) throws -> Self {
        guard ["preferences.update", "preferences.reset"].contains(request.operation) else { throw AgentErrorCode.invalidInput }
        guard grant.capabilities.contains(.preferencesWrite) else { throw AgentErrorCode.permissionDenied }
        let registry = try AgentPreferenceCatalog.make()
        let parameters = try AgentPreferenceSchemas.validatedParameters(for: request, registry: registry)
        guard case .array(let items) = parameters["items"] else { throw AgentErrorCode.invalidInput }
        var storage: [String: StoredValue] = [:]
        var native: [AgentNativePreferenceAccess.Change] = []
        var review = try AgentPreferenceSchemas.mutationRequiresHumanApproval(request, registry: registry)
        func configuration(_ key: String) throws -> String {
            if let staged = storage[key] {
                guard case .scalar(.string(let text)) = staged else { throw AgentErrorCode.invalidInput }
                return text
            }
            guard let stored = defaults.object(forKey: key) else { return "{}" }
            guard let text = stored as? String else { throw AgentErrorCode.invalidInput }
            return text
        }
        for item in items {
            guard case .object(var fields) = item else { throw AgentErrorCode.invalidInput }
            let value = request.operation == "preferences.update" ? fields.removeValue(forKey: "value") : nil
            let addressValue = AgentJSONValue.object(fields)
            let address = try registry.address(addressValue)
            if AgentDevicePreferenceAccess.supportedIDs.contains(address.id) {
                let change = try AgentDevicePreferenceAccess.prepare(address: addressValue, value: value)
                storage[change.storageKey] = change.value.map(StoredValue.scalar) ?? .remove
            } else if AgentListPreferenceAccess.supportedIDs.contains(address.id) {
                let data: Data?
                if let staged = storage["list.options"] {
                    guard case .data(let bytes) = staged else { throw AgentErrorCode.invalidInput }
                    data = bytes
                } else if let stored = defaults.object(forKey: "list.options") {
                    guard let bytes = stored as? Data else { throw AgentErrorCode.invalidInput }
                    data = bytes
                } else { data = nil }
                let change = try AgentListPreferenceAccess.prepare(address: addressValue, value: value, configuration: data)
                storage["list.options"] = .data(change.data)
                if let key = change.legacyKey { storage[key] = change.legacyValue.map(StoredValue.scalar) ?? .remove }
            } else if address.id == WorkspaceDefaults.key {
                let change = try AgentWorkspacePreferenceAccess.prepare(value: value, capabilities: grant.capabilities,
                    scope: grant.scope, workspaceExists: { id in library.workspaces.contains { $0.id == id } })
                storage[change.storageKey] = change.value.map { .scalar(.string($0)) } ?? .remove
            } else if ["application.launchAtLogin", SpotlightPreferences.enabledKey].contains(address.id) {
                let change = try AgentNativePreferenceAccess.prepare(address: addressValue, value: value)
                guard !change.requiresLibraryScope || grant.scope == .library else { throw AgentErrorCode.permissionDenied }
                native.append(change); review = true
            } else {
                let syntax: SyntaxDefinition?
                let key: String
                if address.id.hasPrefix("syntax.") {
                    guard grant.capabilities.contains(.appearanceManage) else { throw AgentErrorCode.permissionDenied }
                    if case .installed(let id) = address.syntax,
                       !grant.scope.permits(.init(kind: .syntax, id: id)) { throw AgentErrorCode.notFound }
                    syntax = try resolveSyntax(address)
                    key = try AgentEncodedPreferenceAccess.syntaxStorageKey(String(address.id.dropFirst("syntax.".count)))
                } else if address.id.hasPrefix("markdown.multi.") || address.id.hasPrefix("markdown.github.") {
                    syntax = nil
                    key = address.id.hasPrefix("markdown.multi.") ? MarkdownPreferences.multiKey : MarkdownPreferences.githubKey
                } else if address.id == "commands.shortcut" {
                    syntax = nil; key = CommandShortcuts.storageKey
                } else { throw AgentErrorCode.unavailable }
                let change = try AgentEncodedPreferenceAccess.prepare(address: addressValue, value: value,
                    configuration: configuration(key), syntax: syntax, actions: library.actions)
                storage[change.storageKey] = .scalar(.string(change.configuration))
                review = review || change.requiresHumanApproval
            }
        }
        return Self(storage: storage, native: native, requiresHumanApproval: review)
    }
}
