import Testing
@testable import Draftly

@Suite("Editor display preferences")
struct EditorSyntaxDisplayPreferencesTests {
    @Test func separateSyntaxesPreserveOtherFieldsAndLegacyHighlight() throws {
        let original = #"{"Markdown":{"unknown":"🐼"},"Plain Text":{"paragraphNumbers":true}}"#
        let changed = try EditorSyntaxDisplayPreferences.setting(.paragraphNumbers, enabled: true, for: "Markdown", encoded: original)
        let disabled = try EditorSyntaxDisplayPreferences.setting(.highlightInsertionPoint, enabled: false, for: "Markdown", encoded: changed)
        #expect(EditorSyntaxDisplayPreferences.value(.paragraphNumbers, for: "Markdown", encoded: disabled))
        #expect(EditorSyntaxDisplayPreferences.value(.paragraphNumbers, for: "Plain Text", encoded: disabled))
        #expect(!EditorSyntaxDisplayPreferences.value(.paragraphNumbers, for: "TaskPaper", encoded: disabled))
        #expect(!EditorSyntaxDisplayPreferences.value(.highlightInsertionPoint, for: "Markdown", encoded: disabled, legacyHighlight: true))
        #expect(EditorSyntaxDisplayPreferences.value(.highlightInsertionPoint, for: "TaskPaper", encoded: disabled, legacyHighlight: true))
        #expect(disabled.contains("🐼"))
    }
    @Test func invalidDocumentsRejectEdits() {
        #expect(throws: (any Error).self) {
            try EditorSyntaxDisplayPreferences.setting(.paragraphNumbers, enabled: true, for: "Markdown", encoded: "invalid")
        }
        #expect(throws: (any Error).self) {
            try EditorSyntaxDisplayPreferences.setting(.paragraphNumbers, enabled: true, for: "Markdown", encoded: #"{"Markdown":3}"#)
        }
    }
}
