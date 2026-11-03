import Foundation
import Testing
@testable import Draftly

@Suite("Codex account connection") @MainActor
struct CodexAccountModelTests {
    @Test(arguments: [true, false])
    func loginCompletionAndBrowserFailureKeepTheReportedAccountAccurate(browserOpens: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-codex")
        let completion = browserOpens
            ? "{\"method\":\"account/login/completed\",\"params\":{\"loginId\":\"neutral-login\",\"success\":true}}"
            : ""
        let reply = browserOpens ? "{\"account\":{\"type\":\"chatgpt\"},\"requiresOpenaiAuth\":true}" : "{\"status\":\"canceled\"}"
        let script = """
        #!/bin/sh
        case "$*" in *keyring*) ;; *) exit 4 ;; esac
        read -r request
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r initialized
        read -r request
        printf '%s\\n' '{"id":2,"result":{"type":"chatgpt","loginId":"neutral-login","authUrl":"https://auth.openai.com/neutral-test"}}' '\(completion)'
        read -r request
        printf '%s\\n' '{"id":3,"result":\(reply)}'
        read -r request
        printf '%s\\n' '{"id":4,"result":{}}'
        while read -r request; do :; done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let model = CodexAccountModel(home: root.appendingPathComponent("home"))
        model.executable = executable
        defer { model.disconnect() }
        var opened: URL?
        await model.signIn { url in opened = url; return browserOpens }
        #expect(opened?.host == "auth.openai.com")
        if browserOpens {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while !model.isSignedIn, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(model.isSignedIn)
            #expect(!model.isAwaitingLogin)
            await model.signOut()
            #expect(!model.isSignedIn)
        } else {
            #expect(!model.isAwaitingLogin)
            #expect(!model.isSignedIn)
            #expect(model.errorMessage?.contains("could not be opened") == true)
        }
    }
}
