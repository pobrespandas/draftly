import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Application agent preference catalog") @MainActor
struct AgentPreferenceCatalogTests {
    @Test func inventoryContainsOnlyReviewedFields() throws {
        let registry = try AgentPreferenceCatalog.make()
        let expected = """
        application.appearance application.showInMenuBar application.showMainWindowAtLaunch
        editor.preferAdvancedFind editor.showCustomTouchBar application.actionMoveNavigation
        capture.newDraftAfter application.launchAtLogin application.indexDraftsInSpotlight
        editor.fontName editor.monospaceFontName editor.fontSize editor.lineSpacing
        editor.lineHeightMultiple editor.paragraphSpacing editor.horizontalMargin editor.verticalMargin editor.maximumWidth
        editor.typewriter editor.highlightInsertionPoint editor.focusOnListSelection editor.cursorOnListSelection
        syntax.fontName syntax.monospaceFontName syntax.fontSize syntax.lineHeightMultiple syntax.paragraphSpacing
        syntax.horizontalMargin syntax.verticalMargin syntax.maximumWidth syntax.spelling syntax.grammar syntax.smartQuotes
        syntax.smartDashes syntax.autoMatch syntax.autoRenumber syntax.autocorrection syntax.writingTools
        syntax.paragraphNumbers syntax.highlightInsertionPoint syntax.indentation syntax.feature
        markdown.processor markdown.multi.markdownCompatibilityMode markdown.multi.smartQuotesEnabled
        markdown.multi.footnotesEnabled markdown.multi.randomFootnotes markdown.multi.noLabels markdown.multi.processHTML
        markdown.multi.noMetadata markdown.multi.obfuscate markdown.multi.criticMarkup markdown.multi.criticMarkupAccept
        markdown.multi.criticMarkupReject markdown.github.tables markdown.github.autoLinks markdown.github.strikethrough
        markdown.github.tagFilters markdown.github.taskLists markdown.github.sourcePOS markdown.github.hardBreaks
        markdown.github.safe markdown.github.unsafe markdown.github.validateUTF8 markdown.github.smartQuotes markdown.github.footnotes
        html.strongMark html.emphasisMark html.ulItemMark html.pasteAsMarkdown html.inlineLinks html.linksEachParagraph
        html.ignoreLinks html.ignoreImages html.ignoreEmphasis list.showPreview list.showTags list.showDate
        list.searchTitlesOnly list.caseSensitiveSearch list.previewSearchMatches list.showLastAction list.highlightFlagged
        list.previewLines workspace.defaultID commands.shortcut
        """.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        #expect(Set(registry.fields.map(\.id)) == Set(expected))
        #expect(registry.fields.count == expected.count)
        #expect(registry.builtInSyntaxNames == ScriptSyntax.names)
        for excluded in ["commands.bindings", "editor.fontBySyntax", "agent.grants", "bookmarks", "icloud.container"] {
            #expect(throws: AgentSchemaError.self) { try registry.field(excluded) }
        }
    }

    @Test func definitionsUseConsumerDefaultsAndPreserveInheritance() throws {
        let registry = try AgentPreferenceCatalog.make()
        for (engine, options) in [("multi", MarkdownPreferences.multiOptions), ("github", MarkdownPreferences.githubOptions)] {
            for option in options {
                let field = try registry.field("markdown." + engine + "." + option.id)
                #expect(field.defaultValue == .bool(option.defaultValue))
                #expect(field.title == option.title)
            }
        }
        for option in EditorTextInputPreferences.Option.allCases {
            #expect(try registry.field("syntax." + option.rawValue).defaultValue == .bool(option.defaultValue))
        }
        for id in ["syntax.fontName", "syntax.fontSize", "syntax.maximumWidth", "syntax.highlightInsertionPoint"] {
            let field = try registry.field(id)
            #expect(field.defaultSource == .inherited)
            #expect(field.defaultValue == nil)
        }
        for id in ["syntax.autocorrection", "syntax.writingTools", "application.launchAtLogin"] {
            #expect(try registry.field(id).defaultSource == .system)
            #expect(try registry.field(id).defaultValue == nil)
        }
        #expect(try registry.field("editor.lineSpacing").writable == false)
        #expect(try registry.field("application.launchAtLogin").requiresHumanApproval)
        #expect(try registry.field(SpotlightPreferences.enabledKey).requiresHumanApproval)
        let commands = try registry.field("commands.shortcut")
        guard case .command(let names) = commands.context else { Issue.record("Missing command context"); return }
        #expect(names == CommandShortcuts.editable)
        #expect(commands.approvalCommands == Set(GlobalShortcuts.names))
    }

    @Test func typedValuesKeepFontsAndRejectInvalidNumbers() throws {
        let registry = try AgentPreferenceCatalog.make()
        try registry.field("editor.fontName").value.validate(.string("未知 Nerd Font"))
        try registry.field("editor.maximumWidth").value.validate(.integer(0))
        #expect(throws: AgentSchemaError.self) { try registry.field("editor.fontSize").value.validate(.integer(0)) }
        #expect(throws: AgentSchemaError.self) { try registry.field("editor.maximumWidth").value.validate(.integer(-1)) }
        try registry.field("syntax.autocorrection").value.validate(.null)
        #expect(throws: AgentSchemaError.self) { try registry.field("editor.fontName").value.validate(.null) }
        #expect(try registry.field("workspace.defaultID").defaultValue == .null)
    }
}
