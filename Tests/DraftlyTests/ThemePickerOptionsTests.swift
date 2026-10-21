import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Theme picker options")
struct ThemePickerOptionsTests {
    @Test func builtInsKeepTheirOrderAndDistinctEditorAndWorkspaceRepresentations() {
        let options = ThemePickerOptions.values(themes: [])
        #expect(options.map(\.title) == ["Default", "Dark", "Light"])
        #expect(options.map(\.id) == ["Default", "Dark", "Light"])
        #expect(options.map(\.editorTag) == ["builtIn:Default", "builtIn:Dark", "builtIn:Light"])
        #expect(options.map(\.reference) == [["name": "Default"], ["name": "Dark"], ["name": "Light"]])
    }

    @Test func installedOptionsKeepInputOrderIdentityAndHomonymousTypesWithoutChangingThemes() {
        let custom = EditorTheme(name: "Default", unknownFields: ["future": .string("Keep")])
        let file = EditorTheme(name: "Café 🐼", type: "file")
        let sameName = EditorTheme(name: "Café 🐼")
        let themes = [custom, file, sameName]
        let options = Array(ThemePickerOptions.values(themes: themes).dropFirst(3))
        #expect(options.map(\.title) == ["Default", "Café 🐼 (File)", "Café 🐼"])
        #expect(options.map(\.id) == [custom.id.uuidString, file.id.uuidString, sameName.id.uuidString])
        #expect(options.map(\.editorTag) == ["custom:" + custom.id.uuidString,
            "file:" + file.id.uuidString, "custom:" + sameName.id.uuidString])
        #expect(options.map(\.reference) == [
            ["name": custom.name, "uuid": custom.id.uuidString, "type": "custom"],
            ["name": file.name, "uuid": file.id.uuidString, "type": "file"],
            ["name": sameName.name, "uuid": sameName.id.uuidString, "type": "custom"]])
        #expect(themes == [custom, file, sameName])
        #expect(custom.unknownFields == ["future": .string("Keep")])
    }

    @Test func renamingAnInstalledThemeKeepsBothSelectionIdentitiesAndUpdatesOnlyItsLabelAndName() throws {
        var theme = EditorTheme(name: "Before", type: "file")
        let before = try #require(ThemePickerOptions.values(themes: [theme]).last)
        theme.name = "After 🦊"
        let after = try #require(ThemePickerOptions.values(themes: [theme]).last)
        #expect(after.id == before.id && after.editorTag == before.editorTag)
        #expect(after.title == "After 🦊 (File)")
        #expect(after.reference == ["name": "After 🦊", "uuid": theme.id.uuidString, "type": "file"])
    }
}
