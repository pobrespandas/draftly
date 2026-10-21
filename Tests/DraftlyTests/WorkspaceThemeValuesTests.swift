import Testing
@testable import Draftly

@Suite("Workspace theme metadata values")
struct WorkspaceThemeValuesTests {
    @Test func readsTheRequestedThemeName() {
        let metadata = ["api": #"{"preferredDarkTheme":{"name":"Café 🐼","uuid":"keep","future":true},"preferredLightTheme":{"name":"Light"}}"#]
        #expect(WorkspaceThemeValues.preference(metadata, key: "preferredDarkTheme") == "Café 🐼")
        #expect(WorkspaceThemeValues.preference(metadata, key: "preferredLightTheme") == "Light")
        #expect(WorkspaceThemeValues.preference(metadata, key: "missing") == nil)
    }

    @Test func missingMetadataHasNoThemeName() {
        #expect(WorkspaceThemeValues.preference(nil, key: "preferredDarkTheme") == nil)
        #expect(WorkspaceThemeValues.preference([:], key: "preferredDarkTheme") == nil)
        #expect(WorkspaceThemeValues.preference(["other": "value"], key: "preferredDarkTheme") == nil)
    }

    @Test(arguments: ["", "{invalid", "[]", "null", "17", #"{"preferredDarkTheme":17}"#,
                      #"{"preferredDarkTheme":[]}"#, #"{"preferredDarkTheme":{}}"#,
                      #"{"preferredDarkTheme":{"name":17}}"#, #"{"preferredDarkTheme":{"name":null}}"#])
    func malformedMetadataAndWrongValueTypesHaveNoThemeName(api: String) {
        #expect(WorkspaceThemeValues.preference(["api": api], key: "preferredDarkTheme") == nil)
    }
}
