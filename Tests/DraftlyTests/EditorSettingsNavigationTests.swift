import Testing
import DraftlyCore
@testable import Draftly

@Suite("Editor settings navigation")
struct EditorSettingsNavigationTests {
    @Test func navigationStartsOnEditingWithMarkdown() {
        let navigation = EditorSettingsNavigation()
        #expect(navigation.section == .editing)
        #expect(navigation.syntax == "Markdown")
    }

    @Test func syntaxCatalogKeepsBuiltInOrderAndSortsUniqueInstalledNames() {
        let installed = ["Zebra", "Café 🐼", "Markdown", "Alpha", "Café 🐼", "markdown", " Alpha "]
        let original = installed
        let names = EditorSettingsNavigation.syntaxes(installed: installed)
        #expect(Array(names.prefix(ScriptSyntax.names.count)) == ScriptSyntax.names)
        #expect(Array(names.dropFirst(ScriptSyntax.names.count)) == [" Alpha ", "Alpha", "Café 🐼", "Zebra", "markdown"])
        #expect(names.filter { $0 == "Markdown" }.count == 1)
        #expect(installed == original)
        #expect(EditorSettingsNavigation.syntaxes(installed: []) == ScriptSyntax.names)
    }

    @Test func reconciliationPreservesValidSyntaxAndFallsBackAfterRemoval() {
        var navigation = EditorSettingsNavigation(section: .themes, syntax: "Café 🐼")
        navigation.reconcile(installed: ["Café 🐼", "Other"])
        #expect(navigation.syntax == "Café 🐼")
        #expect(navigation.section == .themes)
        navigation.reconcile(installed: ["Other"])
        #expect(navigation.syntax == "Markdown")
        #expect(navigation.section == .themes)
        navigation.syntax = "TaskPaper"
        navigation.reconcile(installed: [])
        #expect(navigation.syntax == "TaskPaper")
    }

    @Test func changingSectionsDoesNotChangeSyntaxOrAnotherNavigation() {
        var first = EditorSettingsNavigation(section: .syntax, syntax: "MultiMarkdown")
        let second = first
        for section in EditorSettingsSection.allCases {
            first.section = section
            #expect(first.syntax == "MultiMarkdown")
            #expect(second.section == .syntax)
            #expect(second.syntax == "MultiMarkdown")
        }
    }
}
