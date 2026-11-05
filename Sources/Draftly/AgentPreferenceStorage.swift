import Foundation
import CoreFoundation
import CryptoKit
import AgentContracts

// This store serializes one process. It does not provide a cross-process transaction.
@MainActor final class AgentPreferenceStorage {
    struct Snapshot {
        let version: String
        fileprivate let values: [String: Any]
    }
    typealias Read = () throws -> [String: Any]
    // False means the comparison failed and this call did not write.
    typealias Replace = ([String: Any], [String: Any]) throws -> Bool
    private let read: Read
    private let replace: Replace
    private let key = SymmetricKey(size: .bits256)
    private var committing = false

    init(read: @escaping Read, replace: @escaping Replace) {
        self.read = read; self.replace = replace
    }

    convenience init(defaults: UserDefaults, domain: String) throws {
        guard !domain.isEmpty else { throw AgentErrorCode.invalidInput }
        self.init(read: { defaults.persistentDomain(forName: domain) ?? [:] }, replace: { expected, updated in
            let current = defaults.persistentDomain(forName: domain) ?? [:]
            guard try Self.canonical(current) == Self.canonical(expected) else { return false }
            defaults.setPersistentDomain(updated, forName: domain)
            guard defaults.synchronize() else { throw AgentErrorCode.storageError }
            return true
        })
    }

    func snapshot() throws -> Snapshot {
        let values = try read()
        return Snapshot(version: try version(values), values: values)
    }

    func commit(_ changes: [String: AgentPreferenceBatch.StoredValue], against expected: Snapshot,
                validateCommit: () throws -> Void = {}, authorize: () throws -> Void) throws -> Snapshot {
        guard !committing else { throw AgentErrorCode.busy }
        committing = true; defer { committing = false }
        try authorize()
        let before = try snapshot()
        guard before.version == expected.version else { throw AgentErrorCode.versionConflict }
        var updated = before.values
        for (name, value) in changes {
            switch value {
            case .remove: updated.removeValue(forKey: name)
            case .data(let data): updated[name] = data
            case .scalar(let value): updated[name] = try Self.stored(value)
            }
        }
        guard PropertyListSerialization.propertyList(updated, isValidFor: .binary) else { throw AgentErrorCode.invalidInput }
        let targetVersion = try version(updated)
        try authorize()
        try validateCommit()
        let replaced: Bool
        do { replaced = try replace(before.values, updated) }
        catch { throw AgentErrorCode.outcomeUnknown }
        guard replaced else { throw AgentErrorCode.versionConflict }
        do {
            try authorize()
            let actual = try snapshot()
            guard actual.version == targetVersion else { throw AgentErrorCode.outcomeUnknown }
            return actual
        } catch { throw AgentErrorCode.outcomeUnknown }
    }

    private func version(_ values: [String: Any]) throws -> String {
        Data(HMAC<SHA256>.authenticationCode(for: try Self.canonical(values), using: key)).base64EncodedString()
    }

    private static func stored(_ value: AgentJSONValue) throws -> Any {
        switch value {
        case .string(let value): return value
        case .bool(let value): return value
        case .integer(let value): return NSNumber(value: value)
        case .number(let value):
            let number = NSDecimalNumber(decimal: value).doubleValue
            guard number.isFinite, Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX")) == value else {
                throw AgentErrorCode.invalidInput
            }
            return NSNumber(value: number)
        default: throw AgentErrorCode.invalidInput
        }
    }

    private static func canonical(_ values: [String: Any]) throws -> Data {
        func encode(_ value: Any) throws -> AgentJSONValue {
            func tagged(_ type: String, _ value: AgentJSONValue) -> AgentJSONValue {
                .object(["type": .string(type), "value": value])
            }
            if let value = value as? String { return tagged("string", .string(value)) }
            if let value = value as? Data { return tagged("data", .string(value.base64EncodedString())) }
            if let value = value as? Date {
                guard let decimal = Decimal(string: String(value.timeIntervalSinceReferenceDate)), !decimal.isNaN else {
                    throw AgentErrorCode.storageError
                }
                return tagged("date", .number(decimal))
            }
            if let value = value as? NSNumber {
                if CFGetTypeID(value) == CFBooleanGetTypeID() { return tagged("boolean", .bool(value.boolValue)) }
                guard let decimal = Decimal(string: value.stringValue, locale: Locale(identifier: "en_US_POSIX")), !decimal.isNaN else {
                    throw AgentErrorCode.storageError
                }
                return tagged("number", .number(decimal))
            }
            if let values = value as? [String: Any] { return tagged("dictionary", .object(try values.mapValues(encode))) }
            if let values = value as? [Any] { return tagged("array", .array(try values.map(encode))) }
            throw AgentErrorCode.storageError
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(encode(values))
    }
}
