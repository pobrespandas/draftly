import AppKit
import CryptoKit

enum BookmarkPreferences {
    struct AgentRecord {
        let id: UUID
        let name: String
        let data: Data
    }
    private static let identityKey = "agent.bookmark.identities.v1"
    private static let identityLock = NSRecursiveLock()

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private static func identity(name: String, data: Data, generation: UUID) -> UUID {
        let input = Data("Draftly.BookmarkIdentity.v1".utf8) + Data(generation.uuidString.utf8)
            + Data(name.utf8) + Data(SHA256.hash(data: data))
        var bytes = Array(SHA256.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // Identity binds the permission bytes. The metadata never supplies an arbitrary resource ID.
    static func agentRecords(defaults: UserDefaults = .standard, synchronize: (() -> Bool)? = nil) throws -> [AgentRecord] {
        identityLock.lock(); defer { identityLock.unlock() }
        let previous = defaults.dictionary(forKey: identityKey) as? [String: [String: String]] ?? [:]
        var next: [String: [String: String]] = [:]
        let records = names(defaults: defaults).compactMap { name -> AgentRecord? in
            guard let data = defaults.data(forKey: "bookmark." + name) else { return nil }
            let key = Data(name.utf8).base64EncodedString(), fingerprint = digest(data)
            let generation: UUID
            if let saved = previous[key], saved["digest"] == fingerprint,
               let text = saved["generation"], let id = UUID(uuidString: text) { generation = id }
            else { generation = UUID() }
            next[key] = ["generation": generation.uuidString, "digest": fingerprint]
            return AgentRecord(id: identity(name: name, data: data, generation: generation), name: name, data: data)
        }
        if next != previous {
            if next.isEmpty { defaults.removeObject(forKey: identityKey) }
            else { defaults.set(next, forKey: identityKey) }
            guard (synchronize ?? { defaults.synchronize() })() else {
                if previous.isEmpty { defaults.removeObject(forKey: identityKey) }
                else { defaults.set(previous, forKey: identityKey) }
                throw CocoaError(.fileWriteUnknown)
            }
        }
        return records
    }

    static func store(_ data: Data, named name: String, defaults: UserDefaults = .standard) {
        identityLock.lock(); defer { identityLock.unlock() }
        defaults.set(data, forKey: "bookmark." + name)
        _ = try? agentRecords(defaults: defaults)
    }

    static func data(for url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: .withSecurityScope)
    }

    static func names(defaults: UserDefaults = .standard) -> [String] {
        defaults.dictionaryRepresentation().compactMap { key, value in
            guard key.hasPrefix("bookmark."), value is Data else { return nil }
            let name = String(key.dropFirst("bookmark.".count))
            return name.isEmpty ? nil : name
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func forget(_ name: String, defaults: UserDefaults = .standard) {
        identityLock.lock(); defer { identityLock.unlock() }
        defaults.removeObject(forKey: "bookmark." + name)
        var identities = defaults.dictionary(forKey: identityKey) as? [String: [String: String]] ?? [:]
        identities.removeValue(forKey: Data(name.utf8).base64EncodedString())
        if identities.isEmpty { defaults.removeObject(forKey: identityKey) }
        else { defaults.set(identities, forKey: identityKey) }
    }
}
