import Foundation
import Testing
@testable import DraftlyCore

@Suite("Workspace sort options") @MainActor
struct WorkspaceSortOptionsTests {
    @Test(arguments: [false, true])
    func explicitFlaggedValueReplacesOnlyTheRequestedField(flagged: Bool) throws {
        var options: [String: Any] = ["future": true, "_sorts": [
            "inbox": ["flagged": "future flag", "future": 42] as [String: Any],
            "archive": ["sort": "created"]
        ]]
        Workspace.updateSortOptions(&options, sort: .title, ascending: false,
                                    flaggedFirst: flagged, folder: .inbox)
        let sorts = try #require(options["_sorts"] as? [String: [String: Any]])
        #expect(sorts["inbox"]?["flagged"] as? Bool == flagged)
        #expect(sorts["inbox"]?["future"] as? Int == 42)
        #expect(sorts["inbox"]?["sort"] as? String == "name")
        #expect(sorts["inbox"]?["descending"] as? Bool == true)
        #expect(sorts["archive"]?["sort"] as? String == "created")
        #expect(options["future"] as? Bool == true)
    }

    @Test func omittedFlaggedValueDoesNotCreateTheField() throws {
        var options: [String: Any] = [:]
        Workspace.updateSortOptions(&options, sort: .accessed, ascending: true, folder: .archive)
        let sorts = try #require(options["_sorts"] as? [String: [String: Any]])
        let entry = try #require(sorts["archive"])
        #expect(entry.count == 2)
        #expect(entry["flagged"] == nil)
        #expect(entry["sort"] as? String == "accessed")
        #expect(entry["descending"] as? Bool == false)
    }

    @Test(arguments: NoteSort.allCases.map(\.rawValue), [false, true])
    func bridgeWritesTheCurrentFolderAndKeepsOtherValues(sortName: String, ascending: Bool) throws {
        let sort = try #require(NoteSort(rawValue: sortName))
        let (_, _, _, runner) = try makeAPIContext()
        var workspace = Workspace(name: "Sort options")
        workspace.sort = sort; workspace.ascending = ascending
        workspace.scriptMetadata = ["api": #"{"future":{"keep":true},"_sorts":{"archive":{"sort":"created","descending":true},"inbox":{"sort":"modified","flagged":"future flag","future":42}}}"#]
        let values = try runner.workspaceValue(workspace)
        let sorts = try #require(values["_sorts"] as? [String: [String: Any]])
        let entry = try #require(sorts[workspace.folder.rawValue])
        #expect(entry["sort"] as? String == (sort == .title ? "name" : sort.rawValue))
        #expect(entry["descending"] as? Bool == !ascending)
        #expect(entry["flagged"] as? String == "future flag")
        #expect(entry["future"] as? Int == 42)
        #expect(sorts["archive"]?["sort"] as? String == "created")
        #expect(sorts["archive"]?["descending"] as? Bool == true)
        #expect((values["future"] as? [String: Bool])?["keep"] == true)
    }

    @Test(arguments: [#"{}"#, #"{"_sorts":17}"#, #"{"_sorts":{"archive":17,"inbox":{"flagged":true}}}"#])
    func bridgeReplacesMalformedSortContainers(api: String) throws {
        let (_, _, _, runner) = try makeAPIContext()
        var workspace = Workspace(name: "Malformed sort options")
        workspace.sort = .title; workspace.ascending = true
        workspace.scriptMetadata = ["api": api]
        let values = try runner.workspaceValue(workspace)
        let sorts = try #require(values["_sorts"] as? [String: [String: Any]])
        #expect(sorts.count == 1)
        let entry = try #require(sorts[workspace.folder.rawValue])
        #expect(entry.count == 2)
        #expect(entry["sort"] as? String == "name")
        #expect(entry["descending"] as? Bool == false)
    }
}
