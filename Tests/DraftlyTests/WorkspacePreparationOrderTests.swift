import Foundation
import Combine
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Workspace preparation effect order") @MainActor
struct WorkspacePreparationOrderTests {
    private enum Route: CaseIterable { case script, save, window }
    private enum Failure: CaseIterable { case group, file }

    private func withPendingAction(_ body: (WindowModel, Task<Void, Never>) throws -> Void) async throws {
        let preferences = try TestPreferences(prefix: "Draftly.WorkspacePreparation.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Keep café 🐼")
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: preferences.defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.select(note.id, focusEditor: false)
        model.editor.selection = NSRange(location: 5, length: 4)
        let pending = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        model.actionTask = pending
        model.actionPending = true
        defer {
            library.beforeBatchCommit = nil
            model.actionTask = nil
            model.actionPending = false
        }
        do { try body(model, pending) }
        catch { pending.cancel(); await pending.value; throw error }
        pending.cancel()
        await pending.value
    }

    private func workspace(options: [String: Any] = [:]) throws -> Workspace {
        var workspace = Workspace(name: "Prepared café 🐼")
        workspace.folder = .archive
        workspace.query = "Neutral filter"
        workspace.scriptMetadata = ["api": String(decoding: try JSONSerialization.data(withJSONObject: options), as: UTF8.self),
                                    "future-field": "Keep unknown metadata"]
        return workspace
    }

    @Test func savingCommitsBeforeCancellationAndAppliesAfterCancellation() async throws {
        try await withPendingAction { model, pending in
            let library = model.library
            let group = ActionGroupRecord(name: "Resolved group")
            try library.saveActionGroup(group)
            let candidate = try workspace(options: ["loadActionListGroup": ["uuid": group.id.uuidString, "name": "Old name"],
                                                    "future-option": "Keep this value"])
            let noteID = model.editor.noteID, text = model.editor.content
            let selection = model.editor.selection, focus = model.editor.focusToken
            var events: [String] = []
            library.beforeBatchCommit = {
                events.append("beforeCommit")
                #expect(!pending.isCancelled && model.folder == .inbox)
            }
            let saved = library.$workspaces.dropFirst().sink { values in
                guard values.contains(where: { $0.id == candidate.id }) else { return }
                events.append("saved")
                #expect(!pending.isCancelled && model.folder == .inbox)
            }
            let applied = model.$folder.dropFirst().sink { folder in
                events.append("applied")
                #expect(folder == .archive && pending.isCancelled)
                #expect(library.workspaces.contains { $0.id == candidate.id })
            }
            defer { saved.cancel(); applied.cancel() }
            try model.saveAndApplyWorkspace(candidate)
            #expect(events == ["beforeCommit", "saved", "applied"])
            let stored = try #require(library.workspaces.first { $0.id == candidate.id })
            #expect((stored.apiOptions["loadActionListGroup"] as? [String: String])?["name"] == group.name)
            #expect(stored.apiOptions["future-option"] as? String == "Keep this value")
            #expect(stored.scriptMetadata?["future-field"] == "Keep unknown metadata")
            #expect(model.selectedWorkspace == candidate.id && model.actionGroup == group.name)
            #expect(model.editor.noteID == noteID && model.editor.content == text)
            #expect(model.editor.selection == selection && model.editor.focusToken == focus)
        }
    }

    @Test func scriptApplicationDoesNotSaveOrCancelPendingAction() async throws {
        try await withPendingAction { model, pending in
            let candidate = try workspace()
            var writes = 0
            model.library.beforeBatchCommit = { writes += 1 }
            let applied = model.$folder.dropFirst().sink { _ in #expect(!pending.isCancelled) }
            defer { applied.cancel() }
            try model.applyScriptWorkspace(candidate)
            #expect(model.folder == .archive && model.query == candidate.query)
            #expect(writes == 0 && model.library.workspaces.isEmpty && !pending.isCancelled)
        }
    }

    @Test(arguments: Route.allCases, Failure.allCases)
    private func preparationFailurePreservesEachEntryPointsCancellationOrder(route: Route, failure: Failure) async throws {
        try await withPendingAction { model, pending in
            let theme = EditorThemeDefinition(name: "Neutral file theme", type: "file")
            try model.library.saveTheme(theme)
            var options: [String: Any] = ["preferredLightTheme": ["uuid": theme.id.uuidString, "type": "file", "name": theme.name]]
            if failure == .group { options["loadActionListGroup"] = ["name": "Missing group"] }
            let candidate = try workspace(options: options)
            var writes = 0
            model.library.beforeBatchCommit = { writes += 1 }
            let expected = failure == .group ? "The workspace action group was not found." : "Reselect the file for theme Neutral file theme."
            let text = model.editor.content, selection = model.editor.selection, focus = model.editor.focusToken
            if route == .window {
                model.apply(candidate)
                #expect(model.library.error == expected)
            } else {
                do {
                    if route == .save { try model.saveAndApplyWorkspace(candidate) }
                    else { try model.applyScriptWorkspace(candidate) }
                    Issue.record("Invalid Workspace preparation succeeded.")
                } catch { #expect(error.localizedDescription == expected) }
            }
            #expect(pending.isCancelled == (route == .window))
            #expect(writes == 0 && model.library.workspaces.isEmpty)
            #expect(model.folder == .inbox && model.query.isEmpty && model.selectedWorkspace == nil)
            #expect(model.editor.content == text && model.editor.selection == selection && model.editor.focusToken == focus)
        }
    }

    @Test func storageFailureDoesNotCancelOrApplyThePreparedWorkspace() async throws {
        try await withPendingAction { model, pending in
            let candidate = try workspace()
            var writes = 0
            model.library.beforeBatchCommit = {
                writes += 1
                #expect(!pending.isCancelled && model.folder == .inbox)
                throw DraftlyError.message("Injected Workspace commit failure")
            }
            do { try model.saveAndApplyWorkspace(candidate); Issue.record("The injected failure succeeded.") }
            catch { #expect(error.localizedDescription == "Injected Workspace commit failure") }
            #expect(writes == 1 && !pending.isCancelled && model.library.workspaces.isEmpty)
            #expect(model.folder == .inbox && model.query.isEmpty && model.selectedWorkspace == nil)
        }
    }
}
