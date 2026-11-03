import Foundation
import Testing
@testable import Draftly

@Suite("Codex app-server transport") @MainActor
struct CodexAppServerClientTests {
    @Test func authenticationConnectionCannotStartInferenceOrTools() async {
        let client = CodexAppServerClient.authenticationClient()
        for method in ["thread/start", "turn/start", "mcpServer/tool/call", "config/batchWrite"] {
            do {
                _ = try await client.request(method)
                Issue.record("An authentication connection accepted an execution request.")
            } catch { #expect(error.localizedDescription.contains("authentication connection cannot run")) }
        }
        #expect(throws: (any Error).self) { try client.notify("turn/start") }
    }
    @Test func routesRepliesAndDeniesServerRequestsUntilAHandlerExists() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        read -r request
        printf '%s' '{"id":1,"result":'
        printf '%s\\n' '{"ready":true}}'
        read -r request
        printf '%s\\n' '{"method":"item/commandExecution/requestApproval","id":91,"params":{}}'
        read -r reply
        case "$reply" in
          *'not authorized'*) printf '%s\\n' '{"id":2,"result":{"denied":true}}' ;;
          *) exit 7 ;;
        esac
        while read -r request; do :; done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let client = CodexAppServerClient.protocolFixture()
        defer { client.close() }
        try client.start(executable: executable, home: root.appendingPathComponent("home"))
        let first = try await client.request("initialize")
        #expect((try JSONSerialization.jsonObject(with: first) as? [String: Bool])?["ready"] == true)
        let second = try await client.request("turn/start")
        #expect((try JSONSerialization.jsonObject(with: second) as? [String: Bool])?["denied"] == true)
    }

    @Test func failedLaunchLeavesTheClientDisconnected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = CodexAppServerClient.protocolFixture()
        #expect(throws: (any Error).self) {
            try client.start(executable: root.appendingPathComponent("missing"), home: root)
        }
        await #expect(throws: (any Error).self) { try await client.request("initialize") }
    }
}
