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
        let (_, entries) = try snapshot()
        let cutoff = now().addingTimeInterval(-retention)
        return entries.filter { $0.libraryID == libraryID && $0.date >= cutoff }
            .sorted { $0.date == $1.date ? $0.id.uuidString > $1.id.uuidString : $0.date > $1.date }
    }

    func append(libraryID: UUID, connectionID: UUID, requestID: UUID, operation: String, result: String) throws {
        let timestamp = now()
        guard timestamp.timeIntervalSince1970.isFinite,
              AgentOperationCatalog.operation(named: operation) != nil,
              result == "success" || AgentErrorCode(rawValue: result) != nil else { throw AgentErrorCode.invalidInput }
        let entry = Entry(id: UUID(), libraryID: libraryID, connectionID: connectionID, requestID: requestID,
                          operation: operation, date: timestamp, result: result)
        try update { entries in
            let cutoff = timestamp.addingTimeInterval(-retention)
            entries.removeAll { $0.date < cutoff }
            entries.append(entry)
            if entries.count > limit { entries.removeFirst(entries.count - limit) }
        }
    }

    func clear(libraryID: UUID) throws {
        try update { $0.removeAll { $0.libraryID == libraryID } }
    }

    private func snapshot() throws -> (Data?, [Entry]) {
        let data = try directory.read(file, lockName: lock, maximumBytes: AgentRequest.maximumBytes)
        guard let data else { return (nil, []) }
        do {
            let entries = try JSONDecoder().decode([Entry].self, from: data)
            guard entries.count <= limit, Set(entries.map(\.id)).count == entries.count,
                  entries.allSatisfy({ $0.date.timeIntervalSince1970.isFinite &&
                      AgentOperationCatalog.operation(named: $0.operation) != nil &&
                      ($0.result == "success" || AgentErrorCode(rawValue: $0.result) != nil) }) else {
                throw AgentErrorCode.storageError
            }
            return (data, entries)
        } catch { throw AgentErrorCode.storageError }
    }

    private func update(_ change: (inout [Entry]) -> Void) throws {
        for _ in 0..<3 {
            let (old, current) = try snapshot()
            var next = current; change(&next)
            if next == current { return }
            let data = try JSONEncoder().encode(next)
            do {
                try directory.replace(file, lockName: lock, data: data, expected: old, maximumBytes: AgentRequest.maximumBytes)
                return
            } catch AgentErrorCode.versionConflict { continue }
        }
        throw AgentErrorCode.busy
    }
}
