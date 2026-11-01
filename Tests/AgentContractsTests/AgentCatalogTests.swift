import Foundation
import Testing
@testable import AgentContracts

@Suite("Required agent operation inventory")
struct AgentCatalogTests {
    @Test func requiredOperationsCannotDisappearOrBecomeExecutableByCatalogRegistration() throws {
        let url = try #require(Bundle.module.url(forResource: "required-operations", withExtension: "txt"))
        let required = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        let catalog = AgentOperationCatalog.operations
        #expect(Set(required) == Set(catalog.map(\.name)))
        #expect(catalog.count == Set(catalog.map(\.name)).count)
        #expect(catalog.allSatisfy { !$0.owner.isEmpty && !$0.hasHandler })
    }

    @Test(arguments: ["drafts.purge", "actions.delete", "actionGroups.delete", "workspaces.delete", "themes.delete", "syntaxes.delete", "backups.requestRestore", "native.shell", "native.appleScript", "native.shortcut"])
    func consequentialOperationsNeverBypassHumanApproval(name: String) throws {
        #expect(try #require(AgentOperationCatalog.operation(named: name)).requiresHumanApproval)
    }
}
