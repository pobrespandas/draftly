import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@MainActor struct ActionMoveNavigationTests {
    private func setup(_ preference: ActionMoveNavigation = .createNew) throws -> (LibraryStore, WindowModel, UserDefaults, String) {
        let domain = "Draftly.ActionMoveNavigation." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defaults.set(preference.rawValue, forKey: ActionMoveNavigation.preferenceKey)
        let library = try LibraryStore(inMemory: true, seed: false)
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.sort = .title; model.ascending = true
        return (library, model, defaults, domain)
    }
    private func action(_ destination: String, script: String = "void 0;") -> DraftAction {
        var action = DraftAction(name: "Neutral move", steps: [ActionStep("script", ["script": script])])
        action.afterSuccess = destination
        return action
    }

    @Test func successfulMoveCreatesOnlyAnUnsavedScratchAndPreservesOutcome() async throws {
        let (library, model, defaults, domain) = try setup()
        defer { defaults.removePersistentDomain(forName: domain) }
        let original = try library.createNote(content: "Neutral café 🐼")
        model.select(original.id)
        let outcome = await model.runActionOutcome(action("archive"))
        #expect(outcome?.report.reason == .success)
        #expect(outcome?.draftID == original.id)
        #expect(model.editor.noteID != original.id)
        #expect(model.editor.content.isEmpty)
        #expect(library.notes.count == 1)
        #expect(library.notes.first?.isArchived == true)
        #expect(model.lastNoteID == original.id)
    }

    @Test func nextUsesVisibleOrderThenPreviousAndFallsBackToScratch() async throws {
        let (library, model, defaults, domain) = try setup(.openNext)
        defer { defaults.removePersistentDomain(forName: domain) }
        let a = try library.createNote(content: "A"), b = try library.createNote(content: "B"), c = try library.createNote(content: "C")
        model.select(b.id)
        #expect((await model.runAsync(action("trash")))?.reason == .success)
        #expect(model.editor.noteID == c.id)
        #expect((await model.runAsync(action("archive")))?.reason == .success)
        #expect(model.editor.noteID == a.id)
        #expect((await model.runAsync(action("archive")))?.reason == .success)
        #expect(![a.id, b.id, c.id].contains(model.editor.noteID ?? UUID()))
        #expect(model.editor.content.isEmpty)
        #expect(library.notes.count == 3)
    }

    @Test(arguments: ["context.fail('Neutral failure');", "context.cancel();"])
    func unsuccessfulActionsDoNotNavigate(script: String) async throws {
        let (library, model, defaults, domain) = try setup()
        defer { defaults.removePersistentDomain(forName: domain) }
        let original = try library.createNote(content: "Neutral")
        model.select(original.id)
        let report = await model.runAsync(action("archive", script: script))
        #expect(report?.result.succeeded == false)
        #expect(model.editor.noteID == original.id)
        #expect(library.notes.first?.isArchived == false)
    }

    @Test func scriptChosenEditorAndAnUnchangedDestinationArePreserved() async throws {
        let (library, model, defaults, domain) = try setup()
        defer { defaults.removePersistentDomain(forName: domain) }
        let original = try library.createNote(content: "Original"), target = try library.createNote(content: "Chosen")
        model.select(original.id)
        let report = await model.runAsync(action("archive", script: "editor.load(Draft.find('\(target.id.uuidString)'))"))
        #expect(report?.reason == .success)
        #expect(model.editor.noteID == target.id)
        model.select(original.id)
        #expect((await model.runAsync(action("archive")))?.reason == .success)
        #expect(model.editor.noteID == original.id)
    }

    @Test func automationReturnsProcessedIdentityAndSingleContextCommandUsesPreference() async throws {
        let (library, model, defaults, domain) = try setup()
        defer { defaults.removePersistentDomain(forName: domain) }
        let first = try library.createNote(content: "First")
        model.select(first.id)
        let output = try await AutomationActionExecution.run(action("archive"), noteID: first.id,
            library: library, models: [model], host: model.host, resolveModel: { models, _ in models.first })
        #expect(output.report.reason == .success)
        #expect(output.noteID == first.id)
        #expect(model.editor.noteID != first.id)
        let second = try library.createNote(content: "Second")
        await model.runActionAsync(action("trash"), on: [second.id])
        #expect(model.editor.noteID != second.id && model.editor.content.isEmpty)
        #expect(library.notes.first(where: { $0.id == second.id })?.trashedAt != nil)
    }

    @Test func multipleTargetsKeepTheAgreedLastProcessedDraft() async throws {
        let (library, model, defaults, domain) = try setup()
        defer { defaults.removePersistentDomain(forName: domain) }
        let a = try library.createNote(content: "A"), b = try library.createNote(content: "B")
        await model.runActionAsync(action("archive"), on: [a.id, b.id])
        #expect(model.editor.noteID == b.id)
        #expect(library.notes.allSatisfy { $0.isArchived })
    }

    @Test func failedPendingSaveAndTimeoutDoNotMoveTheEditor() async throws {
        enum Failure: Error { case save }
        let (library, model, defaults, domain) = try setup()
        defer { defaults.removePersistentDomain(forName: domain) }
        let original = try library.createNote(content: "Stored")
        let failing = WindowModel(library: library, dependencies: model.dependencies, saveDraft: { _ in throw Failure.save })
        failing.select(original.id)
        failing.editor.content = "Pending café 🐼"; failing.contentChanged()
        let notStarted = await failing.runAsync(action("archive"))
        #expect(notStarted == nil)
        #expect(failing.editor.noteID == original.id && failing.editor.content == "Pending café 🐼")
        #expect(library.notes.first?.content == "Stored")
        #expect(library.runs.isEmpty)
        model.select(original.id)
        model.runner.scriptTimeout = 0.02
        var timed = DraftAction(name: "Neutral timeout", steps: [ActionStep("script", ["allowAsync": "true", "script": "void 0;"])])
        timed.afterSuccess = "trash"
        let report = await model.runAsync(timed)
        #expect(report?.reason == .timeout)
        #expect(model.editor.noteID == original.id)
        #expect(library.notes.first?.trashedAt == nil)
    }

    @Test func invalidOrAbsentPreferenceUsesCreateNew() throws {
        #expect(ActionMoveNavigation.resolved(nil) == .createNew)
        #expect(ActionMoveNavigation.resolved("future") == .createNew)
        #expect(ActionMoveNavigation.resolved("Open Next Draft") == .openNext)
    }
}
