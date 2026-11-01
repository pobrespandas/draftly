import Foundation
import Testing
@_spi(DraftlyInternal) @testable import DraftlyCore
@testable import Draftly

@Suite("Default action window selection") @MainActor
struct DefaultActionWindowGroupTests {
    @Test func newWindowSelectsAVisibleCatalogGroup() throws {
        let preferences = try TestPreferences(prefix: "Draftly-DefaultActionWindow-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true)
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        #expect(model.actionGroup == "Basic")
        #expect(!library.orderedActions(on: .list).filter { $0.group == model.actionGroup }.isEmpty)
    }
    @Test(arguments: ["All Actions", "Markdown", "Missing 🐼"])
    func reconciliationPreservesValidSelections(selection: String) throws {
        let preferences = try TestPreferences(prefix: "Draftly-DefaultActionSelection-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true)
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.actionGroup = selection
        model.reconcileActionGroup()
        #expect(model.actionGroup == (selection == "Missing 🐼" ? "Basic" : selection))
    }

    @Test func anEmptyCatalogKeepsAllActionsWhenActionsArrive() throws {
        let preferences = try TestPreferences(prefix: "Draftly-DefaultActionArrival-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        #expect(model.actionGroup == "All Actions")
        _ = try library.reinstallDefaultActions()
        model.reconcileActionGroup()
        #expect(model.actionGroup == "All Actions")
    }

}
