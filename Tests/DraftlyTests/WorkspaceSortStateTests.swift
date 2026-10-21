import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Workspace sort writer state") @MainActor
struct WorkspaceSortStateTests {
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
