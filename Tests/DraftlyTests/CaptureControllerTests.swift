import AppKit
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Capture controller") @MainActor
struct CaptureControllerTests {
    private enum Failure: LocalizedError {
        case disk
        var errorDescription: String? { "Capture test disk failure" }
    }

    private func withBuffer(_ body: (CaptureBuffer, UserDefaults) throws -> Void) throws {
        let suite = "DraftlyCaptureControllerTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(CaptureBuffer(defaults: defaults), defaults)
    }

    @Test func constructionDoesNotReadItsInjectedProviders() throws {
        try withBuffer { buffer, _ in
            var libraryReads = 0, windowReads = 0
            let controller = CaptureController(buffer: buffer, libraryProvider: {
                libraryReads += 1
                return nil
            }, windowProvider: {
                windowReads += 1
                return []
            })
            #expect(controller.buffer === buffer)
            #expect(libraryReads == 0 && windowReads == 0)
        }
    }

    @Test func directCaptureSavesOnlyIncomingTextAndKeepsAnEarlierCapture() throws {
        try withBuffer { buffer, defaults in
            let library = try LibraryStore(inMemory: true, seed: false)
            buffer.text = "Earlier capture 🐼\nKeep this"
            buffer.error = "Earlier capture needs attention"
            var windowReads = 0
            let controller = CaptureController(buffer: buffer, libraryProvider: { library }, windowProvider: {
                windowReads += 1
                return []
            })
            let incoming = "Selected café 🐼\nSecond line\n"
            try controller.captureDirectly(incoming)
            let note = try #require(library.notes.first)
            #expect(library.notes.count == 1 && note.content == incoming)
            #expect(!note.isArchived && note.trashedAt == nil)
            #expect(buffer.text == "Earlier capture 🐼\nKeep this")
            #expect(buffer.error == "Earlier capture needs attention")
            #expect(CaptureBuffer(defaults: defaults).text == buffer.text)
            #expect(windowReads == 0)
        }
    }

    @Test func directCaptureFailureRetainsIncomingTextAcrossBufferRecreation() throws {
        try withBuffer { buffer, defaults in
            let library = try LibraryStore(inMemory: true, seed: false)
            library.beforeBatchCommit = { throw Failure.disk }
            defer { library.beforeBatchCommit = nil }
            buffer.text = "Earlier capture"
            let controller = CaptureController(buffer: buffer, libraryProvider: { library }, windowProvider: { [] })
            #expect(throws: Failure.self) { try controller.captureDirectly("Incoming 🐼\nText") }
            #expect(library.notes.isEmpty && library.revisions.isEmpty)
            #expect(buffer.text == "Earlier capture\n\nIncoming 🐼\nText")
            #expect(buffer.error == "Capture test disk failure")
            #expect(CaptureBuffer(defaults: defaults).text == buffer.text)
        }
    }

    @Test func directCaptureWithoutALibraryReturnsAnErrorAndRetainsTheSelection() throws {
        try withBuffer { buffer, defaults in
            let controller = CaptureController(buffer: buffer, libraryProvider: { nil }, windowProvider: { [] })
            #expect(throws: (any Error).self) { try controller.captureDirectly("Unavailable library café 🐼") }
            #expect(buffer.text == "Unavailable library café 🐼")
            #expect(buffer.error == "The library is unavailable.")
            #expect(CaptureBuffer(defaults: defaults).text == buffer.text)
        }
    }

    @Test func emptyDirectCaptureDoesNotCreateADraftOrChangePendingText() throws {
        try withBuffer { buffer, _ in
            let library = try LibraryStore(inMemory: true, seed: false)
            buffer.text = "Keep pending text"
            let controller = CaptureController(buffer: buffer, libraryProvider: { library }, windowProvider: { [] })
            #expect(throws: (any Error).self) { try controller.captureDirectly("") }
            #expect(library.notes.isEmpty)
            #expect(buffer.text == "Keep pending text" && buffer.error == "No text was provided.")
        }
    }

    @Test func savingANewCaptureClearsItOnlyAfterStorageSucceeds() throws {
        try withBuffer { buffer, defaults in
            let library = try LibraryStore(inMemory: true, seed: false)
            var windowReads = 0
            let controller = CaptureController(buffer: buffer, libraryProvider: { library }, windowProvider: {
                windowReads += 1
                return []
            })
            buffer.text = "Capture café 🐼\nSecond line"
            library.beforeBatchCommit = { throw Failure.disk }
            #expect(!controller.save(to: nil))
            #expect(library.notes.isEmpty && buffer.text == "Capture café 🐼\nSecond line")
            #expect(CaptureBuffer(defaults: defaults).text == buffer.text)
            library.beforeBatchCommit = nil
            #expect(controller.save(to: nil))
            #expect(library.notes.map(\.content) == ["Capture café 🐼\nSecond line"])
            #expect(buffer.text.isEmpty && buffer.error == nil)
            #expect(CaptureBuffer(defaults: defaults).text.isEmpty)
            #expect(windowReads == 0)
        }
    }

