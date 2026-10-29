import Foundation
import Testing
@testable import DraftlyCore

@Suite("File manager creation contracts") @MainActor
struct FileManagerCreationContractTests {
    @Test(arguments: [false, true]) func factoryAndDirectoryArgumentsReachHost(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Neutral", host: APIContractHost())
        let action = makeAPIAction("""
        FileManager.create(false).exists('cloud.txt');
        FileManager.create(true).createDirectory('Café 🐼','/parent');
        FileManager.create().createDirectory('legacy');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker))
        let calls = fixture.host.calls.filter { $0.0 == "fileAPI" }.map(\.1)
        try #require(calls.count == 3)
        #expect(calls[0]["storage"] as? String == "cloud")
        #expect(calls[1]["storage"] as? String == "local")
        #expect(calls[1]["path"] as? String == "/parent")
        #expect(calls[1]["name"] as? String == "Café 🐼")
        #expect(calls[2]["path"] as? String == "legacy")
        #expect(calls[2]["name"] == nil)
    }
}
