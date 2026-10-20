import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Window dictation lifetime") @MainActor
struct WindowDictationSessionTests {
    private func model() throws -> WindowModel {
        let model = WindowModel(library: try LibraryStore(inMemory: true, seed: false))
        let note = try model.library.createNote(content: "Neutral 🐼 text")
        model.select(note.id)
        model.editor.focusForDictation = { true }
        model.editor.selection = NSRange(location: 8, length: 2)
        return model
    }

    @Test func returnsImmediatelyWhileThePresenterIsSuspended() async throws {
        let model = try model(), presenter = DictationPresenterFixture()
        model.presentDictation = { try await presenter.present() }
        try model.showDictation()
        #expect(model.dictationActive)
        #expect(model.editor.content == "Neutral 🐼 text")
        await presenter.waitUntilStarted()
        #expect(model.dictationActive)
        presenter.finish(.success("panda"))
        await model.dictationSession.wait()
        #expect(!model.dictationActive)
        #expect(model.editor.content == "Neutral panda text")
        #expect(model.currentNote?.content == "Neutral panda text")
    }

    @Test(arguments: ["content", "selection", "draft", "storage"])
    func changedTargetsRecoverSpeechInsteadOfReplacingText(_ change: String) async throws {
        let model = try model(), presenter = DictationPresenterFixture()
        let originalID = try #require(model.editor.noteID)
        var recovered = ""
        model.recoverDictation = { recovered = $0 }
        model.presentDictation = { try await presenter.present() }
        try model.showDictation()
        await presenter.waitUntilStarted()
        switch change {
        case "content": model.editor.content = "User text"
        case "selection": model.editor.selection = NSRange(location: 0, length: 0)
        case "draft": model.select(try model.library.createNote(content: "Other").id)
        default:
            var note = try #require(model.currentNote); note.content = "Remote text"
            try model.library.saveNote(note)
        }
        let current = model.editor.content
        presenter.finish(.success("Recovered speech"))
        await model.dictationSession.wait()
        #expect(recovered == "Recovered speech")
        #expect(model.editor.content == current)
        if change == "storage" { #expect(model.library.notes.first { $0.id == originalID }?.content == "Remote text") }
    }

    @Test func cancellationCleansUpWithoutAnErrorOrInsertion() async throws {
        let model = try model(), presenter = DictationPresenterFixture()
        model.presentDictation = { try await presenter.present() }
        try model.showDictation(); await presenter.waitUntilStarted()
        model.cancelActions()
        presenter.finish(.success("Late speech"))
        await model.dictationSession.wait()
        #expect(!model.dictationActive && model.editor.content == "Neutral 🐼 text")
        #expect(model.library.error == nil)
    }

    @Test func failedSaveKeepsRecognizedTextAndPendingChanges() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let model = WindowModel(library: library, saveDraft: { _ in throw DraftlyError.message("Expected storage failure") })
        model.select(note.id); model.editor.focusForDictation = { true }
        model.presentDictation = { "Speech " }
        try model.showDictation(); await model.dictationSession.wait()
        #expect(model.editor.content == "Speech Original")
        #expect(model.hasUnsavedChanges)
        #expect(library.notes.first?.content == "Original")
        #expect(library.error == "Expected storage failure")
    }

    @Test func releasingTheWindowCancelsAnUnfinishedSession() async throws {
        var model: WindowModel? = try self.model()
        let presenter = DictationPresenterFixture()
        model?.presentDictation = { try await presenter.present() }
        weak var weakModel = model
        try model?.showDictation(); await presenter.waitUntilStarted()
        model = nil
        #expect(weakModel == nil)
        presenter.finish(.success("Late speech"))
    }
}

@MainActor private final class DictationPresenterFixture {
    private var continuation: CheckedContinuation<String, any Error>?
    private let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    init() { (started, signal) = AsyncStream.makeStream() }
    func present() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            signal.yield(())
        }
    }
    func waitUntilStarted() async { for await _ in started { return } }
    func finish(_ result: Result<String, any Error>) {
        let pending = continuation; continuation = nil; pending?.resume(with: result)
    }
}
