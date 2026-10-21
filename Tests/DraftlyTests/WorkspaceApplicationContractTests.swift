import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Workspace application contracts") @MainActor
struct WorkspaceApplicationContractTests {
    private struct State: Equatable {
        let folder: NoteFolder
        let query: String
        let sort: NoteSort
        let ascending: Bool
        let tags: Set<String>
        let excludedTags: Set<String>
        let matchAnyTag: Bool
        let listOptions: DraftListOptions
        let workspaceID: UUID?
        let metadata: [String: String]?
        let actionGroup: String
        let actionBarGroup: String
        let noteID: UUID?
        let text: String
        let selection: NSRange
        let focus: UUID
    }

    private func state(_ model: WindowModel) -> State {
        State(folder: model.folder, query: model.query, sort: model.sort,
              ascending: model.ascending, tags: model.selectedTags,
              excludedTags: model.excludedTags, matchAnyTag: model.matchAnyTag,
              listOptions: model.listOptions, workspaceID: model.selectedWorkspace,
              metadata: model.workspaceScriptMetadata, actionGroup: model.actionGroup,
              actionBarGroup: model.actionBarGroup, noteID: model.editor.noteID,
              text: model.editor.content, selection: model.editor.selection,
              focus: model.editor.focusToken)
    }

    private func metadata(_ values: [String: Any]) throws -> [String: String] {
        ["api": String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)]
    }

    private func fixture(_ number: Int, _ title: String, created: String, modified: String,
                         accessed: String? = nil, flag: Int = 0, archived: Bool = false,
                         trashed: Bool = false, tags: [String] = ["application-contract"]) -> Note {
        Note(id: UUID(uuidString: String(format: "DAAF7300-0000-4000-8000-%012d", number))!,
             content: title, tags: tags, flag: flag, isArchived: archived,
             trashedAt: trashed ? APIValues.parseDate("2021-01-15T12:00:00Z") : nil,
             createdAt: APIValues.parseDate(created)!, modifiedAt: APIValues.parseDate(modified)!,
             accessedAt: accessed.flatMap(APIValues.parseDate))
    }

    private func model() throws -> WindowModel {
        let library = try LibraryStore(inMemory: true, seed: false)
        for note in [
            fixture(1, "Inbox Alpha", created: "2020-01-15T12:00:00Z", modified: "2020-03-15T12:00:00Z", accessed: "2020-02-15T12:00:00Z"),
            fixture(2, "Inbox Zulu", created: "2020-03-15T12:00:00Z", modified: "2020-01-15T12:00:00Z", flag: 1),
            fixture(3, "Archive Beta", created: "2020-06-15T12:00:00Z", modified: "2020-02-15T12:00:00Z", accessed: "2020-01-15T12:00:00Z", archived: true),
            fixture(4, "Archive Gamma", created: "2020-09-15T12:00:00Z", modified: "2020-04-15T12:00:00Z", accessed: "2020-09-15T12:00:00Z", flag: 2, archived: true),
            fixture(5, "Trash Delta", created: "2020-12-15T12:00:00Z", modified: "2020-05-15T12:00:00Z", trashed: true)
        ] { try library.saveNote(note, preserveDates: true) }
        let source = try library.createNote(content: "Source 🐼 café\nSaved text")
        let model = WindowModel(library: library)
        model.select(source.id)
        model.editor.content = "Source 🐼 café\nPending text"
        model.editor.selection = NSRange(location: 7, length: 2)
        return model
    }

    private func run(_ script: String, on model: WindowModel) {
        let action = DraftAction(name: "Workspace application contract", steps: [
            ActionStep("script", ["script": """
            function check(value, label) { if (!value) throw new Error(label); }
            \(script)
            """])
        ])
        #expect(model.runner.run(action), Comment(rawValue: model.runner.message ?? ""))
    }

    private func withThemes(_ themes: [EditorTheme], library: LibraryStore, body: () throws -> Void) throws {
        try library.saveThemes(themes)
        try body()
    }

    @Test func loadFolderAppliesAllFiveTabsWithoutChangingTheEditorOrSelection() throws {
        let model = try model()
        let original = state(model)
        let cases: [(String, [String])] = [
            ("inbox", ["Inbox Alpha", "Inbox Zulu"]),
            ("archive", ["Archive Beta", "Archive Gamma"]),
            ("flagged", ["Archive Gamma", "Inbox Zulu"]),
            ("trash", ["Trash Delta"]),
            ("all", ["Archive Beta", "Archive Gamma", "Inbox Alpha", "Inbox Zulu"])
        ]
        for (folder, expected) in cases {
            let expectedJSON = String(decoding: try JSONEncoder().encode(expected), as: UTF8.self)
            run("""
            const w=new Workspace();w.name='Folder \(folder)';w.tagFilter='application-contract';
            w.loadFolder='\(folder)';w.setInboxSort('name',false,false);w.setArchiveSort('name',false,false);
            w.setFlaggedSort('name',false);w.setAllSort('name',false,false);w.update();
            const saved=Workspace.find(w.name);check(saved.loadFolder==='\(folder)','stored folder');
            check(JSON.stringify(saved.query('\(folder)').map(d=>d.title))===JSON.stringify(\(expectedJSON)),'script rows');
            check(app.applyWorkspace(saved)===true,'application result');
            """, on: model)
            #expect(model.folder.rawValue == folder)
            #expect(model.visibleNotes.map(\.title) == expected)
            #expect(model.editor.noteID == original.noteID && model.editor.content == original.text)
            #expect(model.editor.selection == original.selection && model.editor.focusToken == original.focus)
            #expect(model.library.notes.first { $0.id == original.noteID }?.content == original.text)
        }
    }

    @Test func actionGroupReferencesResolveUUIDsAfterRenameAndNamesWhenIDsAreOmitted() throws {
        let model = try model()
        var list = ActionGroupRecord(name: "Original list")
        var bar = ActionGroupRecord(name: "Original bar")
        try model.library.saveActionGroup(list)
        try model.library.saveActionGroup(bar)
        var workspace = Workspace(name: "Group identities")
        workspace.scriptMetadata = try metadata([
            "loadActionListGroup": ["uuid": list.id.uuidString, "name": list.name],
            "loadActionBarGroup": ["uuid": bar.id.uuidString, "name": bar.name]
        ])
        list.name = "Renamed list"; bar.name = "Renamed bar"
        try model.library.saveActionGroup(list)
        try model.library.saveActionGroup(bar)
        let before = state(model)
        try model.applyScriptWorkspace(workspace)
        #expect(model.actionGroup == "Renamed list" && model.actionBarGroup == "Renamed bar")
        let resolved = try #require(model.workspaceScriptMetadata?["api"])
        #expect(resolved.contains("Renamed list") && resolved.contains("Renamed bar"))
        #expect(model.editor.noteID == before.noteID && model.editor.content == before.text)
        #expect(model.editor.selection == before.selection && model.editor.focusToken == before.focus)
        workspace.scriptMetadata = try metadata([
            "loadActionListGroup": ["name": "Renamed bar"],
            "loadActionBarGroup": ["name": "Renamed list"]
        ])
        try model.applyScriptWorkspace(workspace)
        #expect(model.actionGroup == "Renamed bar" && model.actionBarGroup == "Renamed list")
    }

    @Test func missingActionGroupIDsOrNamesRejectTheWholeApplication() throws {
        let model = try model()
        let list = ActionGroupRecord(name: "Valid list"), bar = ActionGroupRecord(name: "Valid bar")
        try model.library.saveActionGroup(list); try model.library.saveActionGroup(bar)
        model.actionGroup = "Keep list"; model.actionBarGroup = "Keep bar"
        model.query = "Keep query"; model.folder = .archive
        let before = state(model)
        for key in ["loadActionListGroup", "loadActionBarGroup"] {
            for useID in [true, false] {
                var values: [String: Any] = [
                    "loadActionListGroup": ["uuid": list.id.uuidString, "name": list.name],
                    "loadActionBarGroup": ["uuid": bar.id.uuidString, "name": bar.name]
                ]
                values[key] = useID
                    ? ["uuid": "DAAF7300-0000-4000-8000-000000009999", "name": key == "loadActionListGroup" ? list.name : bar.name]
                    : ["name": "Missing group"]
                var workspace = Workspace(name: "Must not apply")
                workspace.folder = .trash; workspace.query = "Changed query"; workspace.tags = ["changed"]
                workspace.listOptions = DraftListOptions(); workspace.listOptions?.showTags = false
                workspace.scriptMetadata = try metadata(values)
                #expect(throws: (any Error).self) { try model.applyScriptWorkspace(workspace) }
                #expect(state(model) == before)
            }
        }
    }

    @Test(arguments: ["number", "string", "boolean", "array"])
    func malformedReferencesRejectApplicationAndSaveWithoutChangingStoredDefinitionsOrWindow(shape: String) throws {
        let model = try model()
        model.query = "Keep query"; model.folder = .archive
        let original = Workspace(name: "Keep definition")
        try model.library.saveWorkspace(original)
        let before = state(model)
        let invalid: Any
        switch shape {
        case "number": invalid = 17
        case "string": invalid = "Missing reference"
        case "boolean": invalid = false
        default: invalid = ["Missing reference"]
        }
        for key in ["loadActionListGroup", "loadActionBarGroup", "preferredDarkTheme", "preferredLightTheme"] {
            var workspace = original
            workspace.name = "Must not save"; workspace.folder = .trash
            workspace.query = "Changed query"; workspace.tags = ["changed"]
            workspace.listOptions = DraftListOptions(); workspace.listOptions?.showTags = false
            workspace.scriptMetadata = try metadata([key: invalid])
            #expect(throws: (any Error).self) { try model.applyScriptWorkspace(workspace) }
            #expect(state(model) == before)
            #expect(model.library.workspaces == [original])
            #expect(throws: (any Error).self) { try model.saveAndApplyWorkspace(workspace) }
            #expect(state(model) == before)
            #expect(model.library.workspaces == [original])
        }
    }

    @Test func nullGroupAndThemeReferencesRetainNoOverrideBehavior() throws {
        let model = try model()
        model.actionGroup = "Keep list"; model.actionBarGroup = "Keep bar"
        let before = state(model)
        var workspace = Workspace(name: "Null references")
        workspace.folder = .archive; workspace.query = "Applied query"
        workspace.scriptMetadata = try metadata([
            "loadActionListGroup": NSNull(), "loadActionBarGroup": NSNull(),
            "preferredDarkTheme": NSNull(), "preferredLightTheme": NSNull()
        ])
        try model.saveAndApplyWorkspace(workspace)
        #expect(model.folder == .archive && model.query == "Applied query")
        #expect(model.actionGroup == "Keep list" && model.actionBarGroup == "Keep bar")
        #expect(model.editor.noteID == before.noteID && model.editor.content == before.text)
        #expect(model.editor.selection == before.selection && model.editor.focusToken == before.focus)
        let saved = try #require(model.library.workspaces.first { $0.id == workspace.id })
        for key in ["loadActionListGroup", "loadActionBarGroup", "preferredDarkTheme", "preferredLightTheme"] {
            #expect(saved.apiOptions[key] is NSNull)
        }
    }

    @Test func preferredThemesResolveBothCustomIDsAndBuiltInNames() throws {
        let model = try model()
        var dark = EditorTheme(); dark.name = "Night 🐼"; dark.isDark = true
        dark.foreground = "EEEEEE"; dark.background = "202020"
        var light = EditorTheme(); light.name = "Paper café"
        let selectedPreference = UserDefaults.standard.object(forKey: "editor.theme") as? String
        try withThemes([dark, light], library: model.library) {
            let before = state(model)
            var workspace = Workspace(name: "Theme identities")
            workspace.scriptMetadata = try metadata([
                "preferredDarkTheme": ["type": "custom", "uuid": dark.id.uuidString, "name": "Old night"],
                "preferredLightTheme": ["type": "custom", "uuid": light.id.uuidString, "name": "Old paper"]
            ])
            try model.applyScriptWorkspace(workspace)
            #expect(WorkspaceThemeValues.preference(model.workspaceScriptMetadata, key: "preferredDarkTheme") == dark.name)
            #expect(WorkspaceThemeValues.preference(model.workspaceScriptMetadata, key: "preferredLightTheme") == light.name)
            let data = String(decoding: try JSONEncoder().encode(model.library.themes), as: UTF8.self)
            #expect(EditorTheme.selected(name: dark.name, data: data) == dark)
            #expect(EditorTheme.selected(name: light.name, data: data) == light)
            workspace.scriptMetadata = try metadata([
                "preferredDarkTheme": ["type": "builtIn", "name": "Dark"],
                "preferredLightTheme": ["type": "builtIn", "name": "Light"]
            ])
            try model.applyScriptWorkspace(workspace)
            #expect(WorkspaceThemeValues.preference(model.workspaceScriptMetadata, key: "preferredDarkTheme") == "Dark")
            #expect(WorkspaceThemeValues.preference(model.workspaceScriptMetadata, key: "preferredLightTheme") == "Light")
            #expect(model.editor.noteID == before.noteID && model.editor.content == before.text)
            #expect(model.editor.selection == before.selection && model.editor.focusToken == before.focus)
            #expect(UserDefaults.standard.object(forKey: "editor.theme") as? String == selectedPreference)
        }
    }

    @Test func missingPreferredThemeIDsOrNamesRejectBeforeChangingGroupsOrFilters() throws {
        let model = try model()
        let group = ActionGroupRecord(name: "Candidate group")
        try model.library.saveActionGroup(group)
        var theme = EditorTheme(); theme.name = "Existing theme"
        try withThemes([theme], library: model.library) {
            model.query = "Keep query"; model.actionGroup = "Keep list"; model.actionBarGroup = "Keep bar"
            model.folder = .flagged
            let before = state(model)
            let missingCases: [[String: String]] = [
                ["type": "custom", "uuid": "DAAF7300-0000-4000-8000-000000009999", "name": theme.name],
                ["type": "custom", "name": "Missing custom theme"],
                ["type": "builtIn", "name": "Missing built-in theme"]
            ]
            for key in ["preferredDarkTheme", "preferredLightTheme"] {
                for missing in missingCases {
                    var values: [String: Any] = [
                        "loadActionListGroup": ["uuid": group.id.uuidString, "name": group.name],
                        "loadActionBarGroup": ["uuid": group.id.uuidString, "name": group.name],
                        "preferredDarkTheme": ["type": "custom", "uuid": theme.id.uuidString, "name": theme.name],
                        "preferredLightTheme": ["type": "custom", "uuid": theme.id.uuidString, "name": theme.name]
                    ]
                    values[key] = missing
                    var workspace = Workspace(name: "Must not apply")
                    workspace.folder = .trash; workspace.query = "Changed"; workspace.tags = ["changed"]
                    workspace.scriptMetadata = try metadata(values)
                    #expect(throws: (any Error).self) { try model.applyScriptWorkspace(workspace) }
                    #expect(state(model) == before)
                }
            }
        }
    }

    @Test func omittedGroupAndThemePreferencesKeepGroupsAndRemoveWorkspaceThemeOverrides() throws {
        let model = try model()
        model.actionGroup = "Keep list"; model.actionBarGroup = "Keep bar"
        var first = Workspace(name: "Theme override")
        first.scriptMetadata = try metadata([
            "preferredDarkTheme": ["type": "builtIn", "name": "Dark"],
            "preferredLightTheme": ["type": "builtIn", "name": "Light"]
        ])
        try model.applyScriptWorkspace(first)
        let before = state(model)
        let next = Workspace(name: "No preferred groups or themes")
        try model.applyScriptWorkspace(next)
        #expect(model.actionGroup == "Keep list" && model.actionBarGroup == "Keep bar")
        #expect(WorkspaceThemeValues.preference(model.workspaceScriptMetadata, key: "preferredDarkTheme") == nil)
        #expect(WorkspaceThemeValues.preference(model.workspaceScriptMetadata, key: "preferredLightTheme") == nil)
        #expect(model.editor.noteID == before.noteID && model.editor.content == before.text)
        #expect(model.editor.selection == before.selection && model.editor.focusToken == before.focus)
    }

    @Test func datesExclusionsAndFolderOrderMatchQueriesAfterBackupRestoration() throws {
        let model = try model()
        let blocked = fixture(6, "Archive Blocked", created: "2020-07-15T12:00:00Z", modified: "2020-07-15T12:00:00Z", flag: 3, archived: true, tags: ["application-contract", "blocked"])
        try model.library.saveNote(blocked, preserveDates: true)
        let editorBefore = state(model)
        run(#"""
        const w=new Workspace();w.name='Dates and order';w.loadFolder='all';
        w.tagFilter='application-contract,!blocked';w.tagFilterRequireAll=true;
        w.startDate.type='absolute';w.startDate.field='created';w.startDate.date=new Date('2020-04-01T12:00:00Z');
        w.endDate.type='absolute';w.endDate.field='created';w.endDate.date=new Date('2020-10-01T12:00:00Z');
        w.setAllSort('created',false,true);w.setArchiveSort('accessed',false,false);
        w.showDate=false;w.showTags=false;w.update();
        const saved=Workspace.find(w.name);
        check(saved.query('all').map(d=>d.title).join('|')==='Archive Gamma|Archive Beta','flagged first after date and exclusion');
        check(saved.query('archive').map(d=>d.title).join('|')==='Archive Beta|Archive Gamma','Archive access ascending');
        app.applyWorkspace(saved);
        """#, on: model)
        #expect(model.visibleNotes.map(\.title) == ["Archive Gamma", "Archive Beta"])
        #expect(model.editor.noteID == editorBefore.noteID && model.editor.content == editorBefore.text)
        #expect(model.editor.selection == editorBefore.selection)
        let saved = try #require(model.library.workspaces.first { $0.name == "Dates and order" })
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(model.library.backupData())
        let other = WindowModel(library: restored)
        other.select(try #require(editorBefore.noteID))
        other.editor.selection = editorBefore.selection
        let receiverBefore = state(other)
        let restoredWorkspace = try #require(restored.workspaces.first { $0.id == saved.id })
        try other.applyScriptWorkspace(restoredWorkspace)
        #expect(other.visibleNotes.map(\.title) == ["Archive Gamma", "Archive Beta"])
        #expect(other.visibleNotes.map(\.id) == restoredWorkspace.filter(restored.notes).map(\.id))
        #expect(!other.listOptions.showDate && !other.listOptions.showTags)
        #expect(other.editor.noteID == receiverBefore.noteID && other.editor.content == receiverBefore.text)
        #expect(other.editor.selection == receiverBefore.selection && other.editor.focusToken == receiverBefore.focus)
        other.folder = .archive
        #expect(other.visibleNotes.map(\.title) == ["Archive Beta", "Archive Gamma"])
        #expect(other.editor.noteID == receiverBefore.noteID && other.editor.content == receiverBefore.text)
        #expect(other.editor.selection == receiverBefore.selection)
    }
}