    @Test func appendSynchronizesEveryMatchingEditorBeforeAnImmediateFlush() throws {
        try withBuffer { buffer, _ in
            let library = try LibraryStore(inMemory: true, seed: false)
            let note = try library.createNote(content: "Saved text")
            let first = WindowModel(library: library), second = WindowModel(library: library)
            first.select(note.id); second.select(note.id)
            first.editor.content = "Pending 🐼"; second.editor.content = "Pending 🐼"
            first.editor.selection = NSRange(location: 8, length: 2)
            second.editor.selection = NSRange(location: 0, length: 7)
            first.contentChanged(); second.contentChanged()
            let firstFocus = first.editor.focusToken, secondFocus = second.editor.focusToken
            var synchronized = 0
            first.editor.synchronizeScriptEdit = { synchronized += 1 }
            second.editor.synchronizeScriptEdit = { synchronized += 1 }
            let otherLibrary = try LibraryStore(inMemory: true, seed: false)
            let otherNote = Note(id: note.id, content: "Separate library")
            try otherLibrary.saveNote(otherNote)
            let other = WindowModel(library: otherLibrary); other.select(note.id)
            let controller = CaptureController(buffer: buffer, libraryProvider: { library }, windowProvider: { [first, second, other] })
            buffer.text = "Incoming café\nSecond line"
            #expect(controller.save(to: note.id))
            let expected = "Pending 🐼\n\nIncoming café\nSecond line"
            #expect(first.editor.content == expected && second.editor.content == expected)
            #expect(first.editor.selection == NSRange(location: 8, length: 2))
            #expect(second.editor.selection == NSRange(location: 0, length: 7))
            #expect(first.editor.focusToken == firstFocus && second.editor.focusToken == secondFocus)
            #expect(synchronized == 2 && buffer.text.isEmpty)
            #expect(first.flush() && second.flush())
            #expect(library.notes.first { $0.id == note.id }?.content == expected)
            #expect(other.editor.content == "Separate library")
            #expect(otherLibrary.notes.first { $0.id == note.id }?.content == "Separate library")
        }
    }

    @Test(arguments: [false, true])
    func appendDoesNotLetACleanDuplicateOverwritePendingOwnerText(ownerFirst: Bool) throws {
        try withBuffer { buffer, _ in
            let library = try LibraryStore(inMemory: true, seed: false)
            let note = try library.createNote(content: "Stored café 🐼")
            let owner = WindowModel(library: library), duplicate = WindowModel(library: library)
            owner.select(note.id); duplicate.select(note.id)
            owner.editor.content = "Pending café 🐼"; owner.contentChanged()
            owner.editor.selection = NSRange(location: 8, length: 4)
            duplicate.editor.selection = NSRange(location: 0, length: 6)
            let ownerFocus = owner.editor.focusToken, duplicateFocus = duplicate.editor.focusToken
            let controller = CaptureController(buffer: buffer, libraryProvider: { library },
                windowProvider: { ownerFirst ? [owner, duplicate] : [duplicate, owner] })
            buffer.text = "Incoming 🦊\nSecond line"

            #expect(controller.save(to: note.id))

            let expected = "Pending café 🐼\n\nIncoming 🦊\nSecond line"
            #expect(library.notes.first { $0.id == note.id }?.content == expected)
            #expect(owner.editor.content == expected && duplicate.editor.content == expected)
            #expect(owner.editor.selection == NSRange(location: 8, length: 4))
            #expect(duplicate.editor.selection == NSRange(location: 0, length: 6))
            #expect(owner.editor.focusToken == ownerFocus && duplicate.editor.focusToken == duplicateFocus)
            #expect(buffer.text.isEmpty && owner.flush() && duplicate.flush())
            #expect(library.notes.first { $0.id == note.id }?.content == expected)
        }
    }

