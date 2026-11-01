import Foundation
import Testing
import AgentContracts

@Suite("Agent host destination arguments")
struct AgentHostDestinationTests {
    @Test func destinationsRoundTripWithoutReadingFilesOrChangingPathText() throws {
        let id = UUID()
        for destination: AgentHostDestination in [.socket("/tmp/neutral 🐼/s"), .library(id, stateParent: nil),
            .library(id, stateParent: "/tmp/not-created 🐼")] {
            #expect(try AgentHostDestination(cliArguments: destination.cliArguments) == destination)
        }
        #expect(try AgentHostDestination(cliArguments: ["--library", id.uuidString.lowercased()]) == .library(id, stateParent: nil))
    }

    @Test func malformedMixedAndUnknownArgumentsCannotSelectAnotherDestination() {
        let id = UUID().uuidString
        let invalid: [[String]] = [[], ["--library"], ["--library", "bad"], ["--socket", "relative"],
            ["--socket", "/tmp/with\0nul"], ["--library", id, "--state-parent", "relative"],
            ["--library", id, "--state-parent", "/tmp/with\0nul"],
            ["--socket", "/tmp/s", "--state-parent", "/tmp/parent"],
            ["--library", id, "--socket", "/tmp/s"], ["--library", id, "--library", id],
            ["--library", id, "--credential", "not-a-secret"], ["--unknown", "/tmp/s"],
            ["--library", id, "--state-parent", "/tmp/p", "extra"]]
        for args in invalid {
            #expect(throws: AgentErrorCode.invalidInput) { try AgentHostDestination(cliArguments: args) }
        }
    }
}
