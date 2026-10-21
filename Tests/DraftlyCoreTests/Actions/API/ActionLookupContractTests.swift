import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action lookup contracts") @MainActor
struct ActionLookupContractTests {
    @Test(arguments: [false, true])
    func findUsesExactNamesAndReturnsFirstDuplicateOrUndefined(worker: Bool) async throws {
        let (library, _, _, runner) = try makeAPIContext()
        let name = "Café 🐼 & ?"
        var first = DraftAction(name: name, steps: []); first.group = "First group"
        var second = DraftAction(name: name, steps: []); second.group = "Second group"
        first.id = try #require(UUID(uuidString: "BBBF0003-0000-4000-8000-000000000013"))
        second.id = try #require(UUID(uuidString: "BBBF0003-0000-4000-8000-000000000014"))
        try library.saveActions([second, first])
        #expect(library.actions.first?.id == first.id)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.actions.first?.id == first.id)
        let expected = try #require(library.actions.first { $0.name == name })
        let source = makeAPIAction("""
        const found=Action.find('Café 🐼 & ?');
        check(found instanceof Action && found.uuid==='\(expected.id.uuidString)','first installed duplicate');
        check(Action.find('Café 🐼 & ?').uuid===found.uuid,'repeat identity');
        for(const name of ['café 🐼 & ?','Café','Café 🐼 & ? ','','Missing'])
            check(Action.find(name)===undefined,'missing exact name '+name);
        """)
        #expect(await ActionTestExecution.succeeds(source, runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
    }

}
