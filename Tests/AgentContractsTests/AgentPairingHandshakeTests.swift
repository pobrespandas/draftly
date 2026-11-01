import Foundation
import Testing
@testable import AgentContracts

@Suite("Strict pairing wire messages")
struct AgentPairingHandshakeTests {
    @Test func startAndAuthenticationRemainSeparateIntroductions() throws {
        let start = try AgentPairingHandshake.Start(clientName: "Neutral 🐼")
        let data = try AgentPairingHandshake.encode(start)
        guard case .pair(let decoded) = try AgentPairingHandshake.Introduction.decode(data) else { Issue.record("Wrong introduction"); return }
        #expect(decoded.clientName == start.clientName)
        let auth = try AgentLocalHandshake.Hello(connectionID: UUID(), credential: Data(repeating: 1, count: 32))
        guard case .authenticate(let decoded) = try AgentPairingHandshake.Introduction.decode(JSONEncoder().encode(auth)) else {
            Issue.record("Wrong authentication introduction"); return
        }
        #expect(decoded.connectionID == auth.connectionID)
        #expect(throws: AgentErrorCode.invalidInput) { try AgentLocalHandshake.Hello.decode(data) }
    }

    @Test func startRejectsAuthorityInjectionVersionsAndInvalidNames() throws {
        let start = try AgentPairingHandshake.encode(AgentPairingHandshake.Start(clientName: "Client"))
        guard case .object(let base) = try JSONDecoder().decode(AgentJSONValue.self, from: start) else { return }
        for key in ["credential", "capabilities", "scope", "libraryID", "approved", "connectionID"] {
            var changed = base; changed[key] = .string("untrusted")
            #expect(throws: AgentErrorCode.invalidInput) { try AgentPairingHandshake.Start.decode(JSONEncoder().encode(AgentJSONValue.object(changed))) }
        }
        for version: AgentJSONValue in [.integer(2), .number(Decimal(string: "1.00000000000000001")!), .string("1")] {
            var changed = base; changed["apiVersion"] = version
            #expect(throws: AgentErrorCode.invalidInput) { try AgentPairingHandshake.Start.decode(JSONEncoder().encode(AgentJSONValue.object(changed))) }
        }
        for name in ["", " \n", "line\nbreak", String(repeating: "x", count: 257)] {
            #expect(throws: AgentErrorCode.invalidInput) { try AgentPairingHandshake.Start(clientName: name) }
        }
    }

    @Test func controlsAllowOnlyPollOrCancelAndExactKeys() throws {
        for command in [AgentPairingHandshake.Command.poll, .cancel] {
            let input = AgentPairingHandshake.Control(pairingID: UUID(), command: command)
            let output = try AgentPairingHandshake.Control.decode(AgentPairingHandshake.encode(input))
            #expect(output.command == command && output.pairingID == input.pairingID)
        }
        let id = UUID().uuidString
        for extra in [",\"approved\":true", ",\"credential\":null", ",\"targets\":[]"] {
            let raw = "{\"apiVersion\":1,\"pairingID\":\"\(id)\",\"command\":\"poll\"\(extra)}"
            #expect(throws: AgentErrorCode.invalidInput) { try AgentPairingHandshake.Control.decode(Data(raw.utf8)) }
        }
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentPairingHandshake.Control.decode(Data("{\"apiVersion\":1,\"pairingID\":\"\(id)\",\"command\":\"approve\"}".utf8))
        }
    }

    @Test func replyShapesKeepChallengesStatesAndErrorsDistinct() throws {
        let id = UUID(), connection = UUID(), code = UUID().uuidString
        let challenge = try AgentPairingHandshake.Reply.decode(AgentPairingHandshake.encode(AgentPairingHandshake.Reply(
            pairingID: id, code: code, expiresAt: Date(timeIntervalSince1970: 123456))))
        #expect(challenge.pairingID == id && challenge.code == code && challenge.expiresAt == 123456)
        for state in [AgentPairingHandshake.State.pending, .denied, .cancelled, .expired, .invalidated] {
            let decoded = try AgentPairingHandshake.Reply.decode(AgentPairingHandshake.encode(AgentPairingHandshake.Reply(pairingID: id, state: state)))
            #expect(decoded.state == state && decoded.connectionID == nil && decoded.error == nil)
        }
        let approved = try AgentPairingHandshake.Reply.decode(AgentPairingHandshake.encode(AgentPairingHandshake.Reply(pairingID: id, state: .approved, connectionID: connection)))
        #expect(approved.connectionID == connection)
        let failed = try AgentPairingHandshake.Reply.decode(AgentPairingHandshake.encode(AgentPairingHandshake.Reply(pairingID: id, state: .failed, error: .outcomeUnknown)))
        #expect(failed.state == .failed && failed.error == .outcomeUnknown)
        let unavailable = try AgentPairingHandshake.Reply.decode(AgentPairingHandshake.encode(AgentPairingHandshake.Reply(error: .unavailable)))
        #expect(unavailable.state == nil && unavailable.error == .unavailable)
    }

    @Test func malformedRepliesCannotImplyApprovalOrHideAuthorityFields() throws {
        let id = UUID()
        for value in [AgentPairingHandshake.Reply(pairingID: id, state: .approved),
                      .init(pairingID: id, state: .pending, connectionID: UUID()),
                      .init(pairingID: id, state: .failed), .init(pairingID: id, state: .cancelled, error: .cancelled)] {
            #expect(throws: AgentErrorCode.invalidInput) { try AgentPairingHandshake.Reply.decode(AgentPairingHandshake.encode(value)) }
        }
        let raw = "{\"apiVersion\":1,\"pairingID\":\"\(id)\",\"state\":\"pending\",\"credential\":\"secret\"}"
        #expect(throws: AgentErrorCode.invalidInput) { try AgentPairingHandshake.Reply.decode(Data(raw.utf8)) }
    }

    @Test func wireBudgetsApplyBeforeParsingAndEncoding() throws {
        #expect(throws: AgentErrorCode.invalidInput) { try AgentPairingHandshake.Introduction.decode(Data(repeating: 32, count: 4097)) }
        #expect(throws: AgentErrorCode.invalidInput) { try AgentPairingHandshake.Reply.decode(Data(repeating: 32, count: 4097)) }
        // One grapheme can contain many combining marks, despite the character limit.
        let name = "A" + String(repeating: "\u{0301}", count: 3000)
        #expect(AgentConnectionName.isValid(name))
        #expect(throws: AgentErrorCode.invalidInput) { try AgentPairingHandshake.encode(AgentPairingHandshake.Start(clientName: name)) }
    }
}
