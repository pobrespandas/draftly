import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Pending draft routing") @MainActor
struct PendingDraftRoutingTests {
    private func makeController(_ library: LibraryStore, defaults: UserDefaults) -> AppController {
        AppController(library: library, recentDrafts: RecentDraftStore(defaults: defaults))
    }
    private func preferences() throws -> (String, UserDefaults) {
        let name = "Draftly.PendingRoutingTests." + UUID().uuidString
        return (name, try #require(UserDefaults(suiteName: name)))
    }

    @Test func windowRequestBeforeSceneSetupReplaysOnceWithoutLosingItsDraft() throws {
        let (domain, defaults) = try preferences(); defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Cold route café 🐼")
        let controller = makeController(library, defaults: defaults)
        controller.queueDraftSelection(target.id)
        controller.requestLibraryWindow()
        controller.requestLibraryWindow()
        var opens = 0
        controller.openLibrary = { opens += 1 }
        #expect(opens == 1)
        #expect(controller.pendingNoteID == target.id)
        controller.openLibrary = { opens += 1 }
        #expect(opens == 1)
        let model = controller.makeWindowModel(library: library)
        controller.registerWindow(model)
        #expect(model.editor.noteID == target.id)
        #expect(model.editor.content == "Cold route café 🐼")
        controller.requestLibraryWindow()
        #expect(opens == 2)
        #expect(library.notes.count == 1)
    }

    @Test func coldSelectionSurvivesUntilTheModelRegisters() throws {
        let (domain, defaults) = try preferences(); defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Neutral target")
        let controller = makeController(library, defaults: defaults)
        controller.queueDraftSelection(target.id)
        controller.queueDraftSelection(nil)
        #expect(controller.pendingNoteID == target.id)
        let model = controller.makeWindowModel(library: library)
        controller.registerWindow(model)
        #expect(model.editor.noteID == target.id && model.editor.content == "Neutral target")
        #expect(controller.pendingNoteID == nil)
        #expect(library.notes.count == 1)
    }

    @Test func registeredModelCanConsumeWithoutAKeyWindowOrNotification() throws {
        let (domain, defaults) = try preferences(); defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "Source"), target = try library.createNote(content: "Target")
        let controller = makeController(library, defaults: defaults), model = WindowModel(library: library)
        model.select(source.id); controller.registerWindow(model)
        controller.queueDraftSelection(target.id)
        #expect(controller.consumePendingDraft(for: model))
        #expect(model.editor.noteID == target.id && controller.pendingNoteID == nil)
    }

    @Test func failedSaveKeepsTheTargetUntilSuccessfulRetry() throws {
        enum Failure: Error { case save }
        let (domain, defaults) = try preferences(); defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "Stored"), target = try library.createNote(content: "Target")
        var fail = true
        let model = WindowModel(library: library, saveDraft: { note in if fail { throw Failure.save }; try library.saveNote(note) })
        model.select(source.id); model.editor.content = "Pending"; model.contentChanged()
        let controller = makeController(library, defaults: defaults); controller.queueDraftSelection(target.id)
        #expect(!controller.consumePendingDraft(for: model))
        #expect(controller.pendingNoteID == target.id && model.editor.noteID == source.id && model.editor.content == "Pending")
        let other = WindowModel(library: library); controller.registerWindow(other)
        #expect(other.editor.noteID == nil && controller.pendingNoteID == target.id)
        fail = false
        #expect(controller.consumePendingDraft(for: model))
        #expect(controller.pendingNoteID == nil && model.editor.noteID == target.id)
        #expect(library.notes.first { $0.id == source.id }?.content == "Pending")
    }

    @Test func missingTargetReportsAnErrorAndDoesNotLeaveStartupWaiting() throws {
        let (domain, defaults) = try preferences(); defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let controller = makeController(library, defaults: defaults), model = WindowModel(library: library)
        controller.queueDraftSelection(UUID())
        #expect(!controller.consumePendingDraft(for: model))
        #expect(controller.pendingNoteID == nil && library.error == "The requested draft was not found.")
        #expect(model.create())
        #expect(model.editor.noteID != nil)
    }

    @Test func deliberateNewDraftClearsAnOldPendingSelection() throws {
        let (domain, defaults) = try preferences(); defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Target")
        let controller = makeController(library, defaults: defaults), model = WindowModel(library: library)
        controller.queueDraftSelection(target.id)
        #expect(model.create())
        let scratch = model.editor.noteID
        controller.draftSelectionDidChange(scratch, for: model)
        controller.registerWindow(model)
        #expect(controller.pendingNoteID == nil && model.editor.noteID == scratch && scratch != target.id)
    }

    @Test func existingModelsCannotStealANewWindowOrTabSelection() throws {
        let (domain, defaults) = try preferences(); defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "Source"), target = try library.createNote(content: "Target")
        let controller = makeController(library, defaults: defaults)
        let existing = WindowModel(library: library); existing.select(source.id); controller.registerWindow(existing)
        controller.queueNewWindowDraftSelection(target.id)
        controller.queueDraftSelection(nil)
        controller.registerWindow(existing)
        controller.draftSelectionDidChange(existing.editor.noteID, for: existing)
        #expect(controller.pendingNoteID == target.id && existing.editor.noteID == source.id)
        let created = WindowModel(library: library); controller.registerWindow(created)
        #expect(controller.pendingNoteID == nil && created.editor.noteID == target.id)
        #expect(existing.editor.noteID == source.id)
    }

    @Test func closingTheIntendedModelDoesNotRetargetThePendingRequest() throws {
        enum Failure: Error { case save }
        let (domain, defaults) = try preferences(); defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let source = try library.createNote(content: "Source"), target = try library.createNote(content: "Target")
        let closing = WindowModel(library: library, saveDraft: { _ in throw Failure.save }); closing.select(source.id)
        closing.editor.content = "Pending"; closing.contentChanged()
        let controller = makeController(library, defaults: defaults); controller.queueDraftSelection(target.id)
        #expect(!controller.consumePendingDraft(for: closing))
        controller.unregisterWindow(closing)
        let other = WindowModel(library: library); controller.registerWindow(other)
        #expect(controller.pendingNoteID == nil && other.editor.noteID == nil)
    }
}
