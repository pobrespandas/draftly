import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Workspace option editing") @MainActor
struct WorkspaceOptionsEditorTests {
    @Test func collidingGroupUUIDsResolveToTheirOwnNames() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let names = ["B" + String(repeating: "A", count: 16), "?" + String(repeating: "A", count: 15)]
        try library.saveActions(names.map { name in
            var action = DraftAction(name: name, steps: []); action.group = name; return action
        })
        for name in names {
            var workspace = Workspace(name: "Collision reference")
            let id = library.actionGroupRecord(named: name).id.uuidString
            try WorkspaceOptionsEditor.setReference(["uuid": id], key: "loadActionListGroup", in: &workspace)
            let resolved = try WorkspacePresentationResolver.resolve(workspace,
                groupNames: library.groupNames, groups: library.actionGroups, themes: [])
            let reference = try #require(resolved.apiOptions["loadActionListGroup"] as? [String: Any])
            #expect(reference["name"] as? String == name)
            #expect(reference["uuid"] as? String == id)
        }
    }

    @Test func folderSortChangesEffectiveOrderAndPreservesOtherFoldersAndUnknownFields() throws {
        var workspace = Workspace(name: "Order")
        workspace.scriptMetadata = ["future": "keep", "api": #"{"unknown":{"value":42},"_sorts":{"archive":{"sort":"created","descending":false},"inbox":{"sort":"modified","future":true}}}"#]
        try WorkspaceOptionsEditor.setSort(.title, ascending: true, flaggedFirst: true, folder: .inbox, in: &workspace)
        let alpha = Note(content: "Alpha"), zulu = Note(content: "Zulu", flag: 1)
        #expect(workspace.filter([alpha, zulu]).map(\.id) == [zulu.id, alpha.id])
        let sorts = try #require(workspace.apiOptions["_sorts"] as? [String: [String: Any]])
        #expect(sorts["archive"]?["sort"] as? String == "created")
        #expect(sorts["inbox"]?["future"] as? Bool == true)
        #expect((workspace.apiOptions["unknown"] as? [String: Any])?["value"] as? Int == 42)
        #expect(workspace.scriptMetadata?["future"] == "keep")
        try WorkspaceOptionsEditor.setSort(.accessed, ascending: true, flaggedFirst: false, folder: .inbox, in: &workspace)
        var accessed = alpha; accessed.accessedAt = Date()
        #expect(workspace.filter([zulu, accessed]).map(\.id) == [accessed.id, zulu.id])
    }

    @Test func dateAndFlagControlsUseTheSharedEvaluatorAndRetainUnknownDateFields() throws {
        var workspace = Workspace(name: "Filters")
        workspace.scriptMetadata = ["api": #"{"startDate":{"future":"keep"}}"#]
        try WorkspaceOptionsEditor.set("flagged", for: "flaggedStatus", in: &workspace)
        try WorkspaceOptionsEditor.setDate("absolute", component: "type", key: "startDate", in: &workspace)
        try WorkspaceOptionsEditor.setDate("accessed", component: "field", key: "startDate", in: &workspace)
        try WorkspaceOptionsEditor.setDate("2020-01-01T00:00:00Z", component: "date", key: "startDate", in: &workspace)
        var included = Note(content: "Included", flag: 1)
        included.accessedAt = ISO8601DateFormatter().date(from: "2021-01-01T00:00:00Z")
        let unknown = Note(content: "Unknown access", flag: 1)
        #expect(workspace.filter([unknown, included]).map(\.id) == [included.id])
        #expect((workspace.apiOptions["startDate"] as? [String: Any])?["future"] as? String == "keep")
        try WorkspaceOptionsEditor.set(false, for: "inboxIncludesFlagged", in: &workspace)
        #expect(workspace.filter([included]).isEmpty)
        try WorkspaceOptionsEditor.set(true, for: "inboxIncludesFlagged", in: &workspace)
        try WorkspaceOptionsEditor.setDate("none", component: "type", key: "startDate", in: &workspace)
        #expect(Set(workspace.filter([unknown, included]).map(\.id)) == [unknown.id, included.id])
    }

    @Test func referenceChangesPreserveUnknownFieldsAndClearOldIdentity() throws {
        var workspace = Workspace(name: "References")
        workspace.scriptMetadata = ["api": #"{"preferredLightTheme":{"uuid":"old","name":"Old","type":"custom","future":true},"loadActionListGroup":{"name":"Old group"}}"#]
        try WorkspaceOptionsEditor.setReference(["name": "Light"], key: "preferredLightTheme", in: &workspace)
        let theme = try #require(workspace.apiOptions["preferredLightTheme"] as? [String: Any])
        #expect(theme["name"] as? String == "Light")
        #expect(theme["uuid"] == nil && theme["type"] == nil)
        #expect(theme["future"] as? Bool == true)
        let group = ActionGroupRecord(name: "Current group")
        try WorkspaceOptionsEditor.setReference(["uuid": group.id.uuidString, "name": group.name], key: "loadActionListGroup", in: &workspace)
        let resolved = try WorkspacePresentationResolver.resolve(workspace, groupNames: [group.name], groups: [group], themes: [])
        #expect((resolved.apiOptions["loadActionListGroup"] as? [String: Any])?["uuid"] as? String == group.id.uuidString)
        try WorkspaceOptionsEditor.setReference(nil, key: "preferredLightTheme", in: &workspace)
        #expect(workspace.apiOptions["preferredLightTheme"] == nil)
        #expect(workspace.apiOptions["loadActionListGroup"] != nil)
    }

    @Test func editingCopyAndEncodingFailureLeaveOriginalUnchanged() throws {
        let original = Workspace(name: "Original")
        var copy = original
        #expect(throws: (any Error).self) {
            try WorkspaceOptionsEditor.set(Date(), for: "invalid", in: &copy)
        }
        #expect(copy == original)
        try WorkspaceOptionsEditor.set("flagged", for: "flaggedStatus", in: &copy)
        #expect(original.scriptMetadata == nil)
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(copy))
        #expect(decoded == copy)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var library: LibraryStore? = try LibraryStore(directory: folder, seed: false)
        try library!.saveWorkspace(copy)
        library = nil
        let reopened = try LibraryStore(directory: folder, seed: false)
        #expect(reopened.workspaces == [copy])
    }
}
