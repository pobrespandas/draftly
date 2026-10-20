import Foundation
import AppKit
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Window transitions") @MainActor
struct WindowModelTests {
    init() { _ = NSApplication.shared }
    enum SaveFailure: Error { case unavailable }

    private func checkWorkspaceDisplayOption(_ property: String, enabled: Bool, read: (DraftListOptions) -> Bool) throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Display 🐼", tags: ["display-contract"])
        let model = WindowModel(library: library); model.select(note.id)
        model.editor.selection = NSRange(location: 0, length: 7)
        let action = DraftAction(name: property, steps: [ActionStep("script", ["script": """
        const w=new Workspace();w.name='Display';w.tagFilter='display-contract';w.\(property)=\(enabled);
        w.update();app.applyWorkspace(Workspace.find(w.name));
        if(w.query('inbox').length!==1)throw new Error('display query');
        """])])
        #expect(model.runner.run(action), Comment(rawValue: model.runner.message ?? ""))
        #expect(read(model.listOptions) == enabled)
        #expect(model.visibleNotes.map(\.id) == [note.id])
        #expect(model.editor.content == note.content && model.editor.selection == NSRange(location: 0, length: 7))
        let restored = try LibraryStore(inMemory: true, seed: false); try restored.restore(library.backupData())
        let other = WindowModel(library: restored); try other.applyScriptWorkspace(try #require(restored.workspaces.first))
        #expect(read(other.listOptions) == enabled && other.visibleNotes.map(\.id) == [note.id])
    }

    @Test func workspaceShowDateAppliesAndSurvivesBackup() throws { try checkWorkspaceDisplayOption("showDate", enabled: false, read: { $0.showDate }) }
    @Test func workspaceShowPreviewAppliesAndSurvivesBackup() throws { try checkWorkspaceDisplayOption("showPreview", enabled: false, read: { $0.showPreview }) }
    @Test func workspaceShowTagsAppliesAndSurvivesBackup() throws { try checkWorkspaceDisplayOption("showTags", enabled: false, read: { $0.showTags }) }
    @Test func workspaceShowSearchPreviewAppliesAndSurvivesBackup() throws { try checkWorkspaceDisplayOption("showSearchPreview", enabled: false, read: { $0.previewSearchMatches }) }
    @Test func workspaceShowLastActionAppliesAndSurvivesBackup() throws { try checkWorkspaceDisplayOption("showLastAction", enabled: true, read: { $0.showLastAction }) }


