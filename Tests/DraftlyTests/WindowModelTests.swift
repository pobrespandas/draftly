import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Window transitions") @MainActor
struct WindowModelTests {
    enum SaveFailure: Error { case unavailable }

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

    @Test func quickSearchOpensTheListWithoutOpeningFilters() throws {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        model.setDraftListVisible(false)
        let focus = model.noteSearchFocus
        _ = try model.actionUIOperation(["operation": "showQuickSearch"])
        #expect(model.leftPanels == .drafts)
        #expect(model.showNoteSearch && model.noteSearchFocus != focus)
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

        model.select(note.id)

        #expect(opened == [note.id])
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
