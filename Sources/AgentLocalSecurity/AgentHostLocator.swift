import Foundation
import Darwin
import AgentContracts

// A discovery hint, never an authority or a credential. The client must still
// validate the actual socket peer and authenticate its connection.
@MainActor package final class AgentHostLocator {
    package struct Endpoint: Codable, Equatable, Sendable {
        package let libraryID: UUID
        package let epochID: UUID
        package let socketPath: String

        package init(libraryID: UUID, epochID: UUID = UUID(), socketPath: String) throws {
            guard Self.validPath(socketPath) else { throw AgentErrorCode.invalidInput }
            self.libraryID = libraryID; self.epochID = epochID; self.socketPath = socketPath
        }

        fileprivate static func validPath(_ path: String) -> Bool {
            path.hasPrefix("/") && !path.utf8.contains(0)
                && path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        }
    }

    private struct Catalog: Codable {
        let version: Int
        let hosts: [Endpoint]
    }
    private static let maximumBytes = 65_536
    private static let maximumHosts = 64
    private let directory: AgentStateDirectory

    package init(parentDirectory: URL, createIfMissing: Bool = false) throws {
        directory = try AgentStateDirectory(parentDirectory: parentDirectory, createIfMissing: createIfMissing)
    }

    // Does not create a lock file or remove stale entries. A failed connection
    // does not authorize a reader to delete another process's publication.
    package func endpoints() throws -> [Endpoint] {
        try Self.decode(directory.readSnapshot("hosts.json", maximumBytes: Self.maximumBytes))
    }

    package func endpoint(for libraryID: UUID) throws -> Endpoint {
        guard let endpoint = try endpoints().first(where: { $0.libraryID == libraryID }) else {
            throw AgentErrorCode.unavailable
        }
        return endpoint
    }

    // The application must hold and validate the library lease around this call.
    // Replacing a stale hint does not touch its socket or any other library.
    package func publish(_ endpoint: Endpoint) throws {
        guard Endpoint.validPath(endpoint.socketPath) else { throw AgentErrorCode.invalidInput }
        try directory.validateCurrentLocation()
        let old = try directory.read("hosts.json", lockName: "hosts.lock", maximumBytes: Self.maximumBytes)
        var hosts = try Self.decode(old).filter { $0.libraryID != endpoint.libraryID }
        guard hosts.count < Self.maximumHosts else { throw AgentErrorCode.busy }
        hosts.append(endpoint)
        try directory.replace("hosts.json", lockName: "hosts.lock", data: Self.encode(hosts), expected: old,
                              maximumBytes: Self.maximumBytes)
        try directory.validateCurrentLocation()
    }

    // Remove only the exact publication this owner made. A later epoch survives.
    @discardableResult package func withdraw(_ endpoint: Endpoint) throws -> Bool {
        try directory.validateCurrentLocation()
        let old = try directory.read("hosts.json", lockName: "hosts.lock", maximumBytes: Self.maximumBytes)
        let hosts = try Self.decode(old)
        guard hosts.contains(endpoint) else { return false }
        try directory.replace("hosts.json", lockName: "hosts.lock", data: Self.encode(hosts.filter { $0 != endpoint }),
                              expected: old, maximumBytes: Self.maximumBytes)
        try directory.validateCurrentLocation()
        return true
    }

    private static func decode(_ data: Data?) throws -> [Endpoint] {
        guard let data else { return [] }
        guard data.count <= maximumBytes,
              case .object(let root) = try? JSONDecoder().decode(AgentJSONValue.self, from: data),
              Set(root.keys) == ["version", "hosts"], root["version"] == .integer(1),
              case .array(let entries) = root["hosts"], entries.count <= maximumHosts else { throw AgentErrorCode.storageError }
        for entry in entries {
            guard case .object(let fields) = entry,
                  Set(fields.keys) == ["libraryID", "epochID", "socketPath"] else { throw AgentErrorCode.storageError }
        }
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              catalog.hosts.allSatisfy({ Endpoint.validPath($0.socketPath) }),
              Set(catalog.hosts.map(\.libraryID)).count == catalog.hosts.count,
              Set(catalog.hosts.map(\.epochID)).count == catalog.hosts.count else { throw AgentErrorCode.storageError }
        return catalog.hosts.sorted { $0.libraryID.uuidString < $1.libraryID.uuidString }
    }

    private static func encode(_ hosts: [Endpoint]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Catalog(version: 1, hosts: hosts.sorted { $0.libraryID.uuidString < $1.libraryID.uuidString }))
        _ = try decode(data)
        return data
    }
}
