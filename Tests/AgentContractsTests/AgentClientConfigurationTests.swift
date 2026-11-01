import Foundation
import Testing
import AgentContracts

@Suite("Copyable local agent client configuration")
struct AgentClientConfigurationTests {
    @Test func exportedArgumentsSelectExactConnectionAndLibraryWithoutSecrets() throws {
        let connection = UUID(), library = UUID()
        for parent: String? in [nil, "/tmp/neutral 🐼/state"] {
            let configuration = try AgentClientConfiguration(helperPath: "/Applications/Neutral 🐼.app/Contents/Helpers/agent",
                connectionID: connection, libraryID: library, stateParent: parent)
            let data = try configuration.encoded()
            let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(Set(root.keys) == ["mcpServers"])
            let servers = try #require(root["mcpServers"] as? [String: [String: Any]])
            let server = try #require(servers["draftly-" + connection.uuidString.lowercased()])
            #expect(Set(server.keys) == ["command", "args"])
            #expect(server["command"] as? String == "/Applications/Neutral 🐼.app/Contents/Helpers/agent")
            let args = try #require(server["args"] as? [String])
            #expect(Array(args.prefix(3)) == ["mcp", "--connection", connection.uuidString])
            #expect(try AgentHostDestination(cliArguments: Array(args.dropFirst(3))) == .library(library, stateParent: parent))
            #expect(try configuration.encoded() == data)
        }
    }

    @Test func commandRequiresStableLibraryAndRejectsExtraOrMixedArguments() throws {
        let connection = UUID(), library = UUID(), helper = "/tmp/neutral helper"
        let args = ["--connection", connection.uuidString, "--library", library.uuidString]
        #expect(try AgentClientConfiguration(cliArguments: args, helperPath: helper) ==
            AgentClientConfiguration(helperPath: helper, connectionID: connection, libraryID: library))
        let invalid = [[], ["--connection"], ["--connection", "bad", "--library", library.uuidString],
            ["--connection", connection.uuidString, "--socket", "/tmp/socket"],
            args + ["--credential", "neutral"], args + ["--state-parent", "relative"], args + ["extra"]]
        for input in invalid {
            #expect(throws: AgentErrorCode.invalidInput) {
                try AgentClientConfiguration(cliArguments: input, helperPath: helper)
            }
        }
    }

    @Test func invalidPathsCannotProduceClientConfiguration() {
        for path in ["", "relative", "~/Applications/agent", "/tmp/agent\0other"] {
            #expect(throws: AgentErrorCode.invalidInput) {
                try AgentClientConfiguration(helperPath: path, connectionID: UUID(), libraryID: UUID())
            }
            #expect(throws: AgentErrorCode.invalidInput) {
                try AgentClientConfiguration(helperPath: "/tmp/agent", connectionID: UUID(), libraryID: UUID(), stateParent: path)
            }
        }
    }
}
