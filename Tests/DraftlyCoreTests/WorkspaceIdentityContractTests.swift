import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class WorkspaceLinkHost: ActionHost {
    var clipboard = ""
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        guard operation == "clipboard", let text = values["text"] as? String else {
            throw DraftlyError.message("Unexpected Workspace link test operation: \(operation)")
        }
        clipboard = text
        return true
    }
}

@Suite("Workspace identity contracts") @MainActor
struct WorkspaceIdentityContractTests {
    private func link(_ values: [String: Any]) throws -> URL {
        var components = URLComponents()
        components.scheme = "draftly"; components.host = "workspace"
        let data = try JSONSerialization.data(withJSONObject: values)
        components.queryItems = [URLQueryItem(name: "data", value: String(decoding: data, as: UTF8.self))]
        return try #require(components.url)
    }

    @Test func installationLinkUsesTheSharedEvaluatorAndPreservesUnknownFields() throws {
        let id = UUID()
        let url = try link(["uuid": id.uuidString, "name": "Café 🐼", "tagFilter": "keep,!skip",
                            "loadFolder": "archive", "showTags": false,
                            "future": ["neutral": true]])
        let workspace = try WorkspaceInstallation.decode(url)
        #expect(workspace.id == id && workspace.name == "Café 🐼")
        #expect(workspace.folder == .archive && workspace.tags == ["keep"])
        #expect(workspace.excludedTags == ["skip"] && workspace.listOptions?.showTags == false)
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveWorkspace(workspace)
        let reopened = try LibraryStore(inMemory: true, seed: false)
        try reopened.restore(library.backupData())
        #expect(reopened.workspaces.first?.scriptMetadata == workspace.scriptMetadata)
        #expect(workspace.scriptMetadata?["api"]?.contains("future") == true)
    }

