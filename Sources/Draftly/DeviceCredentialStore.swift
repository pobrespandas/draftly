import Foundation
import Security

/// Keep each credential record in one device-local Keychain item.
@MainActor final class DeviceCredentialStore {
    struct Backend {
        let copy: ([String: Any]) -> (OSStatus, Data?)
        let update: ([String: Any], [String: Any]) -> OSStatus
        let add: ([String: Any]) -> OSStatus
        let remove: ([String: Any]) -> OSStatus

        static var system: Self {
            Self(copy: { query in
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                return (status, result as? Data)
            }, update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
                 add: { SecItemAdd($0 as CFDictionary, nil) },
                 remove: { SecItemDelete($0 as CFDictionary) })
        }
    }

    struct Failure: Error, Equatable { let status: OSStatus }
    private let service: String
    private let backend: Backend

    init(service: String, backend: Backend = .system) {
        self.service = service
        self.backend = backend
    }

    func read(_ accountID: UUID) throws -> Data? {
        var query = base(accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = backend.copy(query)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data else { throw Failure(status: errSecDecode) }
        return data
    }

    // The caller encodes the complete validated record, including rotating tokens.
    // A failed replacement leaves the previous item in place.
    func write(_ data: Data, accountID: UUID) throws {
        let query = base(accountID)
        let attributes = [kSecValueData as String: data]
        var status = backend.update(query, attributes)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = backend.add(item)
        }
        try check(status)
    }

    func remove(_ accountID: UUID) throws {
        let status = backend.remove(base(accountID))
        if status != errSecItemNotFound { try check(status) }
    }

    private func base(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString.lowercased(),
         kSecAttrSynchronizable as String: false]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
