import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action catalog rules")
struct ActionCatalogTests {
    @Test func storedGroupsKeepTheirInputOrderBeforeImplicitNamesAndFirstRecordWins() {
        var stored = ActionGroupRecord(name: "Z stored"); stored.order = 9; stored.symbol = "folder.fill"
        var earlier = ActionGroupRecord(name: "A stored"); earlier.order = 0
        var repeated = ActionGroupRecord(name: stored.name); repeated.id = UUID(); repeated.symbol = "star"
        let actions = [action("One", group: "Z implicit"), action("Two", group: "A implicit"), action("Three", group: "Z implicit")]
        let catalog = ActionCatalog(actions: actions, groups: [stored, earlier, repeated])

        #expect(catalog.groupNames == ["Z stored", "A stored", "A implicit", "Z implicit"])
        #expect(catalog.groupRecord(named: stored.name) == stored)
        #expect(catalog.groupIdentifiers[stored.name] == stored.id)
        #expect(catalog.groupRecord(named: "A implicit").id == ActionGroupRecord.identifier(for: "A implicit"))
    }

    @Test func actionOrderUsesGroupPriorityThenExplicitOrDefaultPositionThenNameAndUUID() throws {
        var hidden = action("Hidden", order: -2)
        hidden.presentation.showInList = false; hidden.presentation.showInSearch = false
        let copy = action("Copy"), share = action("Share"), explicitZero = action("Zed", order: 0)
        let item2 = action("Item 2", order: 1), item10 = action("Item 10", order: 1)
        var low = action("Twin", order: 2), high = action("Twin", order: 2)
        low.id = try #require(UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        high.id = try #require(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        let otherGroup = action("Before every position", group: "Second", order: -100)
        let catalog = ActionCatalog(actions: [otherGroup, high, share, item10, hidden, copy, item2, low, explicitZero],
            groups: [ActionGroupRecord(name: "General"), ActionGroupRecord(name: "Second")])
        let visible = [copy, explicitZero, item2, item10, share, low, high, otherGroup].map(\.id)

        #expect(catalog.orderedActions(on: nil).map(\.id) == [hidden.id] + visible)
        #expect(catalog.orderedActions(on: .list).map(\.id) == visible)
        #expect(catalog.orderedActions(on: .bar).map(\.id) == [hidden.id] + visible)
        #expect(catalog.orderedActions(on: .search).map(\.id) == visible)
    }

    private func action(_ name: String, group: String = "General", order: Int? = nil) -> DraftAction {
        var action = DraftAction(name: name, steps: [])
        action.group = group
        if let order { action.presentation.order = order }
        return action
    }
}
