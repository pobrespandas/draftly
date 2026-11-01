import Foundation

// A copyable stdio configuration. It contains routing IDs, not credentials or grants.
package struct AgentClientConfiguration: Encodable, Equatable, Sendable {
    package struct Server: Encodable, Equatable, Sendable {
        package let command: String
        package let args: [String]
    }
    package let mcpServers: [String: Server]

    package init(helperPath: String, connectionID: UUID, libraryID: UUID, stateParent: String? = nil) throws {
        guard AgentHostDestination.absolutePath(helperPath) else { throw AgentErrorCode.invalidInput }
        let destination = AgentHostDestination.library(libraryID, stateParent: stateParent)
        // Validate the same path and argument rules that the executable accepts.
        _ = try AgentHostDestination(cliArguments: destination.cliArguments)
        mcpServers = ["draftly-" + connectionID.uuidString.lowercased(): Server(command: helperPath,
            args: ["mcp", "--connection", connectionID.uuidString] + destination.cliArguments)]
    }

    package init(cliArguments args: [String], helperPath: String) throws {
        guard (args.count == 4 || args.count == 6), args[0] == "--connection",
              let connection = UUID(uuidString: args[1]),
              case .library(let library, let parent) = try AgentHostDestination(cliArguments: Array(args.dropFirst(2))) else {
            throw AgentErrorCode.invalidInput
        }
        try self.init(helperPath: helperPath, connectionID: connection, libraryID: library, stateParent: parent)
    }

    package func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