    @Test func appCaptureWithoutALibraryRetainsIncomingTextUntilStorageRecovers() throws {
        try withBuffer { buffer, defaults in
            let library = try LibraryStore(inMemory: true, seed: false)
            let app = AppController(library: library, recentDrafts: RecentDraftStore(defaults: defaults))
            app.captureController = CaptureController(buffer: buffer,
                libraryProvider: { [weak app] in app?.library })
            app.library = nil
            buffer.text = "Earlier capture"

            app.capture(content: "Incoming café 🐼\nSecond line")

            let expected = "Earlier capture\n\nIncoming café 🐼\nSecond line"
            #expect(buffer.text == expected)
            #expect(CaptureBuffer(defaults: defaults).text == expected)
            #expect(buffer.error == "The library is unavailable.")
            app.library = library
            #expect(app.captureController.save(to: nil))
            #expect(library.notes.map(\.content) == [expected])
            #expect(buffer.text.isEmpty && buffer.error == nil)
        }
    }

    @Test func retryingReceiptWithoutNewTextDoesNotDuplicateThePendingDelivery() throws {
        try withBuffer { buffer, defaults in
            var library: LibraryStore?
            let controller = CaptureController(buffer: buffer, libraryProvider: { library })
            buffer.text = "Earlier capture"
            #expect(!controller.receive("Incoming café 🐼"))
            let expected = "Earlier capture\n\nIncoming café 🐼"
            #expect(!controller.receive(""))
            #expect(buffer.text == expected && CaptureBuffer(defaults: defaults).text == expected)
            library = try LibraryStore(inMemory: true, seed: false)
            #expect(controller.receive(""))
            #expect(buffer.text == expected)
            #expect(controller.save(to: nil))
            #expect(library?.notes.map(\.content) == [expected])
            #expect(buffer.text.isEmpty && buffer.error == nil)
        }
    }

    @Test func destinationsObserveNewRenamedAndTrashedDraftsWithoutReplacingAValidTarget() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var target = try library.createNote(content: "Target café 🐼")
        let destinations = CaptureDestinations()
        destinations.bind(library)
        destinations.target = target.id

        let added = try library.createNote(content: "Added while capturing")
        #expect(Set(destinations.notes.map(\.id)) == [target.id, added.id])
        #expect(destinations.target == target.id)

        target.content = "Renamed 🦊"; try library.saveNote(target)
        #expect(destinations.notes.first { $0.id == target.id }?.title == "Renamed 🦊")
        #expect(destinations.target == target.id)

