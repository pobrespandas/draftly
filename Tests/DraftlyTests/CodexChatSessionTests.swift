import Foundation
import Testing
@testable import Draftly

@Suite("Codex conversation events") @MainActor
struct CodexChatSessionTests {
    private func fixture(_ script: String) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake-codex")
        try ("#!/bin/sh\n" + script + "\nwhile read -r request; do :; done\n")
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (root, executable)
    }

    @Test(arguments: ["completed", "failed", "interrupted"])
    func earlyEventsRequireTheMatchingTurnAndSuccessfulCompletion(status: String) async throws {
        let (root, executable) = try fixture("""
        read -r request
        printf '%s\\n' '{"id":1,"result":{"thread":{"id":"thread-a"}}}'
        read -r request
        printf '%s\\n' \
          '{"method":"item/agentMessage/delta","params":{"threadId":"other","turnId":"turn-a","itemId":"message","delta":"Wrong thread"}}' \
          '{"method":"item/agentMessage/delta","params":{"threadId":"thread-a","turnId":"turn-a","itemId":"message","delta":"café"}}' \
          '{"method":"item/completed","params":{"threadId":"thread-a","turnId":"turn-a","item":{"type":"agentMessage","id":"message","text":"café 🐼"}}}' \
          '{"method":"turn/completed","params":{"threadId":"thread-a","turn":{"id":"turn-a","status":"\(status)","error":{"message":"Neutral failure"}}}}' \
          '{"id":2,"result":{"turn":{"id":"turn-a"}}}'
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = CodexAppServerClient()
        let active = CodexChatSession(client: client)
        client.onNotification = { active.receive($0, data: $1) }
        client.onDisconnect = { active.disconnected() }
        defer { client.close() }
        try client.start(executable: executable, home: root.appendingPathComponent("home"))
        do {
            let text = try await active.respond(prompt: "Neutral text", model: "test", workingDirectory: root)
            #expect(status == "completed")
            #expect(text == "café 🐼")
        } catch {
            #expect(status != "completed")
            if status == "interrupted" { #expect(error is CancellationError) }
            else { #expect(error.localizedDescription == "Neutral failure") }
        }
    }

    @Test func cancelInterruptsTheTurnAndKeepsTheConnectionUsable() async throws {
        let (root, executable) = try fixture("""
        read -r request
        printf '%s\\n' '{"id":1,"result":{"thread":{"id":"thread-a"}}}'
        read -r request
        printf '%s\\n' '{"id":2,"result":{"turn":{"id":"turn-a"}}}' \
          '{"method":"item/agentMessage/delta","params":{"threadId":"thread-a","turnId":"turn-a","itemId":"message","delta":"Started"}}'
        read -r request
        case "$request" in *interrupt*) ;; *) exit 8 ;; esac
        printf '%s\\n' '{"id":3,"result":{}}'
        read -r request
        printf '%s\\n' '{"id":4,"result":{"usable":true}}'
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = CodexAppServerClient()
        let active = CodexChatSession(client: client)
        client.onNotification = { active.receive($0, data: $1) }
        client.onDisconnect = { active.disconnected() }
        defer { client.close() }
        try client.start(executable: executable, home: root.appendingPathComponent("home"))
        var started = false
        active.onText = { _ in started = true }
        let task = Task { try await active.respond(prompt: "Wait", model: "test", workingDirectory: root) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !started, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(started)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let reply = try await client.request("probe")
        #expect((try JSONSerialization.jsonObject(with: reply) as? [String: Bool])?["usable"] == true)
    }
}
