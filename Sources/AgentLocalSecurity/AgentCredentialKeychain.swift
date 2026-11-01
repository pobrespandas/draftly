import Foundation
import Security
import LocalAuthentication
import AgentContracts

// Dedicated device-local items. No Action credential, password or legacy fallback.
@MainActor package final class AgentCredentialKeychain {
    package struct Backend {
        package let validateIdentity: (AgentCredentialRole) throws -> Void
        package let copy: ([String: Any]) -> (OSStatus, Any?)
        package let add: ([String: Any]) -> OSStatus
        package let remove: ([String: Any]) -> OSStatus

        package init(validateIdentity: @escaping (AgentCredentialRole) throws -> Void,
                     copy: @escaping ([String: Any]) -> (OSStatus, Any?),
                     add: @escaping ([String: Any]) -> OSStatus, remove: @escaping ([String: Any]) -> OSStatus) {
            self.validateIdentity = validateIdentity; self.copy = copy
            self.add = add; self.remove = remove
        }

        package static var system: Self {
            Self(validateIdentity: AgentCredentialIdentity.validateCurrentProcess, copy: { query in
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                return (status, result)
            }, add: { SecItemAdd($0 as CFDictionary, nil) }, remove: { SecItemDelete($0 as CFDictionary) })
        }
    }

    package static let service = "com.pobrespandas.draftly.agent-connections.v1"
    private let role: AgentCredentialRole
    private let backend: Backend

    package init(role: AgentCredentialRole, backend: Backend = .system) {
        self.role = role; self.backend = backend
    }

    package func read(_ id: UUID) throws -> Data? {
        try backend.validateIdentity(role)
        var query = base(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = backend.copy(query)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, data.count == 32 else { throw AgentErrorCode.storageError }
        return data
    }

    package func create(_ id: UUID, credential: Data) throws {
        guard role == .application else { throw AgentErrorCode.permissionDenied }
        guard credential.count == 32 else { throw AgentErrorCode.invalidInput }
        try backend.validateIdentity(role)
        var item = base(id)
        item[kSecValueData as String] = credential
        item[kSecAttrLabel as String] = "Draftly agent connection"
        // Create-only. A duplicate must never replace another connection's secret.
        try check(backend.add(item))
    }

    package func remove(_ id: UUID) throws {
        guard role == .application else { throw AgentErrorCode.permissionDenied }
        try backend.validateIdentity(role)
        let status = backend.remove(base(id))
        if status != errSecItemNotFound { try check(status) }
    }

    private func base(_ id: UUID) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: id.uuidString.lowercased(),
            kSecAttrAccessGroup as String: AgentCredentialIdentity.accessGroup,
            kSecUseDataProtectionKeychain as String: true, kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseAuthenticationContext as String: context]
    }

    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecDuplicateItem: throw AgentErrorCode.versionConflict
        case errSecInteractionNotAllowed, errSecInteractionRequired: throw AgentErrorCode.interactionRequired
        case errSecAuthFailed, errSecMissingEntitlement: throw AgentErrorCode.permissionDenied
        case errSecUserCanceled: throw AgentErrorCode.cancelled
        case errSecNotAvailable: throw AgentErrorCode.unavailable
        default: throw AgentErrorCode.storageError
        }
    }
}
