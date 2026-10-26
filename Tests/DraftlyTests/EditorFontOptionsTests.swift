import Testing
@testable import Draftly

@Suite("Editor font choices")
struct EditorFontOptionsTests {
    @Test func commonFontsKeepTheirExistingLabelsAndStoredNames() {
        #expect(EditorFontOptions.common.map(\.title) == ["System", "SF Mono", "Menlo", "Helvetica Neue"])
        #expect(EditorFontOptions.common.map(\.postScriptName) == ["System", "SFMono-Regular", "Menlo-Regular", "HelveticaNeue"])
    }

    @Test func nerdFontsKeepTheirOrderWithoutDuplicateStoredNames() {
        let first = EditorFontOptions.Choice(title: "Nerd café", postScriptName: "NerdCafe-Regular")
        let sameFont = EditorFontOptions.Choice(title: "Duplicate name", postScriptName: first.postScriptName)
        let second = EditorFontOptions.Choice(title: "Nerd Mono", postScriptName: "NerdMono-Regular")
        let commonDuplicate = EditorFontOptions.Choice(title: "Other Menlo label", postScriptName: "Menlo-Regular")
        let options = EditorFontOptions.additional(nerdFonts: [first, sameFont, commonDuplicate, second], selected: second.postScriptName)
        #expect(options == [first, second])
        #expect(EditorFontOptions.additional(nerdFonts: [], selected: "System").isEmpty)
    }

    @Test(arguments: ["CourierNewPS-ItalicMT", "Missing font 🐼", ""])
    func configuredFontOutsideTheCatalogRemainsSelectableByItsExactStoredName(selected: String) {
        let nerd = EditorFontOptions.Choice(title: "Nerd Mono", postScriptName: "NerdMono-Regular")
        let options = EditorFontOptions.additional(nerdFonts: [nerd], selected: selected)
        #expect(options.first == nerd)
        #expect(options.count == 2)
        #expect(options.last?.postScriptName == selected)
        #expect(options.last?.title == (selected.isEmpty ? "Configured Font (empty name)" : selected))
    }
    @Test func installedCatalogIncludesAllFacesAndPreservesExactIdentities() {
        let options = EditorFontOptions.installed(families: ["Nerd 🐼", "Café", "Empty", "Café"]) { family in
            switch family {
            case "Café": [("Cafe-Italic", "Italic"), ("Cafe-Regular", "Regular"), ("", "Invalid")]
            case "Nerd 🐼": [("Nerd-Bold", "Bold"), ("Nerd-Regular", "Regular")]
            default: []
            }
        }
        #expect(options.map(\.postScriptName) == ["Cafe-Italic", "Cafe-Regular", "Nerd-Bold", "Nerd-Regular"])
        #expect(options.first?.title == "Café — Italic")
        #expect(options[1].title == "Café")
        #expect(Set(options.map(\.id)).count == options.count)
        let selected = EditorFontOptions.additional(nerdFonts: options, selected: "Absent 🐼")
        #expect(selected.last?.postScriptName == "Absent 🐼")
    }

}