    @Test func invalidInstallationLinksFailBeforeChangingTheLibrary() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveWorkspace(Workspace(name: "Keep"))
        let before = library.workspaces
        for values: [String: Any] in [[:], ["name": "Invalid", "uuid": "bad"],
                                      ["name": "Invalid", "loadFolder": "bad"],
                                      ["name": "Invalid", "flaggedStatus": "bad"]] {
            let url = try link(values)
            #expect(throws: (any Error).self) { try library.saveWorkspace(WorkspaceInstallation.decode(url)) }
        }
        for raw in ["https://workspace?data=%7B%7D", "draftly://workspace", "draftly://workspace?data=null",
                    "draftly://workspace?data=%7B%7D&data=%7B%7D"] {
            #expect(throws: (any Error).self) { try WorkspaceInstallation.decode(#require(URL(string: raw))) }
        }
        #expect(library.workspaces == before)
    }
    private struct Harness {
        let library: LibraryStore
        let host: WorkspaceLinkHost
        let runner: ActionRunner
    }

    private func harness(library: LibraryStore? = nil) throws -> Harness {
        let library = try library ?? LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "Workspace link source"))
        let host = WorkspaceLinkHost()
        return Harness(library: library, host: host,
                       runner: ActionRunner(library: library, editor: editor, host: host))
    }

    private func run(_ script: String, in harness: Harness) {
        let action = DraftAction(name: "Workspace identity contract", steps: [
            ActionStep("script", ["script": """
            function check(value, label) { if (!value) throw new Error(label); }
            \(script)
            """])
        ])
        #expect(harness.runner.run(action), Comment(rawValue: harness.runner.message ?? ""))
    }

    private func payload(_ link: String) throws -> [String: Any] {
        let components = try #require(URLComponents(string: link))
        #expect(components.scheme == "draftly" && components.host == "workspace")
        let items = try #require(components.queryItems)
        #expect(items.count == 1 && items.first?.name == "data")
        let json = try #require(items.first?.value)
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func namePreservesUnicodeAndRenamesOnlyAfterUpdateWithoutChangingIdentity() throws {
        let value = try harness()
        run(#"""
        const w=new Workspace();check(w.name==='','default empty name');
        w.name='Café 🐼 & "Work" + /?';
        check(w.name==='Café 🐼 & "Work" + /?','string round trip');
        check(Workspace.find(w.name)===undefined,'name assignment does not persist');
        w.update();const uuid=w.uuid;
        check(Workspace.find('Café 🐼 & "Work" + /?').uuid===uuid,'stored name');
        w.name='Projects café 🐼';
        check(Workspace.find('Café 🐼 & "Work" + /?').uuid===uuid,'unsaved rename keeps stored name');
        check(Workspace.find(w.name)===undefined,'unsaved new name absent');
        w.update();
        check(Workspace.find('Café 🐼 & "Work" + /?')===undefined,'old name absent after update');
        check(Workspace.find('Projects café 🐼').uuid===uuid,'rename keeps identity');
        check(Workspace.getAll().length===1,'rename does not create a second Workspace');
        """#, in: value)
        #expect(value.library.workspaces.map(\.name) == ["Projects café 🐼"])
    }

    @Test func installURLContainsLosslessUnicodeConfigurationAndDoesNotMutateTheWorkspace() throws {
        let value = try harness()
        run(#"""
        const w=new Workspace();w.name='Café 🐼 & "Work" + /?';w.queryString='café OR 🐼';
        w.tagFilter='café,!blocked';w.tagFilterRequireAll=false;w.loadFolder='archive';
        w.setInboxSort('modified',true,true);w.setArchiveSort('name',false,false);
        w.setAllSort('accessed',false,false);w.showTags=false;w.showLastAction=true;
        w.startDate.type='absolute';w.startDate.field='created';w.startDate.date=new Date('2020-01-01T12:00:00Z');
        w.futureWorkspaceField={enabled:true,caption:'Unknown 🐼 + &'};w.update();
        const before=JSON.stringify(w), first=w.installURL;
        check(typeof first==='string' && first.startsWith('draftly://workspace?data='),'Draftly installation link');
        check(w.installURL===first,'stable getter');
        w.installURL='invalid';check(w.installURL===first,'read-only installation link');
        check(JSON.stringify(w)===before,'link generation has no mutation');
        app.setClipboard(first);
        """#, in: value)
        let values = try payload(value.host.clipboard)
        let saved = try #require(value.library.workspaces.first)
        #expect(values["uuid"] as? String == saved.id.uuidString)
        #expect(values["name"] as? String == "Café 🐼 & \"Work\" + /?")
        #expect(values["queryString"] as? String == "café OR 🐼")
        #expect(values["tagFilter"] as? String == "café,!blocked")
        #expect(values["tagFilterRequireAll"] as? Bool == false)
        #expect(values["loadFolder"] as? String == "archive")
        #expect(values["showTags"] as? Bool == false && values["showLastAction"] as? Bool == true)
        let date = try #require(values["startDate"] as? [String: Any])
        #expect(date["field"] as? String == "created")
        #expect(APIValues.parseDate(date["date"]) == APIValues.parseDate("2020-01-01T12:00:00Z"))
        let unknown = try #require(values["futureWorkspaceField"] as? [String: Any])
        #expect(unknown["caption"] as? String == "Unknown 🐼 + &" && unknown["enabled"] as? Bool == true)
    }

    @Test func installURLPayloadDecodesAndSurvivesBackupWithItsConfiguration() throws {
        let source = try harness()
        run(#"""
        const w=new Workspace();w.name='Portable café 🐼';w.tagFilter='work,!private';
        w.loadFolder='archive';w.showPreview=false;w.showSearchPreview=true;
        w.inboxIncludesFlagged=false;w.archiveIncludesFlagged=true;
        w.setArchiveSort('created',true,true);w.setInboxSort('name',false,false);
        w.endDate.type='absolute';w.endDate.field='modified';w.endDate.date=new Date('2030-06-15T12:00:00Z');
        w.update();app.setClipboard(w.installURL);
        """#, in: source)
        let values = try payload(source.host.clipboard)
        let receiver = try harness()
        let incoming = try receiver.runner.decodeWorkspace(values)
        try receiver.library.saveWorkspace(incoming)
        run(#"""
        const w=Workspace.find('Portable café 🐼');
        check(w instanceof Workspace && w.endDate instanceof QueryDate,'typed imported values');
        check(w.endDate.date instanceof Date && w.endDate.date.toISOString()==='2030-06-15T12:00:00.000Z','typed imported date');
        check(w.loadFolder==='archive' && w.showPreview===false && w.showSearchPreview===true,'presentation values');
        check(w.inboxIncludesFlagged===false && w.archiveIncludesFlagged===true,'folder flags');
        """#, in: receiver)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(receiver.library.backupData())
        let saved = try #require(restored.workspaces.first)
        #expect(saved.id == incoming.id && saved.name == "Portable café 🐼")
        #expect(saved.tags == ["work"] && saved.excludedTags == ["private"])
        #expect(saved.folder == .archive && saved.sort == .created && !saved.ascending)
        #expect(saved.scriptSort(for: .archive)?.2 == true)
        #expect(saved.scriptSort(for: .inbox)?.0 == .title)
        #expect(saved.listOptions?.showPreview == false && saved.listOptions?.previewSearchMatches == true)
        let end = try #require(saved.apiOptions["endDate"] as? [String: Any])
        #expect(end["field"] as? String == "modified")
        #expect(APIValues.parseDate(end["date"]) == APIValues.parseDate("2030-06-15T12:00:00Z"))
    }
}
