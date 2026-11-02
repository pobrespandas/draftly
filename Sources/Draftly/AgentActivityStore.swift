import Foundation
import AgentContracts
import AgentLocalSecurity

// Device-local metadata only. Never store request parameters or result content.
@MainActor final class AgentActivityStore {
    struct Entry: Codable, Equatable, Identifiable {
        let id: UUID
        let libraryID: UUID
        let connectionID: UUID
        let requestID: UUID
        let operation: String
        let date: Date
        let result: String
    }

    private let directory: AgentStateDirectory
    private let now: () -> Date
    private let retention: TimeInterval = 30 * 24 * 60 * 60
    private let limit = 10_000
    private let file = "activity.json"
    private let lock = "activity.lock"

    init(parentDirectory: URL, now: @escaping () -> Date = Date.init) throws {
        directory = try AgentStateDirectory(parentDirectory: parentDirectory)
        self.now = now
    }

    func entries(libraryID: UUID) throws -> [Entry] {
        let timestamp = now()
        guard timestamp.timeIntervalSince1970.isFinite else { throw AgentErrorCode.unavailable }
        let cutoff = timestamp.addingTimeInterval(-retention)
        let entries = try update { $0.removeAll { $0.date < cutoff } }
        return entries.filter { $0.libraryID == libraryID }
            .sorted { $0.date == $1.date ? $0.id.uuidString > $1.id.uuidString : $0.date > $1.date }
    }

    func append(libraryID: UUID, connectionID: UUID, requestID: UUID, operation: String, result: String) throws {
        let timestamp = now()
        guard timestamp.timeIntervalSince1970.isFinite,
              AgentOperationCatalog.operation(named: operation) != nil,
              result == "success" || AgentErrorCode(rawValue: result) != nil else { throw AgentErrorCode.invalidInput }
        let entry = Entry(id: UUID(), libraryID: libraryID, connectionID: connectionID, requestID: requestID,
                          operation: operation, date: timestamp, result: result)
        _ = try update { entries in
            let cutoff = timestamp.addingTimeInterval(-retention)
            entries.removeAll { $0.date < cutoff }
            entries.append(entry)
            if entries.count > limit { entries.removeFirst(entries.count - limit) }
        }
    }

    func clear(libraryID: UUID) throws {
        _ = try update { $0.removeAll { $0.libraryID == libraryID } }
    }

    private func snapshot() throws -> (Data?, [Entry]) {
        let data = try directory.read(file, lockName: lock, maximumBytes: AgentRequest.maximumBytes)
        guard let data else { return (nil, []) }
        do {
            let entries = try JSONDecoder().decode([Entry].self, from: data)
            guard entries.count <= limit, Set(entries.map(\.id)).count == entries.count,
                  entries.allSatisfy({ $0.date.timeIntervalSince1970.isFinite &&
                      Self.validStoredOperation($0.operation) && Self.validStoredResult($0.result) }) else {
                throw AgentErrorCode.storageError
            }
            return (data, entries)
        } catch { throw AgentErrorCode.storageError }
    }

    // Older builds can read bounded identifiers written by newer builds.
    private static func validStoredOperation(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard value.utf8.count <= 128, parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            guard let first = part.utf8.first, (65...90).contains(first) || (97...122).contains(first) else { return false }
            return part.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
        }
    }

    private static func validStoredResult(_ value: String) -> Bool {
        guard (1...64).contains(value.utf8.count), let first = value.utf8.first, (97...122).contains(first) else { return false }
        return value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
    }

    private func update(_ change: (inout [Entry]) -> Void) throws -> [Entry] {
        for _ in 0..<3 {
            let (old, current) = try snapshot()
            var next = current; change(&next)
            if next == current { return current }
            let data = try JSONEncoder().encode(next)
            do {
                try directory.replace(file, lockName: lock, data: data, expected: old, maximumBytes: AgentRequest.maximumBytes)
                return next
            } catch AgentErrorCode.versionConflict { continue }
        }
        throw AgentErrorCode.busy
    }
}
