import Foundation
import Testing
@testable import DraftlyCore

@Suite("Initial action catalog") @MainActor
struct DefaultActionCatalogTests {
    @Test func statisticsMatchesReferencePreviewWithoutChangingDraft() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "The cat sat on the mat. This is a simple test.")
        let editor = EditorSession(); editor.load(note)
        let host = DefaultCatalogHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = try #require(DefaultActionCatalog.actions.first { $0.name == "Stats" })
        #expect(runner.run(action))
        let html = try #require(host.calls.first { $0.0 == "htmlPreview" }?.1["html"] as? String)
        // Values observed in Drafts 54.1.2 with this exact neutral text.
        let expected = [("Words", "12"), ("Sentences", "3"), ("Words per sentence", "3"),
                        ("Flesch-Kincaid Ease", "119.8"), ("Flesch-Kincaid Grade Level", "-2.9"),
                        ("Gunning Fog", "1"), ("SMOG Index", "1.8"),
                        ("Automated Readability", "-6.6"), ("Coleman Liau", "0.8")]
        for (label, value) in expected {
            #expect(html.contains("<td class=\"lbl\">\(label)</td><td class=\"val\">\(value)</td>"))
        }
        #expect(!html.contains("[[htmltable]]") && !html.contains("[[bodystyle]]"))
        #expect(editor.content == note.content)
        #expect(library.notes.first { $0.id == note.id }?.modifiedAt == note.modifiedAt)
        #expect(library.runs.isEmpty)
        #expect(!host.calls.contains { $0.0 == "actionNotification" })
    }

    @Test func statisticsRejectsEmptyDraftBeforeOpeningPreview() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: ""))
        let host = DefaultCatalogHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        #expect(!runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Stats" })))
        #expect(!host.calls.contains { $0.0 == "htmlPreview" })
        #expect(host.calls.contains { String(describing: $0.1).contains("Empty draft. Text required to calculate statistics.") })
        #expect(editor.content.isEmpty)
    }

    @Test func inboxRestoresAnArchivedDraftWithoutChangingItsTextOrTags() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var note = try library.createNote(content: "Inbox QA 🐼")
        note.isArchived = true
        note.tags = ["neutral"]
        try library.saveNote(note)
        let editor = EditorSession()
        editor.load(note)
        let inbox = try #require(DefaultActionCatalog.actions.first { $0.name == "Inbox" })
        #expect(!inbox.isSeparator)
        #expect(ActionRunner(library: library, editor: editor, host: DefaultCatalogHost()).run(inbox))
        let saved = try #require(library.notes.first { $0.id == note.id })
        #expect(!saved.isArchived)
        #expect(saved.content == note.content && saved.tags == note.tags)
    }

    @Test func saveVersionCreatesDistinctSnapshotsEvenWhenTextIsUnchanged() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Version QA 🐼")
        let editor = EditorSession()
        editor.load(note)
        let runner = ActionRunner(library: library, editor: editor, host: DefaultCatalogHost())
        let action = try #require(DefaultActionCatalog.actions.first { $0.name == "Save Version" })
        let previousIDs = Set(library.revisions.map(\.id))
        #expect(runner.run(action))
        #expect(runner.run(action))
        let added = library.revisions.filter { !previousIDs.contains($0.id) }
        #expect(added.count == 2)
        #expect(added.allSatisfy { $0.noteID == note.id && $0.content == note.content })
        let saved = try #require(library.notes.first { $0.id == note.id })
        #expect(saved.content == note.content)
        #expect(saved.modifiedAt == note.modifiedAt)
        #expect(saved.tags == note.tags && saved.isArchived == note.isArchived)
    }

    @Test(arguments: ["Inbox", "Save Version", "Stats"])
    func reopeningCorrectsOnlyUnchangedLegacyActions(_ name: String) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var library: LibraryStore? = try LibraryStore(directory: folder, seed: false)
        let legacy = name == "Inbox" ? DefaultActionCatalog.legacyInboxSeparator
            : name == "Stats" ? DefaultActionCatalog.legacyStatistics : DefaultActionCatalog.legacySaveVersion
        try library!.saveAction(legacy)
        library = nil
        library = try LibraryStore(directory: folder)
        let corrected = try #require(library!.actions.first { $0.id == legacy.id })
        #expect(!corrected.isSeparator && corrected.steps.count == (name == "Stats" ? 4 : 1))
        library = nil
        library = try LibraryStore(directory: folder)
        #expect(library!.actions == [corrected])
        var edited = legacy
        edited.presentation.description = "My section"
        try library!.saveAction(edited)
        library = nil
        library = try LibraryStore(directory: folder)
        #expect(library!.actions == [edited])
        try library!.deleteAction(edited.id)
        library = nil
        #expect(try LibraryStore(directory: folder).actions.isEmpty)
    }
    @Test func firstOpenInstallsVersionedGroupsAndReopenPreservesEdits() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var library: LibraryStore? = try LibraryStore(directory: folder)
        let actions = library!.orderedActions(on: .list)
        #expect(library!.groupNames == DefaultActionCatalog.groupNames)
        #expect(actions.count == DefaultActionCatalog.actions.count)
        #expect(actions.count == 110)
        #expect(Set(actions.map(\.id)).count == actions.count)
        #expect(Set(actions.flatMap(\.steps).map(\.id)).count == actions.flatMap(\.steps).count)
        #expect(actions.allSatisfy { !$0.symbol.isEmpty && $0.unsupportedSteps.isEmpty })
        var copy = try #require(actions.first { $0.name == "Copy" })
        copy.steps = [ActionStep("clipboard", ["template": "User template 🐼"])]
        try library!.saveAction(copy)
        library = nil
        let reopened = try LibraryStore(directory: folder)
        #expect(reopened.actions.count == actions.count)
        #expect(reopened.actions.first { $0.id == copy.id }?.steps == copy.steps)
        #expect(Set(reopened.actions.map(\.id)) == Set(actions.map(\.id)))
    }

    @Test func aCloudRequestedStoreWaitsForExplicitCatalogInstallation() throws {
        // The memory backend suppresses CloudKit I/O while exercising the requested configuration.
        let library = try LibraryStore(inMemory: true, cloudIdentifier: "iCloud.neutral.catalog-fixture")
        #expect(library.cloudIdentifier == nil)
        #expect(library.actions.isEmpty && library.actionGroups.isEmpty)
        var arriving = try #require(DefaultActionCatalog.actions.first { $0.name == "Copy" })
        arriving.name = "My neutral copy"
        arriving.steps = [ActionStep("clipboard", ["template": "Keep my neutral template 🐼"])]
        arriving.unknownFields["futureField"] = .string("keep")
        try library.saveAction(arriving)
        let result = try library.reinstallDefaultActions()
        #expect(result.actionCount == 110)
        #expect(library.actions.first(where: { $0.id == arriving.id }) == arriving)
        #expect(library.actions.count == 111)
    }

    @Test func existingCustomCatalogDoesNotReceiveUnrequestedDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var library: LibraryStore? = try LibraryStore(directory: folder, seed: false)
        let custom = DraftAction(name: "Personal", steps: [ActionStep("clipboard", ["template": "Neutral"])])
        try library!.saveAction(custom)
        library = nil
        let reopened = try LibraryStore(directory: folder)
        #expect(reopened.actions == [custom])
    }

    @Test func deletingEveryDefaultDoesNotSeedAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var library: LibraryStore? = try LibraryStore(directory: folder)
        for action in library!.actions { try library!.deleteAction(action.id) }
        for group in library!.groupNames { try library!.removeActionGroup(group, movingActionsTo: "Removed") }
        library = nil
        let reopened = try LibraryStore(directory: folder)
        #expect(reopened.actions.isEmpty)
        #expect(reopened.actionGroups.isEmpty)
    }

    @Test func reinstallCreatesIndependentSuffixedGroupsAndActions() throws {
        let library = try LibraryStore(inMemory: true)
        let originalActions = library.actions
        let first = try library.reinstallDefaultActions()
        let second = try library.reinstallDefaultActions()
        #expect(first.groupNames == DefaultActionCatalog.groupNames.map { $0 + " (Default)" })
        #expect(second.groupNames == DefaultActionCatalog.groupNames.map { $0 + " (Default 2)" })
        #expect(first.actionCount == DefaultActionCatalog.actions.count)
        #expect(Set(library.actions.map(\.id)).count == library.actions.count)
        #expect(originalActions.allSatisfy { original in library.actions.contains(original) })
    }

    @Test func reinstallRollsBackEveryRecordWhenCommitFails() throws {
        let library = try LibraryStore(inMemory: true)
        let actions = library.actions, groups = library.actionGroups
        library.beforeBatchCommit = { throw DraftlyError.message("Injected failure") }
        #expect(throws: (any Error).self) { try library.reinstallDefaultActions() }
        #expect(library.actions == actions)
        #expect(library.actionGroups == groups)
    }

    @Test func localCatalogActionsRunAgainstTheEditorAndInjectedHost() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "hello world"))
        editor.selection = NSRange(location: 0, length: 5)
        let host = DefaultCatalogHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let upper = try #require(DefaultActionCatalog.actions.first { $0.name == "UPPER" })
        #expect(runner.run(upper))
        #expect(editor.content == "HELLO world")
        editor.selection = NSRange(location: 0, length: 5)
        let bold = try #require(DefaultActionCatalog.actions.first { $0.name == "Markdown Bold (**)" })
        #expect(runner.run(bold))
        #expect(editor.content == "**HELLO** world")
        let rich = try #require(DefaultActionCatalog.actions.first { $0.name == "Copy as Rich Text" })
        #expect(runner.run(rich))
        #expect((host.calls.first { $0.0 == "htmlToClipboard" }?.1["html"] as? String)?.contains("<strong>HELLO</strong>") == true)
    }

    @Test func syncedDriveActionsUseExplicitBookmarksAndPortablePaths() throws {
        let actions = DefaultActionCatalog.actions
        for (name, bookmark, mode, fileName) in [
            ("Save to iCloud Drive", "iCloud Drive", "create", "[[safe_title]].md"),
            ("Append to iCloud Journal", "iCloud Drive", "append", "Journal.md"),
            ("Save to Google Drive", "Google Drive", "create", "[[safe_title]].md"),
            ("Append to Google Drive Journal", "Google Drive", "append", "Journal.md"),
            ("Save to OneDrive", "OneDrive", "create", "[[safe_title]].md"),
            ("Append to OneDrive Journal", "OneDrive", "append", "Journal.md")
        ] {
            let step = try #require(actions.first { $0.name == name }?.steps.first)
            #expect(step.type == "file")
            #expect(step.values["useBookmark"] == "true")
            #expect(step.values["bookmarkName"] == bookmark)
            #expect(step.values["writeType"] == mode)
            #expect(step.values["name"] == fileName)
            #expect(step.values["folderTemplate"] == nil)
        }
    }

    @Test func optionActionsUseReviewPromptsAndApplyTheSelectedOperation() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "beta\nAlpha"))
        let host = DefaultCatalogHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        host.promptIndex = 0
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Change Case..." })))
        #expect(editor.content == "BETA\nALPHA")
        host.promptIndex = 1
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Sort Lines..." })))
        #expect(editor.content == "BETA\nALPHA")
        #expect(host.calls.filter { $0.0 == "prompt" }.count == 2)
    }

    @Test func encodeAndDecodeOptionsRoundTripUnicodeSelection() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "café & panda"))
        let host = DefaultCatalogHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        host.promptIndex = 0
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Encode..." })))
        #expect(editor.content == "caf%C3%A9%20%26%20panda")
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Decode..." })))
        #expect(editor.content == "café & panda")
    }

    @Test func tagReviewActionsUpdateTheDraftAndRenameAcrossTheLibrary() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = try library.createNote(content: "First", tags: ["old"])
        _ = try library.createNote(content: "Second", tags: ["old", "keep"])
        let editor = EditorSession(); editor.load(first)
        let host = DefaultCatalogHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        host.promptFields = ["tags": "old, added"]
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Update Tags..." })))
        #expect(library.notes.first { $0.id == first.id }?.tags == ["added", "old"])
        host.promptFields = ["oldTag": "old", "newTag": "renamed"]
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Rename Tag..." })))
        #expect(library.notes.filter { $0.tags.contains("renamed") }.count == 2)
        #expect(library.notes.allSatisfy { !$0.tags.contains("old") })
    }

    @Test func tableAndNumberActionsApplyReviewedValues() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "| A |\n| - |"))
        editor.selection = NSRange(location: 0, length: editor.content.utf16.count)
        let host = DefaultCatalogHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        host.promptFields = ["table": "| B |\n| - |"]
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Edit Markdown Table" })))
        #expect(editor.content == "| B |\n| - |")
        editor.content = "1234.5"; editor.selection = NSRange(location: 0, length: 6)
        host.promptFields = ["decimals": 2]
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Format Number" })))
        #expect(editor.content.replacingOccurrences(of: "\u{a0}", with: " ").contains("234"))
        #expect(editor.content.hasSuffix("50"))
    }

    @Test func workspaceActionsUseSelectionAndExistingWorkspaceRouting() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var workspace = Workspace(name: "Tagged"); workspace.tags = ["work"]; try library.saveWorkspace(workspace)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Existing"))
        let host = DefaultCatalogHost(); let runner = ActionRunner(library: library, editor: editor, host: host)
        var applied: [Workspace] = []; runner.applyWorkspace = { applied.append($0) }
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Select Workspace" })))
        #expect(applied.last?.name == "Tagged")
        host.promptFields = ["tag": "focus"]
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "Filter by Tag" })))
        #expect(applied.last?.tags == ["focus"])
        #expect(runner.run(try #require(DefaultActionCatalog.actions.first { $0.name == "New Draft in Workspace" })))
        #expect(editor.noteID != nil)
        #expect(editor.content.isEmpty)
        #expect(library.notes.first { $0.id == editor.noteID }?.tags == ["work"])
    }
}

@MainActor private final class DefaultCatalogHost: ActionHost {
    var calls: [(String, [String: Any])] = []
    var promptIndex = 0
    var promptFields: [String: Any] = [:]
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        calls.append((operation, values))
        if operation == "prompt" { return ["index": promptIndex, "fields": promptFields] }
        if operation == "selectPrompt" { return ["index": 0] }
        return true
    }
}