    @Test func advancedFindUsesItsOwnInterfaceWithoutChangingTheDraft() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Café 🐼")
        let model = WindowModel(library: library); model.select(note.id)
        model.editor.selection = NSRange(location: 0, length: 4)
        _ = try model.actionUIOperation(["operation": "showFind", "args": [true, "café"]])
        #expect(model.showAdvancedFind && model.advancedFindQuery == "café")
        #expect(model.editor.noteID == note.id && model.editor.content == note.content)
        #expect(model.editor.selection == NSRange(location: 0, length: 4))
        _ = try model.actionUIOperation(["operation": "showFind", "args": [true]])
        #expect(model.showAdvancedFind && model.advancedFindQuery.isEmpty)
        _ = try model.actionUIOperation(["operation": "showFind", "args": [false]])
        #expect(!model.showAdvancedFind)
    }

    @Test func findPreferenceSelectsTheDefaultButExplicitArgumentsWin() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Find café 🐼")
        let model = WindowModel(library: library)
        model.select(note.id)
        model.editor.selection = NSRange(location: 5, length: 4)
        model.prefersAdvancedFind = { true }
        _ = try model.actionUIOperation(["operation": "showFind", "args": []])
        #expect(model.showAdvancedFind)
        _ = try model.actionUIOperation(["operation": "showFind", "args": [false]])
        #expect(!model.showAdvancedFind)
        model.prefersAdvancedFind = { false }
        _ = try model.actionUIOperation(["operation": "showFind", "args": [true, "café"]])
        #expect(model.showAdvancedFind && model.advancedFindQuery == "café")
        _ = try model.actionUIOperation(["operation": "showFind", "args": []])
        #expect(!model.showAdvancedFind)
        #expect(model.editor.noteID == note.id && model.editor.content == note.content)
        #expect(model.editor.selection == NSRange(location: 5, length: 4))
    }

    @Test func scriptedInfoUsesItsTargetWithoutOpeningIt() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content:"Current")
        let second = try library.createNote(content:"Info target")
        let model = WindowModel(library:library);model.select(first.id)
        _ = try model.actionUIOperation(["operation":"showDraftInfo", "value":["uuid":second.id.uuidString]])
        #expect(model.infoDraft?.id == second.id)
        #expect(model.editor.noteID == first.id)
        #expect(model.showInfo)
        #expect(throws: (any Error).self) { try model.actionUIOperation(["operation":"showChatConsole"]) }
        #expect(throws: (any Error).self) { try model.actionUIOperation(["operation":"hideChatConsole"]) }
    }

    @Test func scriptedWorkspaceMatchesVisibleRowsAndAppliesGroups() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "Source")
        let kept = try library.createNote(content: "Alpha", tags: ["keep"])
        var flagged = try library.createNote(content: "Zulu", tags: ["keep"]); flagged.flag=1; try library.saveNote(flagged)
        try library.saveAction(DraftAction(name: "Example", steps: []))
        let model = WindowModel(library: library); model.select(source.id)
        let action = DraftAction(name: "Workspace application", steps: [ActionStep("script", ["script": """
        let w=Workspace.create();w.name='Contract';w.tagFilter='keep';w.inboxIncludesFlagged=false;
        w.showTags=false;w.showSearchPreview=true;w.loadFolder='inbox';w.setInboxSort('name',false,true);
        w.loadActionListGroup=ActionGroup.find('General');w.loadActionBarGroup=ActionGroup.find('General');
        w.preferredDarkTheme=Theme.find('builtIn','Dark');w.preferredLightTheme=Theme.find('builtIn','Light');
        w.update();app.applyWorkspace(w);
        if(w.query('inbox').length!==1)throw new Error('query mismatch');
        """])])
        #expect(model.runner.run(action))
        #expect(model.visibleNotes.map(\.id) == [kept.id])
        #expect(model.actionGroup == "General" && model.actionBarGroup == "General")
        #expect(!model.listOptions.showTags && model.listOptions.previewSearchMatches)
        #expect(model.editor.noteID == source.id)
        #expect(WorkspaceThemeValues.preference(model.workspaceScriptMetadata, key: "preferredDarkTheme") == "Dark")
        #expect(WorkspaceThemeValues.preference(model.workspaceScriptMetadata, key: "preferredLightTheme") == "Light")
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        let other = WindowModel(library: restored); other.apply(try #require(restored.workspaces.first))
        #expect(other.visibleNotes.map(\.id) == [kept.id])
    }

    @Test func invalidScriptedWorkspaceDoesNotChangeTheWindow() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        var workspace = Workspace(name: "Invalid"); workspace.query="Changed"
        workspace.scriptMetadata=["api":"{\"loadActionListGroup\":{\"name\":\"Missing\"}}"]
        #expect(throws: (any Error).self) { try model.applyScriptWorkspace(workspace) }
        #expect(model.query.isEmpty)
        workspace.scriptMetadata=["api":"{\"preferredLightTheme\":{\"name\":\"Missing\"}}"]
        #expect(throws: (any Error).self) { try model.applyScriptWorkspace(workspace) }
        #expect(model.query.isEmpty)
    }

    @Test func selectingFromTheListKeepsKeyboardFocus() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "First")
        let second = try library.createNote(content: "Second")
        let model = WindowModel(library: library)
        model.select(first.id)
        let focus = model.editor.focusToken
        model.select(second.id, focusEditor: false)
        #expect(model.editor.noteID == second.id)
        #expect(model.editor.content == "Second")
        #expect(model.editor.focusToken == focus)
        model.select(first.id)
        #expect(model.editor.focusToken != focus)
    }

    @Test func anEmptyNewDraftDoesNotAddAListRow() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let saved = try library.createNote(content: "Saved")
        let model = WindowModel(library: library)
        #expect(model.create())
        #expect(model.visibleNotes.map(\.id) == [saved.id])
        model.editor.content = "New text"
        #expect(model.flush())
        #expect(model.visibleNotes.count == 2)
        #expect(model.visibleNotes.contains { $0.id == model.editor.noteID })
    }

    @Test func libraryOpensWithDraftsStylePanels() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        #expect(model.showFilters)
        #expect(!model.showActions)
        #expect(model.showDraftList)
    }

    @Test func leftPanelsFollowDraftsTransitionsWithoutChangingDraftOrFilters() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Working text", tags: ["work"])
        let model = WindowModel(library: library)
        model.select(note.id); model.tag = "work"; model.query = "Working"
        model.editor.selection = NSRange(location: 2, length: 4)
        model.toggleFilters()
        #expect(!model.showFilters && model.showDraftList)
        model.toggleDraftList()
        #expect(!model.showFilters && !model.showDraftList)
        model.toggleFilters()
        #expect(model.showFilters && model.showDraftList)
        model.toggleDraftList()
        #expect(!model.showFilters && !model.showDraftList)
        model.toggleDraftList()
        #expect(!model.showFilters && model.showDraftList)
        #expect(model.tag == "work" && model.query == "Working")
        #expect(model.visibleNotes.map(\.id) == [note.id])
        #expect(model.editor.noteID == note.id && model.editor.content == "Working text")
        #expect(model.editor.selection == NSRange(location: 2, length: 4))
    }

    @Test func actionAPIAppliesTheSamePanelRules() throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        _ = try model.actionUIOperation(["operation": "hideDraftList"])
        #expect(model.leftPanels == .hidden)
        _ = try model.actionUIOperation(["operation": "hideFilters"])
        #expect(model.leftPanels == .hidden)
        _ = try model.actionUIOperation(["operation": "showFilters"])
        #expect(model.leftPanels == .filters)
        _ = try model.actionUIOperation(["operation": "showDraftList"])
        #expect(model.leftPanels == .filters)
        _ = try model.actionUIOperation(["operation": "hideFilters"])
        #expect(model.leftPanels == .drafts)
        _ = try model.actionUIOperation(["operation": "hideDraftList"])
        _ = try model.actionUIOperation(["operation": "showDraftList"])
        #expect(model.leftPanels == .drafts)
    }

    @Test func quickSearchDoesNotChangeListFiltersOrFocus() throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        model.setDraftListVisible(false)
        let focus = model.noteSearchFocus
        var opened = false
        model.openQuickSearch = { opened = true }
        model.query = "Keep this filter"
        _ = try model.actionUIOperation(["operation": "showQuickSearch"])
        #expect(opened)
        #expect(model.leftPanels == .hidden)
        #expect(!model.showNoteSearch && model.noteSearchFocus == focus)
        #expect(model.query == "Keep this filter")
    }

    @Test func failedCaptureKeepsUnsavedTextAndSelection() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let saved = try library.createNote(content: "Saved text")
        let model = WindowModel(library: library, saveDraft: { _ in throw SaveFailure.unavailable })
        model.select(saved.id)
        model.editor.content = "Unsaved text"
        model.editor.selection = NSRange(location: 3, length: 4)
        model.contentChanged()
        #expect(!model.capture("Incoming capture"))
        #expect(model.editor.noteID == saved.id)
        #expect(model.editor.content == "Unsaved text")
        #expect(model.editor.selection == NSRange(location: 3, length: 4))
        #expect(model.hasUnsavedChanges)
        #expect(library.notes.first?.content == "Saved text")
    }

    @Test func failedCaptureKeepsTemporaryDraft() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library, saveDraft: { _ in throw SaveFailure.unavailable })
        #expect(model.create())
        let id = model.editor.noteID
        model.editor.content = "Temporary text"
        model.contentChanged()
        #expect(!model.capture("Incoming capture"))
        #expect(model.editor.noteID == id)
        #expect(model.editor.content == "Temporary text")
        #expect(library.notes.isEmpty)
    }

    @Test func captureSavesPreviousDraftBeforeReplacingIt() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        model.create()
        let previousID = model.editor.noteID
        model.editor.content = "Previous work"; model.contentChanged()
        #expect(model.capture("Incoming capture"))
        #expect(library.notes.first { $0.id == previousID }?.content == "Previous work")
        #expect(model.editor.noteID != previousID)
        #expect(model.editor.content == "Incoming capture")
        #expect(model.flush())
    }

    @Test func selectingDraftReportsRecentAccess() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Recent draft")
        var opened: [UUID] = []
        let model = WindowModel(library: library, onAccessDraft: { opened.append($0) })

        let modified = try #require(library.notes.first { $0.id == note.id }).modifiedAt
        model.select(note.id)

        #expect(opened == [note.id])
        #expect(library.notes.first { $0.id == note.id }?.accessedAt != nil)
        #expect(library.notes.first { $0.id == note.id }?.modifiedAt == modified)
    }

    @Test func failedAccessKeepsTheCurrentEditorAndSelection() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "Current 🐼")
        let second = try library.createNote(content: "Target")
        let model = WindowModel(library: library)
        model.select(first.id)
        model.editor.selection = NSRange(location: 8, length: 2)
        library.beforeBatchCommit = { throw SaveFailure.unavailable }
        model.select(second.id)
        #expect(model.editor.noteID == first.id)
        #expect(model.editor.content == first.content)
        #expect(model.editor.selection == NSRange(location: 8, length: 2))
        #expect(library.notes.first { $0.id == second.id }?.accessedAt == nil)
        #expect(library.error != nil)
    }

    @Test func clipboardCapturePreservesUnicodeAndLineBreaks() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        model.capture("Existing draft")
        #expect(model.flush())

        let clipboardText = "First line\nSecond line — 🐼\n"
        #expect(model.capture(clipboardText))
        #expect(model.editor.content == clipboardText)
        #expect(model.flush())
        #expect(library.notes.first { $0.id == model.editor.noteID }?.content == clipboardText)
        #expect(library.notes.contains { $0.content == "Existing draft" })
    }

    @Test func clearingFiltersRemovesWorkspaceRestrictions() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Work", tags: ["work"])
        _ = try library.createNote(content: "Personal", tags: ["personal"])
        var workspace = Workspace(name: "Work"); workspace.tags = ["work"]
        try library.saveWorkspace(workspace)
        let model = WindowModel(library: library)
        model.apply(workspace)
        #expect(model.visibleNotes.count == 1)
        #expect(model.tagFilterSummary == "#work")
        model.clearFilters()
        #expect(model.visibleNotes.count == 2)
        #expect(model.selectedWorkspace == nil)
        #expect(model.tagFilterSummary == "No tag filters active")
    }

    @Test func currentTagsFollowTheVisibleDraftsAndTagSearch() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        _ = try library.createNote(content: "Alpha", tags: ["work", "alpha"])
        _ = try library.createNote(content: "Beta", tags: ["work", "beta"])
        _ = try library.createNote(content: "Personal", tags: ["personal"])
        _ = try library.createNote(content: "No tags")
        let model = WindowModel(library: library)
        model.tag = "work"
        #expect(model.matchingTags == ["alpha", "beta", "personal", "work"])
        model.showOnlyCurrentTags = true
        #expect(model.matchingTags == ["alpha", "beta", "work"])
        model.query = "Alpha"
        #expect(model.matchingTags == ["alpha", "work"])
        model.tagQuery = "alp"
        #expect(model.matchingTags == ["alpha"])
        model.tagQuery = ""; model.query = ""; model.tag = nil; model.tagPresence = false
        #expect(model.matchingTags.isEmpty)
        #expect(library.notes.count == 4)
    }

    @Test func pinningDraftAndFloatingWindowAreIndependent() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        model.capture("Working draft"); model.flush()
        let id = model.editor.noteID
        let start = Date()
        model.isDraftPinned = true
        model.toggleFloat()
        #expect(model.isFloating && model.isDraftPinned)
        model.applicationResigned(at: start)
        model.applicationActivated(at: start.addingTimeInterval(60), timeout: 30)
        #expect(model.editor.noteID == id)
        model.isDraftPinned = false
        model.applicationResigned(at: start)
        model.applicationActivated(at: start.addingTimeInterval(60), timeout: 30)
        #expect(model.editor.noteID != id)
        #expect(model.editor.content.isEmpty)
        #expect(model.isFloating)
    }

    @Test func returningBeforeTimeoutOrWithNeverKeepsDraft() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        model.capture("Working draft"); model.flush()
        let id = model.editor.noteID
        let start = Date()
        model.applicationResigned(at: start)
        model.applicationActivated(at: start.addingTimeInterval(10), timeout: 30)
        #expect(model.editor.noteID == id)
        model.applicationResigned(at: start)
        model.applicationActivated(at: start.addingTimeInterval(3600), timeout: 0)
        #expect(model.editor.noteID == id)
    }
    @Test func previewStaysInTheEditorAndPreservesSelection() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        model.capture("# Heading\n**Text**"); model.flush()
        let id = model.editor.noteID
        let selection = NSRange(location: 2, length: 7)
        model.editor.selection = selection
        model.preview()
        #expect(model.showPreview)
        #expect(model.editor.noteID == id)
        #expect(model.editor.selection == selection)
        model.preview()
        #expect(!model.showPreview)
        #expect(model.editor.selection == selection)
        let present = model.host.onActionPreview
        model.host.onActionPreview = { request in
            present?(request)
            #expect(model.showPreview)
            #expect(model.actionPreview?.html == "<h1>Action preview</h1>")
            request.values["answer"] = 42
            request.finish(true)
        }
        let result = try model.host.perform("htmlPreview", values: ["html": "<h1>Action preview</h1>"]) as? [String: Any]
        #expect(result?["success"] as? Bool == true)
        #expect((result?["values"] as? [String: Any])?["answer"] as? Int == 42)
        #expect(model.actionPreview == nil)
        _ = try model.host.perform("previewMarkdown", values: ["text": "# Heading"])
        #expect(model.showPreview)
        model.create()
        #expect(!model.showPreview)
        #expect(model.previewHTML == nil)
    }

}
