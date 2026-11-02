import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Action catalog presentation")
struct ActionCatalogPresentationTests {
    @Test func editingBarContainsEachCatalogActionOnceWithoutSectionDividers() {
        let entries = ActionCatalogPresentation.entries(DefaultActionCatalog.actions, on: .bar, group: "Editing")
        #expect(entries.count == 25)
        #expect(entries.allSatisfy { $0.kind == .action })
        #expect(entries.filter { $0.source.name == "Undo" }.count == 1)
    }
    @Test func defaultsShareAppearanceAcrossSurfacesAndRetainExecution() throws {
        let source = try #require(DefaultActionCatalog.actions.first { $0.name == "Move Left" && $0.group == "Editing" })
        let list = try #require(ActionCatalogPresentation.entries([source], on: .list).first).source
        let bar = try #require(ActionCatalogPresentation.entries([source], on: .bar).first).source
        #expect(list == bar)
        #expect(list.symbol == "chevron.left")
        #expect(list.presentation.tintColor == "yellow")
        #expect(list.steps == source.steps && list.id == source.id)
        #expect(source.symbol == "chevron.left" && source.presentation.tintColor == "yellow")
    }

    @Test func customizedAndUnrelatedActionsKeepTheirAppearance() throws {
        var source = try #require(DefaultActionCatalog.actions.first { $0.name == "Message" })
        source.symbol = "star"
        source.presentation.tintColor = "red"
        #expect(ActionCatalogPresentation.displayAction(source) == source)
        source.id = UUID()
        source.presentation.tintColor = nil
        #expect(ActionCatalogPresentation.displayAction(source) == source)
    }

    @Test func defaultGroupsHaveDistinctSymbolsAndStableColors() {
        let groups = DefaultActionCatalog.groups
        #expect(Set(groups.map { ActionCatalogPresentation.groupSymbol($0.name, groups: groups) }).count == 5)
        #expect(ActionCatalogPresentation.groupColor("Editing", groups: groups) == "gray")
        #expect(ActionCatalogPresentation.groupColor("Processing", groups: groups) == "blue")
    }
    @Test func groupHeaderAndBarUseTheSameSymbolWhileSearchUsesItsOwnIcon() {
        var group = ActionGroupRecord(name: "Basic"); group.symbol = "arrow.up.forward.app"
        #expect(ActionCatalogPresentation.groupSymbol("Basic", groups: [group]) == "arrow.up.forward.app")
        #expect(ActionCatalogPresentation.groupSymbol("Basic", groups: [group], searching: true) == "magnifyingglass")
        #expect(ActionCatalogPresentation.groupSymbol("Missing", groups: [group]) == "arrow.up.right.square")
    }
    @Test func importedTintNamesUseSharedColorsAndUnknownNamesKeepSurfaceDefaults() {
        #expect(ActionTint.color("green") == .green)
        #expect(ActionTint.color("orange") == .orange)
        #expect(ActionTint.color("blue") == .blue)
        #expect(ActionTint.color("none") == .primary)
        #expect(ActionTint.color(nil) == nil)
        #expect(ActionTint.color("future-color") == nil)
    }

    @Test func barLabelsRespectTextChoiceAndKeepFullNameForAccessibility() {
        var action = DraftAction(name: "Full action café 🐼", steps: [])
        #expect(ActionBarLabel(action).text == action.name && ActionBarLabel(action).usesIcon)
        #expect(!ActionBarLabel(action).showsText)
        action.presentation.barLabel = "Short 🐼"
        action.presentation.barUsesIcon = false
        let text = ActionBarLabel(action)
        #expect(text.text == "Short 🐼" && !text.usesIcon)
        #expect(text.accessibilityLabel == action.name)
        action.presentation.barLabel = ""
        #expect(ActionBarLabel(action).text == action.name)
        action.presentation.barUsesIcon = true
        #expect(ActionBarLabel(action).usesIcon)
        #expect(!ActionBarLabel(action).showsText)
        #expect(action.presentation.barLabel == "")
        action.presentation.barLabel = "Insert"
        #expect(ActionBarLabel(action).usesIcon && ActionBarLabel(action).showsText)
        #expect(ActionBarLabel(action).text == "Insert")
    }

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
