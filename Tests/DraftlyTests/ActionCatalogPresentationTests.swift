import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Action catalog presentation")
struct ActionCatalogPresentationTests {
    private func action(_ name: String, group: String = "General", section: String = "", separator: Bool = false) -> DraftAction {
        var action = DraftAction(name: name, steps: [])
        action.group = group
        if separator { action.scriptMetadata = ["isSeparator": "true"] }
        var options = ActionPresentation(); options.section = section; action.options = options
        return action
    }

    @Test func explicitSeparatorsKeepIdentityAndOrderWithoutRunnableRows() {
        let first = action("Z"), separator = action("Section", separator: true), last = action("A")
        let entries = ActionCatalogPresentation.entries([first, separator, last], on: .list)
        #expect(entries.map(\.id) == [first.id, separator.id, last.id])
        #expect(entries[1].kind == .separator && entries[1].runnableAction == nil)
        #expect(entries[1].source.name == "Section")
        #expect(entries.compactMap(\.runnableAction).map(\.id) == [first.id, last.id])
        #expect(first.steps.isEmpty && entries[0].runnableAction != nil)
    }

    @Test func searchAndExecutablePickersNeverReturnSeparators() {
        let separator = action("Match", separator: true), ordinary = action("Match")
        #expect(ActionCatalogPresentation.entries([separator, ordinary], on: .search).map(\.id) == [ordinary.id])
        #expect(ActionCatalogPresentation.entries([separator, ordinary], on: .list, query: "Match").map(\.id) == [ordinary.id])
        #expect(ActionCatalogPresentation.actions([separator, ordinary]).map(\.id) == [ordinary.id])
        #expect(ActionCatalogPresentation.actions([separator]).isEmpty)
    }

    @Test func visibilityAndGroupFiltersApplyBeforePresentation() {
        var hidden = action("Hidden"), separator = action("Group divider", group: "Other", separator: true)
        hidden.options?.showInList = false
        separator.options?.showInBar = false
        let ordinary = action("Visible", group: "Other")
        #expect(ActionCatalogPresentation.entries([hidden, separator, ordinary], on: .list, group: "General").isEmpty)
        #expect(ActionCatalogPresentation.entries([hidden, separator, ordinary], on: .list, group: "Other").map(\.id) == [separator.id, ordinary.id])
        #expect(ActionCatalogPresentation.entries([separator, ordinary], on: .bar, group: "Other").map(\.id) == [ordinary.id])
    }

    @Test func sectionHeadingsRespectOrderedGroupBoundaries() {
        let first = action("First", section: "Section"), second = action("Second", section: "Section")
        let third = action("Third", group: "Other", section: "Section"), fourth = action("Fourth", group: "Other", section: "Next")
        let entries = ActionCatalogPresentation.entries([first, second, third, fourth])
        #expect(entries.map(\.sectionHeading) == ["Section", nil, "Section", "Next"])
    }

    @Test func descriptionSearchKeepsOnlyExecutableMatches() {
        var ordinary = action("Name"), separator = action("Divider", separator: true)
        ordinary.options?.description = "Neutral café search"
        separator.options?.description = "Neutral café search"
        #expect(ActionCatalogPresentation.actions([separator, ordinary], on: .search, query: "café").map(\.id) == [ordinary.id])
    }

    @Test func importedSeparatorPayloadAndUnknownFieldsRemainIntact() throws {
        let data = Data(#"{"name":"Imported section","backingIsSeparator":true,"steps":[],"unknown":{"nested":[1,2]},"keyCommand":{"input":"k","commandKey":true}}"#.utf8)
        let imported = try #require(ActionImporter.decode(data).first)
        let entries = ActionCatalogPresentation.entries([imported], on: .list)
        #expect(entries.count == 1 && entries[0].source == imported && entries[0].runnableAction == nil)
        let exported = try JSONEncoder().encode(entries[0].source)
        let restored = try JSONDecoder().decode(DraftAction.self, from: exported)
        #expect(restored.isSeparator && restored.rawPayload == imported.rawPayload)
        #expect(restored.shortcut == imported.shortcut && restored.shortcutModifiers == imported.shortcutModifiers)
        let original = try #require(restored.rawPayload).data(using: .utf8)
        let raw = try JSONSerialization.jsonObject(with: #require(original)) as? [String: Any]
        #expect((raw?["unknown"] as? [String: Any])?["nested"] as? [Int] == [1, 2])
    }
}
