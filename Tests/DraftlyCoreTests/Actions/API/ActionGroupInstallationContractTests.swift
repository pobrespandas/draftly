import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action group installation contracts") @MainActor
struct ActionGroupInstallationContractTests {
    @Test(arguments: [false, true])
    func emptyAndPopulatedGroupLinksPreserveRecordsAndInstallAtomically(worker: Bool) async throws {
        for populated in [false, true] {
            let (library, _, host, runner) = try makeAPIContext()
            var group = ActionGroupRecord(name: "Café 🐼 & ?")
            group.symbol = "folder.fill"; group.order = 7
            try library.saveActionGroup(group)
            var member = DraftAction(name: "Member café", steps: [])
            member.group = group.name; member.configuredValues = ["key": "value"]
            if populated { try library.saveActions([member]) }
            let source = makeAPIAction("""
            const group=ActionGroup.find('Café 🐼 & ?'), url=group.installURL;
            check(typeof url==='string' && url===group.installURL,'stable link');
            check(Reflect.set(group,'installURL','wrong')===false,'readonly link');
            app.setClipboard(url);
            """)
            let succeeded: Bool
            if worker { succeeded = await runner.runAsync(source).result.succeeded }
            else { succeeded = runner.run(source) }
            #expect(succeeded, Comment(rawValue: runner.message ?? ""))
            let url = try #require(URL(string: host.clipboard))
            let encoded = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "data" }?.value)
            let payload = Data(encoded.utf8)
            let backup = try JSONDecoder().decode(Backup.self, from: payload)
            #expect(backup.actionGroups == [group])
            #expect(backup.actions == (populated ? [member] : []))
            let target = try LibraryStore(inMemory: true, seed: false)
            let before = try target.backupData()
            target.beforeBatchCommit = { throw DraftlyError.message("Injected installation failure") }
            #expect(throws: (any Error).self) { try LibraryFileImport.apply(payload, fileExtension: "json", to: target) }
            target.beforeBatchCommit = nil
            #expect(try target.backupData() == before)
            try LibraryFileImport.apply(payload, fileExtension: "json", to: target)
            #expect(target.actionGroups == [group])
            #expect(target.actions == (populated ? [member] : []))
            #expect(try ActionImporter.installationActions(url) == (populated ? [member] : []))
        }
    }
}
