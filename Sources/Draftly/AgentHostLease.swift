import Foundation
import AgentContracts
import AgentLocalSecurity

// Keep this lease alive for the whole broker lifetime. A locator is not a lease.
@MainActor final class AgentHostLease {
    private struct Identity: Codable {
        let version: Int
        let libraryID: UUID
        let storeID: UUID
        let volumeID: UUID
        let fileID: String
        let locationKey: String

        static func decode(_ data: Data) throws -> Self {
            guard case .object(let root) = try? JSONDecoder().decode(AgentJSONValue.self, from: data),
                  Set(root.keys) == ["version", "libraryID", "storeID", "volumeID", "fileID", "locationKey"],
                  root["version"] == .integer(1), let value = try? JSONDecoder().decode(Self.self, from: data),
                  let fileID = UInt64(value.fileID), String(fileID) == value.fileID,
                  value.locationKey.count == 64, value.locationKey.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw AgentErrorCode.storageError
            }
            return value
        }
    }

    let libraryID: UUID
    let location: AgentLibraryLocation
    private let directory: AgentStateDirectory
    private let pathLock: AgentStateFileLock
    private let physicalLock: AgentStateFileLock
    private let identityBytes: Data
    private var closed = false
    private var invalidated: AgentErrorCode?

    init(location: AgentLibraryLocation) throws {
        try location.validate()
        let directory = try AgentStateDirectory(parentDirectory: location.url.deletingLastPathComponent())
        try directory.validateCurrentLocation()
        let pathLock = try directory.acquireLock("owner-path-" + location.locationKey + ".lock")
        do {
            let physicalLock = try directory.acquireLock("owner-file-" + location.physicalKey + ".lock")
            do {
                try pathLock.validate(); try physicalLock.validate(); try location.validate()
                let identity = try Self.identity(location: location, directory: directory)
                try pathLock.validate(); try physicalLock.validate(); try location.validate()
                self.libraryID = identity.record.libraryID; self.identityBytes = identity.data
                self.location = location; self.directory = directory
                self.pathLock = pathLock; self.physicalLock = physicalLock
            } catch { physicalLock.release(); throw error }
        } catch { pathLock.release(); throw error }
    }

    func close() {
        guard !closed else { return }; closed = true
        physicalLock.release(); pathLock.release()
    }

    func validate() throws {
        guard !closed else { throw AgentErrorCode.cancelled }
        if let invalidated { throw invalidated }
        do {
            try pathLock.validate(); try physicalLock.validate(); try location.validate()
            guard try directory.read(Self.identityName(location), lockName: Self.identityLock(location), maximumBytes: 4096) == identityBytes else {
                throw AgentErrorCode.versionConflict
            }
        } catch {
            let code = (error as? AgentErrorCode) ?? .storageError
            // Contention is temporary. A changed or untrusted owner needs a new
            // host epoch even if someone later restores the previous file.
            if code != .busy { invalidated = code }
            throw code
        }
    }

    private static func identity(location: AgentLibraryLocation, directory: AgentStateDirectory) throws -> (record: Identity, data: Data) {
        let old = try directory.read(identityName(location), lockName: identityLock(location), maximumBytes: 4096)
        if let old {
            let record = try Identity.decode(old)
            guard record.locationKey == location.locationKey else { throw AgentErrorCode.storageError }
            if record.storeID == location.storeID && record.volumeID == location.volumeID && record.fileID == location.fileID {
                return (record, old)
            }
        }
        let record = Identity(version: 1, libraryID: UUID(), storeID: location.storeID, volumeID: location.volumeID,
                              fileID: location.fileID, locationKey: location.locationKey)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        try location.validate(); try directory.validateCurrentLocation()
        try directory.replace(identityName(location), lockName: identityLock(location), data: data, expected: old, maximumBytes: 4096)
        guard try directory.read(identityName(location), lockName: identityLock(location), maximumBytes: 4096) == data else {
            throw AgentErrorCode.storageError
        }
        return (record, data)
    }

    private static func identityName(_ location: AgentLibraryLocation) -> String { location.locationKey + ".identity.json" }
    private static func identityLock(_ location: AgentLibraryLocation) -> String { location.locationKey + ".identity.lock" }
}
