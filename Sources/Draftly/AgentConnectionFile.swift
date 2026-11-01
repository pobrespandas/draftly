import Foundation
import AgentContracts
import AgentLocalSecurity

// Local connection metadata only. Credentials never belong in this file.
@MainActor final class AgentConnectionFile {
    private let directory: AgentStateDirectory

    init(parentDirectory: URL) throws { directory = try AgentStateDirectory(parentDirectory: parentDirectory) }

    func read() throws -> Data? {
        try directory.read("connections.json", lockName: "connections.lock", maximumBytes: AgentRequest.maximumBytes)
    }

    func replace(_ data: Data, expected: Data?) throws {
        try directory.replace("connections.json", lockName: "connections.lock", data: data, expected: expected,
                              maximumBytes: AgentRequest.maximumBytes)
    }
}
