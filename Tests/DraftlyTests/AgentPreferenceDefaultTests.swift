import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Agent preference default characterization") @MainActor
struct AgentPreferenceDefaultTests {
    @Test func nativeEditorDefaultsKeepTheirExistingValues() {
        let editor = NativeEditor(session: EditorSession(), fontName: "System", fontSize: 17,
            lineSpacing: 2, markdown: false, onChange: {})
        #expect(editor.monospaceFontName == "System Monospace")
        #expect(editor.lineHeightMultiple == 0)
        #expect(editor.paragraphSpacing == 0)
        #expect(editor.horizontalMargin == 6)
        #expect(editor.verticalMargin == 26)
        #expect(editor.maximumWidth == 0)
        #expect(editor.showCustomTouchBar)
        #expect(!editor.highlightInsertionPoint)
    }

    @Test func HTMLDefaultsAndLegacyBooleanResolutionStayUnchanged() throws {
        let name = "Draftly-Agent-Defaults-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let value = HTMLPreferences.options(defaults: defaults)
        #expect(value["strongMark"] as? String == "**")
        #expect(value["emphasisMark"] as? String == "_")
        #expect(value["ulItemMark"] as? String == "-")
        #expect(value["inlineLinks"] as? Bool == true)
        #expect(value["ignoreLinks"] as? Bool == false)
        defaults.set("YES", forKey: "html.ignoreLinks")
        #expect(HTMLPreferences.options(defaults: defaults)["ignoreLinks"] as? Bool == true)
        defaults.set("invalid", forKey: "html.strongMark")
        #expect(HTMLPreferences.options(defaults: defaults)["strongMark"] as? String == "**")
    }

    @Test func generalDefaultsDoNotPersistWhenRead() throws {
        let name = "Draftly-Agent-General-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(GeneralPreferences.showMainWindowAtLaunch(defaults: defaults))
        #expect(GeneralPreferences.showInMenuBar(defaults: defaults))
        #expect(!WindowPreferences(defaults: defaults).prefersAdvancedFind)
        #expect((defaults.persistentDomain(forName: name) ?? [:]).isEmpty)
        defaults.set("YES", forKey: GeneralPreferences.advancedFindKey)
        #expect(WindowPreferences(defaults: defaults).prefersAdvancedFind)
    }
}
