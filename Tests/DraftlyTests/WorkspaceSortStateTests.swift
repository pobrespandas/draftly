import Foundation
import Combine
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Workspace sort writer state") @MainActor
struct WorkspaceSortStateTests {
    @Test(arguments: ["inbox", "archive"], [false, true])
    func applyingWorkspaceUsesTheInitialViewsEffectiveOrderWithoutChangingEditor(folderName: String, saved: Bool) throws {
        let folder = try #require(NoteFolder(rawValue: folderName))
        try withModel { model in
            let date = Date(timeIntervalSince1970: 1_600_000_000)
            let alpha = Note(content: "Alpha", tags: ["sort-contract"], isArchived: folder == .archive,
                             modifiedAt: date.addingTimeInterval(3))
            let beta = Note(content: "Beta", tags: ["sort-contract"], isArchived: folder == .archive,
                            modifiedAt: date.addingTimeInterval(2))
            let flagged = Note(content: "Zulu", tags: ["sort-contract"], flag: 1, isArchived: folder == .archive,
                               modifiedAt: date.addingTimeInterval(1))
            for note in [alpha, beta, flagged] { try model.library.saveNote(note, preserveDates: true) }
            let current = try model.library.createNote(content: "Keep 🐼 café")
            model.select(current.id)
            model.editor.content = "Keep pending 🐼 café"
            model.editor.selection = NSRange(location: 13, length: 2)
            let focus = model.editor.focusToken
            model.workspaceScriptMetadata = ["api": try encode(["_sorts": [
                "inbox": ["sort": "accessed", "descending": true],
                "archive": ["sort": "created", "descending": true]
            ], "old": "Discard this prior view metadata"])]

            let values: [String: Any] = ["future": ["keep": true], "_sorts": [
                folder.rawValue: ["sort": "name", "descending": false, "flagged": true, "future": ["key": "café 🐼"]],
                "all": ["sort": "accessed", "descending": true, "future": "Other view"]
            ]]
            var workspace = Workspace(name: "Effective initial sort")
            workspace.folder = folder; workspace.tags = ["sort-contract"]
            workspace.sort = .modified; workspace.ascending = false
            workspace.scriptMetadata = ["future": "Outer field", "api": try encode(values)]
            if saved { try model.library.saveWorkspace(workspace) }

            try model.applyScriptWorkspace(workspace)

            #expect(model.folder == folder && model.sort == .title && model.ascending)
            #expect(model.visibleNotes.map(\.id) == [flagged.id, alpha.id, beta.id])
            #expect(model.visibleNotes.map(\.id) == workspace.filter(model.library.notes).map(\.id))
            #expect(NSDictionary(dictionary: model.workspaceSnapshot(name: "Current").apiOptions).isEqual(to: values))
            #expect(model.workspaceScriptMetadata?["future"] == "Outer field")
            #expect(model.selectedWorkspace == (saved ? workspace.id : nil))
            #expect(model.editor.noteID == current.id && model.editor.content == "Keep pending 🐼 café")
            #expect(model.editor.selection == NSRange(location: 13, length: 2) && model.editor.focusToken == focus)
            if saved { #expect(model.library.workspaces.first == workspace) }
        }
    }

    @Test(arguments: [false, true])
    func navigatingViewsDoesNotWriteSortMetadataButExplicitEditsStillDo(futureSort: Bool) throws {
        try withModel { model in
            let inbox: [String: Any] = ["sort": "name", "descending": false, "flagged": true, "future": "Inbox"]
            let archive: [String: Any] = ["sort": futureSort ? "futureSort" : "accessed",
                "descending": futureSort ? "futureDirection" : true, "flagged": "futureFlag", "future": "Archive"]
            let values: [String: Any] = ["future": ["keep": true], "_sorts": ["inbox": inbox, "archive": archive]]
            var workspace = Workspace(name: "Read view order")
            workspace.scriptMetadata = ["future": "Outer", "api": try encode(values)]
            try model.applyScriptWorkspace(workspace)
            let original = model.workspaceScriptMetadata
            var changes: [[String: String]?] = []
            let subscription = model.$workspaceScriptMetadata.dropFirst().sink { changes.append($0) }
            defer { subscription.cancel() }

            model.folder = .archive
            #expect(model.sort == (futureSort ? .modified : .accessed))
            #expect(model.ascending == futureSort)
            #expect(model.workspaceScriptMetadata == original)
            model.folder = .inbox
            #expect(model.sort == .title && model.ascending)
            #expect(model.workspaceScriptMetadata == original)
            #expect(changes.isEmpty)

            model.sort = .created
            model.ascending = false
            var expectedInbox = inbox
            expectedInbox["sort"] = "created"; expectedInbox["descending"] = true
            var expected = values
            expected["_sorts"] = ["inbox": expectedInbox, "archive": archive]
            #expect(!changes.isEmpty)
            #expect(NSDictionary(dictionary: model.workspaceSnapshot(name: "Current").apiOptions).isEqual(to: expected))
            #expect(model.workspaceScriptMetadata?["future"] == "Outer")
        }
    }

    @Test(arguments: [false, true])
    func applyingWorkspaceWithoutAViewOrderKeepsItsTopLevelSort(hasMetadata: Bool) throws {
        try withModel { model in
            var workspace = Workspace(name: "Top-level fallback")
            workspace.folder = .archive; workspace.sort = .created; workspace.ascending = true
            if hasMetadata { workspace.scriptMetadata = ["future": "Outer", "api": try encode(["future": "Keep"])] }
            try model.applyScriptWorkspace(workspace)
            #expect(model.folder == .archive && model.sort == .created && model.ascending)
            #expect(model.workspaceScriptMetadata == workspace.scriptMetadata)
            model.sort = .title
            if hasMetadata {
                #expect(model.workspaceSnapshot(name: "Current").scriptSort(for: .archive)?.0 == .title)
                #expect(model.workspaceSnapshot(name: "Current").apiOptions["future"] as? String == "Keep")
            } else { #expect(model.workspaceScriptMetadata == nil) }
        }
    }

    @Test(arguments: ["nil", "missing", "invalid", "array", "scalar"])
    func windowSortEditsLeaveUnreadableOrMissingOptionsUnchanged(_ shape: String) throws {
        try withModel { model in
            let metadata = metadata(for: shape)
            model.workspaceScriptMetadata = metadata
            model.sort = .title
            model.ascending = true
            #expect(model.sort == .title && model.ascending)
            #expect(model.workspaceScriptMetadata == metadata)
        }
    }

    @Test(arguments: ["true", "false", "absent", "future"])
    func windowSortEditsPreserveFlaggedAndUnknownFields(_ flagged: String) throws {
        try withModel { model in
            var inbox: [String: Any] = ["sort": "modified", "descending": true, "future": ["keep": 42]]
            switch flagged {
            case "true": inbox["flagged"] = true
            case "false": inbox["flagged"] = false
            case "future": inbox["flagged"] = "future-value"
            default: break
            }
            let archive: [String: Any] = ["sort": "created", "descending": false, "future": "archive"]
            let original: [String: Any] = ["future": ["enabled": true], "_sorts": ["inbox": inbox, "archive": archive]]
            model.workspaceScriptMetadata = ["future": "outer", "api": try encode(original)]

            model.sort = .title
            model.ascending = true
            var expectedInbox = inbox
            expectedInbox["sort"] = "name"; expectedInbox["descending"] = false
            var expected = original
            expected["_sorts"] = ["inbox": expectedInbox, "archive": archive]
            #expect(NSDictionary(dictionary: model.workspaceSnapshot(name: "Current").apiOptions).isEqual(to: expected))
            #expect(model.workspaceScriptMetadata?["future"] == "outer")

            model.sort = .accessed
            model.ascending = false
            expectedInbox["sort"] = "accessed"; expectedInbox["descending"] = true
            expected["_sorts"] = ["inbox": expectedInbox, "archive": archive]
            #expect(NSDictionary(dictionary: model.workspaceSnapshot(name: "Current").apiOptions).isEqual(to: expected))
            #expect(model.workspaceScriptMetadata?["future"] == "outer")
        }
    }

    @Test func folderObserverRestoresSortAndDirectionWithoutChangingOtherViews() throws {
        try withModel { model in
            let inbox: [String: Any] = ["sort": "name", "descending": false, "flagged": true, "future": "inbox"]
            let archive: [String: Any] = ["sort": "accessed", "descending": true, "flagged": false, "future": "archive"]
            let original: [String: Any] = ["future": ["keep": true], "_sorts": ["inbox": inbox, "archive": archive]]
            model.workspaceScriptMetadata = ["future": "outer", "api": try encode(original)]

            model.folder = .archive
            #expect(model.sort == .accessed && !model.ascending)
            #expect(NSDictionary(dictionary: model.workspaceSnapshot(name: "Current").apiOptions).isEqual(to: original))
            model.folder = .inbox
            #expect(model.sort == .title && model.ascending)
            #expect(NSDictionary(dictionary: model.workspaceSnapshot(name: "Current").apiOptions).isEqual(to: original))
            #expect(model.workspaceScriptMetadata?["future"] == "outer")
        }
    }

    @Test(arguments: ["nil", "missing", "invalid", "array", "scalar"])
    func optionsEditorRecoversUnreadableOptionsAndWritesSortedKeys(_ shape: String) throws {
        var workspace = Workspace(name: "Sort recovery")
        workspace.scriptMetadata = metadata(for: shape)
        try WorkspaceOptionsEditor.setSort(.title, ascending: false, flaggedFirst: false, folder: .archive, in: &workspace)
        #expect(workspace.scriptMetadata?["api"] == #"{"_sorts":{"archive":{"descending":true,"flagged":false,"sort":"name"}}}"#)
        #expect(workspace.scriptMetadata?["future"] == (shape == "nil" ? nil : "outer"))
    }

    private func metadata(for shape: String) -> [String: String]? {
        switch shape {
        case "nil": return nil
        case "missing": return ["future": "outer"]
        case "invalid": return ["future": "outer", "api": "{invalid"]
        case "array": return ["future": "outer", "api": "[]"]
        default: return ["future": "outer", "api": "true"]
        }
    }

    private func encode(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    private func withModel(_ body: (WindowModel) throws -> Void) throws {
        let preferences = try TestPreferences(prefix: "Draftly-WorkspaceSortState-")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        try body(WindowModel(library: library, dependencies: dependencies))
    }
}
