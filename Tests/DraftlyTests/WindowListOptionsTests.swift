import AppKit
import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Window list option ownership") @MainActor
struct WindowListOptionsTests {
    private func model(defaults: UserDefaults, library: LibraryStore? = nil) throws -> WindowModel {
        let store = try library ?? LibraryStore(inMemory: true, seed: false)
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: defaults)
        return WindowModel(library: store, dependencies: dependencies)
    }

    private func seed(_ options: DraftListOptions, defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(options), forKey: "list.options")
        defaults.set(options.showPreview, forKey: "list.showPreview")
        defaults.set(options.previewLines, forKey: "list.previewLines")
        defaults.set(options.showTags, forKey: "list.showTags")
        defaults.set(options.showDate, forKey: "list.showDate")
    }

    private var alternative: DraftListOptions {
        var options = DraftListOptions()
        options.showPreview = false; options.previewLines = 3
        options.showTags = false; options.showDate = false
        options.searchTitlesOnly = true; options.caseSensitiveSearch = true
        options.previewSearchMatches = true; options.showLastAction = true; options.highlightFlagged = true
        return options
    }

    @Test(arguments: ["showPreview", "previewLines", "showTags", "showDate", "searchTitlesOnly",
                      "caseSensitiveSearch", "previewSearchMatches", "showLastAction", "highlightFlagged"])
    func localEditsPersistEachOptionThroughInjectedDefaultsAndReopen(property: String) throws {
        let preferences = try TestPreferences(prefix: "Draftly.WindowListOptions.")
        defer { preferences.close() }
        let window = try model(defaults: preferences.defaults)
        var changed = window.listOptions
        switch property {
        case "showPreview": changed.showPreview = false
        case "previewLines": changed.previewLines = 3
        case "showTags": changed.showTags = false
        case "showDate": changed.showDate = false
        case "searchTitlesOnly": changed.searchTitlesOnly = true
        case "caseSensitiveSearch": changed.caseSensitiveSearch = true
        case "previewSearchMatches": changed.previewSearchMatches = true
        case "showLastAction": changed.showLastAction = true
        default: changed.highlightFlagged = true
        }
        window.listOptions = changed
        #expect(window.listOptions == changed)
        #expect(DraftListDefaults.load(defaults: preferences.defaults) == changed)
        let reopened = try model(defaults: preferences.defaults)
        #expect(reopened.listOptions == changed)
    }

    @Test func localWritesKeepUnknownJSONAndSynchronizeExistingLegacyOverrides() throws {
        let preferences = try TestPreferences(prefix: "Draftly.WindowListOptions.")
        defer { preferences.close() }
        try seed(DraftListOptions(), defaults: preferences.defaults)
        let initialData = try #require(preferences.defaults.data(forKey: "list.options"))
        var stored = try #require(JSONSerialization.jsonObject(with: initialData) as? [String: Any])
        stored["future"] = ["values": ["café 🐼", false] as [Any]]
        preferences.defaults.set(try JSONSerialization.data(withJSONObject: stored), forKey: "list.options")
        preferences.defaults.set("Keep device value", forKey: "unrelated.preference")
        let window = try model(defaults: preferences.defaults)
        window.listOptions = alternative

        #expect(DraftListDefaults.load(defaults: preferences.defaults) == alternative)
        #expect(preferences.defaults.bool(forKey: "list.showPreview") == false)
        #expect(preferences.defaults.integer(forKey: "list.previewLines") == 3)
        #expect(preferences.defaults.bool(forKey: "list.showTags") == false)
        #expect(preferences.defaults.bool(forKey: "list.showDate") == false)
        let savedData = try #require(preferences.defaults.data(forKey: "list.options"))
        let saved = try #require(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        let savedFuture = try #require(saved["future"] as? [String: Any])
        let originalFuture = try #require(stored["future"] as? [String: Any])
        #expect(NSDictionary(dictionary: savedFuture).isEqual(to: originalFuture))
        #expect(preferences.defaults.string(forKey: "unrelated.preference") == "Keep device value")
    }

    @Test(arguments: [false, true])
    func appliedWorkspaceOptionsAndEditsNeverReplaceLocalDefaults(saved: Bool) throws {
        let preferences = try TestPreferences(prefix: "Draftly.WindowListOptions.")
        defer { preferences.close() }
        try seed(DraftListOptions(), defaults: preferences.defaults)
        let before = preferences.defaults.data(forKey: "list.options")
        let window = try model(defaults: preferences.defaults)
        var workspace = Workspace(name: "Workspace option origin")
        workspace.listOptions = alternative
        if saved { try window.library.saveWorkspace(workspace) }
        try window.applyScriptWorkspace(workspace)
        #expect(window.selectedWorkspace == (saved ? workspace.id : nil))
        #expect(window.listOptions == alternative)
        window.listOptions.previewLines = 1
        window.listOptions.searchTitlesOnly = false
        #expect(window.workspaceSnapshot(name: "Current").listOptions == window.listOptions)
        #expect(preferences.defaults.data(forKey: "list.options") == before)
        #expect(DraftListDefaults.load(defaults: preferences.defaults) == DraftListOptions())
        if saved { #expect(window.library.workspaces.first == workspace) }
    }

    @Test func clearingWorkspaceOptionsRestoresLocalDefaultsAndAllowsLaterLocalPersistence() throws {
        let preferences = try TestPreferences(prefix: "Draftly.WindowListOptions.")
        defer { preferences.close() }
        try seed(alternative, defaults: preferences.defaults)
        let window = try model(defaults: preferences.defaults)
        var workspace = Workspace(name: "Reset options")
        workspace.listOptions = DraftListOptions()
        try window.applyScriptWorkspace(workspace)
        #expect(window.listOptions == DraftListOptions())
        window.clearFilters()
        #expect(window.listOptions == alternative)
        window.listOptions.previewLines = 1
        var expected = alternative; expected.previewLines = 1
        #expect(DraftListDefaults.load(defaults: preferences.defaults) == expected)
        #expect(try model(defaults: preferences.defaults).listOptions == expected)
    }

    @Test func localWindowsReceivePreferenceEditsWhileWorkspaceAndOtherDeviceOptionsStaySeparate() async throws {
        let preferences = try TestPreferences(prefix: "Draftly.WindowListOptions.")
        let otherPreferences = try TestPreferences(prefix: "Draftly.WindowListOptions.Other.")
        defer { preferences.close(); otherPreferences.close() }
        let first = try model(defaults: preferences.defaults)
        let second = try model(defaults: preferences.defaults, library: first.library)
        let workspaceWindow = try model(defaults: preferences.defaults, library: first.library)
        let otherDevice = try model(defaults: otherPreferences.defaults, library: first.library)
        var workspace = Workspace(name: "Keep override"); workspace.listOptions = DraftListOptions()
        try workspaceWindow.applyScriptWorkspace(workspace)

        first.listOptions = alternative
        await TestMainQueue.drain()

        #expect(second.listOptions == alternative)
        #expect(workspaceWindow.listOptions == DraftListOptions())
        #expect(otherDevice.listOptions == DraftListOptions())
        #expect(otherPreferences.defaults.data(forKey: "list.options") == nil)
    }

    @Test func externalPreferenceNotificationReloadsOnlyLocalWindows() async throws {
        let preferences = try TestPreferences(prefix: "Draftly.WindowListOptions.")
        defer { preferences.close() }
        let local = try model(defaults: preferences.defaults)
        let workspaceWindow = try model(defaults: preferences.defaults, library: local.library)
        try workspaceWindow.applyScriptWorkspace(Workspace(name: "Inherited snapshot"))
        try seed(alternative, defaults: preferences.defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: preferences.defaults)
        await TestMainQueue.drain()

        #expect(local.listOptions == alternative)
        #expect(workspaceWindow.listOptions == DraftListOptions())
        #expect(DraftListDefaults.load(defaults: preferences.defaults) == alternative)
    }

    @Test(arguments: [false, true])
    func omittedWorkspaceOptionsInheritDeviceDefaultsWithoutMaterializingThemInStorage(saved: Bool) throws {
        let preferences = try TestPreferences(prefix: "Draftly.WindowListOptions.")
        defer { preferences.close() }
        try seed(alternative, defaults: preferences.defaults)
        let window = try model(defaults: preferences.defaults)
        let workspace = Workspace(name: "Inherited options")
        if saved { try window.library.saveWorkspace(workspace) }
        try window.applyScriptWorkspace(workspace)
        #expect(window.listOptions == alternative)
        #expect(window.selectedWorkspace == (saved ? workspace.id : nil))
        window.listOptions = DraftListOptions()
        #expect(DraftListDefaults.load(defaults: preferences.defaults) == alternative)
        if saved {
            let restored = try LibraryStore(inMemory: true, seed: false)
            try restored.restore(window.library.backupData())
            let storedWorkspace = try #require(restored.workspaces.first)
            #expect(storedWorkspace.listOptions == nil)
            let reopened = try model(defaults: preferences.defaults, library: restored)
            try reopened.applyScriptWorkspace(storedWorkspace)
            #expect(reopened.listOptions == alternative)
        }
    }

    @Test func listOptionChangesKeepTheCurrentDraftSelectionAndUndoHistory() throws {
        let preferences = try TestPreferences(prefix: "Draftly.WindowListOptions.")
        defer { preferences.close() }
        let window = try model(defaults: preferences.defaults)
        let original = "🐼 café\nTail"
        let note = try window.library.createNote(content: original)
        window.select(note.id)
        let native = NativeEditor(session: window.editor, fontName: "System", fontSize: 17,
                                  lineSpacing: 2, markdown: false, onChange: {})
        let editor = ScriptUndoEditorFixture(native, content: original)
        defer { editor.close() }
        window.editor.selection = NSRange(location: 3, length: 4)
        editor.text.setSelectedRange(window.editor.selection)
        try window.editor.replace(window.editor.selection, with: "té")
        window.editor.synchronizeScriptEdit?()
        let selection = window.editor.selection
        let focus = window.editor.focusToken
        var workspace = Workspace(name: "Editor stays open"); workspace.listOptions = alternative
        try window.applyScriptWorkspace(workspace)
        window.listOptions.previewLines = 1
        window.clearFilters()
        window.listOptions.showTags = false

        #expect(window.editor.noteID == note.id && window.editor.content == "🐼 té\nTail")
        #expect(window.editor.selection == selection && window.editor.focusToken == focus)
        #expect(editor.text.manager.canUndo)
        window.editor.performUndo?(false)
        #expect(window.editor.content == original && editor.text.string == original)
        window.editor.performUndo?(true)
        #expect(window.editor.content == "🐼 té\nTail")
    }
}