        target.trashedAt = Date(); try library.saveNote(target)
        #expect(destinations.notes.map(\.id) == [added.id])
        #expect(destinations.target == nil)
    }

    @Test func rebindingDestinationsKeepsAnAvailableTargetAndStopsObservingTheOldLibrary() throws {
        let originalLibrary = try LibraryStore(inMemory: true, seed: false)
        let target = try originalLibrary.createNote(content: "Original target")
        let replacementLibrary = try LibraryStore(inMemory: true, seed: false)
        var replacement = target; replacement.content = "Replacement café 🐼"
        try replacementLibrary.saveNote(replacement)
        let storedReplacement = try #require(replacementLibrary.notes.first)
        let destinations = CaptureDestinations()
        destinations.bind(originalLibrary)
        destinations.target = target.id

        destinations.bind(replacementLibrary)
        #expect(destinations.notes == [storedReplacement] && destinations.target == target.id)
        _ = try originalLibrary.createNote(content: "Old library only")
        #expect(destinations.notes == [storedReplacement] && destinations.target == target.id)

        destinations.bind(nil)
        #expect(destinations.notes.isEmpty && destinations.target == nil)
    }

    @Test func appendKeepsNativeUndoRedoAndTheEarlierEditHistory() throws {
        try withBuffer { buffer, _ in
            let library = try LibraryStore(inMemory: true, seed: false)
            let note = try library.createNote(content: "Base 🐼")
            let model = WindowModel(library: library); model.select(note.id)
            let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17,
                                      lineSpacing: 2, markdown: false, onChange: { model.contentChanged() })
            let coordinator = NativeEditor.Coordinator(native), text = TestUndoTextView(frame: .zero)
            text.string = model.editor.content; coordinator.textView = text; coordinator.noteID = note.id
            text.manager.groupsByEvent = false
            model.editor.synchronizeScriptEdit = {
                text.manager.beginUndoGrouping()
                coordinator.synchronizeScriptEdit()
                text.manager.endUndoGrouping()
            }
            defer { model.editor.synchronizeScriptEdit = nil }
            model.editor.content = "Pending 🐼"
            model.editor.selection = NSRange(location: 8, length: 2)
            model.editor.synchronizeScriptEdit?(); model.contentChanged()
            let controller = CaptureController(buffer: buffer, libraryProvider: { library }, windowProvider: { [model] })
            buffer.text = "Captured café"
            #expect(controller.save(to: note.id))
            let appended = "Pending 🐼\n\nCaptured café"
            #expect(model.editor.content == appended && text.string == appended)
            #expect(model.editor.selection == NSRange(location: 8, length: 2))
            #expect(model.flush())
            text.manager.undo()
            #expect(model.editor.content == "Pending 🐼" && text.string == "Pending 🐼")
            #expect(model.editor.selection == NSRange(location: 8, length: 2))
            #expect(model.flush())
            text.manager.undo()
            #expect(model.editor.content == "Base 🐼" && model.flush())
            text.manager.redo()
            #expect(model.editor.content == "Pending 🐼" && model.flush())
            text.manager.redo()
            #expect(model.editor.content == appended && text.string == appended && model.flush())
            #expect(library.notes.first { $0.id == note.id }?.content == appended)
        }
    }

    @Test func failedDestinationFlushPreservesCaptureEditorAndStoredText() throws {
        try withBuffer { buffer, defaults in
            let library = try LibraryStore(inMemory: true, seed: false)
            let note = try library.createNote(content: "Stored destination")
            let model = WindowModel(library: library, saveDraft: { _ in throw Failure.disk })
            model.select(note.id); model.editor.content = "Pending destination 🐼"
            model.editor.selection = NSRange(location: 0, length: 7); model.contentChanged()
            let beforeRevisions = library.revisions
            let controller = CaptureController(buffer: buffer, libraryProvider: { library }, windowProvider: { [model] })
            buffer.text = "Keep captured café"
            #expect(!controller.save(to: note.id))
            #expect(buffer.text == "Keep captured café" && CaptureBuffer(defaults: defaults).text == buffer.text)
            #expect(model.editor.content == "Pending destination 🐼" && model.hasUnsavedChanges)
            #expect(model.editor.selection == NSRange(location: 0, length: 7))
            #expect(library.notes.first { $0.id == note.id }?.content == "Stored destination")
            #expect(library.revisions == beforeRevisions)
            #expect(buffer.error == "Save the destination draft before adding text.")
        }
    }

    @Test func failedAppendWriteKeepsTheFlushedDestinationAndCapture() throws {
        try withBuffer { buffer, defaults in
            let library = try LibraryStore(inMemory: true, seed: false)
            let note = try library.createNote(content: "Stored destination")
            let model = WindowModel(library: library, saveDraft: { value in
                try library.saveNote(value)
                library.beforeBatchCommit = { throw Failure.disk }
            })
            defer { library.beforeBatchCommit = nil }
            model.select(note.id); model.editor.content = "Pending destination 🐼"
            model.editor.selection = NSRange(location: 0, length: 7); model.contentChanged()
            var synchronized = false
            model.editor.synchronizeScriptEdit = { synchronized = true }
            let controller = CaptureController(buffer: buffer, libraryProvider: { library }, windowProvider: { [model] })
            buffer.text = "Keep captured café"
            #expect(!controller.save(to: note.id))
            #expect(buffer.text == "Keep captured café" && CaptureBuffer(defaults: defaults).text == buffer.text)
            #expect(buffer.error == "Capture test disk failure")
            #expect(model.editor.content == "Pending destination 🐼")
            #expect(model.editor.selection == NSRange(location: 0, length: 7))
            #expect(library.notes.first { $0.id == note.id }?.content == "Pending destination 🐼")
            #expect(!library.revisions.contains { $0.content.contains("Keep captured café") })
            #expect(!synchronized)
        }
    }

    @Test func missingOrTrashedDestinationDoesNotConsumeCapture() throws {
        try withBuffer { buffer, defaults in
            let library = try LibraryStore(inMemory: true, seed: false)
            var trashed = try library.createNote(content: "Trashed destination")
            trashed.trashedAt = Date(); try library.saveNote(trashed)
            let original = library.notes, revisions = library.revisions
            let controller = CaptureController(buffer: buffer, libraryProvider: { library }, windowProvider: { [] })
            buffer.text = "Keep captured café"
            for id in [UUID(), trashed.id] {
                #expect(!controller.save(to: id))
                #expect(buffer.text == "Keep captured café" && CaptureBuffer(defaults: defaults).text == buffer.text)
                #expect(buffer.error == "The destination draft is no longer available.")
                #expect(library.notes == original && library.revisions == revisions)
            }
        }
    }
}
