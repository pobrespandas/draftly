import Foundation
import Testing
import AgentContracts

@Suite("Local agent authentication envelopes")
struct AgentLocalHandshakeTests {
    @Test func helloRoundTripsOnlyTheConnectionAndFixedSizeCredential() throws {
        let id = UUID(), secret = Data(repeating: 8, count: 32)
        let data = try JSONEncoder().encode(AgentLocalHandshake.Hello(connectionID: id, credential: secret))
        let decoded = try AgentLocalHandshake.Hello.decode(data)
        #expect(decoded.connectionID == id && decoded.credential == secret)
        #expect(throws: AgentErrorCode.invalidInput) { try AgentLocalHandshake.Hello(connectionID: id, credential: Data()) }
    }
    @Test func helloRejectsWrongVersionUnknownAuthorityAndBadCredential() throws {
        let initial = try JSONEncoder().encode(AgentLocalHandshake.Hello(connectionID: UUID(), credential: Data(repeating: 1, count: 32)))
        let root = try #require(JSONSerialization.jsonObject(with: initial) as? [String: Any])
        for change: [String: Any] in [["apiVersion": 2], ["grantID": UUID().uuidString], ["credential": "bad"], ["credential": NSNull()]] {
            let data = try JSONSerialization.data(withJSONObject: root.merging(change, uniquingKeysWith: { _, new in new }))
            #expect(throws: AgentErrorCode.invalidInput) { try AgentLocalHandshake.Hello.decode(data) }
        }
    }
    @Test func welcomeCannotCarryBothAuthorityAndAnErrorOrInventASession() throws {
        let id = UUID(), value = try AgentLocalHandshake.Welcome.decode(JSONEncoder().encode(AgentLocalHandshake.Welcome(libraryID: id)))
        #expect(value.libraryID == id && value.error == nil)
        for root: [String: Any] in [["apiVersion": 1, "libraryID": id.uuidString, "error": "busy"],
                                   ["apiVersion": 1, "libraryID": id.uuidString, "sessionID": UUID().uuidString],
                                   ["apiVersion": 1], ["apiVersion": 2, "error": "busy"], ["apiVersion": 1, "error": NSNull()]] {
            #expect(throws: AgentErrorCode.invalidInput) { try AgentLocalHandshake.Welcome.decode(JSONSerialization.data(withJSONObject: root)) }
        }
        let refused = try AgentLocalHandshake.Welcome.decode(JSONEncoder().encode(AgentLocalHandshake.Welcome(error: .permissionDenied)))
        #expect(refused.error == .permissionDenied && refused.libraryID == nil)
    }
    @Test func authenticationFramesHaveASeparateSmallBudget() {
        let data = Data(repeating: 32, count: AgentLocalHandshake.maximumBytes + 1)
        #expect(throws: AgentErrorCode.invalidInput) { try AgentLocalHandshake.Hello.decode(data) }
        #expect(throws: AgentErrorCode.invalidInput) { try AgentLocalHandshake.Welcome.decode(data) }
    }
}
