import Foundation
import Testing
@testable import DraftlyCore

@Suite("Initial action catalog") @MainActor
struct DefaultActionCatalogTests {
    @Test func firstOpenInstallsVersionedGroupsAndReopenPreservesEdits() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var library: LibraryStore? = try LibraryStore(directory: folder)
        let actions = library!.orderedActions(on: .list)
        #expect(library!.groupNames == DefaultActionCatalog.groupNames)
        #expect(actions.count == DefaultActionCatalog.actions.count)
        #expect(actions.count == 94)
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
}

@MainActor private final class DefaultCatalogHost: ActionHost {
    var calls: [(String, [String: Any])] = []
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        calls.append((operation, values))
        return true
    }
}
